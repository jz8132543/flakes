// === Global State ===
const API = "";
let loggedIn = false;
let user = null;
const loaded = new Set();
let modalsOk = false;

// Practice state
let practiceQs = [];
let practiceIdx = 0;
let practiceAnswers = {};
let practiceMode = "";
let practiceTarget = "";

// === Router ===
async function navigate(tab, btn) {
  if (!loggedIn && tab !== "landing") {
    toast("请先登录");
    openModal("login");
    return;
  }
  const app = document.getElementById("app");
  let el = document.getElementById("v-" + tab);
  if (!el && !loaded.has(tab)) {
    try {
      const r = await fetch("/views/" + tab + ".html");
      if (!r.ok) return;
      const h = await r.text();
      const w = document.createElement("div");
      w.innerHTML = h.trim();
      while (w.firstChild) app.appendChild(w.firstChild);
      loaded.add(tab);
      el = document.getElementById("v-" + tab);
    } catch (e) {
      console.error(e);
    }
  }
  document
    .querySelectorAll(".view")
    .forEach((v) => v.classList.remove("active"));
  if (el) el.classList.add("active");
  document
    .querySelectorAll(".nav-tab")
    .forEach((t) => t.classList.remove("active"));
  if (btn) btn.classList.add("active");
  else {
    const t = document.querySelector('.nav-tab[data-tab="' + tab + '"]');
    if (t) t.classList.add("active");
  }
  const fn = {
    dashboard: loadDashboard,
    practice: loadPractice,
    review: loadReview,
    cohorts: loadCohorts,
    settings: loadSettings,
  };
  if (fn[tab]) fn[tab]();
}

// === Modals ===
async function ensureModals() {
  if (modalsOk) return;
  try {
    const r = await fetch("/views/modals.html");
    if (!r.ok) return;
    document.getElementById("modals-root").innerHTML = await r.text();
    modalsOk = true;
  } catch (e) {
    console.error(e);
  }
}
async function openModal(name) {
  await ensureModals();
  const m = document.getElementById("modal-" + name);
  if (m) m.classList.add("open");
}
function closeModal(name) {
  const m = document.getElementById("modal-" + name);
  if (m) m.classList.remove("open");
}

// === Toast ===
let toastTimer;
function toast(msg) {
  const t = document.getElementById("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 2500);
}

// === Auth ===
async function login() {
  const u = document.getElementById("login-user")?.value?.trim();
  const p = document.getElementById("login-pass")?.value?.trim();
  if (!u || !p) {
    toast("请输入用户名和密码");
    return;
  }
  try {
    const r = await fetch(API + "/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: u, password: p }),
    });
    const d = await r.json();
    if (d.success) {
      loggedIn = true;
      user = d.user || { username: u, token_quota: 50000, token_used: 0 };
      closeModal("login");
      document.getElementById("nav-tabs").style.display = "flex";
      document.getElementById("nav-login-btn").style.display = "none";
      document.getElementById("nav-user").style.display = "flex";
      document.getElementById("nav-uname").textContent = user.username || u;
      document.getElementById("ai-fab").style.display = "flex";
      toast("欢迎，" + (user.username || u));
      navigate("dashboard");
    } else {
      toast(d.message || "登录失败");
    }
  } catch (e) {
    toast("网络错误");
  }
}

async function register() {
  const u = document.getElementById("login-user")?.value?.trim();
  const p = document.getElementById("login-pass")?.value?.trim();
  if (!u || !p) {
    toast("请输入用户名和密码");
    return;
  }
  try {
    const r = await fetch(API + "/api/auth/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: u, password: p }),
    });
    const d = await r.json();
    if (d.success) {
      toast("注册成功，正在登录…");
      await login();
    } else {
      toast(d.message || "注册失败");
    }
  } catch (e) {
    toast("网络错误");
  }
}

