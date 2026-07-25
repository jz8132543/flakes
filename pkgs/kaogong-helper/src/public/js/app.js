const API_BASE = "";
let allowReg = true;
let activeQId = "q101";
let activeTeacher = "花生十三";

// AUTHENTICATION & LOGIN STATE
let isLoggedIn = false;
let currentUser = null;

function openLoginModal() {
  const mod = document.getElementById("modal-login");
  if (mod) mod.style.display = "flex";
}
function closeLoginModal() {
  const mod = document.getElementById("modal-login");
  if (mod) mod.style.display = "none";
}
function performLogin() {
  const usrInput = document.getElementById("login-username-input");
  const name =
    usrInput && usrInput.value ? usrInput.value.trim() : "考公人小王";
  isLoggedIn = true;
  currentUser = { name: name, token: 50000 };
  closeLoginModal();
  const tabsEl = document.getElementById("main-nav-tabs");
  if (tabsEl) tabsEl.style.display = "flex";
  const authBtn = document.getElementById("nav-auth-btn");
  if (authBtn) authBtn.style.display = "none";
  const pillEl = document.getElementById("nav-user-pill");
  if (pillEl) pillEl.style.display = "flex";
  const nameEl = document.getElementById("nav-username");
  if (nameEl) nameEl.innerText = `${name}`;
  showToast(`🎉 欢迎回来，${name}！已加载全部刷题题库与 50,000 Token！`);
  switchTab("dashboard");
}

const loadedViews = new Set();

async function switchTab(tabId, el) {
  if (!isLoggedIn && tabId !== "landing") {
    showToast("🔒 请先登录后使用此专项刷题及 AI 私教功能！");
    openLoginModal();
    return;
  }

  const container = document.getElementById("app-views-container");
  if (!container) return;

  // Lazy load the decoupled webpage module from /views/${tabId}.html if not yet in DOM
  let viewEl = document.getElementById(`view-${tabId}`);
  if (!viewEl && !loadedViews.has(tabId)) {
    try {
      const res = await fetch(`/views/${tabId}.html`);
      if (res.ok) {
        const html = await res.text();
        const temp = document.createElement("div");
        temp.innerHTML = html.trim();
        while (temp.firstChild) {
          container.appendChild(temp.firstChild);
        }
        loadedViews.add(tabId);
        viewEl = document.getElementById(`view-${tabId}`);
      } else {
        console.error(`Failed to load decoupled view: ${tabId}`);
      }
    } catch (err) {
      console.error(`Error fetching view module: ${tabId}`, err);
    }
  }

  document
    .querySelectorAll(".nav-btn")
    .forEach((b) => b.classList.remove("active"));
  document
    .querySelectorAll(".section-view")
    .forEach((v) => v.classList.remove("active"));
  const btn =
    el ||
    (window.event &&
    window.event.target &&
    window.event.target.classList &&
    window.event.target.classList.contains("nav-btn")
      ? window.event.target
      : document.querySelector(`.nav-btn[onclick*="'${tabId}'"]`));
  if (btn && btn.classList) btn.classList.add("active");
  if (viewEl) viewEl.classList.add("active");

  if (tabId === "dashboard") loadDashboard();
  if (tabId === "practice") loadPractice();
  if (tabId === "solutions") loadSolutions();
  if (tabId === "skills") loadSkills();
  if (tabId === "mistakes") loadMistakes();
  if (tabId === "cohorts") loadCohorts();
  if (tabId === "strategies") loadStrategies();
  if (tabId === "career") loadCareer();
  if (tabId === "raid") loadRaid();
  if (tabId === "gacha") loadGacha();
  if (tabId === "settings") loadSettings();
}

// CATEGORY QUESTIONS DATABASE & INTERACTIVE ENGINE
const categoryQuestionsDB = {
  data: [
    {
      id: "d1",
      tag: "百位截位直除",
      year: "2024年国考真题",
      stem: "2023年某省规模以上工业增加值达 14285 亿元，同比增长 8.4%。问 2022 年该省规模以上工业增加值约为多少亿元？",
      options: [
        "A. 13020 亿元",
        "B. 13178 亿元",
        "C. 13450 亿元",
        "D. 13890 亿元",
      ],
      ans: 1,
      analysis:
        "【截位直除秒杀】基期值 = 现期值 / (1 + r) = 14285 / 1.084。百位截位前三位 143 / 108 ≈ 1.324，观察选项直接秒杀 B 选项！比常规长除法快 40 秒。",
    },
    {
      id: "d2",
      tag: "增长率化除为乘",
      year: "2023年联考真题",
      stem: "某市2023年高新技术企业进出口总额为 896 亿美元，同比增长 5.2%。其在全市外贸进出口总额中的比重比上年同期提高了 1.8 个百分点。问全市外贸进出口总额同比增速约为：",
      options: ["A. 3.2%", "B. 5.2%", "C. 7.1%", "D. 8.9%"],
      ans: 0,
      analysis:
        "【部分增速与整体增速判定】部分比重上升，说明部分增速 > 整体增速。已知部分增速为 5.2%，则整体增速必须小于 5.2%，直接排除 B、C、D，秒选 A！",
    },
    {
      id: "d3",
      tag: "比重差口算技巧",
      year: "2024年省考真题",
      stem: "2023年全国新能源汽车销量 958.7 万辆，同比增长 37.9%；汽车总销量 3009.4 万辆，同比增长 12.0%。2023年新能源汽车销量占汽车总销量的比重比上年约提高多少个百分点？",
      options: [
        "A. 1.2 个百分点",
        "B. 3.5 个百分点",
        "C. 6.0 个百分点",
        "D. 12.8 个百分点",
      ],
      ans: 2,
      analysis:
        "【比重差公式估算】差值 = A/B × (a - b)/(1 + a) = (958.7/3009.4) × (37.9% - 12%)/1.379 ≈ 0.32 × 25.9% / 1.38 ≈ 6.0 个百分点。口算锁定 C！",
    },
  ],
  verbal: [
    {
      id: "v1",
      tag: "转折关系锚定",
      year: "2024年国考真题",
      stem: "人工智能技术虽然在生成文本、编写代码方面表现出惊人的效率，大大提升了基础生产力；但在涉及深层人文关怀、复杂伦理抉择与原始艺术创新时，机器算法往往显露出机械与冰冷。这段文字意在强调：",
      options: [
        "A. 人工智能正全面颠覆传统社会生产效率",
        "B. 算法技术无法替代人类在深层人文与伦理领域的核心价值",
        "C. 应该大力拓展人工智能在艺术创新领域的应用",
        "D. 伦理抉择是限制 AI 普及的最大障碍",
      ],
      ans: 1,
      analysis:
        "【转折后重点秒杀】段落结构为“虽然...但是...”，转折词“但”之后为作者真正意图，强调 AI 在人文、伦理与艺术领域的局限性。对应 B 选项！",
    },
    {
      id: "v2",
      tag: "逻辑填空成语辨析",
      year: "2023年国考真题",
      stem: "面对全球基础科学前沿竞争，单纯依靠模仿和跟随已经________，必须实现高水平科技自立自强，走出一条确立核心竞争力的新路。填入横线处最恰当的一项是：",
      options: ["A. 积重难返", "B. 独木难支", "C. 难以为继", "D. 进退维谷"],
      ans: 2,
      analysis:
        "【语境搭配辨析】句意强调过去的“模仿跟随”方式已经不能继续下去了，需要“走出新路”。“难以为继”指难于继续下去，完美对应语境！",
    },
  ],
  logic: [
    {
      id: "l1",
      tag: "图形对称规律",
      year: "2024年联考真题",
      stem: "下列选项中，符合前五幅图形对称轴旋转规律的是：(题干图形图形特征：对称轴依次顺时针旋转 45 度)",
      options: [
        "A. 对称轴呈竖直方向",
        "B. 对称轴呈右斜 45 度",
        "C. 对称轴呈水平方向",
        "D. 对称轴呈左斜 45 度",
      ],
      ans: 3,
      analysis:
        "【顺时针旋转切片】观察题干前图形对称轴位置，顺时针每次旋转 45°，第五幅图为水平方向，再次顺时针旋转 45°应为左斜 45 度，对应 D 选项！",
    },
    {
      id: "l2",
      tag: "否后必否推理",
      year: "2023年国考真题",
      stem: "“只有通过终审验收，工程才能投入运行”。如果上述断定为真，则以下哪项一定为真？",
      options: [
        "A. 只要通过终审验收，工程就投入运行",
        "B. 如果工程投入运行，说明一定通过了终审验收",
        "C. 没通过终审验收，工程也可能投入运行",
        "D. 只有不投入运行，才说明没通过终审验收",
      ],
      ans: 1,
      analysis:
        "【“只有...才...”后推前公式】题干逻辑关系为：投入运行 -> 通过验收。B 选项完美契合该逆否推理逻辑！",
    },
  ],
  math: [
    {
      id: "m1",
      tag: "工程问题赋值法",
      year: "2024年省考真题",
      stem: "一项工程，甲单独做需要 12 天完成，乙单独做需要 15 天完成。现在甲乙合作 4 天后，剩下由乙单独完成，问还需要几天？",
      options: ["A. 5 天", "B. 6 天", "C. 7 天", "D. 8 天"],
      ans: 1,
      analysis:
        "【特值赋值秒杀】赋工程总量为 12 与 15 的最小公倍数 60。则甲效率为 5，乙效率为 4。合作 4 天完成 4 × (5+4) = 36。剩余工作量 24，乙单独做需 24 / 4 = 6 天！秒选 B！",
    },
  ],
  common: [
    {
      id: "c1",
      tag: "新法修法要点",
      year: "2024年国考真题",
      stem: "根据我国新修订的《行政复议法》，关于行政复议管辖与前置程序，下列说法错误的是：",
      options: [
        "A. 对对自然资源所有权确权的决定不服的，应当先申请行政复议",
        "B. 申请人可以自知道行政行为之日起60日内提出行政复议申请",
        "C. 对县级以上地方各级政府工作部门的行政行为不服的，只能向上一级主管部门申请复议",
        "D. 行政复议机关应当自受理申请之日起60日内作出行政复议决定",
      ],
      ans: 2,
      analysis:
        "【常识速记切片】根据新修订《行政复议法》，对县级以上政府工作部门的行政行为不服的，申请人既可以向该部门的本级政府申请复议，也可以向上一级主管部门申请复议。C 项“只能向上一级”表述错误！",
    },
  ],
  essay: [
    {
      id: "e1",
      tag: "大作文规范标题结构",
      year: "2024年国考申论真题",
      stem: "在围绕“以高水平生态保护支撑高质量发展”为主题申论大作文撰写中，下列哪组分论点标题结构符合公考高分阅卷标准？",
      options: [
        "A. 我们要保护环境；发展经济也很重要；大家一起努力",
        "B. 筑牢生态保护“底色”，提升发展效益“成色”；激活绿色创新“引擎”，增强持久动力“潜能”",
        "C. 为什么生态保护这么重要？因为没有绿水青山就没有金山银山",
        "D. 第一，加大资金投入；第二，加强监督检查；第三，严厉处罚违法者",
      ],
      ans: 1,
      analysis:
        "【申论对仗金句规范】B 选项动宾结构对仗工整、寓意深刻（底色 vs 成色，引擎 vs 潜能），符合中组部及阅卷组高分示范文标准！",
    },
  ],
};

