"use client";

import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { useLang } from "@/lib/i18n";

export type UsageSession = {
  id: string;
  started_at: string;
  ended_at: string;
  duration_seconds: number;
};

type Filter = "day" | "week" | "month" | "year" | "custom";

const ease = [0.16, 1, 0.3, 1] as const;
const DAY_MS = 86_400_000;

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function durationHours(session: UsageSession) {
  return Math.max(0, Number(session.duration_seconds) || 0) / 3600;
}

function buildSeries(
  sessions: UsageSession[],
  filter: Filter,
  locale: string,
  fromISO: string,
  toISO: string,
) {
  const labels: string[] = [];
  const full: string[] = [];
  const now = new Date();
  const today = startOfDay(now);
  let values: number[] = [];

  const dayLabel = (date: Date) =>
    date.toLocaleDateString(locale, { day: "numeric", month: "short" });

  if (filter === "day") {
    values = Array.from({ length: 24 }, () => 0);
    for (let hour = 0; hour < 24; hour += 1) {
      labels.push(hour % 6 === 0 ? `${hour}:00` : "");
      full.push(`${String(hour).padStart(2, "0")}:00`);
    }
    sessions.forEach((session) => {
      const endedAt = new Date(session.ended_at);
      if (endedAt >= today && endedAt <= now) {
        values[endedAt.getHours()] += durationHours(session);
      }
    });
  } else if (filter === "week" || filter === "month") {
    const days = filter === "week" ? 7 : 30;
    const start = new Date(today.getTime() - (days - 1) * DAY_MS);
    values = Array.from({ length: days }, () => 0);

    for (let index = 0; index < days; index += 1) {
      const date = new Date(start.getTime() + index * DAY_MS);
      labels.push(
        filter === "week"
          ? date.toLocaleDateString(locale, { weekday: "short" })
          : index % 6 === 0
            ? dayLabel(date)
            : "",
      );
      full.push(dayLabel(date));
    }

    sessions.forEach((session) => {
      const endedAt = new Date(session.ended_at);
      const index = Math.floor((startOfDay(endedAt).getTime() - start.getTime()) / DAY_MS);
      if (index >= 0 && index < days) values[index] += durationHours(session);
    });
  } else if (filter === "year") {
    const months = Array.from({ length: 12 }, (_, index) =>
      new Date(now.getFullYear(), now.getMonth() - 11 + index, 1),
    );
    values = Array.from({ length: 12 }, () => 0);
    months.forEach((date) => {
      labels.push(date.toLocaleDateString(locale, { month: "short" }));
      full.push(date.toLocaleDateString(locale, { month: "long", year: "numeric" }));
    });
    sessions.forEach((session) => {
      const endedAt = new Date(session.ended_at);
      const index = months.findIndex(
        (month) =>
          month.getFullYear() === endedAt.getFullYear() &&
          month.getMonth() === endedAt.getMonth(),
      );
      if (index >= 0) values[index] += durationHours(session);
    });
  } else {
    const from = startOfDay(new Date(`${fromISO}T00:00:00`));
    const requestedTo = startOfDay(new Date(`${toISO}T00:00:00`));
    const span = Math.max(
      1,
      Math.min(92, Math.round((requestedTo.getTime() - from.getTime()) / DAY_MS) + 1),
    );
    const end = new Date(from.getTime() + (span - 1) * DAY_MS);
    const labelStep = Math.max(1, Math.ceil(span / 10));
    values = Array.from({ length: span }, () => 0);

    for (let index = 0; index < span; index += 1) {
      const date = new Date(from.getTime() + index * DAY_MS);
      labels.push(index % labelStep === 0 ? dayLabel(date) : "");
      full.push(dayLabel(date));
    }

    sessions.forEach((session) => {
      const endedAt = startOfDay(new Date(session.ended_at));
      if (endedAt < from || endedAt > end) return;
      const index = Math.floor((endedAt.getTime() - from.getTime()) / DAY_MS);
      values[index] += durationHours(session);
    });
  }

  return { values, labels, full };
}

