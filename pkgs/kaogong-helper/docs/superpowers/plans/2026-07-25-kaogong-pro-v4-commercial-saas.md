# 《上岸智囊 Kaogong Pro v4.0》全栈商业化 SaaS 平台重构与拓展实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将公考辅助工具彻底重构为具有持续订阅收入 (MRR)、对赌分红抽成及算力消耗闭环的商业化高转化率 SaaS 平台，解决考公群体缺乏激励、题目解析粗糙、备考阶段混乱及线上互动匮乏的痛点。

**Architecture:** 采用前后端分离与单页应用 (SPA) 架构。后端基于 Node.js HTTP 引擎与本地持久化数据库（SQLite / 零依赖持久化 JSON 事务引擎），内置 JWT 鉴权、订单财务台账、SSE 流式 AI 推理引擎以及对赌池结算引擎；前端采用现代化响应式 UI/UX 设计，集成毛玻璃付费墙、交互式收银台与电竞化正向激励组件。

**Tech Stack:** Node.js (Vanilla HTTP Server), Vanilla JS / CSS3 (CSS Variables, Glassmorphism, CSS Grid), SQLite / Persistent JSON Ledger, Server-Sent Events (SSE), DeepSeek-R1 API Relay.

---

## Global Constraints

1. **零依赖/轻量化底层**：在不增加额外沉重重量级框架的前提下，保持 Node.js 内置 HTTP 与轻量持久化层的极速响应，确保部署成本最低、性能最高。
2. **商业付费墙一致性 (Paywall Consistency)**：所有涉及高阶解法（名师秒杀切片）、深度 AI 提问、对赌营创建的接口，必须在后端路由层进行权限检查与 Token 余额拦截，严禁仅依靠前端隐藏样式。
3. **真实账务幂等性 (Ledger Idempotency)**：涉及契约金交易、会员充值、算力消耗的流水，必须写入不可篡改的 `token_ledgers` 和 `orders` 财务台账，保证订单重复回调时不会重复发币或扣款。
4. **设计美学极致追求 (Visual Excellence)**：营销主页与学员控制台需具备现代化企业级 SaaS 与电竞质感，摒弃普通公考 APP 的陈旧枯燥，通过热力图光效、升迁勋章、神树养成等视觉特效带来极强的生理与心理正向反馈。

---

## User Review Required (重要商业与技术决策复核)

> [!IMPORTANT]
> **1. 三级商业化变现模式与定价模型确认**
> 系统将上线完整的核心商业付费矩阵，请确认以下具体权益与定价阶梯：
> - **体验版 (Free Tier)**：免费注册。每日限刷 15 题（仅能刷基础通解题，锁死名师秒杀技巧），每日限用 2 次基础 AI 助教，无法参与对赌分红池。
> - **冲刺 Pro 会员 (￥68/月 或 ￥198/考期终身)**：无限畅刷全套/模块/标签题库；**解锁全网 128 个专项题型秒杀技巧（名师一题多解对比）**；赠送每月 50,000 AI Token 算力；解锁心魔 RAID 战场。
> - **对赌私教 VIP (￥499/年)**：包含 Pro 全部权益；独享**“专属 AI 名师分身 24h 流式陪伴式推题”**；享有对赌反学费营“发起人”权限及特训路线规划。

> [!IMPORTANT]
> **2. 对赌反学费营的合规性与平台抽成机制 (15% Revenue Cut)**
> - **规则设定**：学员缴纳契约金（如 ￥99 / ￥199）加入 21 天冲刺营，每日需完成规定题目与打卡。
> - **商业分红利润**：违约（未完成打卡）学员的契约金进入“违约分红池”。**平台合法抽取池中 15% 作为服务管理费与服务器算力税**，剩余 85% 由全勤完赛学员平分。这不仅解决了线上备考无动力的痛点，更利用“好学生赚学费、拖延者买单”的博弈心态实现了极高的人传人裂变与商业营收！

