"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useLang } from "@/lib/i18n";
import { useUser } from "@/lib/useUser";
import styles from "./AdminDashboard.module.css";

type AdminView = "overview" | "users" | "costs";
type RangeKey = "7" | "30" | "90" | "all";

type DailyPoint = { date: string; page_views: number; visitors: number; clicks: number; signups: number };
type RankedItem = { name: string; count: number };
type Summary = {
  page_views: number;
  visitors: number;
  clicks: number;
  signups: number;
  total_users: number;
  revenue_rub: number;
  test_revenue_rub: number;
  estimated_cost_usd: number;
  recorded_cost_usd: number;
  plans: Partial<Record<"free" | "start" | "pro", number>>;
  daily: DailyPoint[];
  top_pages: RankedItem[];
  top_actions: RankedItem[];
};

type AdminUser = {
  user_id: string;
  email: string | null;
  created_at: string;
  last_sign_in_at: string | null;
  is_admin: boolean;
  plan_id: "free" | "start" | "pro";
  total_paid_rub: number;
  usage_seconds: number;
  session_count: number;
};

type CostRow = {
  user_id: string;
  email: string | null;
  plan_id: "free" | "start" | "pro";
  usage_seconds: number;
  session_count: number;
  estimated_cost_usd: number;
  recorded_cost_usd: number;
  recorded_cost_rub: number;
};

const ranges: RangeKey[] = ["7", "30", "90", "all"];

function dateRange(key: RangeKey) {
  const to = new Date();
  const from = key === "all" ? new Date("2020-01-01T00:00:00Z") : new Date(to.getTime() - Number(key) * 86400000);
  return { from: from.toISOString(), to: to.toISOString() };
}

function number(value: unknown) {
  return Number(value) || 0;
}

