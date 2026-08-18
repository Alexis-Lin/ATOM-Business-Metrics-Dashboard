# frontend/ — 前端（Web）开发参考

会议结论（2026-08-18）：**前端直接复用 `prototype/dashboard.html`**，工程化重点放在数据准确性上（"数据准了再上"）。本目录提供把原型接到真实数据所需的契约与改造指引。

## 文件

| 文件 | 说明 |
|---|---|
| `api-contract.ts` | 前后端接口契约：TypeScript 类型 + 端点一览，枚举与后端字段字典严格对齐（`workout_length_type`、`app_category`、四层活跃 a1–a4、用户三档分层等） |

## 原型 → 真实数据的挂载点

`prototype/dashboard.html` 是单文件、无外部依赖的实现，接数只需三步：

1. **替换 mock 数据块。** 原型 `<script>` 顶部有 `series(...)` 生成的 mock 天级序列（`intl` / `cn` 两套）。删除该块，改为启动时并行请求 `API_ENDPOINTS` 下各端点（见 `api-contract.ts`），把返回的 `MetricSeries.points` 映射成原型使用的 `{date, value}` 数组。字段一一对应，图表渲染层（手写 SVG）无需改动。

2. **ⓘ 口径提示与"口径说明"Tab 改读注册表。** 原型内置 `INFO` 对象（metricId → 口径文案）。接数后改为请求 `/api/v1/meta/metrics`（即透传 `schema/metrics.json`），用 `id / name / formula / note` 渲染，保证看板口径文案与 SSOT 单源。

3. **筛选器透传。** 地区（CN/INTL/GLOBAL）、国家、ISO 周范围三个筛选器直接映射为 `MetricQuery` 参数。注意：
   - 一期 `GLOBAL` 按钮保持 `disabled`，默认视图 `INTL`（海外）；
   - CN / INTL 是两套隔离系统，前端也应部署两份或按登录态路由，只有指标数值层可合并展示；
   - 所有日期按 PT（America/Los_Angeles）理解，周 = ISO 周。

## 渲染约定（沿用原型既有实现）

- **活跃指标先百分比、后绝对值**（率优先展示，绝对值可切换）。
- 四层活跃严格嵌套：A1 开机 ⊇ A2 联网 ⊇ A3 应用活跃 ⊇ A4 训练活跃；违反嵌套（如 A3 > A2）视为数据 bug，前端可做断言上报。
- 课程时长类型三档文案统一用 `WORKOUT_LENGTH_LABEL`：短练（<5 分钟）/ 小课（5–15 分钟，含两端）/ 长课（>15 分钟）。
- 用户分层三档（D38）：重度 ≥10 次/月、常规 4–9、轻度 1–3（滚动 28 天，0 次不入档）。
- 未终结数据（`provisionalTail`）用虚线/浅色渲染，避免"最后一天掉坑"误读。
- 会员 Tab 一期渲染"开发后置"横幅（`MembershipResponse.deferred === true`）。
