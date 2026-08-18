# dev/ — 工程开发对接目录

前端（Web）与后端（数仓/埋点）开发所需的全部工程文件都在这一个目录里。口径以 [`../docs/atom-data-dictionary.md`](../docs/atom-data-dictionary.md)为唯一标准（SSOT，版本以文档头为准），本目录是它的机器可读与代码参考形态。

## 文件一览（共 6 个）

| 文件 | 给谁用 | 内容 |
|---|---|---|
| [`dashboard-prototype.html`](dashboard-prototype.html) | 前端 | **看板交互原型**。单文件、无外部依赖，双击即开。会议结论（2026-08-18）：**前端直接复用此 HTML**，只做接数改造（见下） |
| [`frontend-api-contract.ts`](frontend-api-contract.ts) | 前端 ↔ 后端 | **API 接口契约**：TypeScript 类型 + 端点一览。枚举与后端字段严格对齐（四层活跃 a1–a4、`workout_length_type`、`app_category`、用户四档分层等） |
| [`backend-warehouse.sql`](backend-warehouse.sql) | 后端/数据 | **数仓建表 + 指标推导 SQL**（一个文件两部分）：Part 1 全部 DDL（维表、事实表、双基座 `agg_user_daily` / `agg_membership_daily`、`global_metrics_daily`）；Part 2 各模块指标推导示例（有效训练判定、ENG01 矩阵、ENG08/08R、ENG14 四档分层、RET01 周 cohort、TRN08/19、GLOBAL 汇总） |
| [`tracking-events.schema.json`](tracking-events.schema.json) | 客户端/固件/算法 | **埋点事件 JSON Schema**：公共信封 + 9 类事件 payload。`set_completed` 为最高优先级新增埋点 |
| [`metrics-registry.json`](metrics-registry.json) | 全员 | **指标注册表**（机器可读）：全部指标的 id / 口径 / 单位 / 去重方式 / 分子分母 / 期别。看板 ⓘ 提示与"口径说明"Tab 的单一数据源 |
| `README.md` | 全员 | 本文件 |

## 前端：原型 → 真实数据（三步）

1. **替换 mock 数据块。** 原型 `<script>` 顶部有 `series(...)` 生成的模拟天级序列（`intl` / `cn` 两套）。删除该块，启动时并行请求 `frontend-api-contract.ts` 里 `API_ENDPOINTS` 各端点，把返回的 `MetricSeries.points` 映射成原型使用的 `{date, value}` 数组即可，图表渲染层（手写 SVG）无需改动。
2. **ⓘ 口径提示改读注册表。** 原型内置 `INFO` 对象（指标 id → 口径文案）。接数后改为请求 `/api/v1/meta/metrics`（即透传 `metrics-registry.json`），保证看板口径文案与 SSOT 单源。
3. **筛选器透传。** 地区 / 国家 / ISO 周范围直接映射为 `MetricQuery` 参数。注意：一期 `GLOBAL` 按钮保持 `disabled`，默认视图 INTL（海外）；CN / INTL 是两套隔离系统，只有指标数值层可合并。

## 渲染与校验约定

- 所有日期按 **PT（America/Los_Angeles）** 理解；周 = ISO 周。
- 活跃指标**先百分比、后绝对值**（率优先，绝对值可切换）。
- 四层活跃严格嵌套：A1 开机 ⊇ A2 联网 ⊇ A3 应用活跃 ⊇ A4 训练活跃——违反嵌套视为数据 bug，前端可断言上报。
- 时长课型三档文案统一：**短练（<5 分钟）/ 小课（5–15 分钟，含两端）/ 长课（>15 分钟）**（字段 `workout_length_type: mini/short/long`；原拟 workout_type 已被「课程类型」占用）。
- 用户分层四档（D43，近 28 天）：重度 ≥10 次 / 常规 4–9 / 轻度 1–3 / 零训练（0 次但有开机）；基数 = 有 A1 开机的账号，完全不开机不入档（ENG15 静默）。
- 未终结数据（`provisionalTail`）用虚线/浅色渲染；会员 Tab 一期渲染"开发后置"横幅。
- 上线原则（会议结论）：**数据准了再上**——工程重点先放在数据校验。