let userCategoryStats = {
  data: { count: 128, correct: 111, acc: 86.5 },
  verbal: { count: 95, correct: 74, acc: 78.0 },
  logic: { count: 150, correct: 103, acc: 68.5 },
  math: { count: 42, correct: 22, acc: 52.0 },
  common: { count: 85, correct: 63, acc: 74.0 },
  essay: { count: 36, correct: 29, acc: 82.0 },
};

function updateCategoryStatsUI() {
  for (const [key, val] of Object.entries(userCategoryStats)) {
    const countEl = document.getElementById(`cat-count-${key}`);
    const accEl = document.getElementById(`cat-acc-${key}`);
    if (countEl) countEl.innerText = val.count;
    if (accEl) accEl.innerText = val.acc.toFixed(1);
  }
}

function selectDashboardCategory(catKey) {
  if (!isLoggedIn) {
    showToast("🔒 请登录后开启行测分类专项真题刷题！");
    openLoginModal();
    return;
  }
  document
    .querySelectorAll(".cat-stat-card")
    .forEach((c) => (c.style.borderColor = "rgba(255,255,255,0.1)"));
  const selCard = document.getElementById(`cat-card-${catKey}`);
  if (selCard) selCard.style.borderColor = "var(--accent-cyan)";

  const area = document.getElementById("dash-category-practice-area");
  const title = document.getElementById("dash-practice-title");
  const list = document.getElementById("dash-questions-list");
  if (!area || !list) return;

  const names = {
    data: "📊 资料分析",
    verbal: "📖 言语理解与表达",
    logic: "🧩 判断推理",
    math: "🔢 数量关系",
    common: "💡 常识判断",
    essay: "📜 申论与面试",
  };
  if (title)
    title.innerHTML = `<span>🎯 【${names[catKey] || catKey}】专项真题演练区</span>`;
  area.style.display = "block";
  list.innerHTML = "";

  const qList = categoryQuestionsDB[catKey] || [];
  if (qList.length === 0) {
    list.innerHTML = `<div style="color: #94a3b8; text-align: center; padding: 2rem;">本次暂无该专项新题，请稍后再来！</div>`;
    return;
  }

  qList.forEach((q, idx) => {
    const div = document.createElement("div");
    div.style.background = "#1e293b";
    div.style.border = "1px solid rgba(255,255,255,0.1)";
    div.style.borderRadius = "12px";
    div.style.padding = "1.5rem";
    div.id = `qcard-${catKey}-${idx}`;

    let optsHtml = "";
    q.options.forEach((opt, oIdx) => {
      optsHtml += `
              <div class="q-option-btn" style="background: rgba(15,23,42,0.6); border: 1px solid rgba(255,255,255,0.1); padding: 0.8rem 1rem; border-radius: 8px; cursor: pointer; transition: all 0.2s; margin-bottom: 0.6rem; color: #e2e8f0; font-size: 0.95rem;" 
                   onclick="submitCategoryAnswer('${catKey}', ${idx}, ${oIdx})">
                ${opt}
              </div>
            `;
    });

    div.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.8rem;">
              <span style="background: rgba(56,189,248,0.2); color: var(--accent-cyan); font-size: 0.8rem; padding: 0.2rem 0.6rem; border-radius: 6px; font-weight: 700;">📌 技巧标签：${q.tag}</span>
              <span style="color: #64748b; font-size: 0.8rem;">${q.year}</span>
            </div>
            <div style="color: #fff; font-size: 1.05rem; line-height: 1.6; margin-bottom: 1.2rem;">${q.stem}</div>
            <div id="opts-wrap-${catKey}-${idx}">${optsHtml}</div>
            <div id="q-feedback-${catKey}-${idx}" style="display: none; margin-top: 1.2rem; padding: 1.2rem; background: rgba(0,0,0,0.4); border-radius: 10px; border-left: 4px solid var(--accent-cyan);"></div>
            <div style="display: flex; justify-content: flex-end; gap: 1rem; margin-top: 1rem;">
              <button class="btn-hero-secondary" style="padding: 0.4rem 1rem; font-size: 0.85rem;" onclick="switchTab('solutions')">🌟 查看对冲解法</button>
              <button class="btn-hero-primary" style="padding: 0.4rem 1rem; font-size: 0.85rem;" onclick="openAIHelperForQ('${q.tag}')">🤖 召唤 AI 私教解剖</button>
            </div>
          `;
    list.appendChild(div);
  });

  area.scrollIntoView({ behavior: "smooth" });
}

function submitCategoryAnswer(catKey, qIdx, chosenIdx) {
  const q = categoryQuestionsDB[catKey][qIdx];
  if (!q) return;
  const feedbackEl = document.getElementById(`q-feedback-${catKey}-${qIdx}`);
  const wrapEl = document.getElementById(`opts-wrap-${catKey}-${qIdx}`);
  if (!feedbackEl || !wrapEl) return;

  const isCorrect = chosenIdx === q.ans;
  const stat = userCategoryStats[catKey];
  if (stat) {
    stat.count += 1;
    if (isCorrect) stat.correct += 1;
    stat.acc = (stat.correct / stat.count) * 100;
    updateCategoryStatsUI();
  }

  const optEls = wrapEl.children;
  for (let i = 0; i < optEls.length; i++) {
    optEls[i].style.pointerEvents = "none";
    if (i === q.ans) {
      optEls[i].style.background = "rgba(16, 185, 129, 0.25)";
      optEls[i].style.borderColor = "#10b981";
      optEls[i].style.color = "#34d399";
    } else if (i === chosenIdx && !isCorrect) {
      optEls[i].style.background = "rgba(239, 68, 68, 0.25)";
      optEls[i].style.borderColor = "#ef4444";
      optEls[i].style.color = "#fca5a5";
    }
  }

  feedbackEl.style.display = "block";
  if (isCorrect) {
    feedbackEl.style.borderLeftColor = "#10b981";
    feedbackEl.innerHTML = `
            <div style="color: #34d399; font-weight: 800; font-size: 1.1rem; margin-bottom: 0.5rem;">🎉 恭喜回答正确！+10 专注积分</div>
            <div style="color: #cbd5e1; font-size: 0.9rem; line-height: 1.6;">${q.analysis}</div>
          `;
    showToast(`🎯 回答正确！【${catKey}】做题数 +1，热力图打卡点亮！`);
  } else {
    feedbackEl.style.borderLeftColor = "#ef4444";
    feedbackEl.innerHTML = `
            <div style="color: #f87171; font-weight: 800; font-size: 1.1rem; margin-bottom: 0.5rem;">❌ 回答错误！正确答案是 ${String.fromCharCode(65 + q.ans)}</div>
            <div style="color: #cbd5e1; font-size: 0.9rem; line-height: 1.6;">${q.analysis}</div>
          `;
    showToast(`⚠️ 答错了，不用气馁！已自动收入【错题药方】病历本！`);
  }
}

function openAIHelperForQ(tag) {
  showToast(`🤖 正在召唤 AI 助教生成关于【${tag}】的深度辅导答疑...`);
  openTeacherModal(
    "花生十三",
    `请帮我讲解【${tag}】的相关考点和必杀秒杀技巧！`,
  );
}

// ONBOARDING QUIZ STATE
let onbAnswers = { q1: "", q2: "", q3: "" };
function openOnboardingQuiz() {
  document.getElementById("modal-onboarding").style.display = "flex";
  nextOnbStep(1);
}
function closeOnboardingQuiz() {
  document.getElementById("modal-onboarding").style.display = "none";
}
function selectOnbOption(step, val) {
  onbAnswers[`q${step}`] = val;
  const stepEl = document.getElementById(`onb-step-${step}`);
  if (stepEl) {
    stepEl.querySelectorAll(".quiz-opt-btn").forEach((btn) => {
      btn.classList.remove("selected");
      if (btn.innerText.includes(val.substring(0, 6))) {
        btn.classList.add("selected");
      }
    });
  }
  if (step < 3) {
    setTimeout(() => nextOnbStep(step + 1), 350);
  }
}
function nextOnbStep(step) {
  document
    .querySelectorAll(".quiz-step")
    .forEach((el) => el.classList.remove("active"));
  const target = document.getElementById(`onb-step-${step}`);
  if (target) target.classList.add("active");
  const prog = document.getElementById("onb-progress");
  if (prog) prog.innerText = `步骤 ${step} / 3`;
}
function finishOnboarding() {
  closeOnboardingQuiz();
  showToast("🎉 目标考期倒计时与专属计划已生成！送您 5,000 算力 Token！");
  switchTab("dashboard");
}

// CASHIER STATE
let currentOrder = { pkg: "", name: "", price: 0 };
function openCashierModal(pkg, name, price) {
  currentOrder = { pkg, name, price };
  const pkgEl = document.getElementById("cashier-pkg-name");
  if (pkgEl) pkgEl.innerText = name;
  const priceEl = document.getElementById("cashier-price");
  if (priceEl) priceEl.innerText = `￥${price}.00`;
  const mod = document.getElementById("modal-cashier");
  if (mod) mod.style.display = "flex";
}
function closeCashierModal() {
  const mod = document.getElementById("modal-cashier");
  if (mod) mod.style.display = "none";
}
async function simulatePaymentSuccess() {
  closeCashierModal();
  showToast(
    `✅ 模拟支付到账 ￥${currentOrder.price}.00！系统正在为您签发会员权益...`,
  );
  try {
    const res = await fetch(`${API_BASE}/api/billing/webhook`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        order_id: `ORD_${Date.now()}`,
        user_id: "u_101",
        amount: currentOrder.price,
        package_id: currentOrder.pkg,
        status: "SUCCESS",
      }),
    });
    const data = await res.json();
    if (data && data.success) {
      showToast(`👑 恭喜您已升级至 ${currentOrder.name}！已充值 Token 算力！`);
      const usr = document.getElementById("nav-username");
      if (usr) usr.innerText = "备考先锋小王 (VIP名师会员)";
    }
  } catch (err) {
    console.error("Payment webhook simulation failed:", err);
    showToast(`👑 会员权限临时下发成功！(沙盒环境到账)`);
    const usr = document.getElementById("nav-username");
    if (usr) usr.innerText = "备考先锋小王 (VIP名师会员)";
  }
  const setView = document.getElementById("view-settings");
  if (setView && setView.classList.contains("active")) {
    loadSettings();
  }
}

let selectedAvatar = "🎯";
function selectProfileAvatar(emoji, btn) {
  selectedAvatar = emoji;
  document.querySelectorAll(".avatar-select-btn").forEach((b) => {
    b.style.borderColor = "rgba(255,255,255,0.1)";
    b.style.background = "rgba(255,255,255,0.05)";
  });
  if (btn) {
    btn.style.borderColor = "var(--accent-cyan)";
    btn.style.background = "rgba(255,255,255,0.1)";
  }
}

async function saveUserProfile() {
  const nickname = document.getElementById("profile-nickname").value;
  const target = document.getElementById("profile-target").value;
  const date = document.getElementById("profile-date").value;
  try {
    const res = await fetch(`${API_BASE}/api/user/profile`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        user_id: "u1",
        username: nickname,
        avatar: selectedAvatar,
        exam_target: target,
        target_date: date,
      }),
    });
    const d = await res.json();
    if (d && d.success) {
      showToast("💾 个人备考档案修改成功！");
      const usr = document.getElementById("nav-username");
      if (usr) usr.innerText = `${nickname} (${d.user.vip_tier || "VIP"})`;
    }
  } catch (err) {
    showToast("💾 个人档案修改已保存！(本地试用)");
  }
}

async function loadSettings() {
  try {
    const uRes = await fetch(`${API_BASE}/api/user?user_id=u1`);
    const u = await uRes.json();
    if (u) {
      const nickEl = document.getElementById("profile-nickname");
      if (nickEl) nickEl.value = u.username || "备考先锋小王";
      const targEl = document.getElementById("profile-target");
      if (targEl && u.exam_target) targEl.value = u.exam_target;
      const dateEl = document.getElementById("profile-date");
      if (dateEl && u.target_date) dateEl.value = u.target_date;
      const badgEl = document.getElementById("settings-vip-badge");
      if (badgEl)
        badgEl.innerText =
          u.vip_tier === "VIP"
            ? "👑 对赌私教年度 VIP"
            : u.vip_tier === "PRO"
              ? "🚀 冲刺 Pro 会员"
              : "🌱 体验版";
      const expEl = document.getElementById("settings-vip-expire");
      if (expEl) expEl.innerText = u.vip_expire_at || "永不过期";
      const rem = (u.token_quota || 50000) - (u.token_used || 0);
      const tokEl = document.getElementById("settings-token-val");
      if (tokEl) tokEl.innerText = rem.toLocaleString();
      const quotEl = document.getElementById("settings-token-quota");
      if (quotEl) quotEl.innerText = (u.token_quota || 50000).toLocaleString();
      const escEl = document.getElementById("settings-escrow-val");
      if (escEl) escEl.innerText = `￥${(u.escrow_balance || 99).toFixed(2)}`;
    }

    const lRes = await fetch(`${API_BASE}/api/user/ledgers?user_id=u1`);
    const lData = await lRes.json();
    const tbody = document.getElementById("ledgers-table-body");
    if (tbody && lData) {
      tbody.innerHTML = "";
      const allItems = [];
      (lData.orders || []).forEach((o) => {
        allItems.push({
          time: o.created_at,
          id: o.order_id,
          desc: `购买产品套件: ${o.package_id}`,
          val: `-￥${o.amount.toFixed(2)}`,
          status: `<span style="color: #39d353;">✔ 支付到账 (${o.status})</span>`,
        });
      });
      (lData.token_ledgers || []).forEach((t) => {
        allItems.push({
          time: t.created_at,
          id: t.id,
          desc: t.description,
          val: `${t.amount > 0 ? "+" : ""}${t.amount.toLocaleString()} Token`,
          status: `<span style="color: #38bdf8;">结余 ${t.balance_after.toLocaleString()}</span>`,
        });
      });
      allItems.sort((a, b) => new Date(b.time) - new Date(a.time));
      if (allItems.length === 0) {
        tbody.innerHTML = `<tr><td colspan="5" style="padding: 2rem; text-align: center;">暂无流水记录</td></tr>`;
      } else {
        allItems.forEach((item) => {
          const tr = document.createElement("tr");
          tr.style.borderBottom = "1px solid rgba(255,255,255,0.05)";
          tr.innerHTML = `
                  <td style="padding: 0.8rem 1rem; color: #94a3b8; font-size: 0.85rem;">${item.time ? item.time.replace("T", " ").substring(0, 19) : "近期"}</td>
                  <td style="padding: 0.8rem 1rem; font-family: monospace; color: #fff;">${item.id}</td>
                  <td style="padding: 0.8rem 1rem;">${item.desc}</td>
                  <td style="padding: 0.8rem 1rem; font-weight: 700; color: ${item.val.includes("-￥") ? "var(--accent-amber)" : item.val.includes("+") ? "#39d353" : "#fff"};">${item.val}</td>
                  <td style="padding: 0.8rem 1rem;">${item.status}</td>
                `;
          tbody.appendChild(tr);
        });
      }
    }
  } catch (err) {
    console.error("Failed to load settings:", err);
  }
}

function showToast(msg) {
  const t = document.getElementById("toast");
  t.innerText = msg;
  t.classList.add("show");
  setTimeout(() => t.classList.remove("show"), 3500);
}

async function loadDashboard() {
  const res = await fetch(`${API_BASE}/api/dashboard/heatmap`);
  const d = await res.json();
  document.getElementById("stat-days").innerText = d.total_active_days;
  document.getElementById("stat-streak").innerText = d.streak;
  document.getElementById("stat-questions").innerText =
    d.total_questions.toLocaleString();
  document.getElementById("stat-hours").innerText = d.total_study_hours;
  document.getElementById("stat-freeze").innerText = d.freeze_cards;
  document.getElementById("nav-streak").innerText = `🔥 ${d.streak} 天连签`;
  document.getElementById("nav-token").innerText =
    d.tokens_remaining.toLocaleString();
  document.getElementById("token-bar").style.width =
    `${Math.min(100, (d.tokens_remaining / d.token_quota) * 100)}%`;

  const careerMap = {
    1: "备考小白 (初级)",
    2: "实习科员 (五级)",
    3: "四级主任科员 (中级)",
    4: "业务正科长 (四级)",
    5: "调研员处长 (副高)",
    6: "厅局级顶梁柱 (最高)",
  };
  const cTitle = careerMap[d.career_level || 4] || "业务正科长 (四级)";
  const titleEl = document.getElementById("dash-career-title");
  if (titleEl) titleEl.innerText = cTitle;
  const beatEl = document.getElementById("dash-beat-pct");
  if (beatEl) beatEl.innerText = `🚀 ${d.beat_percentage || 94.5}%`;
  const effEl = document.getElementById("dash-focus-eff");
  if (effEl)
    effEl.innerText = `⚡ 备考时间经济比：${d.focus_efficiency || "高能专注 (省下线下机构￥3,200.00学费)"}`;

  if (d.companion_tree) {
    const tName = document.getElementById("tree-name");
    if (tName)
      tName.innerText = d.companion_tree.name || "上岸神树 (能量值 85/100)";
    const tStage = document.getElementById("tree-stage");
    if (tStage)
      tStage.innerText =
        d.companion_tree.stage ||
        "🌱 枝繁叶茂 - 距离开花结果还差 15 次有效专注";
  }

  const c = document.getElementById("heatmap-container");
  c.innerHTML = "";
  d.records.slice(-159).forEach((r, idx) => {
    const cell = document.createElement("div");
    cell.className = "heat-cell";
    cell.setAttribute("data-level", r.green_shade_level);
    cell.title = `${r.date}: 刷题 ${r.count} 道 ${r.count > 0 ? "(专注打卡有效+1)" : ""}`;
    if (r.count > 0 && idx % 7 === 3) {
      cell.innerHTML =
        '<span style="font-size:0.55rem; display:flex; align-items:center; justify-content:center; height:100%;">🔥</span>';
      cell.style.background = "linear-gradient(135deg, #ef4444, #f59e0b)";
      cell.style.boxShadow = "0 0 5px rgba(239, 68, 68, 0.8)";
    }
    c.appendChild(cell);
  });
}

async function checkCareerPromotion() {
  try {
    await fetch(`${API_BASE}/api/user/career/promote`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
  } catch (e) {}
  const res = await fetch(`${API_BASE}/api/user/career`);
  const d = await res.json();
  if (d && d.success) {
    document.getElementById("promo-cert-text").innerText =
      `【中国式公考备考·干部任免决定书】\n\n受封学员：备考先锋\n当前职务序列：${d.current_title} (Level ${d.current_level})\n\n${d.red_header_doc}\n\n组织考察语：\n鉴于该同志在行测五大模块与申论特训中表现出极佳的毅力与解题直觉，特颁发此电子任命状。下一阶段晋升目标为【${d.next_title}】，请不忘初心，继续精进！`;
    document.getElementById("modal-promotion").style.display = "flex";
    if (typeof loadCareer === "function") loadCareer();
    loadDashboard();
  } else {
    showToast("❌ 获取任免证书失败，请稍后重试");
  }
}

function closePromotionModal() {
  document.getElementById("modal-promotion").style.display = "none";
  showToast("🎉 任命书已存入干部履历档案！");
}

async function waterCompanionTree() {
  const res = await fetch(`${API_BASE}/api/user/tree/water`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user_id: "u1" }),
  });
  const d = await res.json();
  if (res.ok && d.success) {
    showToast("💦 浇水成功！消耗 50 Token，神树生机大幅提升！");
    loadDashboard();
  } else {
    showToast("⚠️ " + (d.error || "Token 算力不足或浇水失败"));
  }
}

// --- PRACTICE ENGINE & SKILL MASTERY TREE ---
let currentPracticeQuestions = [];
let currentPracticeIdx = 0;
let currentPracticeAnswers = {};
let practiceTimerInterval = null;
let practiceTimeLeft = 7200;

function loadPractice() {
  const defaultCard = document.getElementById("pmode-FULL_PAPER");
  if (defaultCard) selectPracticeMode("FULL_PAPER", defaultCard);
}

function selectPracticeMode(mode, el) {
  document.querySelectorAll(".practice-mode-card").forEach((c) => {
    c.classList.remove("active");
    c.style.borderColor = "rgba(255,255,255,0.1)";
    c.style.background = "rgba(30, 41, 59, 0.6)";
  });
  if (el) {
    el.classList.add("active");
    el.style.borderColor = "var(--accent-cyan)";
    el.style.background = "rgba(56, 189, 248, 0.15)";
  }
  const panel = document.getElementById("practice-config-panel");
  if (!panel) return;

  if (mode === "FULL_PAPER") {
    panel.innerHTML = `
            <h4 style="color: #fff; font-size: 1.1rem; margin-bottom: 1rem;">🏆 历年国家与地方公务员真题全真模考 (含命题组常态加权评分)</h4>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-bottom: 1.5rem;">
              <div class="paper-select-card active" onclick="selectPaperCard('2025-GUOKAO-XINGCE', this)" style="padding: 1.2rem; background: rgba(56, 189, 248, 0.2); border: 2px solid var(--accent-cyan); border-radius: 10px; cursor: pointer;">
                <div style="display:flex; justify-content:space-between; margin-bottom:0.5rem;"><span style="background:rgba(56,189,248,0.3); color:#fff; padding:0.1rem 0.5rem; border-radius:4px; font-size:0.75rem;">国考真题</span><span style="color:var(--accent-amber); font-weight:700;">★★★★★</span></div>
                <h5 style="color:#fff; font-size:1.05rem; margin-bottom:0.4rem;">2025年国家公务员考试《行测》副省级卷</h5>
                <p style="color:var(--text-muted); font-size:0.82rem;">含资料分析、言语理解、判断推理与数量关系精选试题，120分钟倒计时压迫训练。</p>
              </div>
              <div class="paper-select-card" onclick="selectPaperCard('2025-SHENGKAO-XINGCE', this)" style="padding: 1.2rem; background: rgba(30,41,59,0.5); border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; cursor: pointer;">
                <div style="display:flex; justify-content:space-between; margin-bottom:0.5rem;"><span style="background:rgba(16,185,129,0.3); color:#fff; padding:0.1rem 0.5rem; border-radius:4px; font-size:0.75rem;">省考真题</span><span style="color:var(--accent-amber); font-weight:700;">★★★★☆</span></div>
                <h5 style="color:#fff; font-size:1.05rem; margin-bottom:0.4rem;">2025年多省联考《行测》精选特训卷</h5>
                <p style="color:var(--text-muted); font-size:0.82rem;">强化判断推理与图形对称规律，适合备战省考考生的赛前押题冲刺。</p>
              </div>
            </div>
            <div style="text-align: center;">
              <button class="btn-hero-primary" onclick="startPracticeSession('FULL_PAPER', window.selectedPaperId || '2025-GUOKAO-XINGCE')" style="padding: 0.8rem 2.5rem; font-size: 1.1rem; background: linear-gradient(135deg, #0284c7, #38bdf8); border: none; border-radius: 10px; color: #fff; font-weight: 800; cursor: pointer; box-shadow: 0 0 20px rgba(56,189,248,0.4);">🚀 立即启动 3D 沉浸式模考舱 (开始计时)</button>
            </div>
          `;
  } else if (mode === "MODULE") {
    panel.innerHTML = `
            <h4 style="color: #fff; font-size: 1.1rem; margin-bottom: 1rem;">🧩 定制化行测模块专项秒刷特训</h4>
            <p style="color: var(--text-muted); font-size: 0.9rem; margin-bottom: 1.2rem;">选择单项或多项高频薄弱模块，系统自动从百万题库中抽取绝杀题组：</p>
            <div style="display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.5rem;">
              <button class="mod-pill active" onclick="selectModPill('资料分析', this)" style="padding: 0.8rem 1.5rem; background: rgba(56,189,248,0.2); border: 2px solid var(--accent-cyan); border-radius: 25px; color: #fff; font-weight: 700; cursor: pointer;">📊 资料分析 (极速截位)</button>
              <button class="mod-pill" onclick="selectModPill('言语理解', this)" style="padding: 0.8rem 1.5rem; background: rgba(30,41,59,0.6); border: 1px solid rgba(255,255,255,0.1); border-radius: 25px; color: #fff; font-weight: 700; cursor: pointer;">🗣️ 言语理解 (转折排异)</button>
              <button class="mod-pill" onclick="selectModPill('判断推理', this)" style="padding: 0.8rem 1.5rem; background: rgba(30,41,59,0.6); border: 1px solid rgba(255,255,255,0.1); border-radius: 25px; color: #fff; font-weight: 700; cursor: pointer;">⚙️ 判断推理 (逻辑图推)</button>
              <button class="mod-pill" onclick="selectModPill('数量关系', this)" style="padding: 0.8rem 1.5rem; background: rgba(30,41,59,0.6); border: 1px solid rgba(255,255,255,0.1); border-radius: 25px; color: #fff; font-weight: 700; cursor: pointer;">🔢 数量关系 (秒设公倍)</button>
            </div>
            <div style="text-align: center;">
              <button class="btn-hero-primary" onclick="startPracticeSession('MODULE', window.selectedModuleId || '资料分析')" style="padding: 0.8rem 2.5rem; font-size: 1.1rem; background: linear-gradient(135deg, #10b981, #059669); border: none; border-radius: 10px; color: #fff; font-weight: 800; cursor: pointer; box-shadow: 0 0 20px rgba(16,185,129,0.4);">⚡ 生成 15 题快速随练专项卷 -> </button>
            </div>
          `;
  } else if (mode === "SKILL_TAG") {
    panel.innerHTML = `
            <h4 style="color: #fff; font-size: 1.1rem; margin-bottom: 1rem;">🌳 考公知识树与技巧掌握度图谱突击 (Skill Mastery Tree)</h4>
            <p style="color: var(--text-muted); font-size: 0.9rem; margin-bottom: 1.2rem;">根据您近期热力图与模考数据，系统深度诊断了各专项解法技巧掌握的熟练度：</p>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1rem; margin-bottom: 1.5rem;">
              <div style="background: rgba(16,185,129,0.12); border: 1px solid rgba(16,185,129,0.4); padding: 1rem; border-radius: 10px; display:flex; flex-direction:column; justify-content:space-between;">
                <div><div style="display:flex; justify-content:space-between;"><span style="color:#34d399; font-weight:700;">🏷️ 截位直除法</span><span style="font-size:0.75rem; background:#065f46; color:#fff; padding:0.1rem 0.4rem; border-radius:4px;">熟练度 85%</span></div><p style="color:#94a3b8; font-size:0.8rem; margin:0.5rem 0;">资料分析秒杀大招，建议定期巩固。</p></div>
                <button onclick="startPracticeSession('SKILL_TAG', '截位直除法')" style="width:100%; margin-top:0.8rem; padding:0.4rem; background:#059669; border:none; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;">⚡ 刷此标签题</button>
              </div>
              <div style="background: rgba(244,63,92,0.12); border: 1px solid rgba(244,63,92,0.4); padding: 1rem; border-radius: 10px; display:flex; flex-direction:column; justify-content:space-between;">
                <div><div style="display:flex; justify-content:space-between;"><span style="color:#fb7185; font-weight:700;">🏷️ 对称性规律</span><span style="font-size:0.75rem; background:#9f1239; color:#fff; padding:0.1rem 0.4rem; border-radius:4px;">薄弱 32%</span></div><p style="color:#94a3b8; font-size:0.8rem; margin:0.5rem 0;">图推失分极高的急需突击薄弱项！</p></div>
                <button onclick="startPracticeSession('SKILL_TAG', '对称性规律')" style="width:100%; margin-top:0.8rem; padding:0.4rem; background:#e11d48; border:none; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;">🚨 强力补漏专练</button>
              </div>
              <div style="background: rgba(56,189,248,0.12); border: 1px solid rgba(56,189,248,0.4); padding: 1rem; border-radius: 10px; display:flex; flex-direction:column; justify-content:space-between;">
                <div><div style="display:flex; justify-content:space-between;"><span style="color:#38bdf8; font-weight:700;">🏷️ 概念辨析法</span><span style="font-size:0.75rem; background:#0369a1; color:#fff; padding:0.1rem 0.4rem; border-radius:4px;">熟练度 72%</span></div><p style="color:#94a3b8; font-size:0.8rem; margin:0.5rem 0;">百分比与百分点易错陷阱辨识。</p></div>
                <button onclick="startPracticeSession('SKILL_TAG', '概念辨析法')" style="width:100%; margin-top:0.8rem; padding:0.4rem; background:#0284c7; border:none; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;">⚡ 刷此标签题</button>
              </div>
              <div style="background: rgba(245,158,11,0.12); border: 1px solid rgba(245,158,11,0.4); padding: 1rem; border-radius: 10px; display:flex; flex-direction:column; justify-content:space-between;">
                <div><div style="display:flex; justify-content:space-between;"><span style="color:#fbbf24; font-weight:700;">🏷️ 工程赋值法</span><span style="font-size:0.75rem; background:#b45309; color:#fff; padding:0.1rem 0.4rem; border-radius:4px;">中等 58%</span></div><p style="color:#94a3b8; font-size:0.8rem; margin:0.5rem 0;">设最小公倍数总量秒杀经典方程题。</p></div>
                <button onclick="startPracticeSession('SKILL_TAG', '工程赋值法')" style="width:100%; margin-top:0.8rem; padding:0.4rem; background:#d97706; border:none; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;">🎯 突破训练</button>
              </div>
              <div style="background: rgba(168,85,247,0.12); border: 1px solid rgba(168,85,247,0.4); padding: 1rem; border-radius: 10px; display:flex; flex-direction:column; justify-content:space-between;">
                <div><div style="display:flex; justify-content:space-between;"><span style="color:#c084fc; font-weight:700;">🏷️ 转折锚定法</span><span style="font-size:0.75rem; background:#6b21a8; color:#fff; padding:0.1rem 0.4rem; border-radius:4px;">熟练度 90%</span></div><p style="color:#94a3b8; font-size:0.8rem; margin:0.5rem 0;">言语理解主题词与重点转折句秒排。</p></div>
                <button onclick="startPracticeSession('SKILL_TAG', '转折锚定法')" style="width:100%; margin-top:0.8rem; padding:0.4rem; background:#9333ea; border:none; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;">⚡ 刷此标签题</button>
              </div>
            </div>
          `;
  }
}

function selectPaperCard(id, el) {
  window.selectedPaperId = id;
  document.querySelectorAll(".paper-select-card").forEach((c) => {
    c.classList.remove("active");
    c.style.borderColor = "rgba(255,255,255,0.1)";
    c.style.background = "rgba(30,41,59,0.5)";
  });
  el.classList.add("active");
  el.style.borderColor = "var(--accent-cyan)";
  el.style.background = "rgba(56, 189, 248, 0.2)";
}

function selectModPill(id, el) {
  window.selectedModuleId = id;
  document.querySelectorAll(".mod-pill").forEach((c) => {
    c.classList.remove("active");
    c.style.borderColor = "rgba(255,255,255,0.1)";
    c.style.background = "rgba(30,41,59,0.6)";
  });
  el.classList.add("active");
  el.style.borderColor = "var(--accent-cyan)";
  el.style.background = "rgba(56,189,248,0.2)";
}

async function startPracticeSession(mode, targetId) {
  showToast("⏳ 正在组卷，启动 3D 沉浸式真题考场...");
  const res = await fetch(`${API_BASE}/api/practice/start`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mode, target_id: targetId }),
  });
  const d = await res.json();
  if (d && d.success && d.questions) {
    currentPracticeQuestions = d.questions;
    currentPracticeIdx = 0;
    currentPracticeAnswers = {};
    practiceTimeLeft = d.duration_minutes * 60;

    document.querySelector("#view-practice .glass-card").style.display = "none";
    document.getElementById("practice-result").style.display = "none";
    document.getElementById("practice-arena").style.display = "block";

    if (practiceTimerInterval) clearInterval(practiceTimerInterval);
    practiceTimerInterval = setInterval(() => {
      practiceTimeLeft--;
      if (practiceTimeLeft <= 0) {
        clearInterval(practiceTimerInterval);
        showToast("⏰ 模考倒计时结束！正在为您自动交卷！");
        submitPracticeSession();
        return;
      }
      const mins = Math.floor(practiceTimeLeft / 60);
      const secs = practiceTimeLeft % 60;
      const timerEl = document.getElementById("arena-timer");
      if (timerEl)
        timerEl.innerText = `⏱️ ${mins}:${secs < 10 ? "0" : ""}${secs}`;
    }, 1000);

    renderQuestion(0);
    updateAnswerSheetGrid();
  } else {
    showToast("❌ 组卷失败，请稍后重试");
  }
}

function renderQuestion(idx) {
  if (idx < 0 || idx >= currentPracticeQuestions.length) return;
  currentPracticeIdx = idx;
  const q = currentPracticeQuestions[idx];
  document.getElementById("arena-progress").innerText =
    `第 ${idx + 1} / ${currentPracticeQuestions.length} 题`;
  document.getElementById("arena-tag").innerText =
    `🏷️ ${q.skill_tag || q.module || "专项模考"}`;

  const myAns = currentPracticeAnswers[q.id];
  let optsHtml = q.options
    .map((o) => {
      const isSel =
        myAns === o.key
          ? "border-color: var(--accent-amber); background: rgba(245,158,11,0.2); box-shadow: 0 0 10px rgba(245,158,11,0.3);"
          : "border-color: rgba(255,255,255,0.1); background: rgba(30,41,59,0.5);";
      return `<div onclick="selectArenaOpt('${o.key}', '${q.id}', this)" style="padding: 1rem 1.2rem; border: 2px solid; ${isSel} border-radius: 10px; cursor: pointer; margin-bottom: 0.8rem; transition: all 0.2s; color: #fff; font-size: 1rem; display: flex; align-items: center;"><strong style="color: var(--accent-cyan); margin-right: 0.8rem; font-size: 1.1rem;">${o.key}.</strong> <span>${o.text}</span></div>`;
    })
    .join("");

  document.getElementById("arena-question-area").innerHTML = `
          <div style="display: flex; gap: 0.8rem; align-items: center; margin-bottom: 1rem;">
            <span style="background: rgba(16,185,129,0.2); color: var(--accent-green); font-size: 0.8rem; padding: 0.2rem 0.6rem; border-radius: 6px; font-weight: 700;">考区: ${q.module || "资料分析"}</span>
            <span style="color: var(--accent-amber);">难度: ${"★".repeat(q.difficulty || 3)}</span>
          </div>
          <h3 style="color: #fff; font-size: 1.25rem; line-height: 1.7; margin-bottom: 1.5rem; font-weight: 600;">${idx + 1}. ${q.content}</h3>
          <div style="margin-top: 1rem;">${optsHtml}</div>
        `;
}

function selectArenaOpt(optKey, qId, el) {
  currentPracticeAnswers[qId] = optKey;
  renderQuestion(currentPracticeIdx);
  updateAnswerSheetGrid();
}

function toggleAnswerSheet() {
  const sheet = document.getElementById("floating-answer-sheet");
  if (sheet)
    sheet.style.display = sheet.style.display === "none" ? "block" : "none";
}

function updateAnswerSheetGrid() {
  const countEl = document.getElementById("sheet-count");
  const doneCount = Object.keys(currentPracticeAnswers).length;
  if (countEl)
    countEl.innerText = `${doneCount}/${currentPracticeQuestions.length}`;

  const grid = document.getElementById("sheet-grid");
  if (!grid) return;
  grid.innerHTML = currentPracticeQuestions
    .map((q, idx) => {
      const hasAns = currentPracticeAnswers[q.id];
      const bg = hasAns
        ? "background: var(--accent-cyan); color: #fff; border-color: var(--accent-cyan); font-weight: 800;"
        : "background: rgba(30,41,59,0.8); color: var(--text-muted); border-color: rgba(255,255,255,0.1);";
      const curr =
        idx === currentPracticeIdx ? "box-shadow: 0 0 0 2px #fff;" : "";
      return `<div onclick="renderQuestion(${idx})" style="width: 38px; height: 38px; border-radius: 8px; border: 1px solid; display: flex; align-items: center; justify-content: center; cursor: pointer; ${bg} ${curr}">${idx + 1}</div>`;
    })
    .join("");
}

function navigateQuestion(dir) {
  const nIdx = currentPracticeIdx + dir;
  if (nIdx >= 0 && nIdx < currentPracticeQuestions.length) {
    renderQuestion(nIdx);
  } else if (nIdx >= currentPracticeQuestions.length) {
    showToast("📌已经是最后一题！您可以点击上方的【提前交卷并出分】");
  }
}

function openAITutorForCurrent() {
  if (
    currentPracticeQuestions &&
    currentPracticeQuestions[currentPracticeIdx]
  ) {
    openAITutor(currentPracticeQuestions[currentPracticeIdx].id, "花生十三");
  } else {
    openAITutor("q101", "花生十三");
  }
}

async function submitPracticeSession() {
  if (practiceTimerInterval) clearInterval(practiceTimerInterval);
  showToast("⏳ 正在自动提交模考试卷与计算加权偏离度...");
  const res = await fetch(`${API_BASE}/api/practice/submit`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ answers: currentPracticeAnswers }),
  });
  const d = await res.json();
  if (d && d.success) {
    document.getElementById("practice-arena").style.display = "none";
    const resCard = document.getElementById("practice-result");
    if (resCard) resCard.style.display = "block";
    document.getElementById("res-score").innerText = `${d.score} 分`;
    document.getElementById("res-beat").innerText =
      `超越 ${d.beat_percentage}%`;
    document.getElementById("res-counts").innerText =
      `${d.correct_count} / ${d.total_count}`;

    const radarEl = document.getElementById("res-radar-bars");
    if (radarEl && d.radar_metrics) {
      radarEl.innerHTML = Object.entries(d.radar_metrics)
        .map(
          ([mod, val]) => `
              <div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 0.3rem;"><span style="color: #fff; font-size: 0.9rem;">🧩 ${mod}</span><strong style="color: var(--accent-cyan);">${val} / 100</strong></div>
                <div style="width: 100%; background: #1e293b; height: 8px; border-radius: 4px; overflow: hidden;"><div style="width: ${val}%; background: linear-gradient(90deg, #0284c7, var(--accent-cyan)); height: 100%;"></div></div>
              </div>
            `,
        )
        .join("");
    }
    showToast("🎉 模考出分完毕！建议前往一题多解区查看名师切片！");
  } else {
    showToast("❌ 提交模考结果出现异常");
  }
}

function resetPracticeArena() {
  document.getElementById("practice-result").style.display = "none";
  document.querySelector("#view-practice .glass-card").style.display = "block";
  loadPractice();
}

async function loadSolutions() {
  const res = await fetch(`${API_BASE}/api/questions`);
  const qs = await res.json();
  const c = document.getElementById("questions-container");
  c.innerHTML = "";
  qs.forEach((q, idx) => {
    const card = document.createElement("div");
    card.className = "question-card";
    let tabs = "",
      sols = "";
    q.solutions.forEach((s, sIdx) => {
      const act = sIdx === 0 ? "active" : "";
      const disp = sIdx === 0 ? "block" : "none";
      tabs += `<button class="sol-tab-btn ${act}" onclick="toggleSol(${idx},${sIdx},this)">🏷️ ${s.teacher_name} (${s.time_spent_eval || "15秒"})</button>`;
      if (s.locked) {
        sols += `<div class="sol-content-box sol-box-${idx}" id="sol-box-${idx}-${sIdx}" style="display:${disp}; position:relative; overflow:hidden; border:1px solid rgba(244,63,92,0.4); background:rgba(15,23,42,0.85); border-radius:10px; padding:1.5rem;">
                <div style="filter:blur(6px); opacity:0.25; pointer-events:none;">
                  <h4 style="color:var(--accent-cyan); margin-bottom:0.6rem;">⚡ ${s.approach_name}</h4>
                  <p style="color:#e2e8f0; font-size:0.95rem;">【名师独家秒杀口算秘籍】通过观察选项目前两位数字的特征差距，若差距大于8%，可直接采用左两位截位除法进行高速粗略预估，瞬间锁定唯一解...</p>
                </div>
                <div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; background:rgba(15,23,42,0.88); backdrop-filter:blur(8px); padding:1.5rem; text-align:center; border:1px solid rgba(244,63,92,0.3); border-radius:10px;">
                  <span style="font-size:2.2rem; margin-bottom:0.5rem;">🔒</span>
                  <h4 style="color:#f43f5e; font-size:1.1rem; margin-bottom:0.5rem;">名师绝杀大招 · Pro/VIP 专属付费墙</h4>
                  <p style="color:#cbd5e1; font-size:0.88rem; max-width:340px; margin-bottom:1.2rem; line-height:1.5;">💡 该绝杀切片由原命题组名师研发，可省去竖式计算，帮您节省 80% 考场时间！立即升级解锁全库 128 个大招！</p>
                  <button class="btn-hero-primary" style="padding:0.6rem 1.5rem; font-size:0.9rem; background:linear-gradient(135deg,#f43f5e,#fb7185); border:none; border-radius:8px; color:#fff; font-weight:800; cursor:pointer; box-shadow:0 0 15px rgba(244,63,92,0.4);" onclick="openCashier('PRO', 299)">👑 ￥299 立即升级解锁大招 -> </button>
                </div>
              </div>`;
      } else {
        sols += `<div class="sol-content-box sol-box-${idx}" id="sol-box-${idx}-${sIdx}" style="display:${disp};"><h4 style="color:var(--accent-cyan); margin-bottom:0.6rem;">⚡ ${s.approach_name} ${s.is_ai_generated ? '<span style="font-size:0.75rem; background:rgba(192,132,252,0.3); color:#fff; padding:0.1rem 0.5rem; border-radius:4px;">AI 名师蒸馏</span>' : ""}</h4><p style="color:#e2e8f0; font-size:0.95rem; line-height:1.6;">${s.content}</p><div class="sol-footer" style="margin-top:1.2rem; pt:1rem; border-top:1px solid rgba(255,255,255,0.08); display:flex; justify-content:space-between; align-items:center;"><span style="font-size:0.85rem; color:var(--text-muted);">🌟 契合度与点赞: <strong id="upval-${s.id}" style="color:var(--accent-amber); font-size:1rem;">${s.upvotes}</strong> 赞</span><div style="display:flex; gap:0.6rem;"><button class="upvote-btn" style="background:transparent; border-color:var(--accent-cyan); color:var(--accent-cyan); font-weight:700;" onclick="openAITutor('${q.id}', '${s.teacher_name}')">🤖 提问该名师</button><button class="upvote-btn" style="background:rgba(245,158,11,0.15); border-color:var(--accent-amber); color:var(--accent-amber); font-weight:700;" onclick="upvote('${s.id}')">👍 投TA一票 (优选TA的解法)</button></div></div></div>`;
      }
    });
    card.innerHTML = `<div class="q-header"><span class="q-tag">📌 模块: ${q.module || "资料分析"} | 技巧: ${q.skill_tag || "截位直算法"}</span><span style="color:var(--accent-amber);">难度: ${"★".repeat(q.difficulty || 3)}</span></div><div class="q-content">${idx + 1}. ${q.content}</div><div class="q-options">${q.options.map((o) => `<div class="q-opt ${o.key === q.correct_answer ? "correct" : ""}" onclick="selectOpt(this)">${o.key}. ${o.text}</div>`).join("")}</div><div class="solutions-area"><div class="sol-tabs">${tabs}</div>${sols}</div>`;
    c.appendChild(card);
  });
}

function toggleSol(idx, sIdx, btn) {
  const p = btn.closest(".solutions-area");
  p.querySelectorAll(".sol-tab-btn").forEach((b) =>
    b.classList.remove("active"),
  );
  p.querySelectorAll(`.sol-box-${idx}`).forEach(
    (box) => (box.style.display = "none"),
  );
  btn.classList.add("active");
  document.getElementById(`sol-box-${idx}-${sIdx}`).style.display = "block";
}

function selectOpt(e) {
  showToast(
    e.classList.contains("correct")
      ? "🎉 回答正确！精准秒杀！"
      : "💡 回答错误，请展开下方的名师绝杀解法对照！",
  );
}
async function upvote(id) {
  const res = await fetch(`${API_BASE}/api/solutions/vote`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ solution_id: id, action: "UPVOTE" }),
  });
  const d = await res.json();
  if (d && d.success) {
    const el = document.getElementById(`upval-${id}`);
    if (el) el.innerText = d.upvotes;
    showToast(
      "🎉 投票成功！该名师思路偏好已记入个人契合度引擎，后续刷题将优先展示TA的解析！",
    );
  } else {
    showToast("❌ 投票记录失败");
  }
}

async function loadSkills() {
  const res = await fetch(`${API_BASE}/api/skills/mastery`);
  const sk = await res.json();
  const c = document.getElementById("skills-container");
  c.innerHTML = "";
  sk.forEach((s) => {
    const item = document.createElement("div");
    item.className = "skill-item";
    const bg =
      s.status === "WEAK"
        ? "weak"
        : s.status === "EXCELLENT"
          ? "excellent"
          : "good";
    const txt =
      s.status === "WEAK"
        ? "🚨 薄弱急需强化"
        : s.status === "EXCELLENT"
          ? "🌟 纯熟极速秒杀"
          : "👍 良好水平";
    item.innerHTML = `<div><h4>${s.name}</h4><p style="font-size:0.8rem; color:var(--text-muted);">EMA 掌握度: <strong style="color:#fff;">${s.composite_score}分</strong> | 均速: ${s.avg_time_sec}秒 (基准 ${s.benchmark_time_sec}秒)</p></div><span class="skill-badge ${bg}">${txt}</span>`;
    c.appendChild(item);
  });
}
async function loadMistakes() {
  const res = await fetch(`${API_BASE}/api/mistakes/tree`);
  const d = await res.json();
  const c = document.getElementById("mistakes-tree-container");
  if (!c) return;
  c.innerHTML = "";
  if (d.success && d.tree) {
    d.tree.forEach((item) => {
      const card = document.createElement("div");
      card.style.cssText =
        "background:rgba(30,41,59,0.7); border:1px solid rgba(255,255,255,0.08); padding:1.2rem; border-radius:10px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:1rem;";
      card.innerHTML = `
              <div style="flex:1; min-width:260px;">
                <div style="display:flex; align-items:center; gap:0.6rem; margin-bottom:0.4rem;">
                  <span style="background:rgba(244,63,94,0.2); color:#f43f5e; padding:0.2rem 0.6rem; border-radius:12px; font-size:0.8rem; font-weight:700;">高频错误: ${item.error_count} 次</span>
                  <span style="color:var(--text-muted); font-size:0.85rem;">当前准确率: <strong style="color:${item.accuracy < 50 ? "#f43f5e" : "#fbbf24"};">${item.accuracy}%</strong></span>
                </div>
                <h3 style="color:#fff; font-size:1.15rem; margin-bottom:0.6rem;">${item.name}</h3>
                <div style="background:rgba(15,23,42,0.6); border-left:3px solid #f59e0b; padding:0.6rem 0.8rem; border-radius:4px; font-size:0.88rem; color:#e2e8f0; line-height:1.5;">
                  ${item.prescription}
                </div>
              </div>
              <div>
                <button onclick="triggerRemediate('${item.skill_id}')" style="background:linear-gradient(135deg,#f43f5e,#e11d48); color:#fff; border:none; padding:0.7rem 1.4rem; border-radius:8px; font-weight:800; cursor:pointer; box-shadow:0 0 15px rgba(244,63,94,0.3); transition:all 0.2s;">
                  ⚡ 立即攻克心魔 (${item.skill_id} 特训) ->
                </button>
              </div>
            `;
      c.appendChild(card);
    });
  }
}

async function triggerRemediate(skillId) {
  showToast("⏳ 正在结合近期常错雷达数据为您抽取专项消盲真题...");
  const res = await fetch(`${API_BASE}/api/mistakes/remediate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(skillId ? { skill_id: skillId } : {}),
  });
  const d = await res.json();
  if (d && d.success) {
    showToast(d.message);
    if (d.questions && d.questions.length > 0) {
      currentPracticeQuestions = d.questions;
      currentPracticeIndex = 0;
      currentPracticeAnswers = {};
      switchTab("practice");
      const modeText = document.getElementById("practice-mode-text");
      if (modeText)
        modeText.innerText = `💊 错题药方靶向消盲特训 (${d.questions.length} 题)`;
      renderPracticeArena();
    } else {
      setTimeout(() => switchTab("solutions"), 1000);
    }
  }
}

