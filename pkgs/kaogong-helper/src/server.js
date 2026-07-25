const http = require("http");
const fs = require("fs");
const path = require("path");
const url = require("url");

const PORT = process.env.PORT || 7070;
const HOST = process.env.HOST || "0.0.0.0";

// Domain DB State matching PRD PostgreSQL / Prisma Schema
const db = {
  user: {
    id: "u1",
    username: "备考先锋小王",
    avatar: "🎯",
    exam_target: "2026年山西省联考",
    target_date: "2026-03-13",
    streak: 18,
    total_questions: 1420,
    created_at: "2025-11-01",
  },

  practice_records: generateHeatmapData(),

  skill_tags: [
    { id: "s1", name: "行测 - 资料分析", parent_id: null, level: 1 },
    { id: "s1-1", name: "增长率与倍数计算", parent_id: "s1", level: 2 },
    { id: "s1-1-1", name: "截位直算法", parent_id: "s1-1", level: 3 },
    { id: "s1-1-2", name: "首位估算法", parent_id: "s1-1", level: 3 },
    { id: "s1-1-3", name: "差分比较法", parent_id: "s1-1", level: 3 },
    { id: "s1-2", name: "比重与比重变化", parent_id: "s1", level: 2 },
    { id: "s1-2-1", name: "两期比重差值快速比较", parent_id: "s1-2", level: 3 },
    { id: "s2", name: "行测 - 言语理解", parent_id: null, level: 1 },
    { id: "s2-1", name: "片段阅读", parent_id: "s2", level: 2 },
    { id: "s2-1-1", name: "关联词转折定位法", parent_id: "s2-1", level: 3 },
    { id: "s2-1-2", name: "主题词同义替换识别", parent_id: "s2-1", level: 3 },
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
          teacher_name: "张三老师 (方程派)",
          approach_name: "公式精确求解法",
          content:
            "【公式】2025年产量 = 4582.4 × (1 + 6.8%) = 4582.4 × 1.068 = 4893.99 万吨 ≈ 4894 万吨。适合基础扎实、追求零差错学员。",
          upvotes: 342,
        },
        {
          id: "sol-2",
          teacher_name: "花生十三 (秒杀派)",
          approach_name: "截位直算法 (左两位截位)",
          content:
            "【秒杀技巧】4582.4 截前两位为 46，6.8% 约为 7%。46 × 7% = 3.22，45.8 + 3.2 = 49.0。对比选项 B(4894) 最为接近，15秒内得出答案！",
          upvotes: 890,
        },
        {
          id: "sol-3",
          teacher_name: "粉笔王老师 (拆分派)",
          approach_name: "10% 与 1% 拆分法",
          content:
            "【拆分】4582.4 的 5% = 229.1，1% = 45.8，0.8% ≈ 36.6。6.8% = 5% + 1% + 0.8% = 311.5。4582.4 + 311.5 = 4893.9 万吨。速算无需硬乘！",
          upvotes: 620,
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
            "【解析】横线在文段末尾，起总结说明作用。前面通过“但在现代都市圈”进行转折，强调正向逆转，A选项直接对应“观念逆转”的社会意义，承接最为紧密。",
          upvotes: 412,
        },
        {
          id: "sol-5",
          teacher_name: "郭熙老师 (主题词法)",
          approach_name: "核心主题词锁定",
          content:
            "【解析】前文主题词为“观念/思想”，转折后讨论“现象逆转”，A选项中的“性别平等意识”直接继承“观念”主题，其他选项离题或过度推断。",
          upvotes: 530,
        },
      ],
    },
  ],

  cohorts: [
    {
      id: "c1",
      title: "21天行测高分冲刺契约营 (第 14 期)",
      deposit_amount: 99.0,
      start_date: "2026-07-10",
      end_date: "2026-07-31",
      total_members: 128,
      completed_today: 94,
      pool_amount: 12672.0,
      user_joined: true,
      user_status: "ACTIVE",
      user_checkins_count: 14,
    },
    {
      id: "c2",
      title: "申论名师大题精练打卡营",
      deposit_amount: 199.0,
      start_date: "2026-08-01",
      end_date: "2026-08-21",
      total_members: 64,
      completed_today: 0,
      pool_amount: 12736.0,
      user_joined: false,
      user_status: null,
      user_checkins_count: 0,
    },
  ],

  strategies: [
    {
      id: "strat-101",
      author_name: "上岸老学长(国考155分)",
      author_avatar: "🎓",
      title: "60天零基础高效逆袭省考上岸排期表",
      forked_count: 384,
      days_total: 60,
      timeline_data: [
        {
          phase: "基础强化 (第1-20天)",
          daily_questions: 50,
          daily_hours: 3.5,
          focus: "资料分析直除法 + 言语片段阅读",
        },
        {
          phase: "技巧突破 (第21-40天)",
          daily_questions: 80,
          daily_hours: 4.5,
          focus: "名师蒸馏技巧强化 + 错题消灭",
        },
        {
          phase: "真题冲刺 (第41-60天)",
          daily_questions: 100,
          daily_hours: 5.0,
          focus: "全真模考限时训练 + 申论大作文模板",
        },
      ],
    },
    {
      id: "strat-102",
      author_name: "在职备考小羊 (上岸联考)",
      author_avatar: "💼",
      title: "在职备考每日2小时极致精简90天攻略",
      forked_count: 215,
      days_total: 90,
      timeline_data: [
        {
          phase: "晚间拆解 (第1-30天)",
          daily_questions: 30,
          daily_hours: 2.0,
          focus: "资料分析速算 + 言语逻辑填空",
        },
        {
          phase: "周末冲刺 (第31-60天)",
          daily_questions: 60,
          daily_hours: 4.0,
          focus: "判断推理 + 申论小题",
        },
        {
          phase: "考前抢分 (第61-90天)",
          daily_questions: 50,
          daily_hours: 2.5,
          focus: "高频错题刷一遍 + 技巧树补强",
        },
      ],
    },
  ],
};

