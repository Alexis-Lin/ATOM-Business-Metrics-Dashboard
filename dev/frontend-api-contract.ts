/**
 * Atom 业务指标看板 · 前端 API 契约参考（v1.0）
 * ------------------------------------------------------------------
 * 对应：metrics-registry.json（指标注册表）+ backend-warehouse.sql（推导口径）
 * 原型：dashboard-prototype.html —— 前端可直接复用该 HTML，把 mock 数据块
 *       替换为下述接口返回值即可（见本目录 README.md 的挂载点说明）。
 *
 * 约定：
 *  - 所有日期均为 PT（America/Los_Angeles）口径的日历日，格式 YYYY-MM-DD。
 *  - edition 是硬隔离分区：CN / INTL 各自独立系统；GLOBAL 仅指标数值合并，
 *    一期前端禁用（按钮 disabled），默认视图 INTL（海外）。
 *  - metricId 与 metrics-registry.json 的 id 一一对应（如 "ENG08"）。
 */

// ---------- 基础枚举（与后端字段字典对齐） ----------

export type AccountEdition = 'CN' | 'INTL';
export type EditionView = AccountEdition | 'GLOBAL'; // GLOBAL 一期禁用

export type ActivityTier = 'a1' | 'a2' | 'a3' | 'a4';
// a1 开机 ⊇ a2 联网 ⊇ a3 应用活跃 ⊇ a4 训练活跃（严格嵌套）

export type AppCategory = 'PHYSICAL' | 'DESK' | 'AMBIENT';
// PHYSICAL 身体运动类（唯一喂给 a4）/ DESK 桌面参与类 / AMBIENT 语音交互与桌面把玩类

/**
 * 课程时长类型（注意：不是 workout_type——该字段名已被『课程类型』占用）。
 * 内容侧逐课标注的意图维度，与实际时长/完成度正交。
 */
export type WorkoutLengthType = 'mini' | 'short' | 'long';
export const WORKOUT_LENGTH_LABEL: Record<WorkoutLengthType, string> = {
  mini: '短练（<5 分钟）',
  short: '小课（5–15 分钟，含两端）',
  long: '长课（>15 分钟）',
};

export type MembershipTier = 'FREE' | 'PLUS' | 'PRO_GIFT' | 'PRO_PAID';

/** 用户分层（D43 · 四档，滚动 28 天窗口；基数 = 有 A1 开机的账号，完全不开机不入档） */
export type UserTier = 'heavy' | 'regular' | 'light' | 'zero';
export const USER_TIER_LABEL: Record<UserTier, string> = {
  heavy: '重度（≥10 次/月）',
  regular: '常规（4–9 次/月）',
  light: '轻度（1–3 次/月）',
  zero: '零训练（0 次，但有开机）',
};

export type Granularity = 'day' | 'week' | 'month';
export type DedupMode = 'user_uv' | 'device_uv' | 'pv' | 'ratio';

// ---------- 通用请求/响应 ----------

export interface MetricQuery {
  edition: EditionView;      // 一期只接受 'CN' | 'INTL'
  startDate: string;         // PT 日，含
  endDate: string;           // PT 日，含
  granularity: Granularity;
  countryCode?: string;      // ISO 3166-1，仅 INTL 下有意义
}

export interface MetricPoint {
  date: string;              // 日粒度=PT 日；周粒度=ISO 周一；月粒度=当月 1 号
  value: number;
}

export interface MetricSeries {
  metricId: string;          // metrics-registry.json 的 id
  name: string;
  unit: string;              // 账号 / 设备 / 次 / 分钟 / %
  dedup: DedupMode;
  points: MetricPoint[];
  /** 数据完整性：末尾未终结（finalize 前）的点数，前端以虚线/浅色渲染 */
  provisionalTail?: number;
}

// ---------- 模块化响应（与原型 8 个 Tab 对应） ----------

/** GET /api/v1/overview —— 总览：4 级漏斗 + 记分卡 */
export interface OverviewResponse {
  funnel: {
    act02CumRegistrations: number;   // 累计 App 注册（账号 UV）
    act04CumActivations: number;     // 设备激活数（设备 UV）
    act05EverWorkout: number;        // 有效训练人数（账号 UV，历史累计）
    sub04ProPaid: number;            // 付费人数（账号 UV）
  };
  scorecards: MetricSeries[];        // ENG08(NSM-1) / ENG08R / RET01-W4 / SUB04(NSM-2)
}

