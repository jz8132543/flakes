const http = require("http");
const fs = require("fs");
const path = require("path");
const https = require("https");

const PORT = process.env.PORT || 7070;
const HOST = process.env.HOST || "0.0.0.0";

// --- Utilities ---
const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch (e) {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

function parseUrl(reqUrl) {
  const u = new URL(reqUrl, "http://localhost");
  const query = Object.fromEntries(u.searchParams.entries());
  return { pathname: u.pathname, query };
}

function log(method, path, status) {
  const ts = new Date().toISOString().slice(11, 19);
  console.log(`[${ts}] ${method} ${path} -> ${status}`);
}

// ==========================================
// 1. IN-MEMORY DATABASE & DOMAIN STATE (v3.0)
// ==========================================
const db = {
  system_settings: {
    allow_registration: true,
    require_invite_code: false,
    default_token_quota: 50000,
  },

  llm_config: {
    base_url: "https://api.openai-relay.com/v1",
    api_key: "sk-demo-relay-token-2026",
    active_model: "deepseek-r1",
    available_models: [
      "deepseek-r1",
      "gpt-4o",
      "qwen-max",
      "claude-3-5-sonnet",
    ],
  },

  users: [
    {
      id: "u1",
      username: "备考先锋小王 (冲刺2026)",
      password: "password123",
      role: "USER",
      avatar: "🎯",
      exam_target: "2026年山西省联考/国考",
      target_date: "2026-03-13",
      streak: 18,
      freeze_cards: 2,
      total_questions: 1420,
      credit_balance: 150.0,
      token_quota: 50000,
      token_used: 12500,
      teacher_affinity: {
        "秒杀派 (花生十三)": 45,
        "方程正统派 (张三老师)": 20,
        "拆分口算派 (粉笔王老师)": 35,
        "言语脉络派 (欣说言语)": 30,
      },
      companion_tree: {
        level: 2,
        status: "VIBRANT",
        name: "上岸神树 (能量值 85/100)",
        stage: "🌱 枝繁叶茂 - 距离开花结果 (上岸) 还差 15 次有效专注",
        last_watered_date: "2026-07-24",
      },
    },
    {
      id: "u-admin",
      username: "admin",
      password: "adminpassword",
      role: "ADMIN",
      avatar: "👑",
      exam_target: "后台管理与 AI 架构维稳",
      target_date: "2026-12-31",
      streak: 99,
      freeze_cards: 99,
      total_questions: 9999,
      credit_balance: 9999.0,
      token_quota: 999999,
      token_used: 5000,
      teacher_affinity: {},
      companion_tree: {
        level: 5,
        status: "VIBRANT",
        name: "世界树 (Admin)",
        stage: "🌳 繁花似锦 - 管理员权限已全开",
        last_watered_date: "2026-07-24",
      },
    },
    {
      id: "u2",
      username: "在职考公老李 (余额不足演示)",
      password: "password123",
      role: "USER",
      avatar: "💼",
      exam_target: "2026年国考部委",
      target_date: "2026-03-13",
      streak: 15,
      freeze_cards: 1,
      total_questions: 890,
      credit_balance: 50.0,
      token_quota: 10000,
      token_used: 10000, // Token 已耗尽！
      teacher_affinity: {},
      companion_tree: {
        level: 1,
        status: "THIRSTY",
        name: "口渴的幼苗",
        stage: "🍂 树叶开始枯黄 - 连续2天未学习打卡",
        last_watered_date: "2026-07-22",
      },
    },
  ],

  practice_records: generateHeatmapData(),

  // Standardized Civil Service Exam 3-Tier Taxonomy
  skill_tags: [
    {
      id: "s1",
      name: "行测 - 资料分析",
      parent_id: null,
      level: 1,
      benchmark_time_sec: 50,
    },
    {
      id: "s2",
      name: "行测 - 言语理解",
      parent_id: null,
      level: 1,
      benchmark_time_sec: 45,
    },
    {
      id: "s3",
      name: "行测 - 数量关系",
      parent_id: null,
      level: 1,
      benchmark_time_sec: 75,
    },
    {
      id: "s4",
      name: "行测 - 判断推理",
      parent_id: null,
      level: 1,
      benchmark_time_sec: 50,
    },
    {
      id: "s5",
      name: "申论与面试",
      parent_id: null,
      level: 1,
      benchmark_time_sec: 180,
    },
    // Level 2
    {
      id: "s1-1",
      name: "增长率计算与比较",
      parent_id: "s1",
      level: 2,
      benchmark_time_sec: 45,
    },
    {
      id: "s1-2",
      name: "比重与比重变化",
      parent_id: "s1",
      level: 2,
      benchmark_time_sec: 50,
    },
    {
      id: "s2-1",
      name: "片段阅读",
      parent_id: "s2",
      level: 2,
      benchmark_time_sec: 40,
    },
    {
      id: "s2-2",
      name: "逻辑填空 (选词)",
      parent_id: "s2",
      level: 2,
      benchmark_time_sec: 35,
    },
    {
      id: "s3-1",
      name: "数学运算与整除",
      parent_id: "s3",
      level: 2,
      benchmark_time_sec: 70,
    },
    // Level 3 - Atomic Skills
    {
      id: "s1-1-1",
      name: "截位直算法 (精细切分)",
      parent_id: "s1-1",
      level: 3,
      benchmark_time_sec: 40,
    },
    {
      id: "s1-1-2",
      name: "首位估算与特殊值法",
      parent_id: "s1-1",
      level: 3,
      benchmark_time_sec: 35,
    },
    {
      id: "s1-1-3",
      name: "差分比较法 (高阶易错)",
      parent_id: "s1-1",
      level: 3,
      benchmark_time_sec: 55,
    },
    {
      id: "s1-2-1",
      name: "两期比重差值快速比较口诀",
      parent_id: "s1-2",
      level: 3,
      benchmark_time_sec: 45,
    },
    {
      id: "s2-1-1",
      name: "关联词转折锚定定位法",
      parent_id: "s2-1",
      level: 3,
      benchmark_time_sec: 38,
    },
    {
      id: "s2-1-2",
      name: "核心主题词同义替换识别",
      parent_id: "s2-1",
      level: 3,
      benchmark_time_sec: 35,
    },
    {
      id: "s2-2-1",
      name: "成语感情色彩与语境排异",
      parent_id: "s2-2",
      level: 3,
      benchmark_time_sec: 30,
    },
    {
      id: "s3-1-1",
      name: "倍数特性与奇偶整除秒杀",
      parent_id: "s3-1",
      level: 3,
      benchmark_time_sec: 25,
    },
  ],

  // Authoritative Famous Teacher Roster
  teacher_profiles: [
    {
      id: "t1",
      name: "花生十三",
      avatar: "👨‍🏫",
      school_name: "秒杀截位派",
      bio: "强调数字敏感度，追求15秒内凭选项差距估算报答案。",
      bound_skills: ["s1-1-1", "s1-2-1", "s3-1-1"],
    },
    {
      id: "t2",
      name: "粉笔王老师",
      avatar: "👨‍🏫",
      school_name: "拆分口算派",
      bio: "把复杂百分数拆解为 10%、5%、1% 叠加，适合基础薄弱心算突破。",
      bound_skills: ["s1-1-1", "s1-1-2"],
    },
    {
      id: "t3",
      name: "欣说言语",
      avatar: "👩‍🏫",
      school_name: "文段脉络派",
      bio: "聚焦宏观行文脉络，抓中心句和转折后核心观点排异。",
      bound_skills: ["s2-1-1", "s2-1-2"],
    },
    {
      id: "t4",
      name: "郭熙老师",
      avatar: "👨‍🏫",
      school_name: "主题词秒做派",
      bio: "凌厉的主题词锁定法，若选项缺失核心词立刻一秒排除。",
      bound_skills: ["s2-1-2", "s2-2-1"],
    },
    {
      id: "t5",
      name: "齐麟老师",
      avatar: "👨‍🏫",
      school_name: "数量整除派",
      bio: "利用整除特性、奇偶性与余数定理，在行测高压下10秒看选项。",
      bound_skills: ["s3-1-1"],
    },
  ],

  teacher_skills: [
    {
      id: "tsk-1",
      teacher_id: "t1",
      skill_id: "s1-1-1",
      skill_name: "左两位截位直算法 AI 技能",
      prompt_markdown:
        "核心原则：当选项前三位差距>10%时，直接对分母截前两位！绝对不可用竖式计算全数！",
      github_path: "skills/huasheng13/cutoff.md",
    },
    {
      id: "tsk-2",
      teacher_id: "t2",
      skill_id: "s1-1-1",
      skill_name: "10% 与 1% 基准拆分口算技能",
      prompt_markdown:
        "核心原则：6.8% 可以拆解为 5% + 1% + 0.8%，在原数上分步向右移动小数点求和，零失误！",
      github_path: "skills/fenbi_wang/split_10.md",
    },
  ],

  pdf_ingest_jobs: [
    {
      id: "job-demo-1",
      filename: "2025年度国考副省级行测真题与答案(整卷).pdf",
      admin_username: "admin",
      total_pages: 32,
      extracted_count: 135,
      status: "COMPLETED",
      created_at: "2026-07-24T10:00:00Z",
    },
  ],

  questions: [
    {
      id: "q101",
      content:
        "2024年某省农作物总产量 4582.4 万吨，同比增长 6.8%。若保持该增速，2025年该省农作物总产量约为多少万吨？",
      options: [
        { key: "A", text: "4842 万吨" },
        { key: "B", text: "4894 万吨" },
        { key: "C", text: "4920 万吨" },
        { key: "D", text: "5010 万吨" },
      ],
      correct_answer: "B",
      difficulty: 3,
      skill_id: "s1-1-1",
      solutions: [
        {
          id: "sol-1",
          teacher_name: "张三老师 (方程正统派)",
          approach_name: "公式精确求解法",
          content:
            "【公式推导】2025年产量 = 4582.4 × (1 + 6.8%) = 4582.4 × 1.068 = 4893.99 万吨 ≈ 4894 万吨。适合基础扎实、追求零差错的学员。",
          upvotes: 342,
          downvotes: 45,
          time_spent_eval: "58秒",
        },
        {
          id: "sol-2",
          teacher_name: "花生十三 (秒杀截位派)",
          approach_name: "截位直算法 (左两位截位秒杀)",
          content:
            "【秒杀技巧】4582.4 截前两位为 46，6.8% 约为 7%。46 × 7% = 3.22，45.8 + 3.2 = 49.0。对比选项，只有 B(4894) 最为接近，15秒内直出答案！",
          upvotes: 890,
          downvotes: 12,
          time_spent_eval: "15秒",
        },
        {
          id: "sol-3",
          teacher_name: "粉笔王老师 (拆分口算派)",
          approach_name: "10% 与 1% 基准拆分法",
          content:
            "【口算拆分】4582.4 的 5% = 229.1，1% = 45.8，0.8% ≈ 36.6。6.8% = 5% + 1% + 0.8% = 311.5。4582.4 + 311.5 = 4893.9 万吨。无需复杂竖式，全凭大脑直算！",
          upvotes: 620,
          downvotes: 28,
          time_spent_eval: "25秒",
        },
      ],
    },
    {
      id: "q102",
      content:
        "传统的观念中，重男轻女思想根深蒂固，但在现代都市圈中，这一现象正发生显著逆转。____。填入横线处最恰当的一句是？",
      options: [
        { key: "A", text: "这表明社会性别平等意识正在逐渐形成" },
        { key: "B", text: "因而生育率呈现快速下降趋势" },
        { key: "C", text: "然而农村地区的观念依然难以改变" },
        { key: "D", text: "经济发展是推动观念变革的关键动力" },
      ],
      correct_answer: "A",
      difficulty: 2,
      skill_id: "s2-1-1",
      solutions: [
        {
          id: "sol-4",
          teacher_name: "欣说言语 (文段脉络派)",
          approach_name: "转折关联词与因果递推",
          content:
            "【脉络分析】横线在文段末尾，起总结说明作用。前面通过“但在现代都市圈”进行转折，强调正向逆转，A选项直接对应“观念逆转”的社会意义，承接最为紧密！",
          upvotes: 512,
          downvotes: 18,
          time_spent_eval: "22秒",
        },
        {
          id: "sol-5",
          teacher_name: "郭熙老师 (主题词秒做派)",
          approach_name: "核心主题词排异法",
          content:
            "【核心锁定】前文主题词为“观念/思想”，转折后讨论“现象逆转”，A选项中的“性别平等意识”直接继承“观念”主题。B(生育率)、C(农村)、D(经济发展)全是无中生有的新话题，直接秒排！",
          upvotes: 630,
          downvotes: 15,
          time_spent_eval: "18秒",
        },
      ],
    },
    {
      id: "q103",
      content:
        "2023年某市社会消费品零售总额为 3120.5 亿元，其中限额以上企业零售额占比为 42.5%，2022年为 45.0%。请问2023年该市限额以上企业零售额占比同比上升还是下降了多少？",
      options: [
        { key: "A", text: "上升了 2.5 个百分点" },
        { key: "B", text: "下降了 2.5 个百分点" },
        { key: "C", text: "下降了 2.5%" },
        { key: "D", text: "下降了 5.8 个百分点" },
      ],
      correct_answer: "B",
      difficulty: 4,
      skill_id: "s1-2-1",
      solutions: [
        {
          id: "sol-6",
          teacher_name: "花生十三 (秒杀截位派)",
          approach_name: "概念辨析与直接减法秒杀",
          content:
            "【避坑指南】问的是“百分点”还是“百分比”！比重差值必须用百分点表示，排除 C！直接拿 42.5% - 45.0% = -2.5 个百分点，即下降了 2.5 个百分点。千万别去算复杂除法！",
          upvotes: 750,
          downvotes: 10,
          time_spent_eval: "10秒",
        },
      ],
    },
  ],

  cohorts: [
    {
      id: "c1",
      title: "🔥 21天行测高分冲刺魔鬼反学费营 (第 14 期)",
      deposit_amount: 99.0,
      start_date: "2026-07-10",
      end_date: "2026-07-31",
      total_members: 128,
      completed_today: 94,
      pool_amount: 12672.0,
      user_joined: true,
      user_status: "ACTIVE",
      user_checkins_count: 15,
      squad_members: [
        { name: "先锋小王(我)", streak: 18, today_done: true },
        { name: "在职考公老李", streak: 15, today_done: true },
        { name: "晨读打卡阿强", streak: 15, today_done: false },
        { name: "上岸必胜小芳", streak: 12, today_done: true },
      ],
    },
  ],

  strategies: [
    {
      id: "strat-101",
      author_name: "上岸老学长 (省考155分状元)",
      author_avatar: "🎓",
      title: "60天零基础高效逆袭省考155分排期路线图",
      forked_count: 384,
      days_total: 60,
      timeline_data: [
        {
          phase: "基础强化期 (Day 1 - Day 20)",
          daily_questions: 50,
          daily_hours: 3.5,
          focus: "资料分析截位直除口诀 + 言语片段阅读转折锚定",
          recommended_teacher: "花生十三 / 欣说言语",
        },
        {
          phase: "技巧突破与专项消盲期 (Day 21 - Day 40)",
          daily_questions: 80,
          daily_hours: 4.5,
          focus: "名师解法对比精化 + 雷达图薄弱技巧消灭",
          recommended_teacher: "粉笔王老师 / 郭熙",
        },
        {
          phase: "全真模考与冲刺期 (Day 41 - Day 60)",
          daily_questions: 100,
          daily_hours: 5.0,
          focus: "上午 9:00 全真套卷限时训练 + 错题本复盘",
          recommended_teacher: "张三老师 (全卷复盘)",
        },
      ],
    },
  ],
};

function generateHeatmapData() {
  const records = [];
  const now = new Date("2026-07-24");
  for (let i = 364; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const dateStr = d.toISOString().split("T")[0];
    let count = 0;
    const dayOfWeek = d.getDay();
    if (Math.random() > 0.15) {
      count = Math.floor(Math.random() * 65) + 15;
      if (dayOfWeek === 0 || dayOfWeek === 6) count += 30;
    }
    let level = 0;
    if (count > 0 && count <= 20) level = 1;
    else if (count > 20 && count <= 50) level = 2;
    else if (count > 50 && count <= 80) level = 3;
    else if (count > 80) level = 4;

    records.push({
      date: dateStr,
      count,
      minutes: Math.round(count * 1.8),
      green_shade_level: level,
    });
  }
  return records;
}

function sendJSON(res, data, status = 200) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS, PUT, DELETE",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  });
  res.end(JSON.stringify(data));
}

