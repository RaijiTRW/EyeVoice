"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import EyeMark from "./EyeMark";
import UsageChart, { type UsageSession } from "./UsageChart";
import { supabase } from "@/lib/supabase";
import { useUser } from "@/lib/useUser";
import { useLang } from "@/lib/i18n";
import type { PlanId } from "@/lib/plans";
import { useProfileSection } from "@/lib/profile-section";

const ease = [0.16, 1, 0.3, 1] as const;

type PaymentRow = {
  id: string;
  plan_id: "start" | "pro";
  amount: number;
  currency: string;
  status: "pending" | "waiting_for_capture" | "succeeded" | "canceled";
  payment_method: string | null;
  paid_at: string | null;
  created_at: string;
};

type SubscriptionRow = {
  plan_id: "start" | "pro";
  status: "active" | "expired" | "canceled";
  current_period_end: string;
};

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
  const { section } = useProfileSection();
  const [plan, setPlan] = useState<PlanId>("free"); // saved plan
  const [viewPlan, setViewPlan] = useState<PlanId>("free"); // tab being viewed
  const [saving, setSaving] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [usageSessions, setUsageSessions] = useState<UsageSession[]>([]);
  const [usageLoading, setUsageLoading] = useState(true);
  const [usageFailed, setUsageFailed] = useState(false);
  const [payments, setPayments] = useState<PaymentRow[]>([]);
  const [paymentError, setPaymentError] = useState<string | null>(null);
  const [checkingPayment, setCheckingPayment] = useState(false);

  const plans = t.plans;

  useEffect(() => {
    if (loading || user) return;

    const params = new URLSearchParams(window.location.search);
    const requestedPlan = params.get("plan");
    const cameFromApp = params.get("from") === "app";
    if (cameFromApp && (requestedPlan === "start" || requestedPlan === "pro")) {
      router.replace(`/signup?from=app&plan=${requestedPlan}`);
      return;
    }
    router.replace("/login");
  }, [user, loading, router, plans]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const returnedFromPayment = new URLSearchParams(window.location.search).get("payment") === "return";

    async function loadBilling(attempt = 0) {
      const pendingPaymentId = returnedFromPayment
        ? window.localStorage.getItem("eyevoice_pending_payment")
        : null;
      if (pendingPaymentId) {
        const { data } = await supabase.functions.invoke("confirm-payment", {
          body: { payment_id: pendingPaymentId },
        });
        if (data?.status === "succeeded" || data?.status === "canceled") {
          window.localStorage.removeItem("eyevoice_pending_payment");
        }
      }

      const [{ data: subscription }, { data: paymentRows }] = await Promise.all([
        supabase
          .from("subscriptions")
          .select("plan_id,status,current_period_end")
          .eq("user_id", user!.id)
          .maybeSingle<SubscriptionRow>(),
        supabase
          .from("payments")
          .select("id,plan_id,amount,currency,status,payment_method,paid_at,created_at")
          .eq("user_id", user!.id)
          .order("created_at", { ascending: false })
          .limit(20),
      ]);
      if (cancelled) return;

      const active = subscription?.status === "active" &&
        new Date(subscription.current_period_end) > new Date();
      const nextPlan: PlanId = active ? subscription.plan_id : "free";
      const requestedPlan = new URLSearchParams(window.location.search).get("plan");
      const requestedPaidPlan: PlanId | null =
        requestedPlan === "start" || requestedPlan === "pro" ? requestedPlan : null;
      setPlan(nextPlan);
      setPayments((paymentRows ?? []) as PaymentRow[]);
      if (attempt === 0) setViewPlan(requestedPaidPlan ?? nextPlan);
      else if (active) setViewPlan(nextPlan);

      if (returnedFromPayment && !active && attempt < 12) {
        setCheckingPayment(true);
        timer = setTimeout(() => void loadBilling(attempt + 1), 2000);
      } else {
        setCheckingPayment(false);
        if (returnedFromPayment) {
          const cleanUrl = `${window.location.pathname}${window.location.hash}`;
          window.history.replaceState({}, "", cleanUrl);
        }
      }
    }

    void loadBilling();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [user]);

  useEffect(() => {
    let cancelled = false;

    if (!user) {
      return;
    }
    supabase
      .from("translation_sessions")
      .select("id,started_at,ended_at,duration_seconds")
      .order("ended_at", { ascending: true })
      .then(({ data, error }) => {
        if (cancelled) return;
        setUsageLoading(false);
        if (error) {
          setUsageSessions([]);
          setUsageFailed(true);
          return;
        }
        setUsageSessions(
          (data ?? []).map((session) => ({
            ...session,
            duration_seconds: Number(session.duration_seconds) || 0,
          })),
        );
      });

    return () => {
      cancelled = true;
    };
  }, [user]);

  const usageTotals = useMemo(() => {
    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    return usageSessions.reduce(
      (totals, session) => {
        const seconds = Math.max(0, Number(session.duration_seconds) || 0);
        totals.all += seconds;
        if (new Date(session.ended_at) >= monthStart) totals.month += seconds;
        return totals;
      },
      { all: 0, month: 0 },
    );
  }, [usageSessions]);

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
    if (id === "free" || id === plan) return;
    setSaving(true);
    setPaymentError(null);
    const { data, error } = await supabase.functions.invoke("create-payment", {
      body: { plan_id: id },
    });
    setSaving(false);
    if (error || typeof data?.confirmation_url !== "string") {
      setPaymentError(t.profile.paymentError);
      return;
    }
    if (typeof data.payment_id === "string") {
      window.localStorage.setItem("eyevoice_pending_payment", data.payment_id);
    }
    window.location.assign(data.confirmation_url);
  }

  async function signOut() {
    setSigningOut(true);
    await supabase.auth.signOut();
    router.push("/");
  }

  const statTile = (label: string, value: string, sub?: string) => (
    <div className="min-w-0 rounded-xl border border-line bg-panel/60 p-3 md:p-4">
      <div className="truncate text-lg font-bold tracking-tight md:text-xl">{value}</div>
      <div className="mt-1 text-[7px] uppercase leading-tight tracking-[0.12em] text-faint md:text-[9px]">
        {label}
      </div>
      {sub && <div className="mt-0.5 truncate text-[8px] text-faint md:text-[10px]">{sub}</div>}
    </div>
  );

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.6, ease }}
      className={`mx-auto flex w-full max-w-3xl flex-1 flex-col px-4 pb-[5.9rem] pt-1 md:min-h-0 md:px-6 md:py-5 ${
        section === "stats" ? "min-h-dvh" : ""
      }`}
    >
      <div className="flex flex-1 flex-col rounded-xl border border-line bg-panel/60 md:min-h-0 md:overflow-hidden">
        {/* account */}
        <div className="flex items-center justify-between gap-2 border-b border-line/60 p-3 md:p-4">
          <div className="flex min-w-0 items-center gap-3">
            <div className="flex h-10 w-10 flex-none items-center justify-center rounded-lg border border-line text-accent">
              <EyeMark size={22} />
            </div>
            <div className="min-w-0">
              <div className="truncate text-[11px] font-bold tracking-wide md:text-sm">{user.email}</div>
              <div className="mt-0.5 truncate text-[8px] uppercase tracking-widest text-faint md:text-[10px]">
                {t.profile.accountCreated} {createdAt}
              </div>
            </div>
          </div>
          <button
            onClick={signOut}
            disabled={signingOut}
            className="btn flex-none !px-3 !py-1.5 !text-[9px] disabled:opacity-50 md:!text-[10px]"
          >
            {signingOut ? "• • •" : t.profile.signOut}
          </button>
        </div>

        {/* section content */}
        <motion.div
          key={`${section}-${lang}`}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.32, ease }}
          className="flex-1 p-4 md:min-h-0 md:p-5"
        >
          {section === "plan" && (
            <div className="h-full">
            {/* plan tabs */}
            <div className="flex gap-1 rounded-xl border border-line bg-bg/60 p-1">
              {plans.map((p) => {
                const active = viewPlan === p.id;
                return (
                  <button
                    key={p.id}
                    onClick={() => setViewPlan(p.id)}
                    className="relative flex-1 rounded-lg py-2 text-[9px] font-bold uppercase tracking-widest md:text-[10px]"
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
            <div className="mt-4 flex items-end justify-between gap-4">
              <div>
                <Odometer
                  value={viewing.price}
                  className="text-2xl font-bold tracking-tight md:text-3xl"
                />
                <motion.div
                  key={`hours-${viewPlan}-${lang}`}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.28, ease }}
                  className="mt-1 text-[9px] uppercase tracking-[0.18em] text-faint md:text-[10px]"
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
                  className="pb-1 text-[8px] uppercase tracking-widest text-accent md:text-[9px]"
                >
                  {t.profile.current}
                </motion.span>
              )}
            </div>

            {/* features rebuild per plan */}
            <ul
              key={`features-${viewPlan}-${lang}`}
              className="mt-4 flex flex-col gap-1 border-t border-line/60 pt-3 text-[11px] leading-relaxed text-dim md:text-[12px]"
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
              disabled={viewPlan === "free" || plan === viewPlan || saving || checkingPayment}
              className={`btn mt-4 w-full !py-2 !text-[9px] md:!text-[10px] ${
                viewPlan === "free" || plan === viewPlan ? "opacity-40" : "btn-primary btn-accent"
              } disabled:pointer-events-none`}
            >
              {checkingPayment
                ? t.profile.paymentChecking
                : saving
                  ? t.profile.paymentStarting
                  : viewPlan === "free" && plan !== "free"
                    ? t.profile.freeIncluded
                : plan === viewPlan
                  ? t.profile.chosen
                  : t.profile.choose}
            </button>
            {paymentError && (
              <p className="mt-2 text-[9px] leading-relaxed text-accent md:text-[10px]">
                {paymentError}
              </p>
            )}
            <p className="mt-2 text-[9px] leading-relaxed text-faint md:text-[10px]">
              {t.profile.planNote}
            </p>
            </div>
          )}

          {section === "stats" && (
            <div className="flex h-full min-h-0 flex-col gap-3">
            <div className="grid grid-cols-3 gap-2 md:gap-3">
              {statTile(
                t.profile.hoursThisMonth,
                `${(usageTotals.month / 3600).toFixed(1)} ${t.profile.hoursUnit}`,
                `${t.profile.ofLimit} ${currentPlan.hours}`,
              )}
              {statTile(
                t.profile.totalTranslated,
                `${(usageTotals.all / 3600).toFixed(1)} ${t.profile.hoursUnit}`,
              )}
              {statTile(t.profile.sessions, String(usageSessions.length))}
            </div>
            <UsageChart
              sessions={usageSessions}
              loading={usageLoading}
              failed={usageFailed}
            />
            </div>
          )}

          {section === "history" && (
            <div className="h-full">
              <div className="flex items-center justify-between border-b border-line/60 pb-3 text-[11px] md:text-[12px]">
                <span className="text-dim">{t.profile.paymentMethod}</span>
                <span className="text-faint">{t.profile.notConnected}</span>
              </div>
              {payments.length === 0 ? (
                <div className="mt-3 rounded-lg border border-dashed border-line/80 px-4 py-6 text-center text-[10px] leading-relaxed text-faint md:text-[11px]">
                  {t.profile.noPayments}
                </div>
              ) : (
                <div className="mt-2 divide-y divide-line/60">
                  {payments.map((payment) => {
                    const status = payment.status === "succeeded"
                      ? t.profile.paymentSucceeded
                      : payment.status === "canceled"
                        ? t.profile.paymentCanceled
                        : t.profile.paymentPending;
                    const date = new Date(payment.paid_at ?? payment.created_at).toLocaleDateString(
                      lang === "ru" ? "ru-RU" : "en-US",
                      { day: "2-digit", month: "short", year: "numeric" },
                    );
                    return (
                      <div key={payment.id} className="flex items-center justify-between gap-4 py-3 text-[9px] md:text-[10px]">
                        <div className="min-w-0">
                          <div className="font-bold uppercase tracking-widest text-dim">
                            EyeVoice {payment.plan_id.toUpperCase()}
                          </div>
                          <div className="mt-1 text-faint">{date}</div>
                        </div>
                        <div className="text-right">
                          <div className="font-bold text-ink">
                            {Number(payment.amount).toLocaleString(lang === "ru" ? "ru-RU" : "en-US")} ₽
                          </div>
                          <div className={`mt-1 uppercase tracking-widest ${
                            payment.status === "succeeded" ? "text-accent" : "text-faint"
                          }`}>
                            {status}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </motion.div>
      </div>
    </motion.div>
  );
}