async function loadCohorts() {
  const res = await fetch(`${API_BASE}/api/cohorts`);
  const ch = await res.json();
  const c = document.getElementById("cohorts-container");
  c.innerHTML = "";
  ch.forEach((h) => {
    const card = document.createElement("div");
    card.className = "cohort-card";
    const statusBadge = h.user_joined
      ? h.user_status === "COMPLETED"
        ? `<span style="background:#059669; color:#fff; padding:0.2rem 0.6rem; border-radius:15px; font-size:0.8rem; font-weight:700;">✅ 已成功结营清算</span>`
        : `<span style="background:rgba(16,185,129,0.2); color:#34d399; padding:0.2rem 0.6rem; border-radius:15px; font-size:0.8rem; font-weight:700;">🟢 已在营打卡中</span>`
      : `<span style="background:rgba(245,158,11,0.2); color:#fbbf24; padding:0.2rem 0.6rem; border-radius:15px; font-size:0.8rem; font-weight:700;">⏳ 招募报名中 (席位剩 ${250 - h.total_members})</span>`;

    const actionBtn = h.user_joined
      ? h.user_status === "COMPLETED"
        ? `<button class="btn-checkin" style="background:#334155; cursor:not-allowed;" disabled>✅ 本期契约已通关返款</button>`
        : `<div style="display:flex; flex-direction:column; gap:0.6rem; margin-top:1rem;"><button class="btn-checkin" onclick="checkin('${h.id}')">⚡ 触发今日自动契约打卡 (+1天)</button><button onclick="settleCohort('${h.id}')" style="background:transparent; border:1px solid #f43f5e; color:#f43f5e; padding:0.6rem; border-radius:8px; font-weight:700; cursor:pointer; transition:all 0.2s;">🏆 申请结营清算与瓜分分红 (100%返款+奖金)</button></div>`
      : `<button class="btn-hero-primary" style="margin-top:1rem; width:100%; background:linear-gradient(135deg,#f59e0b,#d97706); border:none; padding:0.8rem; border-radius:8px; color:#fff; font-weight:800; cursor:pointer; box-shadow:0 0 15px rgba(245,158,11,0.3);" onclick="joinCohort('${h.id}', ${h.deposit_amount})">🤝 锁入 ￥${h.deposit_amount} 押金参营对赌 -> </button>`;

    card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center;">${statusBadge}<span style="color:var(--text-muted); font-size:0.8rem;">契约周期: ${h.start_date.slice(5)} ~ ${h.end_date.slice(5)}</span></div>
            <h3 style="margin:0.8rem 0; font-size:1.15rem; color:#fff;">${h.title}</h3>
            <div class="pool-banner" style="background:rgba(15,23,42,0.8); border:1px solid rgba(245,158,11,0.4); padding:0.8rem 1rem; border-radius:8px; display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem;">
              <div><span style="color:var(--text-muted); font-size:0.8rem; display:block;">💰 当前契约对赌分红总池</span><span style="color:var(--accent-amber); font-weight:900; font-size:1.3rem;">￥${h.pool_amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span></div>
              <div style="text-align:right;"><span style="color:var(--text-muted); font-size:0.8rem; display:block;">参营人数 / 契约费率</span><span style="color:var(--accent-cyan); font-weight:700;">${h.total_members} 人 | 平台担保 15%</span></div>
            </div>
            <p style="color:var(--text-muted); font-size:0.85rem; margin-bottom:0.8rem;">今日已坚持打卡: <strong style="color:var(--accent-green);">${h.completed_today}</strong> 人 <span style="margin-left:10px;">个人进度: <strong style="color:var(--accent-cyan);">${h.user_checkins_count || 0}</strong> 天</span></p>
            <div class="squad-box" style="background:rgba(30,41,59,0.5); padding:0.8rem; border-radius:8px; border:1px solid rgba(255,255,255,0.05);">
              <div style="font-size:0.85rem; color:var(--accent-cyan); font-weight:700; margin-bottom:0.4rem;">👥 您的4人死党互审小队状态：</div>
              ${h.squad_members.map((s) => `<div style="display:flex; justify-content:space-between; padding:0.3rem 0; border-bottom:1px solid rgba(255,255,255,0.04); font-size:0.88rem;"><span style="color:#e2e8f0;">${s.name} (${s.streak}天连签)</span><strong style="color:${s.today_done ? "var(--accent-green)" : "var(--accent-rose)"};">${s.today_done ? "✅ 已达标" : "⏳ 待打卡"}</strong></div>`).join("")}
            </div>
            ${actionBtn}
          `;
    c.appendChild(card);
  });
}

async function joinCohort(id, amount) {
  showToast("⏳ 正在核验证件与扣减个人现金余额以锁入对赌契约...");
  const res = await fetch(`${API_BASE}/api/cohorts/join`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ cohort_id: id }),
  });
  const d = await res.json();
  if (d && d.success) {
    showToast(d.message);
    loadCohorts();
    if (typeof loadSettings === "function") loadSettings();
  } else {
    showToast("⚠️ " + (d ? d.error : "入营失败"));
    if (d && d.code === "INSUFFICIENT_FUNDS") {
      setTimeout(() => openCashier("PRO", amount), 1500);
    }
  }
}

async function settleCohort(id) {
  if (
    !confirm(
      "🏆 确认申请对赌营结营清算？\n\n系统将按照商定契约，全额返还您锁入的学费押金，并按幸存人数比例瓜分流约奖金池（平台仅提取 15% 商业担保与服务费）。资金将实时打入您的可提现现金余额！",
    )
  )
    return;
  showToast("⏳ 正在核查全营考勤履历与执行 15% 平台服务费清算...");
  const res = await fetch(`${API_BASE}/api/cohorts/settle`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ cohort_id: id }),
  });
  const d = await res.json();
  if (d && d.success) {
    showToast(d.message);
    const rep = d.settlement_report;
    alert(
      `🎉【${rep.cohort_title} · 终审清算单】\n\n💰 原学费押金返还：￥${rep.deposit_returned.toFixed(2)} (100%返本)\n🎁 瓜分违约池奖金：+￥${rep.bonus_earned.toFixed(2)}\n🏢 平台契约担保费(15%)：-￥${rep.platform_fee_deducted.toFixed(2)}\n👥 全营坚持通关人数：${rep.survivors_count} 人\n💵 本次到账现金总额：￥${rep.total_payout.toFixed(2)}\n\n✨ 您的账户最新可提现余额为：￥${rep.new_cash_balance.toFixed(2)}`,
    );
    loadCohorts();
    if (typeof loadSettings === "function") loadSettings();
  } else {
    showToast("⚠️ " + (d ? d.error : "结营失败"));
  }
}

async function checkin(id) {
  const res = await fetch(`${API_BASE}/api/cohorts/${id}/checkin`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ proof_type: "AUTO" }),
  });
  const d = await res.json();
  showToast(d.message);
  loadCohorts();
  loadDashboard();
}

let allStrategiesList = [];
async function loadStrategies() {
  const res = await fetch(`${API_BASE}/api/strategies`);
  allStrategiesList = await res.json();
  renderStrategiesList("ALL");
}

function filterStrategies(filter, btn) {
  if (btn) {
    document.querySelectorAll(".strat-filter-btn").forEach((b) => {
      b.classList.remove("active");
      b.style.borderColor = "rgba(255,255,255,0.1)";
      b.style.background = "rgba(30,41,59,0.6)";
    });
    btn.classList.add("active");
    btn.style.borderColor = "var(--accent-cyan)";
    btn.style.background = "rgba(56,189,248,0.2)";
  }
  renderStrategiesList(filter);
}

function renderStrategiesList(filter) {
  const c = document.getElementById("strategies-container");
  if (!c) return;
  c.innerHTML = "";
  let list = allStrategiesList;
  if (filter && filter !== "ALL") {
    list = list.filter(
      (s) =>
        s.title.includes(filter) ||
        (s.timeline_data &&
          s.timeline_data.some(
            (t) => t.phase.includes(filter) || t.focus.includes(filter),
          )),
    );
  }
  list.forEach((s) => {
    const card = document.createElement("div");
    card.className = "strat-card";
    card.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;"><span style="color:var(--accent-cyan); font-weight:700; font-size:0.85rem;">📌 状元认证路线图</span><span style="color:var(--text-muted); font-size:0.8rem;">被 Fork ${s.forked_count} 次</span></div>
            <h3 style="font-size:1.25rem; color:#fff; margin-bottom:0.4rem;">${s.author_avatar} ${s.title}</h3>
            <p style="color:var(--text-muted); font-size:0.9rem; margin-bottom:1rem;">由 <strong style="color:var(--accent-amber);">${s.author_name}</strong> 独创 | 原规划周期：<strong style="color:#fff;">${s.days_total}</strong> 天</p>
            <div class="fork-form" style="background:rgba(30,41,59,0.7); padding:1rem; border-radius:8px; border:1px solid rgba(255,255,255,0.08); display:flex; align-items:center; gap:0.8rem; flex-wrap:wrap; margin-bottom:1.5rem;">
              <span style="color:var(--accent-amber); font-weight:700; font-size:0.9rem;">⚡ 目标考期智能倒推配置：</span>
              <span style="color:var(--text-muted); font-size:0.85rem;">目标日:</span> <input type="date" class="fork-input" id="dt-${s.id}" value="2026-11-28" style="background:#0f172a; color:#fff; border:1px solid rgba(255,255,255,0.2); padding:0.4rem 0.6rem; border-radius:6px;">
              <span style="color:var(--text-muted); font-size:0.85rem;">日学时:</span> <input type="number" class="fork-input" id="hr-${s.id}" value="3.5" style="width:70px; background:#0f172a; color:#fff; border:1px solid rgba(255,255,255,0.2); padding:0.4rem 0.6rem; border-radius:6px;">
              <button class="btn-fork" style="background:linear-gradient(135deg,#8b5cf6,#6d28d9); border:none; padding:0.5rem 1.2rem; border-radius:6px; color:#fff; font-weight:700; cursor:pointer;" onclick="forkStrat('${s.id}')">🚀 一键 Fork 派生个人计划</button>
            </div>
            <div style="border-left:2px solid var(--accent-cyan); margin-left:0.5rem; padding-left:1.5rem;">
              ${s.timeline_data.map((t) => `<div style="margin-bottom:1.2rem;"><h4 style="color:#fff; font-size:1.05rem; margin-bottom:0.3rem;">🎯 ${t.phase}</h4><p style="color:var(--accent-cyan); font-size:0.9rem; margin-bottom:0.3rem;">重点突破：${t.focus}</p><p style="color:var(--text-muted); font-size:0.85rem;">每日目标: <strong style="color:#fff;">${t.daily_questions}</strong> 题 | 建议学时: ${t.daily_hours} 小时 | 推荐名师: <span style="color:var(--accent-green);">${t.recommended_teacher || "全库匹配"}</span></p></div>`).join("")}
            </div>
          `;
    c.appendChild(card);
  });
}
async function forkStrat(id) {
  const res = await fetch(`${API_BASE}/api/strategies/${id}/fork`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target_date: document.getElementById(`dt-${id}`).value,
      daily_hours: document.getElementById(`hr-${id}`).value,
    }),
  });
  const d = await res.json();
  showToast(d.message);
  loadStrategies();
}

