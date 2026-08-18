# ATOM Business Metrics Dashboard

Atom（智能硬件 + 软件订阅）商业业绩指标体系与数据看板：口径定义（SSOT）→ 机器可读字段定义 → 看板交互原型 → 前后端开发参考。

## 仓库结构

| 路径 | 说明 |
|---|---|
| [`docs/atom-data-dictionary.md`](docs/atom-data-dictionary.md) | **业务数据定义说明 v2.0（口径 SSOT）**：产品业务定义（四层活跃 A1 开机 ⊇ A2 联网 ⊇ A3 应用活跃 ⊇ A4 训练活跃、有效训练、App 三分类、会员状态机）、指标字典（ACT/ENG/RET/TRN/SUB/DEV 编号 + P1/P2）、PV/UV 单位规范、数据 lineage 与维度分类、后台字段与数仓模型、十轮决议记录 D1–D38 |
| [`docs/atom-metrics-framework.md`](docs/atom-metrics-framework.md) | 战略框架 v0.5（为什么看这些指标、看板结构设计；口径细节以字典为准） |
| [`prototype/dashboard.html`](prototype/dashboard.html) | **看板交互原型**（单文件、无外部依赖，双击即开；会议决议：前端直接复用）。模拟数据 2026-04→08、3–4K 台规模；Filter bar（全球/海外/中国 × 时间区间）、八个 Tab、指标 ⓘ 口径悬浮、口径说明页 |
| [`schema/metrics.json`](schema/metrics.json) | **统计字段定义 · 指标注册表**（机器可读）：全部指标 id/口径/单位/去重方式/分子分母/期别；看板 ⓘ 提示与口径 Tab 的单一数据源 |
| [`schema/events.schema.json`](schema/events.schema.json) | **统计字段定义 · L0 埋点事件 JSON Schema**：公共信封 + 各事件 payload（device_power_on / heartbeat / session_start·end / set_completed ⭐ / device_binding_event / membership_event / wifi_setup / ota_event） |
| [`backend/ddl.sql`](backend/ddl.sql) | **后端开发参考 · 数仓 DDL**：维表（含 `dim_content.workout_length_type`）、事实表、双基座 `agg_user_daily`（a1–a4 flag）/ `agg_membership_daily`、`global_metrics_daily` 指标级合并 |
| [`backend/metrics.sql`](backend/metrics.sql) | **后端开发参考 · 指标推导 SQL**：基座构建（有效训练判定）、ENG01 矩阵、ENG08/08R、ACT05、ENG14 三档分层、RET01 周 cohort、RET06 Aha、TRN08/19、GLOBAL 汇总 |
| [`frontend/api-contract.ts`](frontend/api-contract.ts) | **前端开发参考 · API 契约**：TypeScript 类型 + 端点一览，枚举与后端字段严格对齐 |
| [`frontend/README.md`](frontend/README.md) | 原型接真实数据的三步改造指引（替换 mock、ⓘ 读注册表、筛选器透传） |

## 命名速记

- 模块码：**ACT** Activation 获取激活（账号注册→设备激活）· **ENG** Engagement 活跃（定性）· **RET** 留存 · **TRN** 训练（定量）· **SUB** 会员 · **DEV** 设备
- 编号：`ACT01` 无连字符；比率 = R 后缀（`ENG08R`）；二期指标编号自 90 起
- 四层活跃：A1 开机 ⊇ A2 联网 ⊇ **A3 应用活跃** ⊇ **A4 训练活跃**（D37 更名）
- 时长课型 `workout_length_type`：`mini` 短练（<5 分钟）/ `short` 小课（5–15 分钟，含两端）/ `long` 长课（>15 分钟）——原拟 workout_type 已被「课程类型」占用（D37）
- 用户分层（D38 三档，近 28 天）：重度 ≥10 次 / 常规 4–9 / 轻度 1–3；0 次不入档
- 口径：UV = 按 user_id/device_id 去重（默认）；PV = 次数累计；业务日 = 美国太平洋时间 PT
- North Star：NSM-1 = `ENG08` WAU-训练；NSM-2 = `SUB02` 活跃付费 Pro

## 状态

口径十轮对齐完成（D1–D38）。余项：R16 兑换有效期窗口、R17 Pro 各区价格表、R19 桌面参与阈值、R20 完课阈值（占位 70%）。下一步：按 `backend/` 参考建仓接真实数据，前端按 `frontend/README.md` 把原型接到 API——数据准了再上。