// ============================================================
// Dashboard
// ============================================================
async function loadDashboard() {
  try {
    const [uRes, hmRes] = await Promise.all([
      fetch(API + "/api/user"),
      fetch(API + "/api/dashboard/heatmap"),
    ]);
    const u = await uRes.json();
    const hm = await hmRes.json();

    document.getElementById("d-streak").textContent = (u.streak || 0) + " 天";
    document.getElementById("d-total").textContent = (
      u.total_questions || 0
    ).toLocaleString();
    document.getElementById("d-token").textContent = (
      (u.token_quota || 0) - (u.token_used || 0)
    ).toLocaleString();

    // Heatmap
    const grid = document.getElementById("heatmap");
    grid.innerHTML = "";
    const recs = hm.records || [];
    let days = 0;
    recs.forEach((r) => {
      const c = document.createElement("div");
      c.className =
        "hm" + (r.green_shade_level ? " l" + r.green_shade_level : "");
      c.title = r.date + ": " + r.count + " 题";
      grid.appendChild(c);
      if (r.count > 0) days++;
    });
    const s = document.getElementById("hm-summary");
    if (s) s.textContent = "过去一年活跃 " + days + " 天";

    // Categories
    const cats = [
      {
        key: "data-analysis",
        name: "资料分析",
        icon: "📊",
        color: "var(--blue)",
      },
      { key: "verbal", name: "言语理解", icon: "📖", color: "var(--green)" },
      { key: "logic", name: "判断推理", icon: "🧩", color: "var(--amber)" },
      { key: "math", name: "数量关系", icon: "🔢", color: "var(--red)" },
      { key: "common", name: "常识判断", icon: "🌐", color: "#8b5cf6" },
      { key: "essay", name: "申论", icon: "✍️", color: "#ec4899" },
    ];
    const cg = document.getElementById("cat-grid");
    if (cg) {
      cg.innerHTML = cats
        .map((c) => {
          const done = Math.floor(Math.random() * 200 + 50);
          const acc = Math.floor(Math.random() * 25 + 65);
          return (
            '<div class="stat-card click" onclick="navigate(\'practice\')">' +
            '<div class="flex items-center gap-sm"><span style="font-size:1.2rem">' +
            c.icon +
            '</span><span style="font-weight:600;font-size:0.88rem">' +
            c.name +
            "</span></div>" +
            '<div class="progress" style="margin-top:0.3rem"><div class="progress-fill" style="width:' +
            acc +
            "%;background:" +
            c.color +
            '"></div></div>' +
            '<div class="flex justify-between" style="font-size:0.75rem;color:var(--text-3)"><span>做题 ' +
            done +
            "</span><span>正确率 " +
            acc +
            "%</span></div>" +
            "</div>"
          );
        })
        .join("");
    }
  } catch (e) {
    console.error(e);
  }
}

// ============================================================
// Practice
// ============================================================
function loadPractice() {
  const sel = document.getElementById("p-select");
  const arena = document.getElementById("p-arena");
  if (sel) sel.style.display = "block";
  if (arena) arena.style.display = "none";
  practiceMode = "";
  practiceTarget = "";
  document.querySelectorAll(".pm").forEach((el) => el.classList.remove("sel"));
  const sub = document.getElementById("p-sub");
  if (sub) sub.innerHTML = "";
  const startBtn = document.getElementById("p-start");
  if (startBtn) startBtn.style.display = "none";
}

