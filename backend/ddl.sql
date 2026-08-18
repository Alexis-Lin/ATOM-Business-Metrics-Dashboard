-- =============================================================================
-- Atom 业务指标数仓 DDL 参考（v1.0 · 对应数据字典 v2.0）
-- =============================================================================
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
  metric_id       VARCHAR(12) NOT NULL,            -- 对应 schema/metrics.json 的 id（如 ENG08）
  metric_value    NUMERIC(18,4) NOT NULL,
  PRIMARY KEY (pt_date, account_edition, metric_id)
);
