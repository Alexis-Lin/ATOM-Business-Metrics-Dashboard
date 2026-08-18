# Atom 业务数据定义说明 v1.0

> **本文档是 Atom 商业业绩指标体系的口径 SSOT**（single source of truth）：产品业务定义 + 指标字典 + 后台数据字段定义。
> 战略框架与看板设计见 [`atom-metrics-framework.md`](atom-metrics-framework.md)（其口径描述与本文冲突时，以本文为准）。
> 账号档案字段的 SSOT 是 [`ATOM-UserGoalPreference-and-OnBoarding`](https://github.com/Alexis-Lin/ATOM-UserGoalPreference-and-OnBoarding) 仓（下称 **档案仓**）——本文只引用、不重复定义；计费/订单事实的 SSOT 是订单系统。
> 版本：v1.0（2026-08-18）｜ 已并入第三轮决议（见附录）。

---

## Part A · 产品业务定义

### A1. 产品与账号基础

| 术语 | 定义 | 备注 |
|---|---|---|
| **ATOM 设备** | 便携 AI 健身摄像头（`identity.devices[].device_type = atom`），配合手机 App 使用 | 档案仓 §10.3 |
| **账号** | `user_id`（ULID，全局主键，建议带区前缀）。**中国大陆与国际是两套隔离账号体系**：`account_edition ∈ cn / intl` 是数据驻留分区键，`(account_edition, email)` 组合唯一 | 档案仓 §10.1 铁律④ |
| **产品线 `product_line`** | 指标体系的一级维度，**直接取 `account_edition`**：CN 中国版 / INTL 国际版；INTL 下钻 `country_code` | 与档案仓字段一一对应 |
| **App 注册** | 账号创建成功（`identity.account` 落库，email 必有） | 注册主路径：cn=手机号，intl=邮箱 |
| **设备配对激活** | 一台 ATOM 首次进入 `devices[].state = bound`（首绑）。**一台设备终身只计一次激活**，解绑/换绑不重复计 | 状态机：none → purchased → bound ⇄ unbound |
| **已绑定激活账号** | 名下 ≥1 台 `state=bound` 的 ATOM 的账号 | 活跃/留存/会员渗透率的分母 |
| **业务日** | **America/Los_Angeles（PT）时区的自然日**，全球统一；夏令时随美国切换 | 中国版行为分析另提供北京时间辅助视图 |

### A2. 活跃（三层，账号主键）

| 层 | 名称 | 当日判定（PT 日界，按 `user_id` 去重） | 定稿 |
|---|---|---|---|
| **L1** | 开机活跃 | 名下任一 ATOM 有开机/唤醒/物理交互事件（可离线产生） | 近 7 日回填，第 8 天定稿 |
| **L2** | 联网活跃 | 名下任一 ATOM 与云端有有效心跳或数据同步 | T+1 |
| **L3** | 运动活跃 | 完成 ≥1 次**有效训练** | T+1；上课必须在线 → **L3 ⊆ L2** |

### A3. 有效训练与活跃质量

| 术语 | 定义 |
|---|---|
| **有效训练 Qualified Workout** | 单次训练会话中，**完成 ≥1 个完整组，或训练时长 ≥1 分钟** |
| **完整组 Completed Set** | 按课程/动作对该组的完整性定义判定**完成即计**，组内动作次数多少不作限制（第三轮决议 D12） |
| **训练时长** | 目标口径为有效运动时长（扣除暂停/挂机）；首期若仅有会话时长，先用会话时长并在本表标注，切换时打口径变更标注 |
| **课型** | 大课 `WORKOUT`（20–30 min）/ 短课 `MINI`（5–10 min）/ 微课 `MICRO`（1–2 min，one set / 跳绳）。三类分开统计，不做课次简单加总 |
| **深度训练** | 单次有效训练中 ≥2 完整组 且 ≥5 分钟 |
| **负荷 load** | **用户自填**（设备无阻力/重量传感器，D14）。`log.bodypark.exercise_record.load`。凡基于 load 的指标（volume、强度进步）必须同时报**自填负荷覆盖率** |
| **训练容量 volume** | Σ(reps × 自填 load)，仅在有自填负荷的记录上计算，标注"自报口径" |

### A4. 会员体系（第三轮决议 D13 定案）

**四状态模型**（`membership_tier` 档案仓枚举 free/plus/pro，本文在 pro 内细分权益来源）：

```
FREE ──绑定 ATOM──▶ PLUS（终身免费，随设备自动获得）
                      │
                      ├─套装赠送 1~12 个月──▶ PRO_GIFT（赠送期）──到期──▶ 转 PRO_PAID 或回落 PLUS
                      └─────────自费开通──▶ PRO_PAID（自费）──到期未续──▶ 回落 PLUS
```

| 状态 | 定义 | 判定 |
|---|---|---|
| `FREE` | App 注册但名下无已绑定 ATOM | membership_tier=free |
| `PLUS` | 名下 ≥1 台已绑定 ATOM，**终身免费、自动获得**，无到期概念 | 基础会员=设备权益 |
| `PRO_GIFT` | Pro 权益有效且来源为**套装赠送**（按 ATOM 套装赠 1~12 个月，SKU→月数映射待 R12） | entitlement_source=bundled_gift |
| `PRO_PAID` | Pro 权益有效且来源为**自费订阅** | entitlement_source=self_paid |

**要点：**
- **Plus 不是转化指标**——它随设备自动发放，Plus 数 ≈ 已绑定激活账号数。会员生意的全部看点在 **Pro**。
- **NSM-2 = 活跃付费 Pro 数**（PRO_PAID 在期账号），**不含赠送期**。赠送期是获客成本，不是收入。
- **赠转付转化率是会员漏斗的第一指标**（类比试用转化）：赠送到期后 30 天内转为自费的比例，**必须按赠送月数（1/3/6/12）和套装 SKU 分组看**——不同赠送时长天然构成一组定价实验。
- 已取消自动续费但仍在有效期 → 仍计 PRO_PAID（权益有效），单独出 `cancel_pending` 占比作为流失先行指标。
- **Pro 权益（R13 定案）**：① AI 课程时长用量（配额制）② 视频存储空间 ③ 高阶功能。权益用量本身是指标（E12–E15）：Plus 用户触顶 = 升级信号；Pro 用户不用权益 = 流失高危。
- 边缘：账号解绑全部设备后 Plus 是否保留 → **待拍板 R11**（默认：权益随设备，回落 FREE）。

### A5. Cohort 与留存

| 术语 | 定义 |
|---|---|
| **Cohort 起点** | 账号**首次绑定激活日**（不是 App 注册日/购买日） |
| **粒度** | 周 cohort（ISO 周，前期主用）+ 月 cohort 并行；**历史自 2026 年 4 月起**（D15） |
| **Wn / Mn 留存** | 激活后第 n 个完整周/月内该账号是否活跃（三层各算）——Classic 区间留存 |
| **D1/D7/D30** | 激活后第 n 天当天是否活跃——精确日留存，onboarding 优化用 |
| **流失 Churned** | 近 28 天无任何 L1 活跃 |
| **复活 Resurrected** | 沉默 ≥28 天后重新出现任一层活跃 |
| **Quick Ratio** | (New + Resurrected) / Churned，周/月两粒度 |

### A6. 数据定稿与跨区合并

| 规则 | 内容 |
|---|---|
| **L1 回填** | 开机事件补传窗口 **7 天**：近 7 日"未定稿"每日重跑；第 8 天定稿；迟到 >7 天的事件**不入指标**、入原始表留档并监控量级 |
| **跨区合并（D14 定案）** | CN / INTL **用户级数据物理隔离，永不跨区搬运**。两区各自计算聚合表（agg 层），**只在"指标级"（无用户粒度的聚合结果）做合并**生成全球视图。全球数 = CN 数 + INTL 数，明细下钻只能在各自区内 |
| **退货（D16）** | 退货数据**未打通**，由销售端**手动异步统计**：净激活 = gross − 手动调整文件（月度导入，数据源标注 manual，滞后约 1 个月）。看板默认展示 gross，净值仅在月度定稿包 |

---

## Part B · 指标字典

> 每个指标：编号 / 口径 / 主键 / 默认维度。所有指标默认支持维度：`product_line`（一级）、日期（PT）；标注 ★ 的进高管首屏。刷新频率：无特别标注 = 日更 T+1。

### M1 注册与激活

| # | 指标 | 口径 | 主键 |
|---|---|---|---|
| A01 ★ | 累计配对激活设备数 | count(distinct device_id where first_bound_at ≤ d)；gross 口径（净值见 A11） | device |
| A02 ★ | 新增激活设备 | count(device_id where first_bound_at ∈ 周期)，终身一次 | device |
| A03 | App 注册账号数 | count(user_id where signup_at ∈ 周期)，分 edition | user |
| A04 | 已绑定激活账号数 | count(distinct user_id having ≥1 台 bound ATOM) | user |
| A05 | 激活率 | A01 / 累计售出设备数（售出数据源：销售端） | device |
| A06 | 激活时延 | median/P90(first_bound_at − sold_at) | device |
| A07 | 首次绑定成功率 | 绑定流程完成 / 进入（onboarding 埋点） | device |
| A08 | 已售未激活存量池 | count(sold 且 never bound)，按账龄分桶 0-7/8-30/31-90/90+ 天 | device |
| A09 | 注册→绑定转化率 | A04 中注册后 7 天内完成首绑的比例；差值拆"买前研究线索池 / 绑定失败" | user |
| A10 | 户均设备数 / 多机账号占比 | avg(bound devices per user)；P(≥2 台) | user |
| A11 | 净激活（月度） | A01 − 销售端手动退货调整（月度导入，滞后 ~1 月，manual 源） | device |

### M2 活跃

| # | 指标 | 口径 | 备注 |
|---|---|---|---|
| B01–B09 | 3×3 活跃矩阵 | {DAU, WAU(滚 7 日), MAU(滚 28 日)} × {L1, L2, L3}，user_id 去重 | **B06 = WAU-Workout ★（NSM-1）** |
| B10 ★ | 运动转化率 | WAU-L3 / WAU-L1 | 开机却不练=被劝退 |
| B11 | 联网健康率 | WAU-L2 / WAU-L1 | 低=配网问题+上课天花板 |
| B12 | 周频次分布 | 周内有效训练次数直方图 0/1/2/3/4/5+ | 均值会骗人，看分布 |
| B13 | 周均有效训练次数 | Σ有效训练 / WAU-L3 | 核心运动指标 |
| B14 | 用户分层 | 近 28 天有效训练：Power ≥12 / Regular 4–11 / Light 1–3 / Dormant 0 次但有 L1 / Churned 无活跃 | 月度迁移桑基 |
| B15 | 静默账号 | 近 28 天 L1=0 的已激活账号 | 可召回资产 |

### M3 留存与 Cohort

| # | 指标 | 口径 |
|---|---|---|
| C01 ★ | 周 cohort Wn 留存率 | cohort(激活 ISO 周) × Wn 内是否活跃（L1/L2/L3 各一套）；样本 <100 灰显 |
| C02 | 月 cohort Mn 留存率 | 同上按月；2026-04 起 |
| C03 | D1/D7/D30 留存 | 激活后第 n 天当天活跃 |
| C04 ★ | Quick Ratio | (New + Resurrected) / Churned，周/月 |
| C05 | 复活率 / 复活后留存 | 沉默 ≥28 天账号本期回归比例；回归后 4 周留存 |
| C06 | 首周 ≥3 次占比 | 激活后 7 天内完成 ≥3 次有效训练的账号占比（Aha 前导指标，阈值待数据验证后校准） |

维度：product_line、国家、渠道、**激活时固件版本 × 当前固件**（周 cohort × 固件 = OTA 效果视图）、首课类型、**onboarding 目标大类（goals[].code G0–G7，档案仓）**、**声明周频（pref.schedule.weekly_frequency）**、会员状态。

### M4 训练与内容

| # | 指标 | 口径 |
|---|---|---|
| D01/D02/D03 | Starts / Completions / 完成率 | 按课型 × 单课；完成 = 到课程结束点 |
| D04 | 平均完成度 | mean(completion_pct) |
| D05 | 人均课次 | Σsessions / 活跃账号，按课型 |
| D06 | Time to First Workout | median/P90(首次有效训练 − 首绑) |
| D07 | 首课完成率 | 第一次 session 即完成的比例 |
| D08 | 课型 Mix | WORKOUT/MINI/MICRO 课次占比及随生命周期变化 |
| D09 ★ | 深度训练占比 | 深度训练（≥2 组且 ≥5 min）/ 有效训练 |
| D10 | 组完成率 | 完整组 / 开始的组 |
| D11/D12 | 周人均组数 / 有效时长 | 按账号 |
| D13 | Streak 分布 | 连续 ≥1 次有效训练的周数分布 |
| D14 | 内容库消耗率 | 已练课程 / 可用课程（分 product_line 内容库）；>70% 高消耗用户单列 |
| D15 | 复练率 | 同一课程练 ≥2 次的比例 |
| D16 | 自填负荷覆盖率 | 带 load 的 exercise_record 占比（数据质量指标，volume 的前提） |
| D17 | 训练容量（自报） | Σ(reps × load)，仅有自填负荷的记录，标注自报口径 |
| D18 | AI 动作打分均值 | mean(form_score.form_quality)（档案仓 log.bodypark.form_score，产品差异化指标） |

### M5 订阅会员

| # | 指标 | 口径 |
|---|---|---|
| E01 | 会员状态分布 | 各状态账号数：FREE / PLUS / PRO_GIFT / PRO_PAID，日快照 |
| E02 ★ | 活跃付费 Pro 数 | count(PRO_PAID 在期)（**NSM-2**，不含赠送） |
| E03 | Pro 在期渗透率 | (PRO_GIFT + PRO_PAID) / A04 |
| E04 ★ | 付费渗透率 | PRO_PAID / A04 |
| E05 ★ | 赠转付转化率 | 赠送到期账号中，30 天内转 PRO_PAID 的比例；**按赠送月数(1/3/6/12) × 套装 SKU 分组** |
| E06 | 直接开通率 | 无赠送期直接 PLUS→PRO_PAID 的开通 |
| E07 | 续费率 | PRO_PAID 到期续费比例，首次/二次分开，按计费周期（月/年，待 R12 细化） |
| E08 | 主动取消率 / 支付失败率 | 两者分开；支付失败配催付挽回率 |
| E09 | cancel_pending 占比 | 已取消待到期 / PRO_PAID（流失先行指标） |
| E10 | 赢回率 | 曾 PRO_PAID 流失后重新付费的比例 |
| E11 | 会员净增 & 订阅 Quick Ratio | 新付费+赢回−流失；(新+赢回)/流失 |
| E12 | AI 时长用量 | 人均 AI 课程分钟数 / 配额；按 tier |
| E13 ★ | AI 配额触顶率 | 当期用满配额的账号占比。**PLUS 触顶池 = 最优质升级名单** |
| E14 | 视频存储用量分布 | 按 tier 的存储使用直方图与触顶率 |
| E15 | 高阶功能渗透率 | Pro 在期账号中使用过高阶功能的比例（**不用权益的 Pro = 流失/降级高危**） |
| E16 | 低活跃付费池 | PRO_PAID 且近 28 天 0 有效训练（续费前干预名单） |
| E17 | 高频 Plus 池 | PLUS 且周均 ≥2 次有效训练且非 Pro（转化目标名单） |
| E18 | 赠送期激活质量 | PRO_GIFT 期内的 WAU-L3 / 权益用量（赠送期练起来的人才会转付费——E05 的前导） |

### M6 设备健康

| # | 指标 | 口径 |
|---|---|---|
| F01 | 设备在线率 | 当日 L2 设备 / 近 28 天有 L1 的设备 |
| F02 | 固件版本分布 | 按当前固件聚合，周粒度 |
| F03 | OTA 覆盖率 / 成功率 | 新固件发布后 7/14 天覆盖；升级成功率（与周 cohort 联动） |
| F04 | 配网成功率 | wifi_setup 完成/尝试，失败原因分布 |
| F05 | 补传延迟分布 | power_on 事件 server_received − device_local 的分布（7 天窗口内形态） |
| F06 | 超窗丢弃量 | 迟到 >7 天被丢弃的事件量（异常升高 = 固件补传策略问题） |
| F07 | RMA / 退货 | 手动源（销售端月度），标注 manual |

---

## Part C · 后台数据字段定义

### C1. 账号档案字段（引用档案仓，SSOT 不在本文）

指标体系直接消费的档案字段（code 与档案仓完全一致）：

| 域 | 字段 code | 用途 |
|---|---|---|
| identity.account | `user_id`（ULID） | 全局账号主键 |
| identity.account | `account_edition`（cn/intl） | = product_line 一级维度；数据驻留分区键，**任何查询必须带此条件** |
| identity.account | `email` / `email_source` / `phone` / `auth_methods[]` | 触达渠道（Email 报表、召回）；不入指标 |
| identity.personal | `gender` / `birth_date`（→派生 age_group）/ `country_code` / `languages[]` | 人口维度下钻 |
| identity.devices[] | `{device_id, device_type, model, state, bound_at}` | **设备绑定状态机**：state ∈ none/purchased/bound/unbound；配对激活 = 首次进入 bound |
| identity.business.acquisition | `acquisition_source` / `referral_code` | 渠道维度（枚举待渠道体系，档案仓占位中） |
| identity.business.membership | `membership_tier`（free/plus/pro，只读引用，SSOT=订单系统） | 会员状态基础；pro 细分见 C2-4 |
| goal | `goals[].code`（G0–G7 意图大类）/ `goals[].priority` / `goals[].state` | **cohort 下钻维度**：不同目标人群的留存差 |
| pref.schedule | `weekly_frequency`（声明周频） | 与实际频次对比 → 依从性 gap（声明 3 次实练 1 次 = 干预对象） |
| log.bodypark | `workout_session{date, program_ref, duration}` / `exercise_record{sets, reps, load, rpe, completion}` / `form_score{rep_count, form_quality, errors[]}` | M4 全部指标的原始来源；load 为用户自填 |
| log.analytics | `adherence` / `streak` / `volume_trend`（⚙派生） | 与本文 D 系指标同源；口径以本文为准，档案仓侧展示层复用 |

> 档案仓治理规则同样约束本体系：ULID 主键、append-only 事件不改写、字段只加不删、`profile_` 前缀防撞名（本文数仓资产属分析域，用 `dwh_`/`agg_` 前缀，不与 `profile_*` 冲突）。

### C2. 埋点与业务事件（分析域新增/扩展）

所有事件公共字段：`event_id`（幂等去重）、`device_local_ts` + `server_received_ts`（双时间戳，离线补传正确归日）、`account_edition`。

**C2-1 设备事件（固件侧）**

| 事件 | 关键字段 | 说明 |
|---|---|---|
| `device_power_on` | device_id, is_offline_logged | L1 来源；离线本地 log，联网补传（窗口 7 天） |
| `device_heartbeat` | device_id, fw_version, rssi | L2 来源 |
| `wifi_setup` | device_id, attempt_n, result, error_code | F04 |
| `ota_event` | device_id, from_ver, to_ver, result | F03 |

**C2-2 绑定事件（App/后端）**

| 事件 | 关键字段 | 说明 |
|---|---|---|
| `device_binding_event` | user_id, device_id, action(bind/unbind), ts | 档案仓 devices[] 只存当前态；**分析需要绑定历史事件流**（bridge 表的来源，需后端补） |
| `onboarding_step` | user_id, step, status | A07 绑定漏斗 |

**C2-3 训练事件（App/算法侧，对齐 log.bodypark）**

| 事件 | 关键字段 | 说明 |
|---|---|---|
| `workout_session_start` | session_id, user_id, device_id, content_id, content_type(WORKOUT/MINI/MICRO) | D01 |
| `workout_session_end` | session_id, end_reason(complete/quit/timeout), completion_pct, duration_sec, active_duration_sec? | D02–D04；active_duration 若首期没有则先用 duration |
| `set_completed` | session_id, set_index, is_complete, reps, load?（自填）, form_quality? | **第一优先级埋点**：有效训练判定（≥1 完整组）与 D9–D12/D16–D18 全依赖它 |

**C2-4 会员事件（订单系统 → 分析域，独立管道）**

| 事件 | 关键字段 | 说明 |
|---|---|---|
| `membership_event` | user_id, event_type(gift_start / gift_expire / paid_start / renew / upgrade_direct / cancel_request / expire / payment_fail / win_back), **entitlement_source(bundled_gift/self_paid)**, gift_months?, sku?, billing_cycle?, effective_from, effective_to | 订单系统需补充 entitlement_source 与 gift_months —— membership_tier 三档枚举不够用（区分不了赠送/自费） |
| `quota_usage_daily` | user_id, ai_minutes_used, ai_minutes_quota, video_storage_used_mb, advanced_feature_flags | E12–E15；来自业务后端日结 |

### C3. 数仓模型（每区一套，指标级合并）

```
── 维度 ──
dim_user            user_id, account_edition, country_code, gender, age_group,
                    signup_at, acquisition_source, goal_primary_code(G0–G7),
                    declared_weekly_freq
dim_device          device_id, model/sku, account_edition, fw_current,
                    sold_at?(销售端), first_bound_at
dim_content         content_id, content_type, duration_sec, required_tier,
                    coach, category（分区内容库各自维护）
dim_sku_gift_map    sku → gift_months(1/3/6/12)   ← 待 R12 提供

── 桥接 ──
bridge_user_device  user_id, device_id, bound_at, unbound_at
                    （由 device_binding_event 重建，历史完整）

── 事实（append-only，事件表同名落仓）──
fct_power_on / fct_heartbeat / fct_binding / fct_session / fct_set /
fct_membership_event / fct_quota_daily / fct_sales_manual（销售端手动：售出、退货，月度）

── 聚合底座（看板唯一数据源）──
agg_user_daily        ★ user_id × date(PT)：l1/l2/l3 flag、各课型 sessions、
                        qualified_workouts、sets_completed、active_minutes、
                        deep_workout_flag、load_covered_sets、volume_selfreport
agg_membership_daily  ★ user_id × date：state(FREE/PLUS/PRO_GIFT/PRO_PAID)、
                        cancel_pending、gift_months、sku、ai_minutes_used/quota、
                        video_storage_used、advanced_feature_used
agg_device_daily      device_id × date：设备级活跃、fw_version（硬件团队）
agg_cohort_weekly / agg_cohort_monthly    cohort × period × layer × 维度组合
── 跨区合并层（仅此层出区）──
global_metrics_daily  metric_id × date × dims：CN 与 INTL 各自算好的聚合值 UNION，
                      无任何用户粒度字段（合规出区的唯一形态）
```

**派生规则要点**
1. `agg_user_daily.l3 = 1` ⟺ 当日 qualified_workouts ≥ 1；qualified ⟺ (sets_completed ≥ 1 or duration ≥ 60s)。
2. 会员日快照由 `fct_membership_event` 的生效区间展开；PLUS 由 bridge 表派生（有 bound 设备即 plus，除非在 Pro 期）。
3. L1 回填：每日重算窗口 = 近 7 天；`server_received − device_local > 7d` 的事件跳过。
4. 账号级指标只从 `agg_user_daily` × `agg_membership_daily` 出；全球视图只从 `global_metrics_daily` 出。

### C4. 数据质量与治理

| 项 | 规则 |
|---|---|
| 唯一性 | 事件按 event_id 去重；激活按 device 终身一次；活跃按 (user_id, date) |
| 未定稿标注 | L1 近 7 日；退货/RMA 数据源标 manual + 滞后月份 |
| 覆盖率监控 | 自填负荷覆盖率（D16）、active_duration 可得率、set 埋点上报率 |
| 口径变更 | 版本化 + 重算历史 + 图表标注（含 PT 夏令时切换日、会话时长→有效时长切换日） |
| 合规红线 | 用户级数据不出区；跨区查询必带 account_edition；合并只在 global_metrics_daily |

---

## 附录 · 第三轮决议记录（2026-08-18）

| # | 议题 | 决议 |
|---|---|---|
| D10 | 账号体系（原 R2） | ✅ 已打通——App 注册与订阅计费同一套 user_id |
| D11 | 会员模型（原 R9） | ✅ **Plus = 随 ATOM 终身免费**（非付费档）；**Pro = 按套装赠送 1–12 个月，到期转自费**。NSM-2 改为活跃付费 Pro 数 |
| D12 | 完整组（原 R4） | ✅ 组有完整定义，**完成即计**，次数不作限制 |
| D13 | 会员权益（原 R10） | ✅ AI 课程时长用量、视频存储大小、高阶功能——权益用量入指标（E12–E15） |
| D14 | 跨区（原 R5） | ✅ 用户数据 CN/INTL 分开；商业统计**指标级合并 + 分开**双视图（global_metrics_daily） |
| D15 | 历史（原 R8） | ✅ Cohort 自 **2026 年 4 月**起，周 + 月双粒度 |
| D16 | 退货（原 R6） | ✅ 未打通，销售端手动异步统计——净值月度修正，默认展示 gross |
| D17 | 传感（原 R7） | ✅ 无阻力/重量传感器，**负荷用户自填**——volume 走自报口径 + 覆盖率监控 |

**仍待拍板**

| # | 问题 | 影响 |
|---|---|---|
| R11 | 解绑全部设备后 Plus 是否保留（默认：回落 FREE） | E01 状态机边缘 |
| R12 | 套装 SKU → 赠送月数映射表；Pro 自费定价与计费周期（月/年） | E05/E07、dim_sku_gift_map |
| R13 | AI 时长/存储的具体配额数值（Plus vs Pro） | E12–E14 阈值 |
| R14 | `active_duration_sec`（有效运动时长）算法侧能否首期提供 | A3 时长口径 |
| R15 | 售出数据（sold_at）从销售端接入的方式与频率 | A05/A06/A08 |

*v1.0（2026-08-18）—— 下一步：per-metric SQL 落地（dbt model 与本文编号一一对应）。*
