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
import BillingModal, { type BillingModalTone } from "./BillingModal";
import AdminDashboard from "./AdminDashboard";
import AdminSupportPlaceholder from "./AdminSupportPlaceholder";
import { useAdminAccess } from "@/lib/admin-access";

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
  product_type: "plan" | "extra_hours";
  quantity_hours: number | null;
};

type SubscriptionRow = {
  plan_id: "start" | "pro";
  status: "active" | "expired" | "canceled";
  current_period_start: string;
  current_period_end: string;
  auto_renew: boolean;
  provider_payment_method_id: string | null;
  payment_method_title: string | null;
  card_last4: string | null;
  pending_plan_id: "free" | "start" | "pro" | null;
  cancel_at_period_end: boolean;
  renewal_error: string | null;
};

type UsageBalance = {
  plan_id: PlanId;
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

type ModalState = {
  tone: BillingModalTone;
  eyebrow: string;
  title: string;
  description: string;
  detail?: string | null;
  primaryLabel?: string;
  secondaryLabel?: string;
  primaryAction?: "checkout" | "cancel" | "downgrade" | "unlink" | "retry" | "close";
  dismissible?: boolean;
};

async function edgeErrorMessage(error: unknown, fallback: string) {
  if (!error || typeof error !== "object") return fallback;
  const context = "context" in error ? (error as { context?: unknown }).context : null;
  if (context instanceof Response) {
    try {
      const payload = await context.clone().json();
      if (typeof payload?.error === "string") return payload.error;
    } catch {
      // The fallback below is clearer than a response parsing failure.
    }
  }
  const message = "message" in error ? (error as { message?: unknown }).message : null;
  return typeof message === "string" && message ? message : fallback;
}

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
  const { section, setSection } = useProfileSection();
  const { isAdmin, loading: adminLoading } = useAdminAccess();
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
  const [usageBalance, setUsageBalance] = useState<UsageBalance | null>(null);
  const [usageBalanceError, setUsageBalanceError] = useState(false);
  const [extraHourCount, setExtraHourCount] = useState(1);
  const [buyingHours, setBuyingHours] = useState(false);
  const [balanceRefreshKey, setBalanceRefreshKey] = useState(0);
  const [billingRefreshKey, setBillingRefreshKey] = useState(0);
  const [subscription, setSubscription] = useState<SubscriptionRow | null>(null);
  const [modal, setModal] = useState<ModalState | null>(null);
  const [pendingCheckoutPlan, setPendingCheckoutPlan] = useState<PlanId | null>(null);
  const [billingAction, setBillingAction] = useState<"cancel" | "downgrade" | "unlink" | "card" | null>(null);

  const plans = t.plans;

  useEffect(() => {
    if (loading || user) return;

    const params = new URLSearchParams(window.location.search);
    const requestedPlan = params.get("plan");
    const requestedSection = params.get("section");
    const cameFromApp = params.get("from") === "app";
    if (cameFromApp && (requestedPlan === "start" || requestedPlan === "pro")) {
      router.replace(`/signup?from=app&plan=${requestedPlan}`);
      return;
    }
    if (cameFromApp && requestedSection === "limits") {
      router.replace("/signup?from=app&section=limits");
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
      let paymentPending = false;
      if (pendingPaymentId) {
        if (attempt === 0) {
          setModal({
            tone: "progress",
            eyebrow: t.profile.billingPaymentEyebrow,
            title: t.profile.paymentPendingTitle,
            description: t.profile.paymentPendingDescription,
            dismissible: false,
          });
        }
        const { data, error } = await supabase.functions.invoke("confirm-payment", {
          body: { payment_id: pendingPaymentId },
        });
        if (error) {
          paymentPending = attempt < 11;
          if (!paymentPending) {
            setModal({
              tone: "error",
              eyebrow: t.profile.billingPaymentEyebrow,
              title: t.profile.paymentFailedTitle,
              description: t.profile.paymentFailedDescription,
              detail: await edgeErrorMessage(error, t.profile.paymentError),
              primaryLabel: t.profile.tryAgain,
              secondaryLabel: t.profile.back,
              primaryAction: "retry",
            });
          }
        } else if (data?.status === "succeeded") {
          window.localStorage.removeItem("eyevoice_pending_payment");
          setModal({
            tone: "success",
            eyebrow: t.profile.billingPaymentEyebrow,
            title: t.profile.paymentSuccessTitle,
            description: t.profile.paymentSuccessDescription,
            primaryLabel: t.profile.done,
            primaryAction: "close",
          });
        } else if (data?.status === "canceled") {
          window.localStorage.removeItem("eyevoice_pending_payment");
          setModal({
            tone: "error",
            eyebrow: t.profile.billingPaymentEyebrow,
            title: t.profile.paymentFailedTitle,
            description: t.profile.paymentFailedDescription,
            detail: typeof data?.cancellation_reason === "string" ? data.cancellation_reason : null,
            primaryLabel: t.profile.tryAgain,
            secondaryLabel: t.profile.back,
            primaryAction: "retry",
          });
        } else {
          paymentPending = true;
        }
      } else if (returnedFromPayment && attempt === 0) {
        setModal({
          tone: "error",
          eyebrow: t.profile.billingPaymentEyebrow,
          title: t.profile.paymentFailedTitle,
          description: t.profile.paymentFailedDescription,
          detail: t.profile.paymentError,
          primaryLabel: t.profile.done,
          primaryAction: "close",
        });
      }

      const [{ data: subscription }, { data: paymentRows }] = await Promise.all([
        supabase
          .from("subscriptions")
          .select("plan_id,status,current_period_start,current_period_end,auto_renew,provider_payment_method_id,payment_method_title,card_last4,pending_plan_id,cancel_at_period_end,renewal_error")
          .eq("user_id", user!.id)
          .maybeSingle<SubscriptionRow>(),
        supabase
          .from("payments")
          .select("id,plan_id,amount,currency,status,payment_method,paid_at,created_at,product_type,quantity_hours")
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
      setSubscription(active ? subscription : null);
      setPayments((paymentRows ?? []) as PaymentRow[]);
      if (attempt === 0) setViewPlan(requestedPaidPlan ?? nextPlan);
      else if (active) setViewPlan(nextPlan);

      if (returnedFromPayment && paymentPending && attempt < 12) {
        setCheckingPayment(true);
        timer = setTimeout(() => void loadBilling(attempt + 1), 2000);
      } else {
        setCheckingPayment(false);
        if (returnedFromPayment) {
          setBalanceRefreshKey((value) => value + 1);
          const requestedSection = new URLSearchParams(window.location.search).get("section");
          const cleanUrl = `${window.location.pathname}${requestedSection ? `?section=${requestedSection}` : ""}${window.location.hash}`;
          window.history.replaceState({}, "", cleanUrl);
        }
      }
    }

    void loadBilling();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [user, billingRefreshKey, t.profile]);

  useEffect(() => {
    if (!user) return;
    const returnedFromCard = new URLSearchParams(window.location.search).get("billing") === "card-return";
    if (!returnedFromCard) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const confirmBinding = async (attempt = 0) => {
      const paymentMethodId = window.localStorage.getItem("eyevoice_pending_payment_method");
      if (!paymentMethodId) {
        setModal({
          tone: "error",
          eyebrow: t.profile.billingSettings,
          title: t.profile.cardFailedTitle,
          description: t.profile.cardFailedDescription,
          primaryLabel: t.profile.done,
          primaryAction: "close",
        });
        return;
      }
      if (attempt === 0) {
        setModal({
          tone: "progress",
          eyebrow: t.profile.billingSettings,
          title: t.profile.cardBindingTitle,
          description: t.profile.cardBindingDescription,
          dismissible: false,
        });
      }
      const { data, error } = await supabase.functions.invoke("manage-subscription", {
        body: { action: "confirm_card_binding", payment_method_id: paymentMethodId },
      });
      if (cancelled) return;
      if (!error && data?.status === "active") {
        window.localStorage.removeItem("eyevoice_pending_payment_method");
        setModal({
          tone: "success",
          eyebrow: t.profile.billingSettings,
          title: t.profile.cardSuccessTitle,
          description: t.profile.cardSuccessDescription,
          primaryLabel: t.profile.done,
          primaryAction: "close",
        });
        setBillingRefreshKey((value) => value + 1);
        window.history.replaceState({}, "", window.location.pathname);
        return;
      }
      if (!error && data?.status === "pending" && attempt < 12) {
        timer = setTimeout(() => void confirmBinding(attempt + 1), 2000);
        return;
      }
      window.localStorage.removeItem("eyevoice_pending_payment_method");
      setModal({
        tone: "error",
        eyebrow: t.profile.billingSettings,
        title: t.profile.cardFailedTitle,
        description: t.profile.cardFailedDescription,
        detail: await edgeErrorMessage(error, typeof data?.error === "string" ? data.error : t.profile.paymentError),
        primaryLabel: t.profile.done,
        primaryAction: "close",
      });
      window.history.replaceState({}, "", window.location.pathname);
    };

    void confirmBinding();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [user, t.profile]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase.functions.invoke<UsageBalance>("usage-balance", { body: {} })
      .then(({ data, error }) => {
        if (cancelled) return;
        if (data) setUsageBalance(data);
        setUsageBalanceError(Boolean(error));
      })
      .catch(() => {
        if (!cancelled) setUsageBalanceError(true);
      });
    return () => {
      cancelled = true;
    };
  }, [user, balanceRefreshKey]);

  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get("section");
    if (requested === "limits") setSection("limits");
  }, [setSection]);

  useEffect(() => {
    if (!adminLoading && !isAdmin && (section === "admin" || section === "support")) {
      setSection("plan");
    }
  }, [adminLoading, isAdmin, section, setSection]);

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

  function choosePlan(id: PlanId) {
    if (id === plan && id !== "free") {
      if (subscription?.cancel_at_period_end) {
        void manageSubscription("resume_plan");
        return;
      }
      setModal({
        tone: "warning",
        eyebrow: t.profile.billingSettings,
        title: t.profile.cancelPlanTitle,
        description: t.profile.cancelPlanDescription,
        detail: subscription
          ? `${t.profile.scheduledFree} · ${new Date(subscription.current_period_end).toLocaleDateString(lang === "ru" ? "ru-RU" : "en-US")}`
          : null,
        primaryLabel: t.profile.confirmCancellation,
        secondaryLabel: t.profile.back,
        primaryAction: "cancel",
      });
      return;
    }
    if (plan === "pro" && id === "start") {
      setModal({
        tone: "warning",
        eyebrow: t.profile.billingSettings,
        title: t.profile.downgradeTitle,
        description: t.profile.downgradeDescription,
        detail: subscription
          ? `${t.profile.scheduledStart} · ${new Date(subscription.current_period_end).toLocaleDateString(lang === "ru" ? "ru-RU" : "en-US")}`
          : null,
        primaryLabel: t.profile.confirmDowngrade,
        secondaryLabel: t.profile.back,
        primaryAction: "downgrade",
      });
      return;
    }
    if (id === "free" || id === plan) return;
    setPendingCheckoutPlan(id);
    setModal({
      tone: "card",
      eyebrow: t.profile.billingPaymentEyebrow,
      title: t.profile.paymentConfirmTitle,
      description: t.profile.paymentConfirmDescription,
      detail: `${plans.find((item) => item.id === id)?.name ?? id.toUpperCase()} · ${plans.find((item) => item.id === id)?.price ?? ""}`,
      primaryLabel: t.profile.continuePayment,
      secondaryLabel: t.profile.back,
      primaryAction: "checkout",
    });
  }

  async function startPlanCheckout(id: PlanId) {
    setSaving(true);
    setPaymentError(null);
    setModal({
      tone: "progress",
      eyebrow: t.profile.billingPaymentEyebrow,
      title: t.profile.paymentPreparingTitle,
      description: t.profile.paymentPreparingDescription,
      dismissible: false,
    });
    const { data, error } = await supabase.functions.invoke("create-payment", {
      body: { plan_id: id },
    });
    setSaving(false);
    if (error || typeof data?.confirmation_url !== "string") {
      const detail = await edgeErrorMessage(error, typeof data?.error === "string" ? data.error : t.profile.paymentError);
      setPaymentError(detail);
      setModal({
        tone: "error",
        eyebrow: t.profile.billingPaymentEyebrow,
        title: t.profile.paymentFailedTitle,
        description: t.profile.paymentFailedDescription,
        detail,
        primaryLabel: t.profile.tryAgain,
        secondaryLabel: t.profile.back,
        primaryAction: "retry",
      });
      return;
    }
    if (typeof data.payment_id === "string") {
      window.localStorage.setItem("eyevoice_pending_payment", data.payment_id);
    }
    window.location.assign(data.confirmation_url);
  }

  async function manageSubscription(action: "cancel_plan" | "schedule_downgrade" | "resume_plan" | "unlink_card") {
    const visualAction = action === "cancel_plan"
      ? "cancel"
      : action === "schedule_downgrade"
        ? "downgrade"
        : action === "unlink_card"
          ? "unlink"
          : "card";
    setBillingAction(visualAction);
    const { data, error } = await supabase.functions.invoke("manage-subscription", {
      body: { action },
    });
    setBillingAction(null);
    if (error) {
      setModal({
        tone: "error",
        eyebrow: t.profile.billingSettings,
        title: t.profile.paymentFailedTitle,
        description: t.profile.paymentFailedDescription,
        detail: await edgeErrorMessage(error, t.profile.paymentError),
        primaryLabel: t.profile.done,
        primaryAction: "close",
      });
      return;
    }
    setSubscription((data?.subscription ?? null) as SubscriptionRow | null);
    setModal(null);
    setBillingRefreshKey((value) => value + 1);
  }

  async function startCardBinding() {
    setBillingAction("card");
    setModal({
      tone: "progress",
      eyebrow: t.profile.billingSettings,
      title: t.profile.cardBindingTitle,
      description: t.profile.cardBindingDescription,
      dismissible: false,
    });
    const { data, error } = await supabase.functions.invoke("manage-subscription", {
      body: { action: "create_card_binding" },
    });
    setBillingAction(null);
    if (error || typeof data?.confirmation_url !== "string" || typeof data?.payment_method_id !== "string") {
      setModal({
        tone: "error",
        eyebrow: t.profile.billingSettings,
        title: t.profile.cardFailedTitle,
        description: t.profile.cardFailedDescription,
        detail: await edgeErrorMessage(error, typeof data?.error === "string" ? data.error : t.profile.paymentError),
        primaryLabel: t.profile.done,
        primaryAction: "close",
      });
      return;
    }
    window.localStorage.setItem("eyevoice_pending_payment_method", data.payment_method_id);
    window.location.assign(data.confirmation_url);
  }

  async function buyExtraHours() {
    if (!usageBalance?.can_purchase_extra_hours) {
      setViewPlan("start");
      setSection("plan");
      return;
    }
    setBuyingHours(true);
    setPaymentError(null);
    setModal({
      tone: "progress",
      eyebrow: t.profile.billingPaymentEyebrow,
      title: t.profile.paymentPreparingTitle,
      description: t.profile.paymentPreparingDescription,
      dismissible: false,
    });
    const { data, error } = await supabase.functions.invoke("create-payment", {
      body: { product_type: "extra_hours", hours: extraHourCount },
    });
    setBuyingHours(false);
    if (error || typeof data?.confirmation_url !== "string") {
      const detail = await edgeErrorMessage(error, typeof data?.error === "string" ? data.error : t.profile.paymentError);
      setPaymentError(detail);
      setModal({
        tone: "error",
        eyebrow: t.profile.billingPaymentEyebrow,
        title: t.profile.paymentFailedTitle,
        description: t.profile.paymentFailedDescription,
        detail,
        primaryLabel: t.profile.tryAgain,
        secondaryLabel: t.profile.back,
        primaryAction: "retry",
      });
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
  const formatBalanceHours = (seconds: number) => {
    const safeSeconds = Math.max(0, seconds);
    if (safeSeconds < 3600) {
      if (safeSeconds > 0 && safeSeconds < 60) {
        return `<1 ${t.profile.minutesUnit}`;
      }
      const minutes = Math.round((safeSeconds / 60) * 10) / 10;
      const value = Number.isInteger(minutes) ? String(minutes) : minutes.toFixed(1);
      return `${value} ${t.profile.minutesUnit}`;
    }
    const hours = Math.round((safeSeconds / 3600) * 10) / 10;
    const value = Number.isInteger(hours) ? String(hours) : hours.toFixed(1);
    return `${value} ${t.profile.hoursUnit}`;
  };
  const usageProgress = usageBalance && usageBalance.total_seconds > 0
    ? Math.min(100, (usageBalance.used_seconds / usageBalance.total_seconds) * 100)
    : 0;
  const extraTotal = usageBalance?.extra_hour_price_rub
    ? usageBalance.extra_hour_price_rub * extraHourCount
    : 0;
  const periodEndLabel = subscription
    ? new Date(subscription.current_period_end).toLocaleDateString(
        lang === "ru" ? "ru-RU" : "en-US",
        { day: "numeric", month: "long", year: "numeric" },
      )
    : null;

  const closeModal = () => setModal(null);
  const handleModalPrimary = () => {
    const action = modal?.primaryAction;
    if (action === "checkout" && pendingCheckoutPlan) {
      void startPlanCheckout(pendingCheckoutPlan);
    } else if (action === "cancel") {
      void manageSubscription("cancel_plan");
    } else if (action === "downgrade") {
      void manageSubscription("schedule_downgrade");
    } else if (action === "unlink") {
      void manageSubscription("unlink_card");
    } else if (action === "retry") {
      setModal(null);
      if (section === "limits" && usageBalance?.can_purchase_extra_hours) {
        void buyExtraHours();
      } else if (pendingCheckoutPlan) {
        choosePlan(pendingCheckoutPlan);
      }
    } else {
      closeModal();
      setBillingRefreshKey((value) => value + 1);
      setBalanceRefreshKey((value) => value + 1);
    }
  };

  const planActionLabel = (() => {
    if (checkingPayment) return t.profile.paymentChecking;
    if (saving || billingAction) return t.profile.paymentStarting;
    if (viewPlan === plan && plan !== "free") {
      return subscription?.cancel_at_period_end ? t.profile.resumePlan : t.profile.cancelPlan;
    }
    if (plan === "pro" && viewPlan === "start") return t.profile.downgrade;
    if (viewPlan === "free") return plan === "free" ? t.profile.chosen : t.profile.freeIncluded;
    if (plan === viewPlan) return t.profile.chosen;
    return t.profile.choose;
  })();

  const planActionDisabled = checkingPayment || saving || Boolean(billingAction) ||
    viewPlan === "free";

  return (
    <>
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.6, ease }}
      className={`mx-auto flex w-full flex-1 flex-col px-4 pb-[5.9rem] pt-1 md:min-h-0 md:px-6 md:py-5 ${
        isAdmin && (section === "admin" || section === "support") ? "max-w-6xl" : "max-w-3xl"
      } ${
        section === "stats" || section === "admin" || section === "support" ? "min-h-dvh" : ""
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
              disabled={planActionDisabled}
              className={`btn mt-4 w-full !py-2 !text-[9px] md:!text-[10px] ${
                planActionDisabled ? "opacity-40" : "btn-primary btn-accent"
              } disabled:pointer-events-none`}
            >
              {planActionLabel}
            </button>
            {paymentError && (
              <p className="mt-2 text-[9px] leading-relaxed text-accent md:text-[10px]">
                {paymentError}
              </p>
            )}
            <p className="mt-2 text-[9px] leading-relaxed text-faint md:text-[10px]">
              {t.profile.planNote}
            </p>

            {subscription ? (
              <div className="mt-4 border-t border-line/60 pt-4">
                <div className="flex flex-col gap-3 rounded-xl border border-line bg-bg/45 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <div className="text-[8px] uppercase tracking-[0.2em] text-accent">
                      {t.profile.billingSettings}
                    </div>
                    <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-dim">
                      <span className="font-bold text-ink">
                        {subscription.provider_payment_method_id
                          ? `${t.profile.cardLinked}${subscription.card_last4 ? ` · •••• ${subscription.card_last4}` : ""}`
                          : t.profile.cardMissing}
                      </span>
                      <span className="text-faint">/</span>
                      <span className={subscription.auto_renew ? "text-accent" : "text-faint"}>
                        {subscription.auto_renew ? t.profile.autoRenewOn : t.profile.autoRenewOff}
                      </span>
                    </div>
                    {subscription.pending_plan_id ? (
                      <div className="mt-2 text-[8px] uppercase tracking-widest text-faint">
                        {subscription.pending_plan_id === "free" ? t.profile.scheduledFree : t.profile.scheduledStart}
                        {periodEndLabel ? ` · ${periodEndLabel}` : ""}
                      </div>
                    ) : null}
                    {subscription.renewal_error ? (
                      <div className="mt-2 text-[8px] leading-relaxed text-red-300">
                        {subscription.renewal_error}
                      </div>
                    ) : null}
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      if (subscription.provider_payment_method_id) {
                        setModal({
                          tone: "warning",
                          eyebrow: t.profile.billingSettings,
                          title: t.profile.unlinkCardTitle,
                          description: t.profile.unlinkCardDescription,
                          primaryLabel: t.profile.confirmUnlink,
                          secondaryLabel: t.profile.back,
                          primaryAction: "unlink",
                        });
                      } else {
                        void startCardBinding();
                      }
                    }}
                    disabled={Boolean(billingAction)}
                    className="btn flex-none !px-4 !py-2 !text-[8px] disabled:opacity-45"
                  >
                    {billingAction === "card"
                      ? t.profile.paymentStarting
                      : subscription.provider_payment_method_id
                        ? t.profile.unlinkCard
                        : t.profile.linkCard}
                  </button>
                </div>
              </div>
            ) : null}
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

          {section === "limits" && (
            <div className="flex h-full flex-col gap-4">
              <div>
                <div className="text-[9px] uppercase tracking-[0.2em] text-accent">
                  {t.profile.limitsTitle}
                </div>
                <p className="mt-2 max-w-xl text-[10px] leading-relaxed text-faint md:text-[11px]">
                  {t.profile.limitsLead}
                </p>
              </div>

              <div className="rounded-xl border border-line bg-bg/45 p-4 md:p-5">
                {usageBalanceError && (
                  <div className="mb-3 text-[8px] uppercase tracking-widest text-accent">
                    {t.profile.balanceUnavailable}
                  </div>
                )}
                <div className="flex items-end justify-between gap-3">
                  <div>
                    <div className="text-[8px] uppercase tracking-widest text-faint">
                      {t.profile.used}
                    </div>
                    <div className="mt-1 text-2xl font-bold tracking-tight md:text-3xl">
                      {usageBalance ? formatBalanceHours(usageBalance.used_seconds) : "—"}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-[8px] uppercase tracking-widest text-faint">
                      {t.profile.remaining}
                    </div>
                    <div className="mt-1 text-lg font-bold text-accent md:text-xl">
                      {usageBalance ? formatBalanceHours(usageBalance.remaining_seconds) : "—"}
                    </div>
                  </div>
                </div>
                <div className="mt-4 h-2 overflow-hidden rounded-full bg-white/[0.06]">
                  <motion.div
                    initial={{ width: 0 }}
                    animate={{ width: `${usageProgress}%` }}
                    transition={{ duration: 0.65, ease }}
                    className="h-full rounded-full bg-accent"
                  />
                </div>
                {usageBalance && (
                  <div className="mt-4 grid grid-cols-3 gap-2 border-t border-line/60 pt-3">
                    {[
                      [t.profile.includedHours, usageBalance.base_seconds],
                      [t.profile.rolloverHours, usageBalance.rollover_seconds],
                      [t.profile.extraHours, usageBalance.addon_seconds],
                    ].map(([label, seconds]) => (
                      <div key={String(label)} className="min-w-0">
                        <div className="truncate text-[7px] uppercase tracking-widest text-faint md:text-[8px]">
                          {label}
                        </div>
                        <div className="mt-1 text-[11px] font-bold text-dim md:text-[12px]">
                          {formatBalanceHours(Number(seconds))}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="rounded-xl border border-accent/30 bg-accent/[0.035] p-4 md:p-5">
                <div className="flex flex-col justify-between gap-4 md:flex-row md:items-end">
                  <div className="max-w-md">
                    <div className="text-[10px] font-bold uppercase tracking-widest text-ink">
                      {t.profile.buyHoursTitle}
                    </div>
                    <p className="mt-2 text-[9px] leading-relaxed text-faint md:text-[10px]">
                      {usageBalance?.can_purchase_extra_hours
                        ? t.profile.buyHoursLead
                        : t.profile.upgradeForHours}
                    </p>
                  </div>
                  {usageBalance?.can_purchase_extra_hours ? (
                    <div className="flex flex-wrap items-center gap-2 md:justify-end">
                      <div className="flex h-10 items-center overflow-hidden rounded-lg border border-line bg-bg/70">
                        <button
                          type="button"
                          onClick={() => setExtraHourCount((value) => Math.max(1, value - 1))}
                          className="h-full px-3 text-dim transition-colors hover:text-ink"
                          aria-label="Decrease hours"
                        >
                          −
                        </button>
                        <span className="min-w-16 text-center text-[10px] font-bold uppercase tracking-widest">
                          {extraHourCount} {extraHourCount === 1 ? t.profile.hour : t.profile.hours}
                        </span>
                        <button
                          type="button"
                          onClick={() => setExtraHourCount((value) => Math.min(20, value + 1))}
                          className="h-full px-3 text-dim transition-colors hover:text-ink"
                          aria-label="Increase hours"
                        >
                          +
                        </button>
                      </div>
                      <button
                        type="button"
                        onClick={() => void buyExtraHours()}
                        disabled={buyingHours || checkingPayment}
                        className="btn btn-primary btn-accent h-10 !px-4 !py-0 !text-[9px] disabled:opacity-50"
                      >
                        {buyingHours ? "• • •" : `${t.profile.buyHours} · ${extraTotal.toLocaleString(lang === "ru" ? "ru-RU" : "en-US")} ₽`}
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      onClick={() => {
                        setViewPlan("start");
                        setSection("plan");
                      }}
                      className="btn btn-primary btn-accent !px-4 !py-2 !text-[9px]"
                    >
                      {t.profile.openPlans}
                    </button>
                  )}
                </div>
              </div>
              {paymentError && (
                <p className="text-[9px] text-accent md:text-[10px]">{paymentError}</p>
              )}
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
                            {payment.product_type === "extra_hours"
                              ? `EyeVoice · ${payment.quantity_hours ?? 0} ${t.profile.extraHoursPayment}`
                              : `EyeVoice ${payment.plan_id.toUpperCase()}`}
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

          {section === "admin" && isAdmin && <AdminDashboard />}

          {section === "support" && isAdmin && <AdminSupportPlaceholder />}
        </motion.div>
      </div>
    </motion.div>
    <BillingModal
      open={Boolean(modal)}
      tone={modal?.tone ?? "progress"}
      eyebrow={modal?.eyebrow ?? ""}
      title={modal?.title ?? ""}
      description={modal?.description ?? ""}
      detail={modal?.detail}
      primaryLabel={modal?.primaryLabel}
      secondaryLabel={modal?.secondaryLabel}
      onPrimary={handleModalPrimary}
      onSecondary={closeModal}
      dismissible={modal?.dismissible ?? true}
    />
    </>
  );
}