// --- ADMIN MODULE FUNCTIONS ---
async function discoverModels() {
  const u = document.getElementById("adm-base-url").value;
  const k = document.getElementById("adm-api-key").value;
  const res = await fetch(`${API_BASE}/api/admin/llm/discover-models`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ base_url: u, api_key: k }),
  });
  const d = await res.json();
  if (d.success) {
    const sel = document.getElementById("adm-model-select");
    sel.innerHTML = "";
    d.models.forEach((m) => {
      const o = document.createElement("option");
      o.value = m;
      o.innerText = m;
      sel.appendChild(o);
    });
    showToast(d.message);
  }
}
async function saveLLMConfig() {
  const m = document.getElementById("adm-model-select").value;
  const res = await fetch(`${API_BASE}/api/admin/llm/config`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ active_model: m }),
  });
  const d = await res.json();
  if (d.success) showToast(d.message);
}
async function ingestPDF() {
  const f = document.getElementById("adm-pdf-file").files[0];
  const log = document.getElementById("adm-ingest-log");
  log.style.display = "block";
  log.innerHTML =
    "[SYSTEM] 正在解析真题 PDF 文本...<br>[LLM] 正在进行阶段一：排版清洗与 JSON 抽取...<br>[LLM] 正在进行阶段二：三级考点自动分类打标签...<br>[LLM] 正在调用名师 Skill 蒸馏生成多解法...";
  const res = await fetch(`${API_BASE}/api/admin/ingest/pdf`, {
    method: "POST",
  });
  const d = await res.json();
  if (d.success) {
    setTimeout(() => {
      log.innerHTML += `<br><strong style="color:var(--accent-green);">[SUCCESS] 成功摄取！已自动将整卷习题及 AI 解析并入题库！</strong>`;
      showToast(d.message);
    }, 2500);
  }
}
async function toggleReg() {
  allowReg = !allowReg;
  const res = await fetch(`${API_BASE}/api/admin/settings`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ allow_registration: allowReg }),
  });
  const d = await res.json();
  const btn = document.getElementById("btn-reg-toggle");
  btn.innerText = allowReg ? "🟢 已开启注册" : "🔴 注册已关停";
  btn.style.background = allowReg ? "" : "var(--accent-rose)";
  showToast(`平台普通用户注册功能已${allowReg ? "开启" : "关停"}！`);
}
async function updateQuota(uId) {
  const val = document.getElementById("adm-token-quota").value;
  const res = await fetch(`${API_BASE}/api/admin/users/${uId}/quota`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token_quota: val }),
  });
  const d = await res.json();
  if (d.success) {
    showToast(d.message);
    loadDashboard();
  }
}
async function syncGitHub() {
  const url = document.getElementById("adm-gh-repo").value;
  const res = await fetch(`${API_BASE}/api/admin/github-sync`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ repo_url: url }),
  });
  const d = await res.json();
  if (d.success) showToast(d.message);
}

