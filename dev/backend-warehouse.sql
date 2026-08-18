-- =============================================================================
-- Atom 后端数仓开发参考（backend-warehouse.sql · v1.1）
-- =============================================================================
-- 一个文件两部分：
--   Part 1 建表 DDL —— 维表 / 事实表 / 双聚合基座 / 指标级合并表
--   Part 2 指标推导 SQL —— 基座构建与各模块指标示例（与 metrics-registry.json 对齐）
-- 口径 SSOT：docs/atom-data-dictionary.md（v2.0）
-- =============================================================================

-- ============================ Part 1 · 建表 DDL =============================
-- 约定：
--   · 日界一律 PT（America/Los_Angeles），字段名 pt_date。
--   · account_edition ∈ ('CN','INTL') 是所有表的分区键：两套系统物理隔离，
--     仅 global_metrics_daily 在指标层（L2 数值）汇总，明细永不合并。
--   · 血缘四层：L0 原始事件 → L1 日快照 → L2 计数 → L3 比率。
--   · 指标推导只允许两个基座表：agg_user_daily / agg_membership_daily。
--   · 迟到事件（server_received_ts - device_local_ts > 7 天）不进任何表，
--     归档 late_events 并计入 DEV06。
-- 方言：以 ANSI 为主（TIMESTAMP/DATE/BOOLEAN），落库时按实际引擎微调。
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 维表
-- ---------------------------------------------------------------------------

CREATE TABLE dim_user (
  user_id          VARCHAR(26)  NOT NULL,          -- ULID，账号体系 SSOT
  account_edition  VARCHAR(4)   NOT NULL,          -- 'CN' | 'INTL'（分区键）
  country_code     CHAR(2),                        -- ISO 3166-1，地区筛选
  register_ts      TIMESTAMP    NOT NULL,          -- 注册时间（UTC）
  register_pt_date DATE         NOT NULL,          -- 注册归属日（PT）→ ACT01/ACT02
  register_channel VARCHAR(32),
  PRIMARY KEY (user_id)
);

CREATE TABLE dim_device (
  device_id          VARCHAR(64) NOT NULL,         -- 设备序列号
  account_edition    VARCHAR(4)  NOT NULL,
  model              VARCHAR(32),
  first_bind_ts      TIMESTAMP,                    -- 首次绑定成功（UTC）
  first_bind_pt_date DATE,                         -- 设备激活归属日 → ACT03/ACT04
  current_fw_version VARCHAR(32),                  -- → DEV02 版本分布
  PRIMARY KEY (device_id)
);

CREATE TABLE dim_app (
  app_id       VARCHAR(32) NOT NULL,               -- workout / rope_skip / one_set / posture_pomodoro ...
  app_name     VARCHAR(64) NOT NULL,
  app_category VARCHAR(8)  NOT NULL,               -- 'PHYSICAL' | 'DESK' | 'AMBIENT'
                                                   --   PHYSICAL：身体运动类，唯一喂给 A4 的类别
                                                   --   DESK    ：桌面参与类（抬头番茄），只进 A1–A3
                                                   --   AMBIENT ：语音交互与桌面把玩类
  PRIMARY KEY (app_id)
);

CREATE TABLE dim_content (
  content_id          VARCHAR(64) NOT NULL,        -- 课程/内容 ID
  app_id              VARCHAR(32) NOT NULL REFERENCES dim_app(app_id),
  title               VARCHAR(255),
  workout_length_type VARCHAR(8),                  -- 'mini' | 'short' | 'long'（内容侧逐课标注）
                                                   --   mini  短练：< 5 分钟
                                                   --   short 小课：5–15 分钟（含两端）
                                                   --   long  长课：> 15 分钟
                                                   -- 意图维度，与实际时长/完成度正交。
                                                   -- 命名注：workout_type 已被『课程类型』占用，故用本名。
  planned_duration_sec INTEGER,                    -- 设计时长（标注 length_type 的依据）
  set_count           INTEGER,                     -- 课程结构组数（完成度分母参考）
  PRIMARY KEY (content_id)
);

CREATE TABLE dim_sku_gift_map (
  sku_id      VARCHAR(64) NOT NULL,                -- 硬件礼包 SKU
  gift_months INTEGER     NOT NULL CHECK (gift_months BETWEEN 1 AND 12),
  PRIMARY KEY (sku_id)                             -- → SUB05 兑换率漏斗
);