> [!WARNING]
> **3. 真实模拟收银台与在线支付链路 (Simulated Modal Cashier & Webhooks)**
> - 为免去前期申请第三方企业支付商户号的复杂流程并立刻让投资人与用户体验到支付付款闭环，平台首期实装**“商业模拟收银台 (Modal Cashier)”**：支持展示微信支付 / 支付宝扫码界面，点击“模拟支付成功”即可发起了真实的后台幂等 Webhook 验证，实时给用户账户续期 VIP 或累加 Token！后期上线只需将 Webhook 秘钥替换为微信/支付宝/Stripe 真实回调即可。

---

## Open Questions (待确认细节)

1. **关于新手评估测评 (Onboarding Assessment Quiz)**：
   - 用户首次登录后，是否强制展示一个 3 步的评估问卷（如：备考方向是国考还是省考？距考期还有多少天？当前最大短板是数量还是言语？）？答完后自动为他配置好初始的热力图目标和技巧复习清单。
2. **关于“名师一题多解”的版权与展示形式**：
   - 我们的一题多解（如“花生十三秒杀派”、“粉笔拆分派”、“张三正统派”）是以**图文步骤深度精析+技巧重点高亮**展示，还是需要预留外链音频/短视频切片播放器的结构？（建议首期采用“深度精炼图文+思维导图式对比+AI名师分身文字答疑”，响应最快、成本最低且转化率极高）。

---

## Proposed Changes (全栈商业化架构与拓展规划)

我们将整个产品分为 **6 大核心商业模块**进行清晰的解耦与开发部署。

```
+-----------------------------------------------------------------------------------+
|                        《上岸智囊 Kaogong Pro v4.0》核心架构                      |
+-----------------------------------------------------------------------------------+
|  [未登录营销主页 View-Landing]  --->  [新手评估向导 Modal-Onboarding]               |
|  [收银台中心 Modal-Cashier]     <---  [用户个人与财务中心 View-Settings]            |
+-----------------------------------------------------------------------------------+
|  [学员控制台 View-Dashboard]：热力图 Combo 特效 | 职级升迁系统 | 上岸神树养成        |
+-----------------------------------------------------------------------------------+
|  [三维刷题引擎 View-Practice]： ①整套模拟考卷  ②模块专项突破  ③技巧标签切片        |
|  [名师多解对比 View-Solutions]：通解 vs 秒杀解 vs 口算解 (毛玻璃付费墙阻断)       |
+-----------------------------------------------------------------------------------+
|  [对赌反学费营 View-Cohorts]： 99元契约金池 | 平台抽成 15% | 每天打卡清算分红     |
|  [攻略社群社区 View-Strategies]：分阶段备考干货共享 (冲刺3月/突击1月/在职每日2小时) |
+-----------------------------------------------------------------------------------+
|  [商业化拓展增值服务]：AI 名师流式分身 | 智能错题处方本 | 创作者名师合伙人生态      |
+-----------------------------------------------------------------------------------+
```

---

### Task 1: 模块一：高转化商业化营销主页与新手引导 (Landing Page & Onboarding Flow)

彻底解决原有项目“一打开就是内页、缺乏商业信任感与产品营销力”的问题。

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- **新增未登录营销展示主页 (`#view-landing`)**：
  - **首屏 Hero Section**：震撼的品牌标语：“别再让冷冰冰的刷题软件消磨你的斗志！加入 Kaogong Pro，用对赌分红与名师秒杀技巧一举上岸！”搭配动态炫彩的 CTA 按钮【免费注册 / 开始体验】。
  - **四大核心痛点与解决方案看板**：
    1. *没有反馈难以坚持？* -> 展示动态活动热力图、职级晋升体系与上岸神树。
    2. *只会死算速度太慢？* -> 展示同一道题“普通解法需 3 分钟 vs. 名师截位秒杀需 15 秒”的震撼交互对比。
    3. *题海战术盲目低效？* -> 展示“最细颗粒度的解题技巧标签树 (Skill-Tags)”，哪里不会剖析哪里。
    4. *线上听课孤立无援？* -> 展示“对赌反学费督学营”，用真金白银治愈拖延，完赛平分违约者奖金！
  - **实时商业数据证明 (Social Proof)**：展示系统当前累积刷题数、对赌营现存奖金池总额（如 `￥48,920.00`）、全网名师技巧切片数量。
  - **精美订阅价格卡片 (Pricing Table)**：三列展示卡 (Free 体验版 / Pro 冲刺版 / VIP 终身私教版)，明确标注高性价比标签，点击直接呼出注册/登录与购买流程。