// --- AI TUTOR FUNCTIONS ---
function openAITutor(qId, tName) {
  activeQId = qId;
  activeTeacher = tName;
  document.getElementById("modal-teacher-name").innerText = tName;
  document.getElementById("modal-reply").style.display = "none";
  document.getElementById("ai-modal").style.display = "flex";
}
function closeAITutor() {
  document.getElementById("ai-modal").style.display = "none";
}
async function submitAIQuestion() {
  const prompt = document.getElementById("modal-prompt").value;
  const replyBox = document.getElementById("modal-reply");
  replyBox.style.display = "block";
  replyBox.innerHTML =
    "🤖 <span style='color:var(--accent-amber);'>专属名师 AI 分身正在为您流式推演答题链路...</span>";
  try {
    const res = await fetch(`${API_BASE}/api/ai/ask-stream`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question_id: activeQId,
        teacher_name: activeTeacher,
        prompt: prompt,
      }),
    });
    if (res.status === 402) {
      const d = await res.json();
      replyBox.innerHTML = `<span style='color:var(--accent-rose); font-weight:700;'>${d.error}</span><div style="margin-top:1rem;"><button onclick="openCashier('PRO', 68)" style="background:linear-gradient(135deg,#f59e0b,#d97706); border:none; padding:0.6rem 1.2rem; border-radius:6px; color:#fff; font-weight:800; cursor:pointer;">💎 立即前往收银台充值 / 升级会员</button></div>`;
      showToast("⚠️ Token 配额已耗尽，请充值！");
      return;
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder("utf-8");
    let fullText = "";
    let meta = null;
    replyBox.innerHTML =
      "<div id='sse-text' style='line-height:1.6;'></div><div id='sse-meta' style='margin-top:1rem; border-top:1px dashed rgba(255,255,255,0.1); padding-top:0.6rem; font-size:0.8rem; color:var(--text-muted);'></div>";
    const textBox = document.getElementById("sse-text");
    const metaBox = document.getElementById("sse-meta");
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split("\n");
      for (let l of lines) {
        if (l.startsWith("data: ")) {
          try {
            const data = JSON.parse(l.slice(6));
            if (data.type === "start") {
              meta = data;
              metaBox.innerHTML = `⚡ 算力引擎: ${meta.model_used} | 消耗 Tokens: <strong style="color:var(--accent-amber);">${meta.tokens_consumed}</strong> | 剩余配额: <strong style="color:var(--accent-green);">${Math.max(0, meta.token_quota - meta.token_used).toLocaleString()}</strong>`;
              if (document.getElementById("nav-token")) {
                document.getElementById("nav-token").innerText = Math.max(
                  0,
                  meta.token_quota - meta.token_used,
                ).toLocaleString();
              }
            } else if (data.type === "chunk") {
              fullText += data.text;
              textBox.innerHTML =
                fullText +
                "<span style='display:inline-block; width:6px; height:14px; background:var(--accent-cyan); margin-left:4px;'></span>";
              replyBox.scrollTop = replyBox.scrollHeight;
            } else if (data.type === "done") {
              textBox.innerHTML = fullText;
            }
          } catch (e) {}
        }
      }
    }
  } catch (err) {
    replyBox.innerHTML =
      "<span style='color:var(--accent-rose);'>发生网络连接错误，请重试！</span>";
  }
}

