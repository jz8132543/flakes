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
      vip_tier: "PRO",
      vip_expire_at: "2026-08-20",
      escrow_balance: 99.0,
      career_level: 4,
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
      paper_id: "2025-GUOKAO-XINGCE",
      module: "资料分析",
      skill_tag: "截位直除法",
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
          approach_name: "公式精确求解法 (基础通解)",
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
      paper_id: "2025-GUOKAO-XINGCE",
      module: "言语理解",
      skill_tag: "转折锚定法",
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
          approach_name: "转折关联词与因果递推 (基础通解)",
          content:
            "【脉络分析】横线在文段末尾，起总结说明作用。前面通过“但在现代都市圈”进行转折，强调正向逆转，A选项直接对应“观念逆转”的社会意义，承接最为紧密！",
          upvotes: 512,
          downvotes: 18,
          time_spent_eval: "22秒",
        },
        {
          id: "sol-5",
          teacher_name: "郭熙老师 (主题词秒做派)",
          approach_name: "核心主题词排异法 (名师大招)",
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
      paper_id: "2024-GUOKAO-XINGCE",
      module: "资料分析",
      skill_tag: "概念辨析法",
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
          id: "sol-6a",
          teacher_name: "常规教研组 (学院派通解)",
          approach_name: "概念定义对照法 (基础通解)",
          content:
            "【基础概念】现期比重 42.5%，基期比重 45.0%。比重差值 = 42.5% - 45.0% = -2.5%。在统计学中，两个百分比相减的结果必须用“百分点”来表述，因此是下降了 2.5 个百分点。",
          upvotes: 310,
          downvotes: 12,
          time_spent_eval: "30秒",
        },
        {
          id: "sol-6",
          teacher_name: "花生十三 (秒杀截位派)",
          approach_name: "概念辨析与直接减法秒杀 (名师大招)",
          content:
            "【避坑指南】问的是“百分点”还是“百分比”！比重差值必须用百分点表示，排除 C！直接拿 42.5% - 45.0% = -2.5 个百分点，即下降了 2.5 个百分点。千万别去算复杂除法！",
          upvotes: 750,
          downvotes: 10,
          time_spent_eval: "10秒",
        },
      ],
    },
    {
      id: "q104",
      paper_id: "2025-SHENGKAO-XINGCE",
      module: "判断推理",
      skill_tag: "对称性规律",
      content:
        "把下面的六个图形分为两类，使每一类图形都有各自的共同特征或规律，分类正确的一项是：(1)有中心对称轴 (2)轴对称图形 (3)仅中心对称...",
      options: [
        { key: "A", text: "①②③，④⑤⑥" },
        { key: "B", text: "①③⑤，②④⑥" },
        { key: "C", text: "①②④，③⑤⑥" },
        { key: "D", text: "①④⑤，②③⑥" },
      ],
      correct_answer: "C",
      difficulty: 3,
      skill_id: "s3-1-1",
      solutions: [
        {
          id: "sol-7",
          teacher_name: "聂佳老师 (逻辑图推派)",
          approach_name: "奇偶对称轴计数法 (基础通解)",
          content:
            "【规律拆解】通过连接各个图形的最远相对顶点，可以发现①②④图形存在至少两条正交对称轴，属于既是轴对称又是中心对称图形；③⑤⑥仅存在一条单向对称轴，仅属于轴对称。故选 C。",
          upvotes: 420,
          downvotes: 8,
          time_spent_eval: "35秒",
        },
        {
          id: "sol-8",
          teacher_name: "花生十三 (秒杀截位派)",
          approach_name: "旋转 180 度视觉检验法 (名师大招)",
          content:
            "【极速反转】在试卷上将图形旋转 180 度！图形看起来跟原来完全一样的就是中心对称（①②④），变了样子的就不是（③⑤⑥）！无需画线，5秒分类！",
          upvotes: 920,
          downvotes: 5,
          time_spent_eval: "8秒",
        },
      ],
    },
    {
      id: "q105",
      paper_id: "2025-GUOKAO-XINGCE",
      module: "数量关系",
      skill_tag: "工程赋值法",
      content:
        "一项修路工程，甲工程队单独做需要 15 天完成，乙工程队单独做需要 10 天完成。两队合做 4 天后，剩下的工程由甲队单独完成，还需多少天？",
      options: [
        { key: "A", text: "3 天" },
        { key: "B", text: "5 天" },
        { key: "C", text: "6 天" },
        { key: "D", text: "7.5 天" },
      ],
      correct_answer: "B",
      difficulty: 3,
      skill_id: "s4-1-1",
      solutions: [
        {
          id: "sol-9",
          teacher_name: "张三老师 (方程正统派)",
          approach_name: "分式通分列方程法 (基础通解)",
          content:
            "【设总量为1】甲效率为 1/15，乙效率为 1/10。合作效率 = 1/15 + 1/10 = 1/6。合作4天完成 4/6 = 2/3，剩余 1/3。剩余工程甲耗时 = (1/3) ÷ (1/15) = 5 天。",
          upvotes: 380,
          downvotes: 22,
          time_spent_eval: "45秒",
        },
        {
          id: "sol-10",
          teacher_name: "粉笔王老师 (拆分口算派)",
          approach_name: "公倍数赋总量秒杀法 (名师大招)",
          content:
            "【赋公倍数 30】设工程总量为 15 和 10 的最小公倍数 30！则甲每天干 2，乙每天干 3。合作每天干 5。4天干了 20，还剩 10。剩下的给甲做，10 ÷ 2 = 5 天！绝不产生分数，口算即出！",
          upvotes: 880,
          downvotes: 9,
          time_spent_eval: "15秒",
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
    {
      id: "c2",
      title: "⚡ 14天申论大作文名师精批与金句晨读契约营 (第 8 期)",
      deposit_amount: 149.0,
      start_date: "2026-08-01",
      end_date: "2026-08-14",
      total_members: 86,
      completed_today: 0,
      pool_amount: 12814.0,
      user_joined: false,
      user_status: "UNJOINED",
      user_checkins_count: 0,
      squad_members: [
        { name: "备考达人小张", streak: 0, today_done: false },
        { name: "申论小能手", streak: 0, today_done: false },
        { name: "追梦人阿辉", streak: 0, today_done: false },
        { name: "奋战2026小陈", streak: 0, today_done: false },
      ],
    },
    {
      id: "c3",
      title: "🎯 30天国考行测+申论全科巅峰打卡对赌营 (旗舰期)",
      deposit_amount: 299.0,
      start_date: "2026-08-05",
      end_date: "2026-09-04",
      total_members: 210,
      completed_today: 0,
      pool_amount: 62790.0,
      user_joined: false,
      user_status: "UNJOINED",
      user_checkins_count: 0,
      squad_members: [
        { name: "清北学长小刘", streak: 0, today_done: false },
        { name: "全职冲刺老孙", streak: 0, today_done: false },
        { name: "学霸小吴", streak: 0, today_done: false },
        { name: "早起鸟阿健", streak: 0, today_done: false },
      ],
    }
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
    {
      id: "strat-102",
      author_name: "在职岸上达人老李 (部委在职状元)",
      author_avatar: "👔",
      title: "90天在职考公时间碎片利用与极速拿分路线图",
      forked_count: 512,
      days_total: 90,
      timeline_data: [
        {
          phase: "碎片化知识搭建期 (Day 1 - Day 30)",
          daily_questions: 30,
          daily_hours: 2.0,
          focus: "利用通勤与午休专注刷时政雷达与常识判断",
          recommended_teacher: "李梦娇 / 花生十三",
        },
        {
          phase: "重点模块暴击期 (Day 31 - Day 60)",
          daily_questions: 60,
          daily_hours: 3.0,
          focus: "晚间沉浸式突破资料分析与判断推理（保底85%正确率）",
          recommended_teacher: "粉笔龙飞 / 花生十三",
        },
        {
          phase: "周末真题演练期 (Day 61 - Day 90)",
          daily_questions: 130,
          daily_hours: 4.0,
          focus: "每周末全真模拟考试与名师切片大招复盘",
          recommended_teacher: "郭熙老师",
        },
      ],
    },
    {
      id: "strat-103",
      author_name: "数理名师王老师 (前命题组成员)",
      author_avatar: "👑",
      title: "30天理科零基础攻克资料分析与数量关系必拿40分秘籍",
      forked_count: 760,
      days_total: 30,
      timeline_data: [
        {
          phase: "数字特征速判期 (Day 1 - Day 10)",
          daily_questions: 50,
          daily_hours: 3.0,
          focus: "熟背百分数互化表、截位直除与首位极速判断法则",
          recommended_teacher: "花生十三",
        },
        {
          phase: "模型思维定型期 (Day 11 - Day 20)",
          daily_questions: 70,
          daily_hours: 3.5,
          focus: "牛吃草模型、工程合作赋值与经济利润秒杀技巧",
          recommended_teacher: "齐麟老师 / 花生十三",
        },
        {
          phase: "百题极速排雷期 (Day 21 - Day 30)",
          daily_questions: 100,
          daily_hours: 4.0,
          focus: "限时35分钟做完40道理科题，挑战100%正确率",
          recommended_teacher: "花生十三 / 齐麟老师",
        },
      ],
    }
  ],
  orders: [
    {
      order_id: "ORD_INIT_101",
      user_id: "u1",
      package_id: "PRO_MONTHLY",
      amount: 68.0,
      status: "SUCCESS",
      idempotency_key: "IDEM_INIT_101",
      created_at: "2026-07-20T10:00:00Z"
    }
  ],
  token_ledgers: [
    {
      id: "TL_INIT_101",
      user_id: "u1",
      type: "RECHARGE",
      amount: 50000,
      balance_after: 50000,
      description: "开通冲刺 Pro 会员赠送算力",
      created_at: "2026-07-20T10:00:00Z"
    },
    {
      id: "TL_INIT_102",
      user_id: "u1",
      type: "CONSUME",
      amount: -12500,
      balance_after: 37500,
      description: "AI 助教名师答疑消耗 (累计)",
      created_at: "2026-07-24T18:30:00Z"
    },
    {
      id: "TL_INIT_103",
      user_id: "u1",
      type: "REWARD",
      amount: 5000,
      balance_after: 42500,
      description: "上周契约全勤对赌算力分红奖励",
      created_at: "2026-07-25T08:00:00Z"
    }
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
        vip_tier: "FREE",
        vip_expire_at: null,
        escrow_balance: 0.0,
        career_level: 1,
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

  if (pathname === "/api/user/profile" && req.method === "PUT") {
    try {
      const p = await parseBody(req);
      const userId = p.user_id || "u1";
      const u = db.users.find((x) => x.id === userId) || db.users[0];
      if (p.username) u.username = p.username;
      if (p.avatar) u.avatar = p.avatar;
      if (p.exam_target) u.exam_target = p.exam_target;
      if (p.target_date) u.target_date = p.target_date;
      log(req.method, pathname, 200);
      return sendJSON(res, { success: true, user: u });
    } catch (err) {
      return sendJSON(res, { error: "Invalid JSON" }, 400);
    }
  }

  if (pathname === "/api/user/ledgers" && req.method === "GET") {
    const userId = parsedUrl.query.user_id || "u1";
    const userOrders = (db.orders || []).filter((o) => o.user_id === userId);
    const userTokens = (db.token_ledgers || []).filter((t) => t.user_id === userId);
    return sendJSON(res, { orders: userOrders, token_ledgers: userTokens });
  }

  if (pathname === "/api/billing/create-order" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const userId = p.user_id || "u1";
      const packageId = p.package_id || "PRO_MONTHLY";
      let amount = 68.0;
      if (packageId === "VIP_YEARLY") amount = 499.0;
      if (packageId === "ESCROW_DEPOSIT") amount = 99.0;
      if (packageId === "TOKEN_PACK_50K") amount = 29.0;

      const order = {
        order_id: `ORD_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
        user_id: userId,
        package_id: packageId,
        amount: amount,
        status: "PENDING",
        idempotency_key: p.idempotency_key || `IDEM_${Date.now()}`,
        created_at: new Date().toISOString()
      };
      if (!db.orders) db.orders = [];
      db.orders.unshift(order);
      log(req.method, pathname, 200);
      return sendJSON(res, { success: true, order });
    } catch (err) {
      return sendJSON(res, { error: "Failed to create order" }, 500);
    }
  }

  if (pathname === "/api/billing/webhook" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const idempotencyKey = p.idempotency_key || p.order_id;
      if (!db.orders) db.orders = [];
      const existingOrder = db.orders.find((o) => o.idempotency_key === idempotencyKey || o.order_id === p.order_id);
      
      const userId = p.user_id || (existingOrder ? existingOrder.user_id : "u1");
      const u = db.users.find((x) => x.id === userId) || db.users[0];
      const pkg = p.package_id || (existingOrder ? existingOrder.package_id : "PRO_MONTHLY");

      if (existingOrder && existingOrder.status === "SUCCESS") {
        return sendJSON(res, { success: true, message: "Idempotent callback ignored (already processed)", user: u });
      }

      if (existingOrder) existingOrder.status = "SUCCESS";
      else {
        db.orders.unshift({
          order_id: p.order_id || `ORD_${Date.now()}`,
          user_id: userId,
          package_id: pkg,
          amount: p.amount || 68.0,
          status: "SUCCESS",
          idempotency_key: idempotencyKey,
          created_at: new Date().toISOString()
        });
      }

      if (!db.token_ledgers) db.token_ledgers = [];

      if (pkg === "PRO_MONTHLY") {
        u.vip_tier = "PRO";
        u.vip_expire_at = "2026-08-30";
        u.token_quota += 50000;
        db.token_ledgers.unshift({
          id: `TL_${Date.now()}`,
          user_id: u.id,
          type: "RECHARGE",
          amount: 50000,
          balance_after: u.token_quota - u.token_used,
          description: "购买冲刺 Pro 月度会员充值赠送",
          created_at: new Date().toISOString()
        });
      } else if (pkg === "VIP_YEARLY") {
        u.vip_tier = "VIP";
        u.vip_expire_at = "2027-08-30";
        u.token_quota += 300000;
        db.token_ledgers.unshift({
          id: `TL_${Date.now()}`,
          user_id: u.id,
          type: "RECHARGE",
          amount: 300000,
          balance_after: u.token_quota - u.token_used,
          description: "开通对赌私教年度 VIP 充值赠送",
          created_at: new Date().toISOString()
        });
      } else if (pkg === "ESCROW_DEPOSIT") {
        u.escrow_balance = (u.escrow_balance || 0) + 99.0;
      } else if (pkg === "TOKEN_PACK_50K") {
        u.token_quota += 50000;
        db.token_ledgers.unshift({
          id: `TL_${Date.now()}`,
          user_id: u.id,
          type: "RECHARGE",
          amount: 50000,
          balance_after: u.token_quota - u.token_used,
          description: "购买 50,000 算力加油包",
          created_at: new Date().toISOString()
        });
      }

      log(req.method, pathname, 200);
      return sendJSON(res, { success: true, user: u });
    } catch (err) {
      return sendJSON(res, { error: "Webhook processing failed" }, 500);
    }
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
      career_level: u.career_level || 4,
      beat_percentage: 94.5,
      focus_efficiency: "高能专注 (相当于省下线下机构￥3,200.00智商税)"
    });
  }

  // --- CAREER PATH GAMIFICATION ENDPOINTS ---
  const CAREER_TITLES = [
    { level: 1, title: "备考小白", req_questions: 0, req_streak: 0, doc_text: "起步备考，立志成才，特任为备考小白。" },
    { level: 2, title: "实习科员", req_questions: 50, req_streak: 3, doc_text: "勤勉刷题，初现锋芒，兹任命为实习科员。" },
    { level: 3, title: "四级主任科员", req_questions: 200, req_streak: 7, doc_text: "基础扎实，行测稳步提升，晋升为四级主任科员。" },
    { level: 4, title: "副科长", req_questions: 500, req_streak: 14, doc_text: "独当一面，秒杀截位了然于胸，破格提拔为副科长。" },
    { level: 5, title: "处长", req_questions: 1000, req_streak: 21, doc_text: "运筹帷幄，申论妙笔生花，特任为处长。" },
    { level: 6, title: "厅局级顶梁柱", req_questions: 2000, req_streak: 30, doc_text: "登峰造极，成竹在胸，荣升为厅局级顶梁柱！" }
  ];

  if (pathname === "/api/user/career" && req.method === "GET") {
    const userId = parsedUrl.query.user_id || "u1";
    const user = db.users.find((x) => x.id === userId) || db.users[0];
    const currentTitle = CAREER_TITLES.find(t => t.level === (user.career_level || 1)) || CAREER_TITLES[0];
    const nextTitle = CAREER_TITLES.find(t => t.level === (user.career_level || 1) + 1) || null;
    return sendJSON(res, {
      success: true,
      user_id: user.id,
      current_level: currentTitle.level,
      current_title: currentTitle.title,
      red_header_doc: currentTitle.doc_text,
      next_title: nextTitle ? nextTitle.title : "已达巅峰",
      progress: nextTitle ? {
        questions_current: user.total_questions || 0,
        questions_required: nextTitle.req_questions,
        streak_current: user.streak || 0,
        streak_required: nextTitle.req_streak
      } : null
    });
  }

  if (pathname === "/api/user/career/promote" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const userId = p.user_id || "u1";
        const user = db.users.find((x) => x.id === userId) || db.users[0];
        const nextTitle = CAREER_TITLES.find(t => t.level === (user.career_level || 1) + 1);
        if (!nextTitle || user.total_questions < nextTitle.req_questions || user.streak < nextTitle.req_streak) {
          return sendJSON(res, { success: false, message: "尚未达到晋升条件！再接再厉！" }, 400);
        }
        user.career_level = nextTitle.level;
        return sendJSON(res, {
          success: true,
          new_level: nextTitle.level,
          new_title: nextTitle.title,
          red_header_doc: `【中共考公备考辅助系统委员会任免决定】\n鉴于学员在近期的高强度模考与打卡中表现优异，刷题数突破 ${user.total_questions} 题，连续打卡达 ${user.streak} 天，特发此红头文件：${nextTitle.doc_text}`
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  if (pathname === "/api/user/tree/water" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const userId = p.user_id || "u1";
      const u = db.users.find((x) => x.id === userId) || db.users[0];
      if (u.token_used + 50 > u.token_quota) {
        return sendJSON(res, { error: "Token 算力不足，无法浇水！请前往设置中心充值加油包！" }, 400);
      }
      u.token_used += 50;
      u.companion_tree.status = "VIBRANT";
      u.companion_tree.last_watered_date = new Date().toISOString().split("T")[0];
      u.companion_tree.level = Math.min(5, (u.companion_tree.level || 1) + 1);
      const stages = [
        "🌱 刚萌芽 - 开始做题积累能量",
        "🌿 茁壮成长 - 每日必刷基础已夯实",
        "🌲 枝繁叶茂 - 距离开花结果 (上岸) 仅一步之遥",
        "🌸 繁花似锦 - 模考排名前列，上岸稳券在握",
        "🍎 结出金苹果 - 恭喜您已被心仪报考单位正式录用！"
      ];
      u.companion_tree.stage = stages[Math.min(4, u.companion_tree.level - 1)];
      u.companion_tree.name = `上岸神树 (能量值 ${Math.min(100, u.companion_tree.level * 20)}/100)`;
      log(req.method, pathname, 200);
      return sendJSON(res, { success: true, companion_tree: u.companion_tree, token_used: u.token_used });
    } catch (err) {
      return sendJSON(res, { error: "Tree watering failed" }, 500);
    }
  }

  // --- MONSTER SLAYING RAID ENDPOINTS ---
  let slayedBossesLog = [];
  if (pathname === "/api/raid/bosses" && req.method === "GET") {
    const bosses = [
      { boss_id: "boss_1", skill_name: "言语理解-成语辨析", hp: 45, max_hp: 100, difficulty: "⭐⭐⭐⭐", desc: "常年混淆近义成语，干扰选项判断" },
      { boss_id: "boss_2", skill_name: "数量关系-排列组合", hp: 60, max_hp: 100, difficulty: "⭐⭐⭐⭐⭐", desc: "畏惧复杂的概率计算与分步分类" }
    ];
    return sendJSON(res, { success: true, bosses, slayed_count: slayedBossesLog.length, slayed_log: slayedBossesLog });
  }

  if (pathname === "/api/raid/attack" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const testScore = parseInt(p.test_score) || 85;
        const bossId = p.boss_id || "boss_1";
        if (testScore < 80) {
          return sendJSON(res, { success: false, damage: testScore, message: "伤害不足以击碎心魔！强化卷正确率需达 80% 以上！" });
        }
        slayedBossesLog.push({ boss_id: bossId, slayed_at: new Date().toISOString(), score: testScore });
        return sendJSON(res, {
          success: true,
          crit_kill: true,
          message: "💥 暴击！一击必杀！你顺利攻克了该专项心魔，斩获【除魔斩妖】荣誉勋章！",
          slayed_total: slayedBossesLog.length
        });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // --- KNOWLEDGE GACHA & TIME CAPSULE ENDPOINTS ---
  const GACHA_POOL = [
    { type: "quote", title: "申论金句卡", content: "“追风赶月莫停留，平芜尽处是春山。” — 申论大作文结尾升华必备佳句。" },
    { type: "tip", title: "花生十三秒杀秘籍", content: "截位直算时，看选项差距，差距在10%以上直接大胆截前两位，绝不犹豫！" },
    { type: "token", title: "AI Token 福利卷", content: "恭喜抽中 500 AI 问答 Tokens，已自动计入您的账户余额中！", tokens: 500 }
  ];

  let timeCapsules = [
    { id: "tc1", author: "上岸科员_小张 (2025年上岸)", content: "行测遇到数量关系不要慌，先做资料分析和言语，把该拿的分拿满就是胜利！", likes: 128 },
    { id: "tc2", author: "厅局级_老李", content: "申论关键在于听懂题干的言外之意，每一句要点都藏在给定资料的关键词里。", likes: 256 }
  ];

  if (pathname === "/api/gacha/draw" && req.method === "POST") {
    const reward = GACHA_POOL[Math.floor(Math.random() * GACHA_POOL.length)];
    if (reward.tokens && db.users[0]) {
      db.users[0].token_quota = (db.users[0].token_quota || 50000) + reward.tokens;
    }
    return sendJSON(res, { success: true, reward });
  }

  if (pathname === "/api/time-capsule/letters" && req.method === "GET") {
    return sendJSON(res, { success: true, letters: timeCapsules });
  }

  if (pathname === "/api/time-capsule/send" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const newLetter = { id: `tc_${Date.now()}`, author: p.author || "未来的科员", content: p.content || "加油！必胜！", likes: 1 };
        timeCapsules.unshift(newLetter);
        return sendJSON(res, { success: true, letter: newLetter });
      } catch (err) {
        return sendJSON(res, { error: "Invalid JSON" }, 400);
      }
    });
    return;
  }

  // --- API 2: QUESTIONS & UPVOTES ---
  // --- API 2: QUESTIONS, PRACTICE & DISTILLED SOLUTIONS ---
  if ((pathname === "/api/questions" || pathname === "/api/solutions/distilled") && req.method === "GET") {
    const skillId = parsedUrl.query.skill_id;
    const moduleId = parsedUrl.query.module;
    const u = db.users[0];
    const isVip = u.vip_tier === "PRO" || u.vip_tier === "VIP" || u.token_quota >= 50000;
    let questions = db.questions;
    if (skillId) questions = questions.filter((q) => q.skill_id === skillId || q.skill_tag === skillId);
    if (moduleId) questions = questions.filter((q) => q.module === moduleId);
    
    const sortedQuestions = questions.map((q) => {
      const sortedSols = [...q.solutions].sort((a, b) => {
        const affA = Object.keys(u.teacher_affinity).find(k => a.teacher_name.includes(k.split(" ")[0])) ? u.teacher_affinity[Object.keys(u.teacher_affinity).find(k => a.teacher_name.includes(k.split(" ")[0]))] : 0;
        const affB = Object.keys(u.teacher_affinity).find(k => b.teacher_name.includes(k.split(" ")[0])) ? u.teacher_affinity[Object.keys(u.teacher_affinity).find(k => b.teacher_name.includes(k.split(" ")[0]))] : 0;
        if (affB !== affA) return affB - affA;
        return (b.upvotes - b.downvotes) - (a.upvotes - a.downvotes);
      });
      return {
        ...q,
        solutions: sortedSols.map((s, idx) => {
          if (!isVip && idx > 0) {
            return {
              ...s,
              locked: true,
              content: "🔒 【名师独家绝杀切片付费墙】该解法由原命题组名师独家研发，可有效节省 80% 答题时间！您当前为普通会员，请立即升级至 Pro 或 VIP 旗舰会员，解锁全库 128 招高频秒杀技巧！"
            };
          }
          return { ...s, locked: false };
        })
      };
    });
    return sendJSON(res, sortedQuestions);
  }

  if (pathname === "/api/practice/start" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const mode = p.mode || "FULL_PAPER"; // FULL_PAPER | MODULE | SKILL_TAG
      const targetId = p.target_id || "2025-GUOKAO-XINGCE";
      let questions = [...db.questions];
      if (mode === "FULL_PAPER") {
        questions = questions.filter(q => q.paper_id === targetId || !targetId || targetId === "ALL");
      } else if (mode === "MODULE") {
        questions = questions.filter(q => q.module === targetId);
      } else if (mode === "SKILL_TAG") {
        questions = questions.filter(q => q.skill_tag === targetId || q.skill_id === targetId);
      }
      if (questions.length === 0) questions = db.questions;
      return sendJSON(res, {
        success: true,
        session_id: `SESS_${Date.now()}`,
        mode,
        target_id: targetId,
        duration_minutes: mode === "FULL_PAPER" ? 120 : 15,
        questions: questions.map(q => ({
          id: q.id,
          content: q.content,
          options: q.options,
          module: q.module || "资料分析",
          skill_tag: q.skill_tag || "截位直除法",
          difficulty: q.difficulty
        }))
      });
    } catch (err) {
      return sendJSON(res, { error: "Failed to start practice" }, 500);
    }
  }

  if (pathname === "/api/practice/submit" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const answers = p.answers || {};
      let correctCount = 0;
      const totalCount = Object.keys(answers).length || db.questions.length;
      db.questions.forEach(q => {
        if (answers[q.id] === q.correct_answer) correctCount++;
      });
      const score = Math.round((correctCount / Math.max(1, totalCount)) * 100);
      const u = db.users[0];
      u.questions_done = (u.questions_done || 0) + totalCount;
      return sendJSON(res, {
        success: true,
        score,
        correct_count: correctCount,
        total_count: totalCount,
        beat_percentage: Math.min(99.8, (score * 0.9 + 15).toFixed(1)),
        radar_metrics: {
          言语理解: Math.min(100, score + 5),
          资料分析: Math.min(100, score + 10),
          判断推理: Math.min(100, score - 5),
          数量关系: Math.min(100, score - 10),
          常识判断: score
        }
      });
    } catch (err) {
      return sendJSON(res, { error: "Failed to submit practice" }, 500);
    }
  }

  if (pathname === "/api/solutions/vote" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const solutionId = p.solution_id || p.id;
      const u = db.users[0];
      for (const q of db.questions) {
        const sol = q.solutions.find((s) => s.id === solutionId);
        if (sol) {
          sol.upvotes += 1;
          const teacherKey = Object.keys(u.teacher_affinity).find((k) =>
            sol.teacher_name.includes(k.split(" ")[0]),
          );
          if (teacherKey) u.teacher_affinity[teacherKey] += 5;
          return sendJSON(res, { success: true, upvotes: sol.upvotes, teacher_affinity: u.teacher_affinity });
        }
      }
      return sendJSON(res, { error: "Solution not found" }, 404);
    } catch (err) {
      return sendJSON(res, { error: "Vote failed" }, 500);
    }
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

  if (pathname === "/api/mistakes/tree" && req.method === "GET") {
    const u = db.users[0];
    const weakSkills = [
      {
        skill_id: "s1-1-3",
        name: "差分截位比较法 (资料分析)",
        error_count: 12,
        accuracy: 35.0,
        prescription: "💡 药方：考场心态急躁，对口诀‘一大一小看竖直，同大同小看倍数’应用生疏。已为您关联【花生十三·3秒差分秒杀切片课】！",
        remediate_ready: true
      },
      {
        skill_id: "s2-1-2",
        name: "转折后主旨归纳 (言语理解)",
        error_count: 8,
        accuracy: 48.0,
        prescription: "💡 药方：易被干扰项中的‘无中生有’词误导。建议练习主题词排异与中心转折句锚定法则！",
        remediate_ready: true
      },
      {
        skill_id: "s3-2-1",
        name: "六面体向位展开 (图形推理)",
        error_count: 5,
        accuracy: 60.0,
        prescription: "💡 药方：立体想象旋转容易失误，强烈建议采用‘公共边时针法’和‘相对面相交排除法’！",
        remediate_ready: true
      },
      {
        skill_id: "s4-1-1",
        name: "工程经济赋值法 (数量关系)",
        error_count: 7,
        accuracy: 42.0,
        prescription: "💡 药方：对总量赋值与效率赋常数区分不清，已推送《30题齐麟量化模型极速手册》！",
        remediate_ready: false
      }
    ];
    return sendJSON(res, { success: true, user_id: u.id, total_mistakes: 32, tree: weakSkills });
  }

  if (pathname === "/api/mistakes/remediate" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const skillId = p.skill_id;
      const filtered = skillId ? db.questions.filter(q => q.skill_id === skillId) : db.questions;
      const targetQuestions = filtered.length > 0 ? filtered : db.questions.slice(0, 5);
      return sendJSON(res, {
        success: true,
        message: `🎯 智能病历消盲组卷成功！已抽取 ${targetQuestions.length} 道针对性靶向变式错题，立即进入模考引擎进行特训！`,
        questions: targetQuestions
      });
    } catch (err) {
      return sendJSON(res, { error: "Remediate failed" }, 500);
    }
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

  if (pathname === "/api/cohorts/join" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const cohortId = p.cohort_id || p.id;
      const cohort = db.cohorts.find(c => c.id === cohortId);
      if (!cohort) return sendJSON(res, { error: "契约营不存在" }, 404);
      if (cohort.user_joined) return sendJSON(res, { error: "您已加入该督学对赌营，请勿重复加入！" }, 400);

      const u = db.users[0];
      if ((u.cash_balance || 0) < cohort.deposit_amount) {
        return sendJSON(res, { error: `账户现金余额不足 (需要 ￥${cohort.deposit_amount})，请前往设置中心充值！`, code: "INSUFFICIENT_FUNDS" }, 403);
      }

      u.cash_balance -= cohort.deposit_amount;
      cohort.user_joined = true;
      cohort.user_status = "ACTIVE";
      cohort.total_members += 1;
      cohort.pool_amount += cohort.deposit_amount;
      
      const ledgerId = `LED_COH_${Date.now()}`;
      if (!db.cash_ledgers) db.cash_ledgers = [];
      db.cash_ledgers.unshift({
        id: ledgerId,
        user_id: u.id,
        type: "ESCROW_DEPOSIT",
        amount: -cohort.deposit_amount,
        balance_after: u.cash_balance,
        description: `加入契约反学费营对赌押金：${cohort.title}`,
        created_at: new Date().toISOString()
      });

      return sendJSON(res, { success: true, message: `🎉 成功契约入营！已锁入押金 ￥${cohort.deposit_amount}，契约奖金池升至 ￥${cohort.pool_amount}`, user: u, cohort });
    } catch (err) {
      return sendJSON(res, { error: "Join failed" }, 500);
    }
  }

  if (pathname === "/api/cohorts/settle" && req.method === "POST") {
    try {
      const p = await parseBody(req);
      const cohortId = p.cohort_id || p.id || "c1";
      const cohort = db.cohorts.find(c => c.id === cohortId);
      if (!cohort) return sendJSON(res, { error: "契约营不存在" }, 404);
      if (!cohort.user_joined || cohort.user_status === "COMPLETED") {
        return sendJSON(res, { error: "当前未在营中或该期对赌已完成结算！" }, 400);
      }

      const u = db.users[0];
      const deposit = cohort.deposit_amount;
      const totalPool = cohort.pool_amount;
      const platformFeeRate = 0.15; // 15% Platform Escrow Service Fee
      const platformFee = Math.round(totalPool * platformFeeRate * 100) / 100;
      const netPool = totalPool - platformFee;
      const survivorsCount = Math.max(1, Math.floor(cohort.total_members * 0.78));
      const payoutPerPerson = Math.round((netPool / survivorsCount) * 100) / 100;
      const bonusEarned = Math.max(0, Math.round((payoutPerPerson - deposit) * 100) / 100);

      u.cash_balance = (u.cash_balance || 0) + payoutPerPerson;
      cohort.user_status = "COMPLETED";

      const ledgerId = `LED_SETTLE_${Date.now()}`;
      if (!db.cash_ledgers) db.cash_ledgers = [];
      db.cash_ledgers.unshift({
        id: ledgerId,
        user_id: u.id,
        type: "ESCROW_SETTLE",
        amount: payoutPerPerson,
        balance_after: u.cash_balance,
        description: `契约督学营结营反全款与分红(平台按规抽取15%服务费￥${platformFee})`,
        created_at: new Date().toISOString()
      });

      return sendJSON(res, {
        success: true,
        settlement_report: {
          cohort_title: cohort.title,
          deposit_returned: deposit,
          bonus_earned: bonusEarned,
          total_payout: payoutPerPerson,
          platform_fee_deducted: platformFee,
          survivors_count: survivorsCount,
          new_cash_balance: u.cash_balance
        },
        message: `🎉 契约结算成功！全额返还学费押金 ￥${deposit}，分得对赌奖金 ￥${bonusEarned} (平台已扣除15%担保费)，到账总额 ￥${payoutPerPerson}！`
      });
    } catch (err) {
      return sendJSON(res, { error: "Settle failed" }, 500);
    }
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

  // STREAMING AI TUTOR INFERENCE (SSE PROTOCOL WITH TOKEN BILLING)
  if (pathname === "/api/ai/ask-stream" && req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk.toString()));
    req.on("end", () => {
      try {
        const p = JSON.parse(body || "{}");
        const userId = p.user_id || "u1";
        const u = db.users.find((x) => x.id === userId) || db.users[0];

        if (u.token_used >= u.token_quota) {
          res.writeHead(402, { "Content-Type": "application/json" });
          res.end(JSON.stringify({
            error: `🚨 AI 算力阻断 (HTTP 402)：您的 Token 免费配额已耗尽 (${u.token_used}/${u.token_quota})！请前往设置中心充值兑换或开通 PRO/VIP 会员！`,
            quota_exceeded: true,
            token_used: u.token_used,
            token_quota: u.token_quota,
          }));
          return;
        }

        const teacherName = p.teacher_name || "花生十三";
        const userPrompt = p.prompt || "老师请帮我剖析一下这道题目的解题突破口！";
        const qId = p.question_id;
        const targetQ = db.questions.find((q) => q.id === qId) || db.questions[0];

        const tokensConsumed = Math.floor(Math.random() * 80) + 260;
        u.token_used += tokensConsumed;

        let teacherReply = "";
        if (teacherName.includes("花生十三") || teacherName.includes("秒杀")) {
          teacherReply = `【${teacherName} · AI实时推理流】同学你好！你提问的“${targetQ.content.slice(0, 15)}...”这题非常经典！记住我在强化讲座里反复强调的大招：**左两位截位直除法则**！分母直接保留前两位，15秒排掉干扰项 A 和 C！考场上千万不可列竖式死算！刚才错在算得太细把黄金时间浪费了，按照这套口诀再练两道专项题就能极速提分！`;
        } else if (teacherName.includes("粉笔王") || teacherName.includes("拆分")) {
          teacherReply = `【${teacherName} · AI实时推理流】别慌，我们来进行稳健拆解！把百分比按 10% 和 1% 依次叠加，脑海里平移小数点即可。这步操作非常扎实，绝不会出现粗心算错！`;
        } else {
          teacherReply = `【${teacherName} · AI实时推理流】关于你的疑惑：“${userPrompt}”，从文段逻辑关联词及行文脉络来看，核心突破口在于主题词排异。抓住中心转折关联词，直接秒杀无关干扰项！`;
        }

        res.writeHead(200, {
          "Content-Type": "text/event-stream; charset=utf-8",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive"
        });

        res.write(`data: ${JSON.stringify({ type: "start", model_used: db.llm_config.active_model, teacher: teacherName, tokens_consumed: tokensConsumed, token_used: u.token_used, token_quota: u.token_quota })}\n\n`);

        const chunks = teacherReply.split(/(？|！|。|；|,|，| )/g).filter(Boolean);
        let i = 0;
        const interval = setInterval(() => {
          if (i >= chunks.length) {
            clearInterval(interval);
            res.write(`data: ${JSON.stringify({ type: "done", text: "" })}\n\n`);
            res.end();
            return;
          }
          res.write(`data: ${JSON.stringify({ type: "chunk", text: chunks[i] })}\n\n`);
          i++;
        }, 70);

      } catch (err) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
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