export default function UsageChart({
  sessions,
  loading,
  failed,
}: {
  sessions: UsageSession[];
  loading: boolean;
  failed: boolean;
}) {
  const { t, lang } = useLang();
  const c = t.profile.chart;
  const locale = lang === "ru" ? "ru-RU" : "en-US";

  const [filter, setFilter] = useState<Filter>("week");
  const [from, setFrom] = useState(
    () => new Date(Date.now() - 13 * DAY_MS).toISOString().slice(0, 10),
  );
  const [to, setTo] = useState(() => new Date().toISOString().slice(0, 10));
  const [hover, setHover] = useState<number | null>(null);

  const { values, labels, full } = useMemo(
    () => buildSeries(sessions, filter, locale, from, to),
    [sessions, filter, locale, from, to],
  );
  const max = Math.max(...values, 0.01);
  const total = values.reduce((sum, value) => sum + value, 0);

  const filters: Array<[Filter, string]> = [
    ["day", c.day],
    ["week", c.week],
    ["month", c.month],
    ["year", c.year],
    ["custom", c.custom],
  ];

  return (
    <div className="flex min-h-0 flex-1 flex-col rounded-xl border border-line bg-panel/60 p-4 md:p-5">
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <h3 className="text-[9px] uppercase tracking-[0.18em] text-faint md:text-[10px]">
          {c.title}
        </h3>
        <div className="text-[9px] tabular-nums md:text-[11px]">
          {hover !== null ? (
            <span>
              <span className="text-faint">{full[hover]} · </span>
              <span className="font-bold text-ink">
                {values[hover].toFixed(1)} {t.profile.hoursUnit}
              </span>
            </span>
          ) : (
            <span>
              <span className="text-faint">{c.total} · </span>
              <span className="font-bold text-ink">
                {total.toFixed(1)} {t.profile.hoursUnit}
              </span>
            </span>
          )}
        </div>
      </div>

      <div className="mb-2 flex flex-wrap items-center gap-1">
        {filters.map(([id, label]) => (
          <button
            key={id}
            onClick={() => setFilter(id)}
            className={`rounded-md border px-2 py-1 text-[8px] uppercase tracking-widest transition-colors md:px-2.5 md:text-[9px] ${
              filter === id
                ? "border-ink bg-ink text-bg"
                : "border-line text-dim hover:border-dim"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {filter === "custom" && (
        <motion.div
          initial={{ opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.25, ease }}
          className="mb-2 flex flex-wrap items-center gap-1.5 text-[8px] text-faint md:text-[9px]"
        >
          <span className="uppercase tracking-widest">{c.from}</span>
          <input
            type="date"
            value={from}
            max={to}
            onChange={(event) => setFrom(event.target.value)}
            className="input !w-auto !px-2 !py-1 !text-[9px] md:!text-[10px]"
          />
          <span className="uppercase tracking-widest">{c.to}</span>
          <input
            type="date"
            value={to}
            min={from}
            onChange={(event) => setTo(event.target.value)}
            className="input !w-auto !px-2 !py-1 !text-[9px] md:!text-[10px]"
          />
        </motion.div>
      )}

      {loading ? (
        <div className="h-28 animate-pulse rounded-lg border border-line/50 bg-ink/[0.03] md:h-36" />
      ) : (
        <div
          key={`${filter}-${lang}-${from}-${to}`}
          className="flex h-28 items-end gap-[2px] border-b border-line/60 md:h-36"
          onMouseLeave={() => setHover(null)}
        >
          {values.map((value, index) => (
            <div
              key={index}
              className="group relative flex h-full flex-1 items-end"
              onMouseEnter={() => setHover(index)}
            >
              <motion.div
                initial={{ height: 0 }}
                animate={{ height: value > 0 ? `${Math.max(2, (value / max) * 100)}%` : 0 }}
                transition={{ duration: 0.5, delay: index * 0.012, ease }}
                className={`w-full rounded-t-[4px] transition-colors ${
                  hover === index ? "bg-accent" : "bg-accent/55"
                }`}
              />
            </div>
          ))}
        </div>
      )}

      {!loading && (
        <div className="mt-2 flex gap-[2px]">
          {labels.map((label, index) => (
            <div
              key={index}
              className="flex-1 overflow-visible whitespace-nowrap text-[7px] uppercase tracking-wide text-faint md:text-[8px]"
            >
              {label}
            </div>
          ))}
        </div>
      )}

      <p className="mt-2 text-[8px] leading-relaxed text-faint md:text-[9px]">
        <span className="text-accent">● </span>
        {loading ? c.loading : failed ? c.unavailable : sessions.length === 0 ? c.empty : c.live}
      </p>
    </div>
  );
}
