import { adminHeaders, requiredEnv, type PlanId } from "./billing.ts";

export type UsagePlanId = "free" | PlanId;

export type UsageBalance = {
  plan_id: UsagePlanId;
  period_start: string;
  period_end: string;
  base_seconds: number;
  rollover_seconds: number;
  addon_seconds: number;
  total_seconds: number;
  used_seconds: number;
  remaining_seconds: number;
  extra_hour_price_rub: number | null;
  can_purchase_extra_hours: boolean;
};

type SubscriptionRow = {
  plan_id: PlanId;
  current_period_start: string;
  current_period_end: string;
};

type UsagePeriodRow = {
  plan_id: PlanId;
  period_start: string;
  period_end: string;
  base_seconds: number | string;
  rollover_seconds: number | string;
  addon_seconds: number | string;
};

async function rest(path: string, init: RequestInit = {}) {
  return fetch(`${requiredEnv("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { ...adminHeaders(), ...(init.headers ?? {}) },
  });
}

async function rows<T>(path: string): Promise<T[]> {
  const response = await rest(path);
  if (!response.ok) throw new Error(await response.text());
  return await response.json() as T[];
}

async function usedSeconds(userId: string, start: string, end: string) {
  const sessions = await rows<{ duration_seconds?: number | string }>(
    `translation_sessions?user_id=eq.${encodeURIComponent(userId)}` +
      `&ended_at=gte.${encodeURIComponent(start)}` +
      `&ended_at=lt.${encodeURIComponent(end)}` +
      "&select=duration_seconds",
  );
  return sessions.reduce(
    (total, session) => total + Math.max(0, Number(session.duration_seconds) || 0),
    0,
  );
}

function paidBalance(period: UsagePeriodRow, used: number): UsageBalance {
  const base = Number(period.base_seconds) || 0;
  const rollover = Number(period.rollover_seconds) || 0;
  const addon = Number(period.addon_seconds) || 0;
  const total = base + rollover + addon;
  return {
    plan_id: period.plan_id,
    period_start: period.period_start,
    period_end: period.period_end,
    base_seconds: base,
    rollover_seconds: rollover,
    addon_seconds: addon,
    total_seconds: total,
    used_seconds: used,
    remaining_seconds: Math.max(0, total - used),
    extra_hour_price_rub: period.plan_id === "pro" ? 199 : 299,
    can_purchase_extra_hours: true,
  };
}

export async function getUsageBalance(userId: string): Promise<UsageBalance> {
  const now = new Date();
  const nowISO = now.toISOString();
  const subscriptions = await rows<SubscriptionRow>(
    `subscriptions?user_id=eq.${encodeURIComponent(userId)}` +
      "&status=eq.active" +
      `&current_period_start=lte.${encodeURIComponent(nowISO)}` +
      `&current_period_end=gt.${encodeURIComponent(nowISO)}` +
      "&select=plan_id,current_period_start,current_period_end&limit=1",
  );
  const subscription = subscriptions[0];

  if (subscription) {
    let periods = await rows<UsagePeriodRow>(
      `usage_periods?user_id=eq.${encodeURIComponent(userId)}` +
        `&period_start=lte.${encodeURIComponent(nowISO)}` +
        `&period_end=gt.${encodeURIComponent(nowISO)}` +
        "&select=plan_id,period_start,period_end,base_seconds,rollover_seconds,addon_seconds" +
        "&order=period_start.desc&limit=1",
    );

    if (!periods[0]) {
      const response = await rest("rpc/activate_usage_period", {
        method: "POST",
        body: JSON.stringify({
          p_user_id: userId,
          p_plan_id: subscription.plan_id,
          p_period_start: subscription.current_period_start,
          p_period_end: subscription.current_period_end,
        }),
      });
      if (!response.ok) throw new Error(await response.text());
      const created = await response.json() as UsagePeriodRow | UsagePeriodRow[];
      periods = Array.isArray(created) ? created : [created];
    }

    const period = periods[0];
    const used = await usedSeconds(userId, period.period_start, period.period_end);
    return paidBalance(period, used);
  }

  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const monthEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const latestPeriods = await rows<{ period_end: string }>(
    `usage_periods?user_id=eq.${encodeURIComponent(userId)}` +
      `&period_end=lte.${encodeURIComponent(nowISO)}` +
      "&select=period_end&order=period_end.desc&limit=1",
  );
  const latestPaidEnd = latestPeriods[0]?.period_end
    ? new Date(latestPeriods[0].period_end)
    : null;
  const freeStart = latestPaidEnd && latestPaidEnd > monthStart ? latestPaidEnd : monthStart;
  const used = await usedSeconds(userId, freeStart.toISOString(), monthEnd.toISOString());
  const total = 30 * 60;
  return {
    plan_id: "free",
    period_start: freeStart.toISOString(),
    period_end: monthEnd.toISOString(),
    base_seconds: total,
    rollover_seconds: 0,
    addon_seconds: 0,
    total_seconds: total,
    used_seconds: used,
    remaining_seconds: Math.max(0, total - used),
    extra_hour_price_rub: null,
    can_purchase_extra_hours: false,
  };
}