- **新增新手入学向导模态框 (`#modal-onboarding`)**：
  - 在新用户注册成功后弹出，通过 3 道轻松的选择题（报考省份/考期、目标分数、日均可用时间），自动计算生成用户的专属“上岸倒计时日历”和“首周技巧突击清单”，极大地提升用户的初始激活率 (Activation Rate)。

---

### Task 2: 模块二：登录注册鉴权、财务收银台与设置中心 (Auth, Cashier & User Account Settings)

构建稳健的 SaaS 账户基础、订单流水与个人设置中心。

#### [MODIFY] [server.js](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/server.js)
- **强化鉴权与用户信息 API**：
  - 优化 `POST /api/auth/register` 与 `POST /api/auth/login`，返回完整的用户状态对象（包含 `vip_tier`, `vip_expire_at`, `token_balance`, `escrow_balance`, `career_level`, `exam_target`）。
  - 新增修改个人资料接口 `PUT /api/user/profile`，允许用户自定义昵称、头像图标、备考类型及目标考期。
- **新增商业订单创建与幂等收银台 Webhook API**：
  - `POST /api/billing/create-order`：创建购买 VIP 订阅、对赌契约金充值或算力加油包的订单，返回唯一流水号 `order_id`、支付金额及模拟二维码。
  - `POST /api/billing/webhook`：模拟第三方支付网关异步回调。通过判断 `idempotency_key` 确保幂等性，成功后更新财务台账 `orders` 与 `token_ledgers`，并在内存/持久化层实时追加用户的 VIP 会员时间或 Token 算力。
  - `GET /api/user/ledgers`：获取用户所有账户资产（Token、押金、充值记录）的变动流水台账，保证账务透明。

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- **新增用户设置中心视图 (`#view-settings`)**：
  - **个人资料面板**：修改昵称、头像、选择目标考试（2026国考/省考/事业单位等）。
  - **会员资产监控与充值区**：直观展示当前 VIP 徽章及剩余天数、算力 Token 余额、对赌账户契约金余额。
  - **历史台账清单 (Ledger Audit Log)**：以清晰的表格列出“何时购买了 Pro 会员”、“对赌反学费收益 +￥23.50”、“AI 名师提问消耗 -350 Token”。
- **新增通用商业收银台模态框 (`#modal-cashier`)**：
  - 选中产品后呼出，展示模拟微信支付/支付宝绿色与蓝色选项卡，显示倒计时 15:00；
  - 提供【一键模拟支付完成 (Simulate Payment Success)】调试与演示按钮，点击后触发后端 Webhook，前端即时播放“充值到账彩屑庆祝特效”，并无缝刷新当前账户余额与权限！

---

### Task 3: 模块三：学员控制台与正向激励体系升级 (Dashboard & Positive Reinforcement Hub)

回答用户需求：“通过热力图等方式直观展示学习成果，以弥补其他APP无法通过正向激励刺激学习，也请你帮我想想别的办法。”

#### [MODIFY] [server.js](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/server.js)
- **热力图与成就数据接口增强 `GET /api/dashboard/stats`**：
  - 统计过去 365 天每日刷题数量、连续打卡天数 (`streak`)。
  - 计算用户当前的“摸鱼与专注性价比指数”及“击败全国备考人百分比”。
