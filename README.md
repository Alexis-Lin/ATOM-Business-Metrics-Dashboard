# ATOM Business Metrics Dashboard

Atom（智能硬件 + 软件订阅）商业业绩指标体系与数据看板。仓库只有两个目录：**`docs/` 看口径，`dev/` 做开发**。

## 仓库结构

```
docs/   业务口径文档（给管理层 / 全员）
dev/    工程开发对接（给前端 / 后端 / 数据 / 客户端）
```

| 路径 | 说明 |
|---|---|
| [`docs/atom-data-dictionary.md`](docs/atom-data-dictionary.md) | **业务数据定义说明 v2.0 —— 口径唯一标准（SSOT）**：四层活跃（A1 开机 ⊇ A2 联网 ⊇ A3 应用活跃 ⊇ A4 训练活跃）、有效训练、App 三分类、会员状态机、指标字典（ACT/ENG/RET/TRN/SUB/DEV）、PV/UV 规范、数据 lineage、十轮决议记录 D1–D38 |
| [`docs/atom-metrics-framework.md`](docs/atom-metrics-framework.md) | 战略框架 v0.5：为什么看这些指标、看板结构设计（口径细节以字典为准） |
| [`dev/dashboard-prototype.html`](dev/dashboard-prototype.html) | **看板交互原型**（单文件，双击即开；前端直接复用，只做接数改造） |
| [`dev/frontend-api-contract.ts`](dev/frontend-api-contract.ts) | 前后端 **API 接口契约**（TypeScript 类型 + 端点一览） |
| [`dev/backend-warehouse.sql`](dev/backend-warehouse.sql) | 后端 **数仓建表 DDL + 指标推导 SQL**（一个文件两部分） |
| [`dev/tracking-events.schema.json`](dev/tracking-events.schema.json) | **埋点事件 JSON Schema**（公共信封 + 9 类事件；`set_completed` 最高优先级） |
| [`dev/metrics-registry.json`](dev/metrics-registry.json) | **指标注册表**（机器可读）：id / 口径 / 单位 / 去重 / 分子分母 / 期别 |
| [`dev/README.md`](dev/README.md) | 开发对接说明：文件导览 + 原型接真实数据三步指引 |

## 命名速记

- 模块码：**ACT** Activation 获取激活（账号注册→设备激活）· **ENG** Engagement 活跃（定性）· **RET** 留存 · **TRN** 训练（定量）· **SUB** 会员 · **DEV** 设备
- 编号：`ACT01` 无连字符；比率 = R 后缀（`ENG08R`）；二期指标编号自 90 起
- 四层活跃：A1 开机 ⊇ A2 联网 ⊇ **A3 应用活跃** ⊇ **A4 训练活跃**（D37）
- 时长课型 `workout_length_type`：`mini` 短练（<5 分钟）/ `short` 小课（5–15 分钟，含两端）/ `long` 长课（>15 分钟）——原拟 workout_type 已被「课程类型」占用（D37）
- 用户分层（D38 三档，近 28 天）：重度 ≥10 次 / 常规 4–9 / 轻度 1–3；0 次不入档
- 口径：UV = 按 user_id/device_id 去重（默认）；PV = 次数累计；业务日 = 美国太平洋时间 PT
- North Star：NSM-1 = `ENG08` WAU-训练；NSM-2 = `SUB02` 活跃付费 Pro

## 状态

口径十轮对齐完成（D1–D38）。余项：R16 兑换有效期窗口、R17 Pro 各区价格表、R19 桌面参与阈值、R20 完课阈值（占位 70%）。下一步：后端按 `dev/backend-warehouse.sql` 建仓接真实数据，前端按 `dev/README.md` 三步把原型接到 API——数据准了再上。