function selectPracticeMode(mode, el) {
  practiceMode = mode;
  document.querySelectorAll(".pm").forEach((e) => e.classList.remove("sel"));
  if (el) el.classList.add("sel");
  const sub = document.getElementById("p-sub");
  const startBtn = document.getElementById("p-start");
  if (mode === "FULL_PAPER") {
    sub.innerHTML =
      '<div class="card card-click" onclick="setPracticeTarget(\'2025-GUOKAO-XINGCE\',this)" style="padding:0.8rem;margin-top:0.5rem">' +
      '<div style="font-weight:600;font-size:0.88rem">2025年国考行测真题</div>' +
      '<div style="font-size:0.78rem;color:var(--text-3)">135题 · 120分钟</div></div>' +
      '<div class="card card-click" onclick="setPracticeTarget(\'2024-GUOKAO-XINGCE\',this)" style="padding:0.8rem;margin-top:0.5rem">' +
      '<div style="font-weight:600;font-size:0.88rem">2024年国考行测真题</div>' +
      '<div style="font-size:0.78rem;color:var(--text-3)">135题 · 120分钟</div></div>';
    startBtn.style.display = "none";
  } else if (mode === "MODULE") {
    const mods = ["资料分析", "言语理解", "判断推理", "数量关系", "常识判断"];
    sub.innerHTML =
      '<div class="flex gap-sm" style="flex-wrap:wrap;margin-top:0.5rem">' +
      mods
        .map(
          (m) =>
            '<button class="btn btn-g btn-sm mod-pill" onclick="setPracticeTarget(\'' +
            m +
            "',this)\">" +
            m +
            "</button>",
        )
        .join("") +
      "</div>";
    startBtn.style.display = "none";
  } else {
    const tags = [
      "截位直除法",
      "转折锚定法",
      "概念辨析法",
      "对称性规律",
      "工程赋值法",
    ];
    sub.innerHTML =
      '<div class="flex gap-sm" style="flex-wrap:wrap;margin-top:0.5rem">' +
      tags
        .map(
          (t) =>
            '<button class="btn btn-g btn-sm tag-pill" onclick="setPracticeTarget(\'' +
            t +
            "',this)\">" +
            t +
            "</button>",
        )
        .join("") +
      "</div>";
    startBtn.style.display = "none";
  }
}

function setPracticeTarget(target, el) {
  practiceTarget = target;
  // highlight
  if (el) {
    el.parentElement
      ?.querySelectorAll(".btn-g, .card-click")
      .forEach((e) => e.classList.remove("active"));
    el.classList.add("active");
    if (el.classList.contains("card-click")) {
      el.style.borderColor = "var(--blue)";
    }
  }
  document.getElementById("p-start").style.display = "block";
}

async function startPracticeSession() {
  try {
    const r = await fetch(API + "/api/practice/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode: practiceMode, target_id: practiceTarget }),
    });
    const d = await r.json();
    if (d.success && d.questions) {
      practiceQs = d.questions;
      practiceIdx = 0;
      practiceAnswers = {};
      document.getElementById("p-select").style.display = "none";
      document.getElementById("p-arena").style.display = "block";
      renderQuestion(0);
    } else {
      toast(d.message || "获取题目失败");
    }
  } catch (e) {
    toast("网络错误");
  }
}

function renderQuestion(idx) {
  if (idx < 0 || idx >= practiceQs.length) return;
  practiceIdx = idx;
  const q = practiceQs[idx];
  document.getElementById("a-prog").textContent =
    idx + 1 + " / " + practiceQs.length;
  const pct = Math.round(((idx + 1) / practiceQs.length) * 100);
  document.getElementById("a-bar").style.width = pct + "%";
  document.getElementById("a-q").textContent = q.content;
  const opts = document.getElementById("a-opts");
  const chosen = practiceAnswers[q.id];
  opts.innerHTML = (q.options || [])
    .map(
      (o) =>
        '<div class="q-opt' +
        (chosen === o.key ? " sel" : "") +
        '" onclick="pickOpt(\'' +
        q.id +
        "','" +
        o.key +
        "',this)\">" +
        "<strong>" +
        o.key +
        ".</strong> " +
        o.text +
        "</div>",
    )
    .join("");
}

function pickOpt(qId, key, el) {
  practiceAnswers[qId] = key;
  el.parentElement
    .querySelectorAll(".q-opt")
    .forEach((e) => e.classList.remove("sel"));
  el.classList.add("sel");
}

function prevQ() {
  if (practiceIdx > 0) renderQuestion(practiceIdx - 1);
}
function nextQ() {
  if (practiceIdx < practiceQs.length - 1) renderQuestion(practiceIdx + 1);
}

