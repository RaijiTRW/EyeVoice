"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import EyeMark from "./EyeMark";
import UsageChart from "./UsageChart";
import { supabase } from "@/lib/supabase";
import { useUser } from "@/lib/useUser";
import { useLang } from "@/lib/i18n";
import type { PlanId } from "@/lib/plans";

type Section = "plan" | "stats" | "history";

const ease = [0.16, 1, 0.3, 1] as const;

/** Odometer: on change each character rolls in from above/below, alternating. */
function Odometer({ value, className }: { value: string; className?: string }) {
  return (
    <span className={`flex ${className ?? ""}`} aria-label={value}>
      {value.split("").map((ch, i) => (
        <span
          key={i}
          className="relative inline-flex h-[1.18em] items-baseline overflow-hidden"
        >
          <motion.span
            key={ch}
            initial={{ y: i % 2 === 0 ? "95%" : "-95%", opacity: 0 }}
            animate={{ y: "0%", opacity: 1 }}
            transition={{ duration: 0.34, delay: i * 0.03, ease }}
            className="inline-block whitespace-pre"
          >
            {ch}
          </motion.span>
        </span>
      ))}
    </span>
  );
}

export default function ProfileView() {
  const router = useRouter();
  const { user, loading } = useUser();
  const { t, lang } = useLang();
  const [section, setSection] = useState<Section>("plan");
  const [plan, setPlan] = useState<PlanId>("free"); // saved plan
  const [viewPlan, setViewPlan] = useState<PlanId>("free"); // tab being viewed
  const [saving, setSaving] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const plans = t.plans;

  useEffect(() => {
    if (!loading && !user) router.replace("/login");
    const saved = user?.user_metadata?.plan as PlanId | undefined;
    if (saved && plans.some((p) => p.id === saved)) {
      setPlan(saved);
      setViewPlan(saved);
    }
  }, [user, loading, router, plans]);

  if (loading || !user) {
    return (
      <div className="flex flex-1 items-center justify-center py-40 text-[12px] uppercase tracking-widest text-faint">
        • • •
      </div>
    );
  }

  const createdAt = user.created_at
    ? new Date(user.created_at).toLocaleDateString(
        lang === "ru" ? "ru-RU" : "en-US",
        { day: "numeric", month: "long", year: "numeric" },
      )
    : "—";
  const currentPlan = plans.find((p) => p.id === plan)!;
  const viewing = plans.find((p) => p.id === viewPlan)!;

  async function choosePlan(id: PlanId) {
    setSaving(true);
    const { error } = await supabase.auth.updateUser({ data: { plan: id } });
    setSaving(false);
    if (!error) setPlan(id);
  }

  async function signOut() {
    setSigningOut(true);
    await supabase.auth.signOut();
    router.push("/");
  }

  const sections: Array<[Section, string]> = [
    ["plan", t.profile.tabPlan],
    ["stats", t.profile.tabStats],
    ["history", t.profile.tabHistory],
  ];

  const statTile = (label: string, value: string, sub?: string) => (
    <div className="rounded-2xl border border-line bg-panel/60 p-6">
      <div className="text-2xl font-bold tracking-tight">{value}</div>
      <div className="mt-2 text-[10px] uppercase tracking-[0.2em] text-faint">
        {label}
      </div>
      {sub && <div className="mt-0.5 text-[11px] text-faint">{sub}</div>}
    </div>
  );

  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease }}
      className="mx-auto w-full max-w-3xl px-6 py-16"
    >
      {/* account */}
      <div className="mb-6 flex flex-col items-start justify-between gap-4 rounded-2xl border border-line bg-panel/60 p-7 md:flex-row md:items-center">
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-line text-accent">
            <EyeMark size={26} />
          </div>
          <div>
            <div className="text-sm font-bold tracking-wide">{user.email}</div>
            <div className="mt-1 text-[11px] uppercase tracking-widest text-faint">
              {t.profile.accountCreated} {createdAt}
            </div>
          </div>
        </div>
        <button
          onClick={signOut}
          disabled={signingOut}
          className="btn !px-4 !py-2 !text-[11px] disabled:opacity-50"
        >
          {signingOut ? "• • •" : t.profile.signOut}
        </button>
      </div>

      {/* section tabs */}
      <div className="mb-6 flex gap-1 rounded-xl border border-line bg-panel/40 p-1">
        {sections.map(([id, label]) => {
          const active = section === id;
          return (
            <button
              key={id}
              onClick={() => setSection(id)}
              className="relative flex-1 rounded-lg py-2.5 text-[11px] font-bold uppercase tracking-widest"
            >
              {active && (
                <motion.span
                  layoutId="sectionTab"
                  className="absolute inset-0 rounded-lg bg-ink"
                  transition={{ type: "spring", stiffness: 420, damping: 34 }}
                />
              )}
              <span
                className={`relative z-10 transition-colors ${
                  active ? "text-bg" : "text-dim"
                }`}
              >
                {label}
              </span>
            </button>
          );
        })}
      </div>

      {/* section content */}
      <motion.div
        key={`${section}-${lang}`}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.32, ease }}
      >
        {section === "plan" && (
          <div className="rounded-2xl border border-line bg-panel/60 p-7">
            {/* plan tabs */}
            <div className="flex gap-1 rounded-xl border border-line bg-bg/60 p-1">
              {plans.map((p) => {
                const active = viewPlan === p.id;
                return (
                  <button
                    key={p.id}
                    onClick={() => setViewPlan(p.id)}
                    className="relative flex-1 rounded-lg py-2.5 text-[11px] font-bold uppercase tracking-widest"
                  >
                    {active && (
                      <motion.span
                        layoutId="planTab"
                        className="absolute inset-0 rounded-lg bg-ink"
                        transition={{
                          type: "spring",
                          stiffness: 420,
                          damping: 34,
                        }}
                      />
                    )}
                    <span
                      className={`relative z-10 flex items-center justify-center gap-1.5 transition-colors ${
                        active ? "text-bg" : "text-dim"
                      }`}
                    >
                      {p.name}
                      {plan === p.id && (
                        <span
                          className={active ? "text-accent" : "text-accent/70"}
                        >
                          •
                        </span>
                      )}
                    </span>
                  </button>
                );
              })}
            </div>

            {/* price odometer + hours */}
            <div className="mt-7 flex items-end justify-between gap-4">
              <div>
                <Odometer
                  value={viewing.price}
                  className="text-3xl font-bold tracking-tight md:text-4xl"
                />
                <motion.div
                  key={`hours-${viewPlan}-${lang}`}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.28, ease }}
                  className="mt-2 text-[11px] uppercase tracking-[0.2em] text-faint"
                >
                  {viewing.hours}
                </motion.div>
              </div>
              {plan === viewPlan && (
                <motion.span
                  key={`current-${viewPlan}`}
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ duration: 0.25, ease }}
                  className="pb-1 text-[10px] uppercase tracking-widest text-accent"
                >
                  {t.profile.current}
                </motion.span>
              )}
            </div>

            {/* features rebuild per plan */}
            <ul
              key={`features-${viewPlan}-${lang}`}
              className="mt-6 flex flex-col gap-2 border-t border-line/60 pt-5 text-[13px] text-dim"
            >
              {viewing.features.map((f, i) => (
                <motion.li
                  key={f}
                  initial={{ opacity: 0, x: -12 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.05 * i, ease }}
                >
                  <span className="text-faint">· </span>
                  {f}
                </motion.li>
              ))}
            </ul>

            <button
              onClick={() => choosePlan(viewPlan)}
              disabled={plan === viewPlan || saving}
              className={`btn mt-6 w-full !py-2.5 !text-[11px] ${
                plan === viewPlan ? "opacity-40" : "btn-primary btn-accent"
              } disabled:pointer-events-none`}
            >
              {saving
                ? "• • •"
                : plan === viewPlan
                  ? t.profile.chosen
                  : t.profile.choose}
            </button>
            <p className="mt-3 text-[11px] leading-relaxed text-faint">
              {t.profile.planNote}
            </p>
          </div>
        )}

        {section === "stats" && (
          <div className="flex flex-col gap-4">
            <div className="grid gap-4 md:grid-cols-3">
              {statTile(
                t.profile.hoursThisMonth,
                `0.0 ${t.profile.hoursUnit}`,
                `${t.profile.ofLimit} ${currentPlan.hours}`,
              )}
              {statTile(t.profile.totalTranslated, `0.0 ${t.profile.hoursUnit}`)}
              {statTile(t.profile.sessions, "0")}
            </div>
            <UsageChart />
          </div>
        )}

        {section === "history" && (
          <div className="rounded-2xl border border-line bg-panel/60 p-7">
            <div className="flex items-center justify-between border-b border-line/60 pb-4 text-[13px]">
              <span className="text-dim">{t.profile.paymentMethod}</span>
              <span className="text-faint">{t.profile.notConnected}</span>
            </div>
            <div className="mt-4 rounded-xl border border-dashed border-line/80 px-6 py-8 text-center text-[12px] leading-relaxed text-faint">
              {t.profile.noPayments}
            </div>
          </div>
        )}
      </motion.div>
    </motion.div>
  );
}