-- 一账号多设备：账号是主键实体，设备经桥表归属账号
CREATE TABLE bridge_user_device (
  user_id     VARCHAR(26) NOT NULL,
  device_id   VARCHAR(64) NOT NULL,
  bind_ts     TIMESTAMP   NOT NULL,
  unbind_ts   TIMESTAMP,                           -- NULL = 当前仍绑定
  is_current  BOOLEAN     NOT NULL DEFAULT TRUE,
  PRIMARY KEY (user_id, device_id, bind_ts)
);

-- ---------------------------------------------------------------------------
-- L0 → L1 事实表（按事件裁剪，字段与 schema/events.schema.json 对齐）
-- ---------------------------------------------------------------------------

CREATE TABLE fct_device_power_on (        -- A1 依据（含 ≤7 天离线回补）
  event_id        VARCHAR(36) NOT NULL,
  device_id       VARCHAR(64) NOT NULL,
  user_id         VARCHAR(26),                     -- 经 bridge 回填，可空
  account_edition VARCHAR(4)  NOT NULL,
  device_local_ts TIMESTAMP   NOT NULL,
  pt_date         DATE        NOT NULL,            -- 由 device_local_ts 换算 PT
  was_offline_backfill BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (event_id)
);

CREATE TABLE fct_session (                -- A3/A4 依据：session_start+end 合并落一行
  session_id          VARCHAR(36) NOT NULL,
  user_id             VARCHAR(26) NOT NULL,
  device_id           VARCHAR(64),
  app_id              VARCHAR(32) NOT NULL REFERENCES dim_app(app_id),
  account_edition     VARCHAR(4)  NOT NULL,
  content_id          VARCHAR(64),
  workout_length_type VARCHAR(8),                  -- 快照自 dim_content（以维表为准）
  start_ts            TIMESTAMP   NOT NULL,
  end_ts              TIMESTAMP,
  pt_date             DATE        NOT NULL,        -- 归属日 = start_ts 的 PT 日
  duration_sec        INTEGER,
  sets_completed      INTEGER     NOT NULL DEFAULT 0,   -- 与 fct_set_completed 对账
  completion_pct      NUMERIC(5,2),                -- 完课阈值占位 70%（R20）
  is_qualified_workout BOOLEAN    NOT NULL DEFAULT FALSE,
      -- 有效训练判定（仅 PHYSICAL）：sets_completed >= 1 OR duration_sec >= 60
  PRIMARY KEY (session_id)
);

CREATE TABLE fct_set_completed (          -- ⭐ 最高优先级新增埋点
  event_id      VARCHAR(36) NOT NULL,
  session_id    VARCHAR(36) NOT NULL,
  user_id       VARCHAR(26) NOT NULL,
  app_id        VARCHAR(32) NOT NULL,
  account_edition VARCHAR(4) NOT NULL,
  pt_date       DATE        NOT NULL,
  set_index     INTEGER     NOT NULL,
  movement_code VARCHAR(32),
  rep_count     INTEGER,                           -- 信息用途；有效性与次数无关
  user_reported_load_kg NUMERIC(6,2),              -- 用户自填负重（无阻力传感器）
  PRIMARY KEY (event_id)
);

CREATE TABLE fct_membership_event (       -- SUB 模块（开发后置 D35）
  event_id           VARCHAR(36) NOT NULL,
  user_id            VARCHAR(26) NOT NULL,
  account_edition    VARCHAR(4)  NOT NULL,
  pt_date            DATE        NOT NULL,
  action             VARCHAR(16) NOT NULL,         -- grant/gift_redeem/purchase/renew/expire/cancel
  tier               VARCHAR(10) NOT NULL,         -- FREE/PLUS/PRO_GIFT/PRO_PAID
  entitlement_source VARCHAR(16),                  -- device_bundle/gift_code/paid_order/ops_grant
  gift_months        INTEGER,
  order_id           VARCHAR(64),
  PRIMARY KEY (event_id)
);

CREATE TABLE late_events (                -- 超期迟到事件归档（不进指标）→ DEV06
  event_id           VARCHAR(36) NOT NULL,
  event_type         VARCHAR(32) NOT NULL,
  account_edition    VARCHAR(4)  NOT NULL,
  device_local_ts    TIMESTAMP,
  server_received_ts TIMESTAMP   NOT NULL,
  lag_days           NUMERIC(6,2),
  raw_payload        TEXT,
  PRIMARY KEY (event_id)
);

-- ---------------------------------------------------------------------------
-- L1 聚合基座（指标推导只允许从这两张表出发）
-- ---------------------------------------------------------------------------

