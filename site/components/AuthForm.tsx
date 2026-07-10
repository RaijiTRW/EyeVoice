"use client";

import { useEffect, useId, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import LivingEyeMark from "./LivingEyeMark";
import styles from "./AuthForm.module.css";
import { supabase } from "@/lib/supabase";
import { useLang, type Dict } from "@/lib/i18n";

const ease = [0.16, 1, 0.3, 1] as const;

function humanizeError(message: string, errors: Dict["auth"]["errors"]): string {
  const m = message.toLowerCase();
  if (m.includes("invalid login credentials")) return errors.invalidCreds;
  if (m.includes("email not confirmed")) return errors.notConfirmed;
  if (m.includes("already registered")) return errors.exists;
  if (m.includes("rate limit") || m.includes("too many")) return errors.rateLimit;
  if (m.includes("email address") && m.includes("invalid")) return errors.invalidEmail;
  if (m.includes("password should be")) return errors.shortPassword;
  if (
    m.includes("token has expired") ||
    m.includes("token is invalid") ||
    m.includes("otp expired") ||
    m.includes("invalid otp")
  ) return errors.invalidOtp;
  return message;
}

export default function AuthForm({ mode }: { mode: "signup" | "login" }) {
  const router = useRouter();
  const { t } = useLang();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [otp, setOtp] = useState("");
  const [resending, setResending] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const consentId = useId();

  const isSignup = mode === "signup";

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const timeout = window.setTimeout(
      () => setResendCooldown((seconds) => Math.max(0, seconds - 1)),
      1000,
    );
    return () => window.clearTimeout(timeout);
  }, [resendCooldown]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (isSignup && !acceptedTerms) {
      setError(t.auth.acceptRequired);
      return;
    }

    setLoading(true);

    if (isSignup) {
      const { data, error } = await supabase.auth.signUp({ email, password });
      setLoading(false);
      if (error) {
        setError(humanizeError(error.message, t.auth.errors));
        return;
      }
      if (data.session) {
        router.push("/profile");
      } else {
        setOtp("");
        setNotice(null);
        setResendCooldown(60);
        setDone(true);
      }
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      setLoading(false);
      if (error) {
        setError(humanizeError(error.message, t.auth.errors));
        return;
      }
      router.push("/profile");
    }
  }

  async function onVerify(e: React.FormEvent) {
    e.preventDefault();
    if (otp.length !== 6 || loading) return;

    setError(null);
    setNotice(null);
    setLoading(true);
    const { data, error } = await supabase.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: otp,
      type: "email",
    });
    setLoading(false);

    if (error) {
      setError(humanizeError(error.message, t.auth.errors));
      return;
    }
    if (!data.session) {
      setError(t.auth.errors.sessionMissing);
      return;
    }
    router.push("/profile");
  }

  async function onResend() {
    if (resending || resendCooldown > 0) return;

    setError(null);
    setNotice(null);
    setResending(true);
    const { error } = await supabase.auth.resend({
      type: "signup",
      email: email.trim().toLowerCase(),
    });
    setResending(false);

    if (error) {
      setError(humanizeError(error.message, t.auth.errors));
      return;
    }
    setOtp("");
    setResendCooldown(60);
    setNotice(t.auth.codeResent);
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease }}
      className="w-full max-w-sm rounded-2xl border border-line bg-panel/60 p-8"
    >
      <div className="mb-8 text-center">
        <div className="mb-3 flex justify-center text-accent">
          <LivingEyeMark size={46} />
        </div>
        <h1 className="text-lg font-bold uppercase tracking-[0.2em]">
          {isSignup ? t.auth.signupTitle : t.auth.loginTitle}
        </h1>
        <p className="mt-2 text-[12px] text-faint">
          {isSignup ? t.auth.signupSub : t.auth.loginSub}
        </p>
      </div>

      <AnimatePresence mode="wait">
        {done ? (
          <motion.form
            key="done"
            initial={{ opacity: 0, scale: 0.96 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.4, ease }}
            onSubmit={onVerify}
            className={styles.otpCard}
          >
            <div className={styles.otpStep}>{t.auth.codeStep}</div>
            <h2 className={styles.otpTitle}>{t.auth.codeTitle}</h2>
            <p className={styles.otpDescription}>
              {t.auth.codeSentTo} <span>{email}</span>. {t.auth.codeAfter}
            </p>

            <label className={styles.otpLabel}>
              <span>{t.auth.codeLabel}</span>
              <input
                type="text"
                required
                autoFocus
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                value={otp}
                onChange={(event) => {
                  setOtp(event.target.value.replace(/\D/g, "").slice(0, 6));
                  setError(null);
                  setNotice(null);
                }}
                placeholder="000000"
                aria-describedby="otp-help"
                className={styles.otpInput}
              />
            </label>

            {error && (
              <div role="alert" className={styles.otpError}>
                [ ! ] {error}
              </div>
            )}
            {notice && (
              <div role="status" className={styles.otpNotice}>
                {notice}
              </div>
            )}

            <button
              type="submit"
              disabled={loading || otp.length !== 6}
              className="btn btn-primary btn-accent w-full disabled:pointer-events-none disabled:opacity-50"
            >
              {loading ? "• • •" : t.auth.confirmCode}
            </button>

            <div id="otp-help" className={styles.otpActions}>
              <span>{t.auth.noCode}</span>{" "}
              <button
                type="button"
                disabled={resending || resendCooldown > 0}
                onClick={onResend}
              >
                {resending
                  ? t.auth.resendingCode
                  : resendCooldown > 0
                    ? `${t.auth.resendIn} ${resendCooldown} ${t.auth.secondsShort}`
                    : t.auth.resendCode}
              </button>
            </div>

            <button
              type="button"
              className={styles.changeEmail}
              onClick={() => {
                setDone(false);
                setOtp("");
                setNotice(null);
                setError(null);
              }}
            >
              {t.auth.changeEmail}
            </button>
          </motion.form>
        ) : (
          <motion.form
            key="form"
            exit={{ opacity: 0, scale: 0.98 }}
            onSubmit={onSubmit}
            className="flex flex-col gap-4"
          >
            <label className="flex flex-col gap-2">
              <span className="text-[10px] uppercase tracking-[0.2em] text-faint">
                {t.auth.email}
              </span>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                className="input"
                autoComplete="email"
              />
            </label>
            <label className="flex flex-col gap-2">
              <span className="text-[10px] uppercase tracking-[0.2em] text-faint">
                {t.auth.password}
              </span>
              <input
                type="password"
                required
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="input"
                autoComplete={isSignup ? "new-password" : "current-password"}
              />
            </label>
            {isSignup ? (
              <div className={styles.consent}>
                <input
                  id={consentId}
                  type="checkbox"
                  required
                  checked={acceptedTerms}
                  onChange={(event) => setAcceptedTerms(event.target.checked)}
                  className={styles.nativeCheckbox}
                />
                <label
                  htmlFor={consentId}
                  className={styles.checkmark}
                  aria-label={t.auth.acceptLabel}
                >
                  <span aria-hidden="true">✓</span>
                </label>
                <p className={styles.consentText}>
                  <label htmlFor={consentId}>{t.auth.acceptPrefix}</label>{" "}
                  <Link href="/privacy">{t.auth.privacyLink}</Link>{" "}
                  <label htmlFor={consentId}>{t.auth.acceptJoin}</label>{" "}
                  <Link href="/terms">{t.auth.termsLink}</Link>.
                </p>
              </div>
            ) : null}
            {error && (
              <div className="rounded-lg border border-accent/40 bg-accent/5 px-3 py-2 text-[12px] text-accent">
                [ ! ] {error}
              </div>
            )}
            <button
              type="submit"
              disabled={loading || (isSignup && !acceptedTerms)}
              className="btn btn-primary btn-accent mt-2 w-full disabled:pointer-events-none disabled:opacity-50"
            >
              {loading
                ? "• • •"
                : isSignup
                  ? t.auth.submitSignup
                  : t.auth.submitLogin}
            </button>
          </motion.form>
        )}
      </AnimatePresence>

      {!done && <div className="mt-6 text-center text-[12px] text-faint">
        {isSignup ? (
          <>
            {t.auth.haveAccount}{" "}
            <Link href="/login" className="text-dim underline-offset-4 transition-colors hover:text-ink hover:underline">
              {t.auth.loginLink}
            </Link>
          </>
        ) : (
          <>
            {t.auth.noAccount}{" "}
            <Link href="/signup" className="text-dim underline-offset-4 transition-colors hover:text-ink hover:underline">
              {t.auth.signupLink}
            </Link>
          </>
        )}
      </div>}
    </motion.div>
  );
}