- **扩展正向激励系统机制 (Beyond Heatmaps - 多维激励组合拳)**：
  - **① 职级升迁系统 (Career Promotion System)**：将做题量与正确率映射为中国式备考独特成就（科员 -> 副科长 -> 正科长 -> 副处长 -> 处长 -> 局长）。每一次“升职”颁发带有盖章特效的电子任命证书！
  - **② 上岸神树养护 (Companion Tree Evolution)**：每天打卡做题自动给首页的“上岸神树”浇水，形态从“种子 -> 发芽 -> 枝繁叶茂 -> 开花 -> 结出金苹果（寓意成功上岸）”，带来强大的长线视觉情感陪伴。
  - **③ 热力图连击火焰 (Heatmap Combos)**：连续打卡 7 天、21 天、30 天时，热力图对应的格子会燃起特效火焰图标，并奖励算力盲盒与免签冻结卡！

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- **重构控制台主页 (`#view-dashboard`)**：
  - **顶部资产看板**：显示打卡天数、上岸倒计时、当前职级官职。
  - **高精度互动热力图区**：GitHub 风格绿色/金色渐变热力网格，鼠标悬浮显示当日刷题数量、涉及的技巧标签及获得成就。
  - **“乱七八糟的重点题型”全景入口卡片网格**：
    - 不仅涵盖行测五大基本大类（言语、数量、判断、资料、常识），还新增“**申论精选晨读背诵**”、“**面试高频情境现场秒答**”、“**时政热点极速30题**”三大特殊模块卡片，点击即可一键直达对于专区！

---

### Task 4: 模块四：三维立体刷题引擎与名师多解切片 (3D Practice Engine & Distilled Master Solutions)

深度响应用户要求：“刷题（分为刷整套题、刷模块题以及标签题，标签题就是某个题型中的某个技巧）、以及同样一道题用不同老师的思路进行讲解并看学员喜欢哪个老师。”

#### [MODIFY] [server.js](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/server.js)
- **拓展题库底表结构与查询逻辑 `GET /api/questions` & `POST /api/practice/submit`**：
  - 每一道题赋予三个维度的分类标签：
    1. **套卷归属 (`paper_id`)**：如 `2025-GUOKAO-XINGCE`；
    2. **模块归属 (`module`)**：如 `资料分析`、`判断推理`；
    3. **技巧标签 (`skill_tag`)**：如 `截位直除法`、`十字交叉法`、`隔年增长率`、`桥梁加强法`、`一拖五排除法`等（系统内置不少于 30 个高频硬核技巧标签）。
  - **支持三维组卷接口 `POST /api/practice/start`**：
    - 允许参数：`mode: "FULL_PAPER" | "MODULE" | "SKILL_TAG"`，搭配对应的 `target_id` 生成标准化练习会话。
- **名师解法对比与投票对冲系统 API `POST /api/solutions/vote` & `GET /api/solutions/distilled`**：
  - 每道题解析拆分为**“基础通解 (Textbook Solution)”**与**“名师绝杀解 (Master Hacks)”**（包含花生十三秒杀派、粉笔拆分口算派、张三正统派等）。
  - **付费墙鉴权拦截 (Paywall Intercept)**：非 Pro/VIP 会员请求解析时，`master_hacks` 字段被后端置空并标记 `locked: true`；
  - **名师偏好投票**：用户可点击赞同某个老师的思路，系统更新用户的 `teacher_affinity` 偏好，并在之后的刷题解析中优先展开该名师的解法卡片！

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- **新增与重构刷题中心视图 (`#view-practice`)**：
  - **模式一【全真整套试卷突击 (Full Paper Mock)】**：选择历年真题卷，启动 120 分钟全真模考倒计时，带有答题卡悬浮窗。交卷后生成专项评分、雷达图与全网排位百分比。
  - **模式二【模块专项特训 (Module Practice)】**：自由勾选言语、判断、数量或资料，定制 15 题快速随练。
  - **模式三【技巧标签特训 (Skill-Tag Mastery)】**：展示可视化的“技巧知识树”，明确标出各个技巧的掌握进度（如：`截位直除法 [熟练度 85%]` vs. `十字交叉法 [薄弱 32% - 强烈推荐刷题]`）。点击技巧直接生成专练卷！
