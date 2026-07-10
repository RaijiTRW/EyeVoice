"use client";

import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { useLang } from "@/lib/i18n";

type Filter = "day" | "week" | "month" | "year" | "custom";

const ease = [0.16, 1, 0.3, 1] as const;
const DAY_MS = 86400000;

// deterministic demo data until the app reports real usage
function noise(n: number) {
  const h = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return h - Math.floor(h);
}

function dayIndex(d: Date) {
  return Math.floor(d.getTime() / DAY_MS);
}

function buildSeries(filter: Filter, locale: string, fromISO: string, toISO: string) {
  const values: number[] = [];
  const labels: string[] = []; // sparse, under the bars
  const full: string[] = []; // for the hover readout
  const now = new Date();

  const dayLabel = (d: Date) =>
    d.toLocaleDateString(locale, { day: "numeric", month: "short" });

  if (filter === "day") {
    const seed = dayIndex(now) * 31;
    for (let h = 0; h < 24; h++) {
      const base = h >= 18 || h <= 1 ? 0.3 : h >= 9 ? 0.16 : 0.03;
      values.push(base * (0.35 + noise(seed + h)));
      labels.push(h % 6 === 0 ? `${h}:00` : "");
      full.push(`${String(h).padStart(2, "0")}:00`);
    }
  } else if (filter === "week" || filter === "month") {
    const days = filter === "week" ? 7 : 30;
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(now.getTime() - i * DAY_MS);
      values.push(0.15 + noise(dayIndex(d)) * 1.6);
      labels.push(
        filter === "week"
          ? d.toLocaleDateString(locale, { weekday: "short" })
          : i % 6 === 0
            ? dayLabel(d)
            : "",
      );
      full.push(dayLabel(d));
    }
  } else if (filter === "year") {
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      values.push(3 + noise(d.getFullYear() * 12 + d.getMonth()) * 13);
      labels.push(d.toLocaleDateString(locale, { month: "short" }));
      full.push(d.toLocaleDateString(locale, { month: "long", year: "numeric" }));
    }
  } else {
    const from = new Date(fromISO);
    const to = new Date(toISO);
    const span = Math.max(
      1,
      Math.min(92, Math.round((to.getTime() - from.getTime()) / DAY_MS) + 1),
    );
    const step = Math.max(1, Math.ceil(span / 10));
    for (let i = 0; i < span; i++) {
      const d = new Date(from.getTime() + i * DAY_MS);
      values.push(0.15 + noise(dayIndex(d)) * 1.6);
      labels.push(i % step === 0 ? dayLabel(d) : "");
      full.push(dayLabel(d));
    }
  }

  return { values, labels, full };
}

export default function UsageChart() {
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
    () => buildSeries(filter, locale, from, to),
    [filter, locale, from, to],
  );
  const max = Math.max(...values, 0.1);
  const total = values.reduce((a, b) => a + b, 0);

  const filters: Array<[Filter, string]> = [
    ["day", c.day],
    ["week", c.week],
    ["month", c.month],
    ["year", c.year],
    ["custom", c.custom],
  ];

  return (
    <div className="rounded-2xl border border-line bg-panel/60 p-6">
      {/* header: title + hover readout / total */}
      <div className="mb-5 flex items-baseline justify-between gap-4">
        <h3 className="text-[11px] uppercase tracking-[0.2em] text-faint">
          {c.title}
        </h3>
        <div className="text-[12px] tabular-nums">
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

      {/* filters in one row */}
      <div className="mb-3 flex flex-wrap items-center gap-1.5">
        {filters.map(([id, label]) => (
          <button
            key={id}
            onClick={() => setFilter(id)}
            className={`rounded-lg border px-3 py-1.5 text-[10px] uppercase tracking-widest transition-colors ${
              filter === id
                ? "border-ink bg-ink text-bg"
                : "border-line text-dim hover:border-dim"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* custom range */}
      {filter === "custom" && (
        <motion.div
          initial={{ opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.25, ease }}
          className="mb-4 flex flex-wrap items-center gap-2 text-[11px] text-faint"
        >
          <span className="uppercase tracking-widest">{c.from}</span>
          <input
            type="date"
            value={from}
            max={to}
            onChange={(e) => setFrom(e.target.value)}
            className="input !w-auto !px-3 !py-1.5 !text-[12px]"
          />
          <span className="uppercase tracking-widest">{c.to}</span>
          <input
            type="date"
            value={to}
            min={from}
            onChange={(e) => setTo(e.target.value)}
            className="input !w-auto !px-3 !py-1.5 !text-[12px]"
          />
        </motion.div>
      )}

      {/* bars */}
      <div
        key={`${filter}-${lang}-${from}-${to}`}
        className="flex h-44 items-end gap-[2px] border-b border-line/60"
        onMouseLeave={() => setHover(null)}
      >
        {values.map((v, i) => (
          <div
            key={i}
            className="group relative flex h-full flex-1 items-end"
            onMouseEnter={() => setHover(i)}
          >
            <motion.div
              initial={{ height: 0 }}
              animate={{ height: `${Math.max(2, (v / max) * 100)}%` }}
              transition={{ duration: 0.5, delay: i * 0.012, ease }}
              className={`w-full rounded-t-[4px] transition-colors ${
                hover === i ? "bg-accent" : "bg-accent/55"
              }`}
            />
          </div>
        ))}
      </div>

      {/* sparse x labels */}
      <div className="mt-2 flex gap-[2px]">
        {labels.map((label, i) => (
          <div
            key={i}
            className="flex-1 overflow-visible whitespace-nowrap text-[9px] uppercase tracking-wide text-faint"
          >
            {label}
          </div>
        ))}
      </div>

      <p className="mt-4 text-[10px] leading-relaxed text-faint">
        <span className="text-accent">● </span>
        {c.demo}
      </p>
    </div>
  );
}