/** GET /api/v1/engagement —— 四层活跃矩阵（率优先，绝对值可切换） */
export interface EngagementResponse {
  matrix: Array<{
    tier: ActivityTier;
    tierName: string;                // A1 开机 / A2 联网 / A3 应用活跃 / A4 训练活跃
    dau: MetricSeries;               // ENG02–05
    wau: MetricSeries;               // ENG06–09（ENG08 = A4 周 = NSM-1）
    mau: MetricSeries;               // ENG10–13 绝对值族
    wauRate: MetricSeries;           // ÷ ACT02，如 ENG08R
  }>;
  deskGap: MetricSeries;             // ENG18 = A3 − A4
  deskCurve: MetricSeries;           // ENG16 DESK 类会话曲线
  userTiers: Array<{ tier: UserTier; accounts: number }>; // ENG14（D43 四档）
  silentAccounts: MetricSeries;      // ENG15
}

/** GET /api/v1/retention —— 周度同期群（2026-04 起） */
export interface RetentionResponse {
  tierFilter: ActivityTier;          // 檔位可选 A1/A3/A4，默认 A4
  cohorts: Array<{
    cohortWeek: string;              // ISO 周一
    cohortSize: number;
    checkpoints: { w2: number; w3: number; w4: number; w8: number }; // 0–1
  }>;
  aha: MetricSeries;                 // RET06 首周≥2 次
  quickRatio: MetricSeries;
}

/** GET /api/v1/training —— 训练量与课型结构 */
export interface TrainingResponse {
  workouts: MetricSeries;            // TRN01 有效训练次数（PV）
  minutes: MetricSeries;             // TRN03 训练分钟
  sets: MetricSeries;                // TRN05 完整组数
  lengthTypeMix: Array<{             // TRN08：按 workout_length_type 拆分（① 基础结构）
    type: WorkoutLengthType;
    series: MetricSeries;
  }>;
  /** 组数（D47）：只单列完成组数；应练组数（TRN21）为服务端内部分母，不出接口 */
  sets: {
    completed: MetricSeries;         // TRN22 = Σ set_completed
    completionRate: MetricSeries;    // TRN10 = TRN22 ÷ TRN21（分母服务端折算，R22）
  };
  /** 真实时长（D47）：单一人均时长指标 + 分布（分布是主读数）；TRN23 已并入 TRN20 */
  realDuration: {
    perUserMinutes: MetricSeries;    // TRN20（分母 = 周训练活跃账号）
    distribution: Array<{ bucket: '<15' | '15-30' | '30-60' | '60-120' | '>=120'; share: number }>; // TRN24
  };
  perApp: Array<{                    // TRN19 分应用统计
    appId: string;
    appName: string;
    appCategory: AppCategory;
    sessionsPv: number;
    usersUv: number;
    minutes: number;
  }>;
}

/** GET /api/v1/membership —— SUB（开发后置 D35：一期只出占位横幅+基础计数） */
export interface MembershipResponse {
  deferred: true;                    // 一期恒为 true，前端渲染『开发后置』横幅
  counts: Record<MembershipTier, number>;
  redemptionRate?: number;           // SUB05 礼包兑换率
}

/** GET /api/v1/device —— 设备健康 */
export interface DeviceResponse {
  liveOnline: number;                // DEV07 实时在线（heartbeat 5 分钟窗）
  fwVersionDist: Array<{ version: string; devices: number }>; // DEV02
  lateEventVolume: MetricSeries;     // DEV06 迟到事件量
}

// ---------- 端点一览 ----------

export const API_ENDPOINTS = {
  overview: '/api/v1/overview',
  engagement: '/api/v1/engagement',
  retention: '/api/v1/retention',
  training: '/api/v1/training',
  membership: '/api/v1/membership',
  device: '/api/v1/device',
  /** 单指标透传：?metricId=ENG08&... 直接读 global_metrics_daily */
  metric: '/api/v1/metric',
  /** 指标口径注册表：直接回传 metrics-registry.json，前端 ⓘ 提示与口径 Tab 数据源 */
  metricRegistry: '/api/v1/meta/metrics',
} as const;