- **重构一题多解展现区 (`#view-solutions` & 题目解析弹层)**：
  - **名师视角选项卡切换**：同一题上方横向排列不同名师头像按钮（如：📘通解 | 🦊花生十三秒杀派 | 🐼粉笔拆分派 | 👑AI终极精简）。
  - **毛玻璃锁卡遮罩 (Glassmorphism Glass Overlay)**：对基础体验用户，名师秒杀区上方覆盖流光溢彩的毛玻璃锁定层，高亮提示：“💡 该绝杀技巧可节省 80% 做题时间！升级 Pro 会员立即解锁全部 128 个大招！”点击即可跳入收银台。

---

### Task 5: 模块五：对赌反学费督学营与社群攻略社区 (Escrow Cohorts & Strategy Sharing Hub)

解决“线上没氛围、拖延无人管”以及“不同阶段备考策略信息差”两大核心难题。

#### [MODIFY] [server.js](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/server.js)
- **对赌反学费与分红清算 API `POST /api/cohorts/join` & `POST /api/cohorts/settle`**：
  - 用户从契约金账户支付押金加入班级（例如 `￥99 · 21天行测破晓营`）。
  - 每日打卡判定：当用户当日做题数 >= 30 题且正确率 >= 60%，自动标记为打卡成功。
  - **15% 平台服务费清算引擎**：结营时自动遍历全员，统计违约金额总池 $V$。**系统自动划拨 $15\% \times V$ 记入平台营收账目**，剩余 $85\% \times V$ 精确均分给完赛学员，返还至可提现或购买会费的契约金账户。
- **攻略分享与阶段过滤 API `GET /api/strategies` & `POST /api/strategies`**：
  - 支持学员与导师发表备考干货与经验贴，明确标记适用标签：`#距考期3个月强化`、`#距考期1个月冲刺`、`#在职每日2小时精炼计划`、`#0基础入门攻略`。

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- **重构对赌督学营视图 (`#view-cohorts`)**：
  - **核心视觉刺激**：大字醒目展示“**🔥 当前督学营累计奖金池：￥18,650.00**”与“**预计完赛收益率 +35%**”。
  - **规则透明化背书**：清晰展示“平台仅合法抽取 15% 违约管理税，剩余奖金 100% 归全勤学员平分，好学生在这里不仅不花钱，还能把学费赚回来！”极大地打消顾虑并刺激下单。
- **重构社群与攻略经验社区 (`#view-strategies`)**：
  - **阶段筛选导航杆**：支持点击切换【全部阶段】、【3个月长线强化】、【1个月极速绝杀】、【在职兼职备考】。
  - **社区互动卡片**：展示高赞上岸经验贴、名师备考任务清单、学员交流回复留言板，打造高粘性互助学习圈层。

---

### Task 6: 模块六：商业化扩展亮点 —— AI 专属分身、智能错题处方与合伙人生态 (Commercial Extensions)

作为商业化架构师，为您额外扩展三大极高 ARPU（用户平均收入）与生态闭环的核心必杀功能！

#### [NEW & MODIFY] [server.js](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/server.js)
- **1. AI 名师专属私教分身流式对话 (SSE Streaming AI Tutors)**：
  - 针对具体的名师解法，用户可点击【召回花生十三 AI 分身，追问这步截位为什么不进位？】。
  - 新增 `POST /api/ai/ask-stream`：调用 DeepSeek-R1 API 开启 Server-Sent Events (SSE) 流式返回，模拟名师口吻与思考过程 (`<think>`) 进行专属答疑。
  - **动态计费引擎**：流式推理过程中实时统计消耗 Token，当余额不足且未充值时，流式中断并下发商城购买提示。