async function submitPractice() {
  const answers = practiceQs.map((q) => ({
    question_id: q.id,
    chosen: practiceAnswers[q.id] || "",
  }));
  try {
    const r = await fetch(API + "/api/practice/submit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ answers }),
    });
    const d = await r.json();
    if (d.success) {
      const correct = d.correct_count || 0;
      const total = d.total || practiceQs.length;
      // Show results inline
      const arena = document.getElementById("p-arena");
      arena.innerHTML =
        '<div class="card text-center" style="padding:3rem 2rem">' +
        '<div style="font-size:2.5rem;margin-bottom:0.5rem">🎉</div>' +
        '<div style="font-size:1.3rem;font-weight:700;margin-bottom:0.5rem">答题完成</div>' +
        '<div style="font-size:2rem;font-weight:800;color:var(--blue);margin-bottom:0.3rem">' +
        correct +
        " / " +
        total +
        "</div>" +
        '<div style="font-size:0.85rem;color:var(--text-2);margin-bottom:1.5rem">正确率 ' +
        Math.round((correct / total) * 100) +
        "%</div>" +
        '<button class="btn btn-p" onclick="loadPractice()">再来一轮</button>' +
        "</div>";
      toast("交卷成功，正确 " + correct + " / " + total);
    } else {
      toast(d.message || "提交失败");
    }
  } catch (e) {
    toast("网络错误");
  }
}

// ============================================================
// Review
// ============================================================
let reviewLoaded = {};

async function loadReview() {
  if (!reviewLoaded.solutions) await loadSolutions();
}

function switchReviewTab(tab, btn) {
  document
    .querySelectorAll(".rv-tab")
    .forEach((e) => e.classList.remove("active"));
  if (btn) btn.classList.add("active");
  ["solutions", "mistakes", "mastery"].forEach((t) => {
    const el = document.getElementById("rv-" + t);
    if (el) el.style.display = t === tab ? "block" : "none";
  });
  if (tab === "solutions" && !reviewLoaded.solutions) loadSolutions();
  if (tab === "mistakes" && !reviewLoaded.mistakes) loadMistakes();
  if (tab === "mastery" && !reviewLoaded.mastery) loadMastery();
}

async function loadSolutions() {
  try {
    const r = await fetch(API + "/api/solutions/distilled");
    const d = await r.json();
    const qs = d.questions || d || [];
    const el = document.getElementById("rv-solutions");
    el.innerHTML = qs
      .map(
        (q, i) =>
          '<div class="card mb">' +
          '<div style="font-size:0.88rem;line-height:1.7;margin-bottom:1rem"><strong>Q' +
          (i + 1) +
          ".</strong> " +
          q.content +
          "</div>" +
          (q.solutions || [])
            .map(
              (s) =>
                '<div style="padding:0.6rem;background:var(--bg-input);border-radius:var(--r-sm);margin-bottom:0.5rem">' +
                '<div class="flex justify-between items-center" style="margin-bottom:0.3rem">' +
                '<span style="font-size:0.82rem;font-weight:600;color:var(--blue)">' +
                s.teacher_name +
                "</span>" +
                '<span style="font-size:0.75rem;color:var(--text-3)">' +
                (s.time_spent_eval || "") +
                "</span></div>" +
                '<div style="font-size:0.82rem;color:var(--text-2);line-height:1.6">' +
                s.content +
                "</div>" +
                "</div>",
            )
            .join("") +
          "</div>",
      )
      .join("");
    reviewLoaded.solutions = true;
  } catch (e) {
    console.error(e);
  }
}

async function loadMistakes() {
  try {
    const r = await fetch(API + "/api/mistakes/tree");
    const d = await r.json();
    const items = d.tree || d.mistakes || [];
    const el = document.getElementById("rv-mistakes");
    if (items.length === 0) {
      el.innerHTML =
        '<div class="card text-center" style="padding:2rem;color:var(--text-3)">暂无错题记录</div>';
    } else {
      el.innerHTML = items
        .map(
          (m) =>
            '<div class="card mb flex justify-between items-center">' +
            '<div><div style="font-weight:600;font-size:0.88rem">' +
            (m.skill_name || m.name || "未知技巧") +
            "</div>" +
            '<div style="font-size:0.78rem;color:var(--text-3)">错误率 ' +
            (m.error_rate || m.ema_error_rate || "—") +
            "</div></div>" +
            '<button class="btn btn-p btn-sm" onclick="remediate(\'' +
            (m.skill_id || m.id) +
            "')\">专项特训</button>" +
            "</div>",
        )
        .join("");
    }
    reviewLoaded.mistakes = true;
  } catch (e) {
    console.error(e);
  }
}

