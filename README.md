# ATOM Business Metrics Dashboard

Atom（智能硬件 + 软件订阅）商业业绩指标体系与数据看板。

## 文档

- [`docs/atom-metrics-framework.md`](docs/atom-metrics-framework.md) — 指标框架 v0.2
  注册与激活 / 三层活跃 / Cohort 留存 / 上课与运动指标 / 变现 / 设备健康，
  含看板结构、数据模型与埋点清单、交付形态、实施路线图，以及待确认的口径清单。

## 当前状态

三轮口径对齐完成，数据字典 v1.0 已发布；余项 R11–R15（见字典附录）确认后进入 dbt 落地。账号字段对齐 ATOM-UserGoalPreference-and-OnBoarding 仓（user_id / account_edition / devices[] / membership_tier）。