-- 账号 × PT 日 快照：四层活跃嵌套 A1 ⊇ A2 ⊇ A3 ⊇ A4
CREATE TABLE agg_user_daily (
  pt_date          DATE        NOT NULL,
  user_id          VARCHAR(26) NOT NULL,
  account_edition  VARCHAR(4)  NOT NULL,
  country_code     CHAR(2),
  a1_power_on      BOOLEAN NOT NULL DEFAULT FALSE, -- A1 开机：名下任一设备当日有 power_on
  a2_online        BOOLEAN NOT NULL DEFAULT FALSE, -- A2 联网：当日有 heartbeat
  a3_app_active    BOOLEAN NOT NULL DEFAULT FALSE, -- A3 应用活跃：任一 App 会话（任意类别）
  a4_workout_active BOOLEAN NOT NULL DEFAULT FALSE,-- A4 训练活跃：≥1 次有效训练（仅 PHYSICAL）
  qualified_workout_cnt INTEGER NOT NULL DEFAULT 0,-- 当日有效训练次数（PV）→ 分层窗口累加
  session_cnt      INTEGER NOT NULL DEFAULT 0,     -- 当日全部 App 会话数（PV）
  physical_session_cnt INTEGER NOT NULL DEFAULT 0,
  desk_session_cnt INTEGER NOT NULL DEFAULT 0,     -- → ENG16 DESK 曲线
  desk_minutes     INTEGER NOT NULL DEFAULT 0,     -- → ENG17 桌面参与分钟（阈值 R19）
  set_cnt          INTEGER NOT NULL DEFAULT 0,
  train_minutes    INTEGER NOT NULL DEFAULT 0,
  mini_workout_cnt  INTEGER NOT NULL DEFAULT 0,    -- 按 workout_length_type 的有效训练拆分
  short_workout_cnt INTEGER NOT NULL DEFAULT 0,    --   mini 短练 / short 小课 / long 长课
  long_workout_cnt  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (pt_date, user_id)
);

-- 账号 × PT 日 会员快照
CREATE TABLE agg_membership_daily (
  pt_date         DATE        NOT NULL,
  user_id         VARCHAR(26) NOT NULL,
  account_edition VARCHAR(4)  NOT NULL,
  tier            VARCHAR(10) NOT NULL,            -- 当日末状态：FREE/PLUS/PRO_GIFT/PRO_PAID
  entitlement_source VARCHAR(16),
  pro_expire_date DATE,
  PRIMARY KEY (pt_date, user_id)
);

-- ---------------------------------------------------------------------------
-- L2 指标层汇总（唯一允许 CN/INTL 同表的地方：只存指标数值，无明细）
-- ---------------------------------------------------------------------------

CREATE TABLE global_metrics_daily (
  pt_date         DATE        NOT NULL,
  account_edition VARCHAR(6)  NOT NULL,            -- 'CN' | 'INTL' | 'GLOBAL'（GLOBAL=数值相加）
  metric_id       VARCHAR(12) NOT NULL,            -- 对应 metrics-registry.json 的 id（如 ENG08）
  metric_value    NUMERIC(18,4) NOT NULL,
  PRIMARY KEY (pt_date, account_edition, metric_id)
);