function generateHeatmapData() {
  const records = [];
  const now = new Date("2026-07-24");
  for (let i = 300; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const dateStr = d.toISOString().split("T")[0];
    let count = 0;
    const dayOfWeek = d.getDay();
    const rand = Math.random();
    if (rand > 0.15) {
      count = Math.floor(Math.random() * 65) + 15;
      if (dayOfWeek === 0 || dayOfWeek === 6) count += 30;
    }
    records.push({
      date: dateStr,
      count: count,
      minutes: Math.round(count * 1.8),
      accuracy: Math.round(70 + Math.random() * 25),
    });
  }
  return records;
}

function sendJSON(res, data, status = 200) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(JSON.stringify(data));
}

const PUBLIC_DIR = path.join(__dirname, "public");

const server = http.createServer((req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    return res.end();
  }

  // --- API ROUTES FOR UNI-APP & H5 ---
  if (pathname === "/api/user" && req.method === "GET") {
    return sendJSON(res, db.user);
  }

  if (pathname === "/api/dashboard/heatmap" && req.method === "GET") {
    return sendJSON(res, {
      records: db.practice_records,
      total_days: db.practice_records.filter((r) => r.count > 0).length,
      streak: db.user.streak,
      total_questions: db.practice_records.reduce(
        (acc, cur) => acc + cur.count,
        0,
      ),
    });
  }

  if (pathname === "/api/questions" && req.method === "GET") {
    const questionsWithSortedSolutions = db.questions.map((q) => ({
      ...q,
      solutions: [...q.solutions].sort((a, b) => b.upvotes - a.upvotes),
    }));
    return sendJSON(res, questionsWithSortedSolutions);
  }

  if (
    pathname.startsWith("/api/solutions/") &&
    pathname.endsWith("/upvote") &&
    req.method === "POST"
  ) {
    const parts = pathname.split("/");
    const solutionId = parts[3];
    for (const q of db.questions) {
      const sol = q.solutions.find((s) => s.id === solutionId);
      if (sol) {
        sol.upvotes += 1;
        return sendJSON(res, { success: true, upvotes: sol.upvotes });
      }
    }
    return sendJSON(res, { error: "Solution not found" }, 404);
  }

  if (pathname === "/api/skills/tree" && req.method === "GET") {
    return sendJSON(res, db.skill_tags);
  }

  if (pathname === "/api/skills/mastery" && req.method === "GET") {
    const leafSkills = db.skill_tags.filter((s) => s.level === 3);
    const masteryData = leafSkills.map((skill) => {
      let accuracy = 75;
      if (skill.id === "s1-1-1") accuracy = 92;
      if (skill.id === "s1-1-2") accuracy = 68;
      if (skill.id === "s1-1-3") accuracy = 58;
      if (skill.id === "s1-2-1") accuracy = 84;
      if (skill.id === "s2-1-1") accuracy = 88;
      if (skill.id === "s2-1-2") accuracy = 72;
      return {
        id: skill.id,
        name: skill.name,
        accuracy: accuracy,
        recent_attempts: 50,
        avg_time_seconds: Math.round(45 - accuracy * 0.2),
      };
    });
    return sendJSON(res, masteryData);
  }

  if (pathname === "/api/cohorts" && req.method === "GET") {
    return sendJSON(res, db.cohorts);
  }

  if (
    pathname.startsWith("/api/cohorts/") &&
    pathname.endsWith("/checkin") &&
    req.method === "POST"
  ) {
    const parts = pathname.split("/");
    const cohortId = parts[3];
    const cohort = db.cohorts.find((c) => c.id === cohortId);
    if (cohort) {
      cohort.completed_today += 1;
      cohort.user_checkins_count += 1;
      return sendJSON(res, {
        success: true,
        message: "打卡成功！契约金返还资格保持中",
        user_checkins_count: cohort.user_checkins_count,
      });
    }
    return sendJSON(res, { error: "Cohort not found" }, 404);
  }

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
        const payload = JSON.parse(body || "{}");
        const targetDate = payload.target_date || db.user.target_date;
        const parts = pathname.split("/");
        const stratId = parts[3];
        const originalStrat = db.strategies.find((s) => s.id === stratId);

        if (!originalStrat)
          return sendJSON(res, { error: "Strategy not found" }, 404);

        const today = new Date("2026-07-24");
        const target = new Date(targetDate);
        const diffDays = Math.max(
          15,
          Math.ceil((target - today) / (1000 * 60 * 60 * 24)),
        );
        const ratio = diffDays / originalStrat.days_total;

        const newTimeline = originalStrat.timeline_data.map((item) => ({
          ...item,
          daily_questions: Math.round(
            item.daily_questions * Math.min(1.5, Math.max(0.7, 1 / ratio)),
          ),
          daily_hours:
            Math.round(
              item.daily_hours * Math.min(1.4, Math.max(0.8, 1 / ratio)) * 10,
            ) / 10,
        }));

        const newStrat = {
          id: `strat-fork-${Date.now()}`,
          author_name: db.user.username,
          author_avatar: db.user.avatar,
          title: `[派生自 ${originalStrat.author_name}] ${originalStrat.title} (${diffDays}天重算版)`,
          forked_count: 0,
          days_total: diffDays,
          timeline_data: newTimeline,
          forked_from_id: originalStrat.id,
        };

        originalStrat.forked_count += 1;
        db.strategies.unshift(newStrat);

        return sendJSON(res, {
          success: true,
          message: `攻略派生成功！已为您根据目标考试日期 (${targetDate}) 自动排写时间节点`,
          strategy: newStrat,
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
    if (err || !stats.isFile()) {
      filePath = path.join(PUBLIC_DIR, "index.html");
    }
    const ext = path.extname(filePath);
    let contentType = "text/html; charset=utf-8";
    if (ext === ".css") contentType = "text/css";
    if (ext === ".js") contentType = "application/javascript";
    if (ext === ".json") contentType = "application/json";
    if (ext === ".svg") contentType = "image/svg+xml";

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500);
        res.end("Server Error");
      } else {
        res.writeHead(200, { "Content-Type": contentType });
        res.end(content);
      }
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`====================================================`);
  console.log(`🚀 考公备考辅助系统 (Civil Service Exam Prep System)`);
  console.log(`🌐 Server running at http://${HOST}:${PORT}`);
  console.log(`====================================================`);
});