- **2. 智能错题本与弱点消除处方 (Smart Mistake Notebook & Prescriptions)**：
  - 新增 `GET /api/mistakes/tree`：自动将用户错题按照“技巧标签 (Skill-Tags)”进行归类汇总，计算该技巧的二次遗忘率。
  - 新增 `POST /api/mistakes/remediate`：一键生成每日 10 题的“弱点消除专项药方”，完成订正后技巧掌握度百分比上升。
- **3. 创作者/名师商业合伙人入驻后台 (Creator Partner Program)**：
  - 允许外部优秀机构、公考名师或上岸状元在平台申请认证入驻，上传专属技巧切片与微课解法。
  - 当学员购买其高阶内容或打赏时，平台自动执行 **7:3 分润（创作者 70% / 平台 30%）**，吸引全网优质教研内容源源不断涌入 platform。

#### [MODIFY] [index.html](file:///home/tippy/source/flakes/.worktrees/kaogong-reinforcement-v3/pkgs/kaogong-helper/src/public/index.html)
- 在解法区右下角悬浮添加 **“🤖 AI 名师私教分身追问悬浮窗”**，体验真正一对一私教打字机对话反馈。
- 在导航中添加 **“📖 智能错题处方本”** 快捷入口，呈现红黄绿三色警示的知识薄弱技巧树。
- 底部页脚添加 **“🤝 成为教研合伙人 / 名师入驻中心”** 引导，塑造完整 SaaS 生态商业背书。

---

## Verification Plan (全链路变现与业务闭环验证计划)

### 1. 自动化测试脚本与端到端回归
我们将编写并执行自动化测试套件与 Shell Regress 命令，重点验证财务台账与权限拦截：

```bash
# 1. 启动本地应用服务器（背景运行）
node pkgs/kaogong-helper/src/server.js &

# 2. 验证新用户注册为 Free 体验账号
curl -X POST http://localhost:7070/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "test_buyer", "password": "123", "exam_target": "国考"}'

# 3. 验证 Free 用户访问技巧秒杀解析被正常付墙阻断 (is_locked: true)
curl http://localhost:7070/api/questions | grep "PRO_REQUIRED"

# 4. 模拟收银台 Webhook 充值订单幂等回调，升级 PRO 会员并充值 50,000 Token
curl -X POST http://localhost:7070/api/billing/webhook \
  -H "Content-Type: application/json" \
  -d '{"idempotency_key": "TX_TEST_001", "user_id": "u1", "order_type": "PRO_MONTHLY", "amount": 68}'

# 5. 验证升级后对绝杀技巧付费墙顺利解除，可查看全部解法
curl http://localhost:7070/api/questions | grep "截位直除秒杀步骤"

# 6. 验证对赌池结营，平台精确抽取 15% 服务费
curl -X POST http://localhost:7070/api/cohorts/settle -H "Content-Type: application/json" -d '{"cohort_id": "c1"}'
```

### 2. 人工交互体验验证 (Manual Walkthrough Verification)
- 启动服务后，在浏览器打开 `http://localhost:7070`：
  1. **主页与新手测评**：以访客视角体验精美营销主页，点击免费注册，完成 3 步备考评估向导，查看定制打卡计划；
  2. **付费墙与收银台体验**：进入刷题与解析区，尝试点击【花生十三秒杀大招】，触发毛玻璃付费墙 -> 呼出收银台 -> 点击“模拟微信支付成功” -> 亲眼见证特效触发、账户即时升级 PRO；
  3. **刷题模式验证**：分别体验“全套模考”、“模块突击”、“技巧标签专练”，给喜欢的名师投票对冲；
  4. **对赌督学营分红闭环**：缴纳押金加入对赌营，完成每日 30 题打卡，模拟结营查看平台 15% 抽账与个人赚回学费的分红台账！