-- ========================= Part 2 · 指标推导 SQL ============================
-- 原则：
--   · 所有指标只从 agg_user_daily / agg_membership_daily 两个基座推导。
--   · UV 按 user_id 去重；PV 直接累加计数列；比率 = 分子 ⊆ 分母。
--   · 每条查询均按 account_edition 过滤（CN/INTL 隔离）；GLOBAL 只在
--     global_metrics_daily 做数值相加，永不 UNION 明细。
--   · :edition / :start_date / :end_date 为绑定参数。
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) 基座构建：agg_user_daily（每日增量任务）
-- ---------------------------------------------------------------------------
-- 有效训练判定（仅 PHYSICAL 类）：≥1 完整组 或 ≥60 秒，组做完即算、次数无关。
INSERT INTO agg_user_daily
SELECT
  d.pt_date,
  d.user_id,
  d.account_edition,
  u.country_code,
  MAX(CASE WHEN d.src = 'power_on'  THEN TRUE ELSE FALSE END) AS a1_power_on,
  MAX(CASE WHEN d.src = 'heartbeat' THEN TRUE ELSE FALSE END) AS a2_online,
  MAX(CASE WHEN d.src = 'session'   THEN TRUE ELSE FALSE END) AS a3_app_active,
  MAX(CASE WHEN d.src = 'session' AND d.is_qualified THEN TRUE ELSE FALSE END) AS a4_workout_active,
  SUM(CASE WHEN d.is_qualified THEN 1 ELSE 0 END)                       AS qualified_workout_cnt,
  SUM(CASE WHEN d.src = 'session' THEN 1 ELSE 0 END)                    AS session_cnt,
  SUM(CASE WHEN d.app_category = 'PHYSICAL' THEN 1 ELSE 0 END)          AS physical_session_cnt,
  SUM(CASE WHEN d.app_category = 'DESK' THEN 1 ELSE 0 END)              AS desk_session_cnt,
  SUM(CASE WHEN d.app_category = 'DESK' THEN d.duration_sec/60 ELSE 0 END) AS desk_minutes,
  SUM(d.sets_completed)                                                 AS set_cnt,
  SUM(CASE WHEN d.app_category = 'PHYSICAL' THEN d.duration_sec/60 ELSE 0 END) AS train_minutes,
  SUM(CASE WHEN d.is_qualified AND d.workout_length_type = 'mini'  THEN 1 ELSE 0 END) AS mini_workout_cnt,
  SUM(CASE WHEN d.is_qualified AND d.workout_length_type = 'short' THEN 1 ELSE 0 END) AS short_workout_cnt,
  SUM(CASE WHEN d.is_qualified AND d.workout_length_type = 'long'  THEN 1 ELSE 0 END) AS long_workout_cnt
FROM (
  -- 开机（A1）：设备事件经桥表归到账号；迟到 >7 天的已在入仓时丢弃
  SELECT p.pt_date, b.user_id, p.account_edition,
         'power_on' AS src, NULL AS app_category, FALSE AS is_qualified,
         0 AS duration_sec, 0 AS sets_completed, NULL AS workout_length_type
  FROM fct_device_power_on p
  JOIN bridge_user_device b
    ON b.device_id = p.device_id
   AND p.device_local_ts >= b.bind_ts
   AND (b.unbind_ts IS NULL OR p.device_local_ts < b.unbind_ts)
  UNION ALL
  -- 联网（A2）：同上，来源 heartbeat（略，同 power_on 形状，src='heartbeat'）
  -- ...
  -- 会话（A3/A4）
  SELECT s.pt_date, s.user_id, s.account_edition,
         'session' AS src, a.app_category,
         (a.app_category = 'PHYSICAL'
          AND (s.sets_completed >= 1 OR s.duration_sec >= 60)) AS is_qualified,
         s.duration_sec, s.sets_completed, s.workout_length_type
  FROM fct_session s
  JOIN dim_app a ON a.app_id = s.app_id
) d
JOIN dim_user u ON u.user_id = d.user_id
WHERE d.pt_date = :run_date
GROUP BY d.pt_date, d.user_id, d.account_edition, u.country_code;

-- ---------------------------------------------------------------------------
-- 1) ENG01 四层活跃矩阵：A1 开机 / A2 联网 / A3 应用活跃 / A4 训练活跃 × 日/周/月
-- ---------------------------------------------------------------------------
-- 日（DAU 族）
SELECT pt_date,
       COUNT(DISTINCT CASE WHEN a1_power_on       THEN user_id END) AS dau_a1_power_on,   -- ENG02
       COUNT(DISTINCT CASE WHEN a2_online         THEN user_id END) AS dau_a2_online,     -- ENG03
       COUNT(DISTINCT CASE WHEN a3_app_active     THEN user_id END) AS dau_a3_app,        -- ENG04
       COUNT(DISTINCT CASE WHEN a4_workout_active THEN user_id END) AS dau_a4_workout     -- ENG05
FROM agg_user_daily
WHERE account_edition = :edition AND pt_date BETWEEN :start_date AND :end_date
GROUP BY pt_date;

-- 周（WAU 族，ISO 周）。ENG08 = WAU-训练（北极星 NSM-1）
SELECT DATE_TRUNC('week', pt_date) AS iso_week,
       COUNT(DISTINCT CASE WHEN a1_power_on       THEN user_id END) AS wau_a1,            -- ENG06
       COUNT(DISTINCT CASE WHEN a2_online         THEN user_id END) AS wau_a2,            -- ENG07
       COUNT(DISTINCT CASE WHEN a3_app_active     THEN user_id END) AS wau_a3,            -- ENG09
       COUNT(DISTINCT CASE WHEN a4_workout_active THEN user_id END) AS wau_a4_workout     -- ENG08 ⭐
