# ATOM Business Metrics Dashboard

Atom（智能硬件 + 软件订阅）商业业绩指标体系与数据看板。

## 内容

| 文件 | 说明 |
|---|---|
| [`prototype/dashboard.html`](prototype/dashboard.html) | **看板交互原型**（单文件、无外部依赖，双击即开）。模拟数据 2026-04→08、3–4K 台规模；含 Filter bar（全球/海外/中国 × 时间区间）、八个 Tab、指标 ⓘ 口径悬浮、口径说明页 |
| [`docs/atom-data-dictionary.md`](docs/atom-data-dictionary.md) | **业务数据定义说明 v1.6（口径 SSOT）**：产品业务定义、指标字典（ACT/ENG/RET/TRN/SUB/DEV 编号 + P1/P2 标注）、PV/UV 单位规范、四层数据 lineage 与维度分类、后台字段与数仓模型、六轮决议记录 |
| [`docs/atom-metrics-framework.md`](docs/atom-metrics-framework.md) | 战略框架 v0.5（为什么看这些指标、看板结构设计；口径细节以字典为准） |

## 命名速记

- 模块码：**ACT** Activation 获取激活（账号注册→设备激活）· **ENG** Engagement 活跃（定性）· **RET** 留存 · **TRN** 训练（定量）· **SUB** 会员 · **DEV** 设备
- 编号：`ACT01` 无连字符；比率 = R 后缀（`ENG08R`）；二期指标编号自 90 起
- 口径：UV = 按 user_id/device_id 去重（默认）；PV = 次数累计；业务日 = 美国太平洋时间 PT
- North Star：NSM-1 = `ENG08` WAU-Workout；NSM-2 = `SUB02` 活跃付费 Pro

## 状态

口径六轮对齐完成。余项：R16 兑换有效期窗口、R17 Pro 各区价格表与计费周期。下一步：按字典编号写 dbt model 接真实数据（`agg_user_daily` + `agg_membership_daily` 双底座）。