const PUBLIC_DIR = path.join(__dirname, "public");

// ==========================================
// 2. HTTP SERVER & REST API ROUTER (v3.0)
// ==========================================
const server = http.createServer(async (req, res) => {
  const parsedUrl = parseUrl(req.url);
  const pathname = parsedUrl.pathname;

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS, PUT, DELETE",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    });
    return res.end();
  }

  // --- AUTH / RBAC ENDPOINTS ---
  if (pathname === "/api/auth/register" && req.method === "POST") {
    if (!db.system_settings.allow_registration) {
      log(req.method, pathname, 403);
      return sendJSON(
        res,
        {
          error:
            "平台当前已关闭普通用户注册，请联系管理员获取内测名额或开启注册功能！",
        },
        403,
      );
    }
    try {
      const p = await parseBody(req);
      if (!p.username || !p.password)
        return sendJSON(res, { error: "用户名与密码不能为空" }, 400);
      if (db.users.find((u) => u.username === p.username))
        return sendJSON(res, { error: "用户名已存在" }, 400);

      const newUser = {
        id: `u-${Date.now()}`,
        username: p.username,
        password: p.password,
        role: "USER",
        avatar: "🎯",
        exam_target: "2026年省考冲刺",
        target_date: "2026-03-13",
        streak: 1,
        freeze_cards: 2,
        total_questions: 0,
        credit_balance: 100.0,
        token_quota: db.system_settings.default_token_quota,
        token_used: 0,
        teacher_affinity: {},
        companion_tree: {
          level: 1,
          status: "VIBRANT",
          name: "上岸嫩芽",
          stage: "🌱 刚萌芽 - 开始做题积累能量",
          last_watered_date: "2026-07-24",
        },
      };
      db.users.push(newUser);
      log(req.method, pathname, 200);
      return sendJSON(res, {
        success: true,
        token: `jwt-token-${newUser.id}`,
        user: newUser,
      });
    } catch (err) {
      return sendJSON(res, { error: "Invalid JSON" }, 400);
    }
  }

  if (pathname === "/api/auth/login" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const u = db.users.find(
        (x) => x.username === p.username && x.password === p.password,
      );
      if (!u) {
        log(req.method, pathname, 401);
        return sendJSON(
          res,
          { error: "用户名或密码错误！演示管理员账号: admin / adminpassword" },
          401,
        );
      }
      log(req.method, pathname, 200);
      return sendJSON(res, {
        success: true,
        token: `jwt-token-${u.id}`,
        user: u,
      });
    } catch (err) {
      return sendJSON(res, { error: "Invalid JSON" }, 400);
    }
  }

  // --- API 1: USER PROFILE & DASHBOARD ---
  if (pathname === "/api/user" && req.method === "GET") {
    const userId = parsedUrl.query.user_id || "u1";
    const u = db.users.find((x) => x.id === userId) || db.users[0];
    return sendJSON(res, u);
  }

  if (pathname === "/api/dashboard/heatmap" && req.method === "GET") {
    const userId = parsedUrl.query.user_id || "u1";
    const u = db.users.find((x) => x.id === userId) || db.users[0];
    const activeDays = db.practice_records.filter((r) => r.count > 0).length;
    const totalQ = db.practice_records.reduce((acc, cur) => acc + cur.count, 0);
    const totalMin = db.practice_records.reduce(
      (acc, cur) => acc + cur.minutes,
      0,
    );

    return sendJSON(res, {
      records: db.practice_records,
      total_active_days: activeDays,
      streak: u.streak,
      freeze_cards: u.freeze_cards,
      total_questions: totalQ,
      total_study_hours: (totalMin / 60).toFixed(1),
      companion_tree: u.companion_tree,
      token_quota: u.token_quota,
      token_used: u.token_used,
      tokens_remaining: Math.max(0, u.token_quota - u.token_used),
    });
  }

  // --- API 2: QUESTIONS & UPVOTES ---
  if (pathname === "/api/questions" && req.method === "GET") {
    const skillId = parsedUrl.query.skill_id;
    let questions = db.questions;
    if (skillId) questions = questions.filter((q) => q.skill_id === skillId);
    const sortedQuestions = questions.map((q) => ({
      ...q,
      solutions: [...q.solutions].sort(
        (a, b) => b.upvotes - b.downvotes - (a.upvotes - a.downvotes),
      ),
    }));
    return sendJSON(res, sortedQuestions);
  }

  if (
    pathname.startsWith("/api/solutions/") &&
    pathname.endsWith("/upvote") &&
    req.method === "POST"
  ) {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const action = p.action || "UPVOTE";
        const solutionId = pathname.split("/")[3];
        const u = db.users[0];

        for (const q of db.questions) {
          const sol = q.solutions.find((s) => s.id === solutionId);
          if (sol) {
            if (action === "UPVOTE") {
              sol.upvotes += 1;
              const teacherKey = Object.keys(u.teacher_affinity).find((k) =>
                sol.teacher_name.includes(k.split(" ")[0]),
              );
              if (teacherKey) u.teacher_affinity[teacherKey] += 5;
            } else {
              sol.downvotes += 1;
            }
            return sendJSON(res, {
              success: true,
              upvotes: sol.upvotes,
              downvotes: sol.downvotes,
            });
          }
        }
        return sendJSON(res, { error: "Solution not found" }, 404);
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // --- API 3: SKILLS RADAR & REMEDIATE ---
  if (pathname === "/api/skills/tree" && req.method === "GET") {
    return sendJSON(res, db.skill_tags);
  }

  if (pathname === "/api/skills/mastery" && req.method === "GET") {
    const MASTERY_SEED = {
      "s1-1-1": { ema: 94, time: 28 },
      "s1-1-2": { ema: 82, time: 34 },
      "s1-1-3": { ema: 54, time: 62 },
      "s1-2-1": { ema: 88, time: 30 },
      "s2-1-1": { ema: 86, time: 35 },
      "s2-1-2": { ema: 58, time: 48 },
      "s2-2-1": { ema: 78, time: 32 },
      "s3-1-1": { ema: 90, time: 25 },
    };
    const leafSkills = db.skill_tags.filter((s) => s.level === 3);
    const masteryData = leafSkills.map((sk) => {
      const seed = MASTERY_SEED[sk.id] || { ema: 75, time: 42 };
      const accuracyEma = seed.ema,
        avgTimeSec = seed.time;

      const comp = Math.min(
        100,
        Math.round(
          accuracyEma * 0.75 +
            Math.min(1.5, sk.benchmark_time_sec / avgTimeSec) * 25,
        ),
      );
      return {
        skill_id: sk.id,
        name: sk.name,
        parent_id: sk.parent_id,
        accuracy_ema: accuracyEma,
        avg_time_sec: avgTimeSec,
        benchmark_time_sec: sk.benchmark_time_sec,
        composite_score: comp,
        status: comp < 65 ? "WEAK" : comp >= 85 ? "EXCELLENT" : "GOOD",
      };
    });
    return sendJSON(res, masteryData);
  }

  if (pathname === "/api/skills/remediate" && req.method === "POST") {
    const weakQuestions = db.questions.filter((q) =>
      ["s1-1-3", "s2-1-2"].includes(q.skill_id),
    );
    return sendJSON(res, {
      success: true,
      message:
        "为您生成了针对【差分比较法】与【主题词同义替换】的 15 题红点短板特训组卷！",
      questions: weakQuestions,
    });
  }

  // --- API 4: COHORTS CHECK-IN ---
  if (pathname === "/api/cohorts" && req.method === "GET") {
    return sendJSON(res, db.cohorts);
  }

  if (
    pathname.startsWith("/api/cohorts/") &&
    pathname.endsWith("/checkin") &&
    req.method === "POST"
  ) {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const cohortId = pathname.split("/")[3];
        const cohort = db.cohorts.find((c) => c.id === cohortId);
        if (!cohort) return sendJSON(res, { error: "打卡营不存在" }, 404);
        const u = db.users[0];

        cohort.completed_today += 1;
        cohort.user_checkins_count += 1;
        u.streak += 1;
        u.companion_tree.status = "VIBRANT";
        u.companion_tree.last_watered_date = new Date()
          .toISOString()
          .split("T")[0];
        const sq = cohort.squad_members.find(
          (s) => s.name.includes("小王") || s.name.includes("我"),
        );
        if (sq) sq.today_done = true;

        return sendJSON(res, {
          success: true,
          message:
            p.proof_type === "AUTO"
              ? "🎉 系统自动校验：您今日站内做题已达标，打卡成功！神树能量+5！"
              : "🎉 凭证上传成功，死党互审通过！",
          user_checkins_count: cohort.user_checkins_count,
          pool_amount: cohort.pool_amount,
          new_streak: u.streak,
          squad_members: cohort.squad_members,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // --- API 5: STRATEGY FORKING ---
  if (pathname === "/api/strategies" && req.method === "GET") {
    return sendJSON(res, db.strategies);
  }

  if (
    pathname.startsWith("/api/strategies/") &&
    pathname.endsWith("/fork") &&
    req.method === "POST"
  ) {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const stratId = pathname.split("/")[3];
        const orig = db.strategies.find((s) => s.id === stratId);
        if (!orig) return sendJSON(res, { error: "攻略不存在" }, 404);

        const target = new Date(p.target_date || "2026-03-13");
        const diffDays = Math.max(
          15,
          Math.ceil((target - new Date("2026-07-24")) / (1000 * 3600 * 24)),
        );
        const ratio = diffDays / orig.days_total;
        const factor = Math.min(1.5, Math.max(0.7, 1 / ratio));
        const hours = parseFloat(p.daily_hours) || 3.0;

        const newTimeline = orig.timeline_data.map((item, idx) => ({
          ...item,
          daily_questions: Math.min(
            120,
            Math.round(item.daily_questions * factor),
          ),
          daily_hours: Math.min(
            6.0,
            Math.round(hours * (idx === 1 ? 1.2 : 1.0) * 10) / 10,
          ),
          custom_note: `⚡ 倒推重算：根据您剩余 ${diffDays} 天及日均 ${hours} 小时自动适配`,
        }));

        const newStrat = {
          id: `strat-fork-${Date.now()}`,
          author_name: db.users[0].username,
          author_avatar: db.users[0].avatar,
          title: `[定制派生自 ${orig.author_name}] ${orig.title} (${diffDays}天重算版)`,
          forked_count: 0,
          days_total: diffDays,
          timeline_data: newTimeline,
        };
        orig.forked_count += 1;
        db.strategies.unshift(newStrat);
        return sendJSON(res, {
          success: true,
          message: `🚀 一键 Fork 派生倒推成功！已为您重生成剩余 ${diffDays} 天专属路线图！`,
          strategy: newStrat,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // ==========================================
  // MODULE 6: ADMIN CONTROL & SETTINGS
  // ==========================================
  if (pathname === "/api/admin/settings" && req.method === "GET") {
    return sendJSON(res, {
      settings: db.system_settings,
      llm_config: db.llm_config,
      teachers: db.teacher_profiles,
      users: db.users,
    });
  }

  if (pathname === "/api/admin/settings" && req.method === "PUT") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        if (p.allow_registration !== undefined)
          db.system_settings.allow_registration = p.allow_registration;
        if (p.default_token_quota !== undefined)
          db.system_settings.default_token_quota = parseInt(
            p.default_token_quota,
          );
        return sendJSON(res, {
          success: true,
          message: "全局系统设置更新成功！",
          settings: db.system_settings,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  if (
    pathname.startsWith("/api/admin/users/") &&
    pathname.endsWith("/quota") &&
    req.method === "POST"
  ) {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const targetUserId = pathname.split("/")[4];
        const u = db.users.find(
          (x) => x.id === targetUserId || x.username === targetUserId,
        );
        if (!u) return sendJSON(res, { error: "用户不存在" }, 404);
        if (p.token_quota !== undefined)
          u.token_quota = parseInt(p.token_quota);
        if (p.token_used !== undefined) u.token_used = parseInt(p.token_used);
        return sendJSON(res, {
          success: true,
          message: `用户【${u.username}】AI Token 配额已调整为 ${u.token_quota.toLocaleString()}，已用 ${u.token_used.toLocaleString()}！`,
          user: u,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // ==========================================
  // MODULE 7 & 8: GITHUB SKILLS SYNC ENGINE
  // ==========================================
  if (pathname === "/api/admin/github-sync" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const repoUrl =
          p.repo_url || "https://github.com/jz8132543/kaogong-teacher-skills";
        // Simulate pulling latest skills from GitHub repo
        const syncedCount = db.teacher_skills.length + 3;
        db.teacher_skills.push({
          id: `tsk-${Date.now()}`,
          teacher_id: "t3",
          skill_id: "s2-1-1",
          skill_name: "欣说言语-关联词转折锚定技能",
          prompt_markdown:
            "当出现‘但’、‘然而’、‘不过’时，重点转折之后，转折前非重点直接忽略！",
          github_path: "skills/xin_shuo/turning_point.md",
        });
        return sendJSON(res, {
          success: true,
          message: `🚀 成功连接并拉取 GitHub 仓库 [${repoUrl}]！自动扫描更新了 ${syncedCount} 条名师 AI 提示词技能库！`,
          synced_count: syncedCount,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // ==========================================
  // MODULE 9: AI TRUE EXAM PDF INGESTION PIPELINE
  // ==========================================
  if (pathname === "/api/admin/ingest/pdf" && req.method === "POST") {
    // Simulate multipart upload and LLM extraction pipeline
    const newJob = {
      id: `job-${Date.now()}`,
      filename: `历年国考省考联考真题卷_${Math.floor(Math.random() * 1000)}.pdf`,
      admin_username: "admin",
      total_pages: 18,
      extracted_count: 45,
      status: "EXTRACTING",
      created_at: new Date().toISOString(),
    };
    db.pdf_ingest_jobs.unshift(newJob);

    // Asynchronously advance status through the 4 AI stages
    setTimeout(() => {
      newJob.status = "TAGGING";
    }, 2000);
    setTimeout(() => {
      newJob.status = "GENERATING_SOLUTIONS";
    }, 4000);
    setTimeout(() => {
      newJob.status = "COMPLETED";
      // Add a newly extracted question to db.questions
      db.questions.unshift({
        id: `q-ai-${Date.now()}`,
        content:
          "【AI 自动从真题 PDF 抽取清洗】2024年全国国内旅游出游人次为 54.83 亿，同比增长 12.8%。请问2024年全国国内旅游出游人次同比增加了约多少亿人次？",
        options: [
          { key: "A", text: "5.62 亿人次" },
          { key: "B", text: "6.22 亿人次" },
          { key: "C", text: "6.85 亿人次" },
          { key: "D", text: "7.10 亿人次" },
        ],
        correct_answer: "B",
        difficulty: 3,
        skill_id: "s1-1-1",
        solutions: [
          {
            id: `sol-ai-1-${Date.now()}`,
            teacher_name: "花生十三 (秒杀截位派)",
            approach_name: "截位直除增长量公式",
            content:
              "【AI 名师蒸馏】利用公式 现期量/(1+N)。12.8% 约为 1/7.8。54.83 / 8.8 ≈ 6.23 亿。选项 B 6.22 极其接近，12秒直出！",
            upvotes: 120,
            downvotes: 3,
            time_spent_eval: "12秒",
            is_ai_generated: true,
          },
          {
            id: `sol-ai-2-${Date.now()}`,
            teacher_name: "粉笔王老师 (拆分口算派)",
            approach_name: "10% 基准拆分估算",
            content:
              "【AI 名师蒸馏】54.83 的 10% = 5.48。2.8% 约为 1.53。5.48 + 0.74 ≈ 6.22 亿。直接对齐选项 B！",
            upvotes: 95,
            downvotes: 2,
            time_spent_eval: "20秒",
            is_ai_generated: true,
          },
        ],
      });
    }, 6000);

    return sendJSON(res, {
      success: true,
      message: `📑 真题 PDF 上传成功！系统已启动 4 阶段 AI 智能摄取流水线 (作业号: ${newJob.id})`,
      job: newJob,
    });
  }

  if (pathname === "/api/admin/ingest/jobs" && req.method === "GET") {
    return sendJSON(res, db.pdf_ingest_jobs);
  }

  // ==========================================
  // MODULE 10: AI RELAY DISCOVERY & STUDENT TUTOR
  // ==========================================
  if (pathname === "/api/admin/llm/discover-models" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const baseUrl = p.base_url || db.llm_config.base_url;
        const apiKey = p.api_key || db.llm_config.api_key;

        // Auto-discover available models. In demo/sandbox, we immediately return rich compatible models
        const discoveredModels = [
          "deepseek-r1 (推荐：超强逻辑思考)",
          "deepseek-v3 (极速秒答)",
          "gpt-4o",
          "gpt-4o-mini",
          "qwen-max (阿里云百炼)",
          "claude-3-5-sonnet",
        ];
        db.llm_config.base_url = baseUrl;
        db.llm_config.api_key = apiKey;
        db.llm_config.available_models = discoveredModels;

        return sendJSON(res, {
          success: true,
          message: `🌐 成功连接至 AI 中转站 [${baseUrl}]！自动识别出 ${discoveredModels.length} 个可用模型！`,
          models: discoveredModels,
          llm_config: db.llm_config,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  if (pathname === "/api/admin/llm/config" && req.method === "PUT") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        if (p.active_model) db.llm_config.active_model = p.active_model;
        if (p.base_url) db.llm_config.base_url = p.base_url;
        return sendJSON(res, {
          success: true,
          message: `✅ 全局默认 AI 引擎已切换至：${db.llm_config.active_model}`,
          llm_config: db.llm_config,
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // STUDENT INTERACTIVE AI TUTOR (WITH TOKEN QUOTA CHECK)
  if (pathname === "/api/ai/ask" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const userId = p.user_id || "u1";
        const u = db.users.find((x) => x.id === userId) || db.users[0];

        // STRICT TOKEN QUOTA ENFORCEMENT
        if (u.token_used >= u.token_quota) {
          return sendJSON(
            res,
            {
              error: `🚨 AI 提问阻断 (HTTP 402)：您的 Token 配额已耗尽 (${u.token_used}/${u.token_quota})！请在管理员后台为该账号充值或利用契约积分兑换！`,
              quota_exceeded: true,
              token_used: u.token_used,
              token_quota: u.token_quota,
            },
            402,
          );
        }

        const teacherName = p.teacher_name || "花生十三";
        const userPrompt = p.prompt || "老师请指点一下这道题！";
        const qId = p.question_id;
        const targetQ =
          db.questions.find((q) => q.id === qId) || db.questions[0];

        // Simulate token consumption (~380 tokens per round trip)
        const tokensConsumed = Math.floor(Math.random() * 120) + 320;
        u.token_used += tokensConsumed;

        let teacherReply = "";
        if (teacherName.includes("花生十三") || teacherName.includes("秒杀")) {
          teacherReply = `【花生十三老师 AI 分身答疑】同学你好！你在“${targetQ.content.slice(0, 15)}...”这题遇到的疑惑问到点子上了！记住我课上反复讲的：**左两位截位法则**！你看这题选项差距大于10%，千万不可死算竖式！直接把分母留前两位，15秒就能排掉干扰项 A 和 C！你刚才错在截得太细浪费了考场黄金时间，再练两组就通了！`;
        } else if (
          teacherName.includes("粉笔王") ||
          teacherName.includes("拆分")
        ) {
          teacherReply = `【粉笔王老师 AI 分身答疑】同学别急，我们来心算拆解！把百分比按 10%、1% 进行叠加，脑海里平移小数点就行。步骤其实挺踏实，稳住心态绝对能拿分！`;
        } else {
          teacherReply = `【${teacherName} AI 分身答疑】关于你的提问：“${userPrompt}”，从文段脉络或逻辑关联词来看，核心技巧在主题词排异。抓住中心句，秒排无关选项！`;
        }

        return sendJSON(res, {
          success: true,
          answer: teacherReply,
          model_used: db.llm_config.active_model,
          tokens_consumed: tokensConsumed,
          token_used: u.token_used,
          token_quota: u.token_quota,
          tokens_remaining: Math.max(0, u.token_quota - u.token_used),
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // --- STATIC FILE RENDERING LAYER ---
  let filePath = path.join(
    PUBLIC_DIR,
    pathname === "/" ? "index.html" : pathname,
  );
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    return res.end("Forbidden");
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) filePath = path.join(PUBLIC_DIR, "index.html");
    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || "application/octet-stream";

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500);
        res.end("Server Error");
      } else {
        res.writeHead(200, {
          "Content-Type": contentType,
          "Cache-Control": "public, max-age=3600",
        });
        res.end(content);
      }
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(
    `========================================================================`,
  );
  console.log(`🚀 考公备考辅助系统 (Kaogong Helper v3.0 旗舰版) 后端引擎启动`);
  console.log(`🌐 监听地址: http://${HOST}:${PORT}`);
  console.log(`👑 管理员账号: admin / adminpassword | 注册管控: 开放中`);
  console.log(
    `🤖 AI 中转站接入: ${db.llm_config.active_model} | Token 配额计费生效中`,
  );
  console.log(
    `========================================================================`,
  );
});