FROM agg_user_daily
WHERE account_edition = :edition AND pt_date BETWEEN :start_date AND :end_date
GROUP BY 1;

-- ENG08R 周训练活跃率 = ENG08 ÷ ACT02（累计注册账号）
WITH wau AS (
  SELECT COUNT(DISTINCT user_id) AS n
  FROM agg_user_daily
  WHERE account_edition = :edition
    AND a4_workout_active
    AND pt_date BETWEEN :week_start AND :week_end
), base AS (
  SELECT COUNT(*) AS n FROM dim_user
  WHERE account_edition = :edition AND register_pt_date <= :week_end
)
SELECT wau.n::NUMERIC / NULLIF(base.n, 0) AS eng08r FROM wau, base;

-- ENG19 DAU/MAU 粘性比率（D40 · 同一层级相除，示例 A4；A1–A3 同形）
WITH dau AS (
  SELECT COUNT(DISTINCT user_id) AS n FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active AND pt_date = :as_of_date
), mau AS (
  SELECT COUNT(DISTINCT user_id) AS n FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active
    AND pt_date > :as_of_date - INTERVAL '28 days' AND pt_date <= :as_of_date
)
SELECT dau.n::NUMERIC / NULLIF(mau.n,0) AS eng19_dau_mau FROM dau, mau;

-- ENG18 桌面陪伴缺口 = A3 − A4（当日应用活跃但未训练的账号数）
SELECT pt_date,
       COUNT(DISTINCT CASE WHEN a3_app_active AND NOT a4_workout_active THEN user_id END) AS eng18_desk_gap
FROM agg_user_daily
WHERE account_edition = :edition AND pt_date BETWEEN :start_date AND :end_date
GROUP BY pt_date;

-- ---------------------------------------------------------------------------
-- 2) ACT 激活漏斗
-- ---------------------------------------------------------------------------
-- ACT01 新增注册（日）/ ACT02 累计注册
SELECT register_pt_date AS pt_date, COUNT(*) AS act01_new_reg
FROM dim_user WHERE account_edition = :edition
GROUP BY register_pt_date;

-- ACT03 新增设备激活（首绑）/ ACT04 累计激活
SELECT first_bind_pt_date AS pt_date, COUNT(*) AS act03_new_activation
FROM dim_device
WHERE account_edition = :edition AND first_bind_pt_date IS NOT NULL
GROUP BY first_bind_pt_date;

-- ACT05 首次有效训练（UV：账号首次 a4 当日计入；单调不回退）
SELECT first_a4_date AS pt_date, COUNT(*) AS act05_first_workout
FROM (
  SELECT user_id, MIN(pt_date) AS first_a4_date
  FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active
  GROUP BY user_id
) t
GROUP BY first_a4_date;

-- ---------------------------------------------------------------------------
-- 3) ENG14 用户分层（D38 · 三档，滚动 28 天 ≈ 一个月）
-- ---------------------------------------------------------------------------
--   heavy 重度：≥10 次 | regular 常规：4–9 次 | light 轻度：1–3 次
--   0 次不入档（沉默用户走 ENG15）。
SELECT tier, COUNT(*) AS accounts
FROM (
  SELECT user_id,
         CASE
           WHEN SUM(qualified_workout_cnt) >= 10 THEN 'heavy'
           WHEN SUM(qualified_workout_cnt) >= 4  THEN 'regular'
           WHEN SUM(qualified_workout_cnt) >= 1  THEN 'light'
         END AS tier
  FROM agg_user_daily
  WHERE account_edition = :edition
    AND pt_date > :as_of_date - INTERVAL '28 days' AND pt_date <= :as_of_date
  GROUP BY user_id
  HAVING SUM(qualified_workout_cnt) >= 1
) t
GROUP BY tier;