async function loadMastery() {
  try {
    const r = await fetch(API + "/api/skills/mastery");
    const d = await r.json();
    const skills = d.skills || d || [];
    const el = document.getElementById("rv-mastery");
    el.innerHTML = skills
      .map(
        (s) =>
          '<div class="flex items-center gap mb" style="padding:0.5rem 0">' +
          '<span style="font-size:0.85rem;min-width:160px">' +
          s.name +
          "</span>" +
          '<div class="progress" style="flex:1"><div class="progress-fill" style="width:' +
          (s.mastery || 0) +
          "%;background:" +
          (s.mastery > 70
            ? "var(--green)"
            : s.mastery > 40
              ? "var(--amber)"
              : "var(--red)") +
          '"></div></div>' +
          '<span style="font-size:0.78rem;color:var(--text-3);min-width:40px;text-align:right">' +
          (s.mastery || 0) +
          "%</span>" +
          "</div>",
      )
      .join("");
    reviewLoaded.mastery = true;
  } catch (e) {
    console.error(e);
  }
}

async function remediate(skillId) {
  try {
    const r = await fetch(API + "/api/mistakes/remediate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ skill_id: skillId }),
    });
    const d = await r.json();
    if (d.success && d.questions) {
      practiceQs = d.questions;
      practiceIdx = 0;
      practiceAnswers = {};
      navigate("practice");
      document.getElementById("p-select").style.display = "none";
      document.getElementById("p-arena").style.display = "block";
      renderQuestion(0);
      toast("已生成专项特训题目");
    }
  } catch (e) {
    toast("生成特训失败");
  }
}

// ============================================================
// Cohorts
// ============================================================
async function loadCohorts() {
  try {
    const r = await fetch(API + "/api/cohorts");
    const d = await r.json();
    const list = d.cohorts || d || [];
    const el = document.getElementById("cohort-list");
    el.innerHTML = list
      .map(
        (c) =>
          '<div class="card mb">' +
          '<div style="font-weight:600;font-size:0.92rem;margin-bottom:0.6rem">' +
          c.title +
          "</div>" +
          '<div class="flex gap" style="flex-wrap:wrap;font-size:0.82rem;color:var(--text-2);margin-bottom:0.8rem">' +
          "<span>押金 ¥" +
          c.deposit_amount +
          "</span>" +
          "<span>成员 " +
          c.total_members +
          " 人</span>" +
          "<span>今日打卡 " +
          c.completed_today +
          "/" +
          c.total_members +
          "</span>" +
          '<span style="color:var(--amber)">奖金池 ¥' +
          c.pool_amount.toLocaleString() +
          "</span>" +
          "</div>" +
          (c.user_joined
            ? '<button class="btn btn-p btn-sm" onclick="checkinCohort(\'' +
              c.id +
              "')\">今日打卡</button>"
            : '<button class="btn btn-g btn-sm" onclick="joinCohort(\'' +
              c.id +
              "'," +
              c.deposit_amount +
              ')">加入 (¥' +
              c.deposit_amount +
              ")</button>") +
          "</div>",
      )
      .join("");
  } catch (e) {
    console.error(e);
  }
}

async function joinCohort(id, amount) {
  try {
    const r = await fetch(API + "/api/cohorts/join", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ cohort_id: id, deposit_amount: amount }),
    });
    const d = await r.json();
    toast(d.message || (d.success ? "加入成功" : "加入失败"));
    if (d.success) loadCohorts();
  } catch (e) {
    toast("网络错误");
  }
}

async function checkinCohort(id) {
  try {
    const r = await fetch(API + "/api/cohorts/checkin", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ cohort_id: id }),
    });
    const d = await r.json();
    toast(d.message || (d.success ? "打卡成功" : "打卡失败"));
    if (d.success) loadCohorts();
  } catch (e) {
    toast("网络错误");
  }
}