// --- REINFORCEMENT UI MODULES ---
async function loadCareer() {
  const res = await fetch(`${API_BASE}/api/user/career`);
  const d = await res.json();
  const c = document.getElementById("career-container");
  if (d.success) {
    c.innerHTML = `
            <div style="text-align: center; margin-bottom: 1.5rem;">
              <span style="font-size: 4rem;">🎖️</span>
              <h2 style="color: var(--accent-amber); font-size: 1.8rem; margin: 0.5rem 0;">当前行政序列职务：【${d.current_title}】 (Lv.${d.current_level})</h2>
              <p style="color: var(--text-muted);">下一目标职级：<strong style="color: #fff;">${d.next_title}</strong></p>
            </div>
            ${
              d.progress
                ? `
            <div style="background: rgba(0,0,0,0.4); padding: 1.2rem; border-radius: 10px; margin-bottom: 1.5rem;">
              <h4 style="color: var(--accent-cyan); margin-bottom: 0.8rem;">📈 晋升业绩考察指标</h4>
              <p style="margin-bottom: 0.4rem;">累计做题总数: <strong style="color: var(--accent-green);">${d.progress.questions_current}</strong> / ${d.progress.questions_required} 题</p>
              <div style="width:100%; background:#1e293b; height:8px; border-radius:4px; margin-bottom: 1rem;"><div style="width:${Math.min(100, (d.progress.questions_current / d.progress.questions_required) * 100)}%; background:var(--accent-green); height:100%;"></div></div>
              <p style="margin-bottom: 0.4rem;">连续打卡天数: <strong style="color: var(--accent-amber);">${d.progress.streak_current}</strong> / ${d.progress.streak_required} 天</p>
              <div style="width:100%; background:#1e293b; height:8px; border-radius:4px;"><div style="width:${Math.min(100, (d.progress.streak_current / d.progress.streak_required) * 100)}%; background:var(--accent-amber); height:100%;"></div></div>
            </div>`
                : ""
            }
            <div style="border: 2px solid #dc2626; background: rgba(220, 38, 38, 0.08); padding: 1.5rem; border-radius: 12px; position: relative;">
              <div style="color: #dc2626; font-weight: 800; font-size: 1.1rem; text-align: center; border-bottom: 1px solid #dc2626; padding-bottom: 0.5rem; margin-bottom: 1rem;">📜 中共考公备考辅助系统委员会 · 电子任命文件</div>
              <p style="color: #fff; font-size: 1.05rem; line-height: 1.6; white-space: pre-line;">${d.red_header_doc}</p>
            </div>
          `;
  }
}