-- ---------------------------------------------------------------------------
-- 4) RET01 周度同期群留存（2026-04 起 · 檔位可选 A1/A3/A4，示例用 A4）
-- ---------------------------------------------------------------------------
--   同期群 = 首次有效训练所在 ISO 周；检查点 W2/W3/W4/W8。
WITH cohort AS (
  SELECT user_id, DATE_TRUNC('week', MIN(pt_date)) AS cohort_week
  FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active
  GROUP BY user_id
), activity AS (
  SELECT DISTINCT user_id, DATE_TRUNC('week', pt_date) AS act_week
  FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active
)
SELECT c.cohort_week,
       COUNT(DISTINCT c.user_id) AS cohort_size,
       COUNT(DISTINCT CASE WHEN a.act_week = c.cohort_week + INTERVAL '1 week' THEN c.user_id END)::NUMERIC
         / NULLIF(COUNT(DISTINCT c.user_id),0) AS w2,
       COUNT(DISTINCT CASE WHEN a.act_week = c.cohort_week + INTERVAL '2 week' THEN c.user_id END)::NUMERIC
         / NULLIF(COUNT(DISTINCT c.user_id),0) AS w3,
       COUNT(DISTINCT CASE WHEN a.act_week = c.cohort_week + INTERVAL '3 week' THEN c.user_id END)::NUMERIC
         / NULLIF(COUNT(DISTINCT c.user_id),0) AS w4,
       COUNT(DISTINCT CASE WHEN a.act_week = c.cohort_week + INTERVAL '7 week' THEN c.user_id END)::NUMERIC
         / NULLIF(COUNT(DISTINCT c.user_id),0) AS w8
FROM cohort c LEFT JOIN activity a ON a.user_id = c.user_id
WHERE c.cohort_week >= DATE '2026-03-30'
GROUP BY c.cohort_week ORDER BY c.cohort_week;

-- RET06 Aha：首周（首次训练起 7 天内）≥2 次有效训练的账号占比
WITH first_day AS (
  SELECT user_id, MIN(pt_date) AS d0
  FROM agg_user_daily
  WHERE account_edition = :edition AND a4_workout_active
  GROUP BY user_id
)
SELECT COUNT(CASE WHEN w1_cnt >= 2 THEN 1 END)::NUMERIC / NULLIF(COUNT(*),0) AS ret06_aha
FROM (
  SELECT f.user_id, SUM(u.qualified_workout_cnt) AS w1_cnt
  FROM first_day f
  JOIN agg_user_daily u
    ON u.user_id = f.user_id
   AND u.pt_date BETWEEN f.d0 AND f.d0 + INTERVAL '6 days'
  GROUP BY f.user_id
) t;

-- ---------------------------------------------------------------------------
-- 5) TRN 训练：课型结构（workout_length_type：mini 短练 / short 小课 / long 长课）
-- ---------------------------------------------------------------------------
-- TRN08 课型结构占比（PV：有效训练次数按课型拆分）
SELECT pt_date,
       SUM(mini_workout_cnt)  AS trn_mini_cnt,    -- 短练 <5min
       SUM(short_workout_cnt) AS trn_short_cnt,   -- 小课 5–15min（含两端）
       SUM(long_workout_cnt)  AS trn_long_cnt     -- 长课 >15min
FROM agg_user_daily
WHERE account_edition = :edition AND pt_date BETWEEN :start_date AND :end_date
GROUP BY pt_date;

-- TRN19 分应用统计（每 App：会话数 PV / 活跃账号 UV / 分钟数）
SELECT s.pt_date, s.app_id, a.app_category,
       COUNT(*)                    AS sessions_pv,
       COUNT(DISTINCT s.user_id)   AS users_uv,
       SUM(s.duration_sec) / 60    AS minutes_total
FROM fct_session s JOIN dim_app a ON a.app_id = s.app_id
WHERE s.account_edition = :edition AND s.pt_date BETWEEN :start_date AND :end_date
GROUP BY s.pt_date, s.app_id, a.app_category;

-- ---------------------------------------------------------------------------
-- 6) DEV 设备健康
-- ---------------------------------------------------------------------------
-- DEV06 迟到事件量监控（回补窗口健康度）
SELECT DATE(server_received_ts) AS recv_date, event_type, COUNT(*) AS late_cnt
FROM late_events
WHERE account_edition = :edition
GROUP BY 1, 2;

-- ---------------------------------------------------------------------------
-- 7) GLOBAL 汇总（唯一合并点：指标数值相加，明细永不跨系统）
-- ---------------------------------------------------------------------------
INSERT INTO global_metrics_daily (pt_date, account_edition, metric_id, metric_value)
SELECT pt_date, 'GLOBAL', metric_id, SUM(metric_value)
FROM global_metrics_daily
WHERE account_edition IN ('CN','INTL') AND pt_date = :run_date
GROUP BY pt_date, metric_id;
-- 注意：仅可加性指标（计数类 L2）可直接相加；比率类 L3 须由 GLOBAL 分子/分母重算。