// ============================================================
// Settings
// ============================================================
async function loadSettings() {
  try {
    const [uRes, lRes] = await Promise.all([
      fetch(API + "/api/user"),
      fetch(API + "/api/user/ledgers"),
    ]);
    const u = await uRes.json();
    const l = await lRes.json();

    const tgt = document.getElementById("s-target");
    if (tgt) tgt.value = u.exam_target || "";
    const dt = document.getElementById("s-date");
    if (dt) dt.value = u.target_date || "";
    const uname = document.getElementById("s-uname");
    if (uname) uname.textContent = u.username || "";

    // Token bar
    const used = u.token_used || 0;
    const total = u.token_quota || 50000;
    const remain = total - used;
    document.getElementById("s-token-val").textContent =
      remain.toLocaleString() + " / " + total.toLocaleString();
    document.getElementById("s-token-bar").style.width =
      Math.round((remain / total) * 100) + "%";
    const vip = document.getElementById("s-vip");
    if (vip)
      vip.textContent =
        (u.vip_tier || "免费") +
        (u.vip_expire_at ? " · 到期 " + u.vip_expire_at : "");

    // Ledgers
    const ledgers = l.ledgers || l || [];
    const tbody = document.getElementById("s-ledger-body");
    tbody.innerHTML = ledgers
      .map(
        (e) =>
          "<tr><td>" +
          (e.created_at || "").slice(0, 10) +
          "</td>" +
          "<td>" +
          (e.type || "") +
          "</td>" +
          '<td style="color:' +
          (e.amount > 0 ? "var(--green)" : "var(--red)") +
          '">' +
          (e.amount > 0 ? "+" : "") +
          e.amount +
          "</td>" +
          "<td>" +
          (e.description || "") +
          "</td></tr>",
      )
      .join("");
  } catch (e) {
    console.error(e);
  }
}

async function saveProfile() {
  const target = document.getElementById("s-target")?.value;
  const date = document.getElementById("s-date")?.value;
  try {
    const r = await fetch(API + "/api/user/profile", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ exam_target: target, target_date: date }),
    });
    const d = await r.json();
    toast(d.success ? "保存成功" : d.message || "保存失败");
  } catch (e) {
    toast("网络错误");
  }
}

function openCashier() {
  openModal("cashier");
}

async function simulatePay(pkg, name, price) {
  try {
    const r = await fetch(API + "/api/billing/create-order", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        package_id: pkg,
        package_name: name,
        amount: price,
      }),
    });
    const d = await r.json();
    if (d.success && d.order_id) {
      // Simulate webhook
      await fetch(API + "/api/billing/webhook", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ order_id: d.order_id, status: "SUCCESS" }),
      });
      toast("充值成功");
      closeModal("cashier");
      loadSettings();
    }
  } catch (e) {
    toast("支付失败");
  }
}

// ============================================================
// AI Tutor
// ============================================================
async function openAITutor() {
  await ensureModals();
  openModal("ai");
}

async function sendAI() {
  const prompt = document.getElementById("ai-prompt")?.value?.trim();
  if (!prompt) return;
  const reply = document.getElementById("ai-reply");
  reply.style.display = "block";
  reply.textContent = "思考中…";
  try {
    const r = await fetch(API + "/api/ai/ask-stream", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question_id: "q101",
        teacher_name: "花生十三",
        prompt,
      }),
    });
    const reader = r.body.getReader();
    const dec = new TextDecoder();
    reply.textContent = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = dec.decode(value);
      for (const line of text.split("\n")) {
        if (!line.startsWith("data: ")) continue;
        try {
          const d = JSON.parse(line.slice(6));
          if (d.type === "chunk") reply.textContent += d.text;
          if (d.type === "error") {
            reply.textContent = d.message || "请求失败";
            break;
          }
        } catch {}
      }
    }
  } catch (e) {
    reply.textContent = "请求失败，请检查 Token 余额";
  }
}

// ============================================================
// Init
// ============================================================
window.onload = async () => {
  await navigate("landing");
};