async function promoteCareer() {
  const res = await fetch(`${API_BASE}/api/user/career/promote`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  const d = await res.json();
  if (d.success) {
    showToast(`🎉 恭喜晋升为【${d.new_title}】！`);
    loadCareer();
    loadDashboard();
  } else {
    showToast(d.message);
  }
}

async function loadRaid() {
  const res = await fetch(`${API_BASE}/api/raid/bosses`);
  const d = await res.json();
  const c = document.getElementById("raid-container");
  if (d.success) {
    c.innerHTML = d.bosses
      .map(
        (b) => `
            <div class="cohort-card" style="border-color: var(--accent-rose);">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h3 style="color: var(--accent-rose); font-size: 1.2rem;">👾 ${b.skill_name}</h3>
                <span style="font-size: 0.85rem; background: rgba(244,63,92,0.2); color: var(--accent-rose); padding: 0.2rem 0.6rem; border-radius: 6px; font-weight: 700;">心魔系数 ${b.difficulty}</span>
              </div>
              <p style="color: #fff; font-size: 0.95rem; margin-bottom: 1rem;">⚠️ 诱因诊断：${b.desc}</p>
              <div class="pool-banner" style="background: rgba(244,63,92,0.1); border-color: rgba(244,63,92,0.3); color: var(--accent-rose);">
                <span>当前护盾 HP: <strong>${b.hp}</strong> / ${b.max_hp}</span>
                <span style="font-size: 0.9rem;">全网击杀 ${d.slayed_count} 次</span>
              </div>
              <button class="btn-checkin" style="background: linear-gradient(135deg, var(--accent-rose), #e11d48);" onclick="attackBoss('${b.boss_id}')">⚡ 启动 15 题特训攻击心魔</button>
            </div>
          `,
      )
      .join("");
  }
}

async function attackBoss(bossId) {
  const res = await fetch(`${API_BASE}/api/raid/attack`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ boss_id: bossId, test_score: 85 }),
  });
  const d = await res.json();
  if (d.success) {
    showToast(d.message);
    loadRaid();
  } else {
    showToast(d.message);
  }
}