export default function AdminDashboard() {
  const { lang } = useLang();
  const { user } = useUser();
  const [view, setView] = useState<AdminView>("overview");
  const [range, setRange] = useState<RangeKey>("30");
  const [summary, setSummary] = useState<Summary | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [costs, setCosts] = useState<CostRow[]>([]);
  const [search, setSearch] = useState("");
  const [plan, setPlan] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [mutating, setMutating] = useState<string | null>(null);

  const copy = lang === "ru" ? {
    eyebrow: "EyeVoice / управление",
    title: "Пульс продукта",
    overview: "обзор",
    users: "пользователи",
    costs: "расходы",
    all: "всё",
    views: "просмотры",
    visitors: "посетители",
    clicks: "нажатия",
    signups: "регистрации",
    revenue: "выручка",
    estimatedCost: "оценка затрат",
    traffic: "динамика посещений",
    viewsHint: "просмотры страниц",
    topPages: "популярные страницы",
    topActions: "что нажимают",
    plans: "распределение тарифов",
    search: "поиск по email",
    created: "регистрация",
    lastSeen: "последний вход",
    plan: "тариф",
    paid: "оплачено",
    usage: "использовано",
    sessions: "сессии",
    admin: "админ",
    noRows: "По выбранным фильтрам данных нет.",
    loadError: "Не удалось загрузить административные данные. Проверьте миграцию Supabase и права текущего аккаунта.",
    costTitle: "Расходы API за период",
    costNote: "Оценка рассчитана по длительности переводов. Фактические cost-события хранятся отдельно и появятся после отправки usage из провайдера.",
    estimate: "оценка USD",
    recorded: "зафиксировано USD",
    recordedRub: "зафиксировано RUB",
    allPlans: "все тарифы",
  } : {
    eyebrow: "EyeVoice / operations",
    title: "Product pulse",
    overview: "overview",
    users: "users",
    costs: "costs",
    all: "all",
    views: "page views",
    visitors: "visitors",
    clicks: "clicks",
    signups: "signups",
    revenue: "revenue",
    estimatedCost: "estimated cost",
    traffic: "traffic trend",
    viewsHint: "page views",
    topPages: "top pages",
    topActions: "top actions",
    plans: "plan distribution",
    search: "search by email",
    created: "created",
    lastSeen: "last sign-in",
    plan: "plan",
    paid: "paid",
    usage: "usage",
    sessions: "sessions",
    admin: "admin",
    noRows: "No data matches the selected filters.",
    loadError: "Unable to load admin data. Check the Supabase migration and current account access.",
    costTitle: "API costs for period",
    costNote: "Estimate is based on translation duration. Recorded provider costs are stored separately once actual usage is submitted.",
    estimate: "estimate USD",
    recorded: "recorded USD",
    recordedRub: "recorded RUB",
    allPlans: "all plans",
  };

  const { from, to } = useMemo(() => dateRange(range), [range]);

  useEffect(() => {
    let cancelled = false;
    const timer = window.setTimeout(async () => {
      setLoading(true);
      setError(null);
      const request = view === "overview"
        ? supabase.rpc("admin_dashboard_summary", { p_from: from, p_to: to })
        : view === "users"
          ? supabase.rpc("admin_list_users", { p_search: search, p_plan: plan, p_from: null, p_to: null, p_limit: 200, p_offset: 0 })
          : supabase.rpc("admin_list_costs", { p_search: search, p_from: from, p_to: to, p_limit: 200, p_offset: 0 });
      const { data, error: requestError } = await request;
      if (cancelled) return;
      if (requestError) {
        setError(requestError.message);
      } else if (view === "overview") {
        setSummary(data as Summary);
      } else if (view === "users") {
        setUsers((data ?? []) as AdminUser[]);
      } else {
        setCosts((data ?? []) as CostRow[]);
      }
      setLoading(false);
    }, view === "overview" ? 0 : 260);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [view, range, from, to, search, plan]);

  const toggleAdmin = async (row: AdminUser) => {
    setMutating(row.user_id);
    const next = !row.is_admin;
    const { error: updateError } = await supabase.rpc("admin_set_user_admin", {
      p_user_id: row.user_id,
      p_is_admin: next,
    });
    if (updateError) setError(updateError.message);
    else setUsers((current) => current.map((item) => item.user_id === row.user_id ? { ...item, is_admin: next } : item));
    setMutating(null);
  };

  const maxViews = Math.max(1, ...(summary?.daily ?? []).map((point) => number(point.page_views)));
  const totalEstimated = costs.reduce((sum, row) => sum + number(row.estimated_cost_usd), 0);
  const totalRecorded = costs.reduce((sum, row) => sum + number(row.recorded_cost_usd), 0);
  const totalRecordedRub = costs.reduce((sum, row) => sum + number(row.recorded_cost_rub), 0);
  const locale = lang === "ru" ? "ru-RU" : "en-US";
  const date = (value: string | null) => value ? new Date(value).toLocaleDateString(locale, { day: "2-digit", month: "short", year: "2-digit" }) : "—";
  const hours = (seconds: unknown) => `${(number(seconds) / 3600).toFixed(1)} h`;

  return (
    <section className={styles.root} data-analytics-ignore>
      <div className={styles.topbar}>
        <div>
          <div className={styles.eyebrow}>{copy.eyebrow}</div>
          <h1 className={styles.title}>{copy.title}</h1>
        </div>
        <div className={styles.range} aria-label="Period">
          {ranges.map((item) => (
            <button key={item} type="button" className={range === item ? styles.active : ""} onClick={() => setRange(item)}>
              {item === "all" ? copy.all : `${item}d`}
            </button>
          ))}
        </div>
      </div>

      <div className={styles.subnav}>
        {(["overview", "users", "costs"] as AdminView[]).map((item) => (
          <button key={item} type="button" className={view === item ? styles.active : ""} onClick={() => setView(item)}>
            {copy[item]}
          </button>
        ))}
      </div>

      <div className={styles.body}>
        {error ? <div className={styles.error}>{copy.loadError}<br />{error}</div> : null}
        {loading ? <div className={styles.skeleton} aria-label="Loading" /> : null}

        {!loading && !error && view === "overview" && summary ? (
          <>
            <div className={styles.metricRail}>
              {[
                [copy.views, summary.page_views],
                [copy.visitors, summary.visitors],
                [copy.clicks, summary.clicks],
                [copy.signups, summary.signups],
                [copy.revenue, `${number(summary.revenue_rub).toLocaleString(locale)} ₽`],
                [copy.estimatedCost, `$${number(summary.estimated_cost_usd).toFixed(2)}`],
              ].map(([label, value], index) => (
                <div className={styles.metric} key={String(label)}>
                  <div className={styles.metricLabel}>{label}</div>
                  <div className={`${styles.metricValue} ${index === 5 ? styles.metricAccent : ""}`}>{value}</div>
                </div>
              ))}
            </div>

            <div className={styles.overviewGrid}>
              <div className={styles.panel}>
                <div className={styles.panelHeader}><span className={styles.panelTitle}>{copy.traffic}</span><span className={styles.panelHint}>{copy.viewsHint}</span></div>
                <div className={styles.chart}>
                  {(summary.daily ?? []).map((point) => (
                    <div className={styles.barWrap} key={point.date} title={`${date(point.date)} · ${point.page_views}`}>
                      <div className={styles.bar} style={{ height: `${Math.max(2, number(point.page_views) / maxViews * 100)}%` }} />
                    </div>
                  ))}
                </div>
                <div className={styles.legend}><span>{date(summary.daily?.[0]?.date ?? null)}</span><span>{date(summary.daily?.at(-1)?.date ?? null)}</span></div>
              </div>

              <div className={styles.panel}>
                <div className={styles.panelHeader}><span className={styles.panelTitle}>{copy.plans}</span><span className={styles.panelHint}>{summary.total_users}</span></div>
                <div className={styles.planStrip}>
                  {(["free", "start", "pro"] as const).map((item) => <div className={styles.planCell} key={item}><b>{summary.plans?.[item] ?? 0}</b><span>{item.toUpperCase()}</span></div>)}
                </div>
                <div className={styles.panelHeader} style={{ marginTop: "1rem" }}><span className={styles.panelTitle}>{copy.topPages}</span></div>
                <RankList rows={summary.top_pages} />
              </div>

              <div className={styles.panel} style={{ gridColumn: "1 / -1" }}>
                <div className={styles.panelHeader}><span className={styles.panelTitle}>{copy.topActions}</span><span className={styles.panelHint}>{copy.clicks}</span></div>
                <RankList rows={summary.top_actions} />
              </div>
            </div>
          </>
        ) : null}

        {!loading && !error && view === "users" ? (
          <>
            <div className={styles.filters}>
              <input className={styles.input} value={search} onChange={(event) => setSearch(event.target.value)} placeholder={copy.search} />
              <select className={styles.select} value={plan} onChange={(event) => setPlan(event.target.value)}>
                <option value="all">{copy.allPlans}</option><option value="free">FREE</option><option value="start">START</option><option value="pro">PRO</option>
              </select>
            </div>
            {users.length ? (
              <div className={styles.tableWrap}><table className={styles.table}><thead><tr>
                <th>Email</th><th>{copy.created}</th><th>{copy.lastSeen}</th><th>{copy.plan}</th><th>{copy.paid}</th><th>{copy.usage}</th><th>{copy.sessions}</th><th>{copy.admin}</th>
              </tr></thead><tbody>{users.map((row) => <tr key={row.user_id}>
                <td className={styles.email}>{row.email ?? "—"}</td><td>{date(row.created_at)}</td><td>{date(row.last_sign_in_at)}</td><td><span className={styles.planBadge}>{row.plan_id.toUpperCase()}</span></td><td>{number(row.total_paid_rub).toLocaleString(locale)} ₽</td><td>{hours(row.usage_seconds)}</td><td>{row.session_count}</td>
                <td><button type="button" aria-label={`${copy.admin}: ${row.email}`} aria-pressed={row.is_admin} disabled={mutating === row.user_id || row.user_id === user?.id} onClick={() => void toggleAdmin(row)} className={`${styles.toggle} ${row.is_admin ? styles.toggleOn : ""}`} /></td>
              </tr>)}</tbody></table></div>
            ) : <div className={styles.empty}>{copy.noRows}</div>}
          </>
        ) : null}

        {!loading && !error && view === "costs" ? (
          <>
            <div className={styles.costHeadline}>
              <div><span>{copy.costTitle}</span><strong>${totalEstimated.toFixed(2)}</strong></div>
              <p>{copy.recorded}: ${totalRecorded.toFixed(2)} · {copy.recordedRub}: {totalRecordedRub.toLocaleString(locale)} ₽<br />{copy.costNote}</p>
            </div>
            <div className={styles.filters}><input className={styles.input} value={search} onChange={(event) => setSearch(event.target.value)} placeholder={copy.search} /></div>
            {costs.length ? (
              <div className={styles.tableWrap}><table className={styles.table}><thead><tr><th>Email</th><th>{copy.plan}</th><th>{copy.usage}</th><th>{copy.sessions}</th><th>{copy.estimate}</th><th>{copy.recorded}</th><th>{copy.recordedRub}</th></tr></thead>
              <tbody>{costs.map((row) => <tr key={row.user_id}><td className={styles.email}>{row.email ?? "—"}</td><td><span className={styles.planBadge}>{row.plan_id.toUpperCase()}</span></td><td>{hours(row.usage_seconds)}</td><td>{row.session_count}</td><td>${number(row.estimated_cost_usd).toFixed(4)}</td><td>${number(row.recorded_cost_usd).toFixed(4)}</td><td>{number(row.recorded_cost_rub).toLocaleString(locale)} ₽</td></tr>)}</tbody></table></div>
            ) : <div className={styles.empty}>{copy.noRows}</div>}
          </>
        ) : null}
      </div>
    </section>
  );
}

function RankList({ rows }: { rows: RankedItem[] }) {
  return rows?.length ? <div className={styles.rankList}>{rows.map((row, index) => <div className={styles.rankRow} key={`${row.name}-${index}`}><span className={styles.rankIndex}>{String(index + 1).padStart(2, "0")}</span><span className={styles.rankName}>{row.name}</span><span className={styles.rankCount}>{row.count}</span></div>)}</div> : <div className={styles.notice}>—</div>;
}