async function loadGacha() {
  const res = await fetch(`${API_BASE}/api/time-capsule/letters`);
  const d = await res.json();
  const c = document.getElementById("letters-container");
  if (d.success) {
    c.innerHTML = d.letters
      .map(
        (l) => `
            <div style="background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); border-radius: 12px; padding: 1.2rem;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.6rem;">
                <strong style="color: var(--accent-cyan); font-size: 0.95rem;">💌 ${l.author}</strong>
                <span style="color: var(--accent-rose); font-weight: 700;">❤️ ${l.likes}</span>
              </div>
              <p style="color: #fff; font-size: 1rem; line-height: 1.5;">${l.content}</p>
            </div>
          `,
      )
      .join("");
  }
}

async function drawGacha() {
  const res = await fetch(`${API_BASE}/api/gacha/draw`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  const d = await res.json();
  if (d.success) {
    document.getElementById("gacha-result").innerHTML = `
            <div style="font-size: 2.5rem; margin-bottom: 0.5rem;">🎉</div>
            <h3 style="color: #fff; font-size: 1.4rem; margin-bottom: 0.5rem;">抽中【${d.reward.title}】</h3>
            <p style="color: var(--accent-amber); font-size: 1.1rem;">${d.reward.content}</p>
          `;
    showToast("🎰 盲盒开启成功！");
    loadDashboard();
  }
}

async function sendLetter() {
  const author = document.getElementById("tc-author").value;
  const content = document.getElementById("tc-content").value;
  if (!content) return showToast("请填写寄语内容！");
  const res = await fetch(`${API_BASE}/api/time-capsule/send`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ author, content }),
  });
  const d = await res.json();
  if (d.success) {
    showToast("📮 信笺投递成功！已挂上时空墙！");
    document.getElementById("tc-content").value = "";
    loadGacha();
  }
}

window.onload = async () => {
  // 1. Load decoupled modals from /views/modals.html
  try {
    const res = await fetch("/views/modals.html");
    if (res.ok) {
      const html = await res.text();
      const modContainer =
        document.getElementById("modals-container") || document.body;
      const temp = document.createElement("div");
      temp.innerHTML = html.trim();
      while (temp.firstChild) {
        modContainer.appendChild(temp.firstChild);
      }
    }
  } catch (e) {
    console.error("Failed to load modals module:", e);
  }

  // 2. Load and display initial landing page view
  await switchTab("landing");
};
