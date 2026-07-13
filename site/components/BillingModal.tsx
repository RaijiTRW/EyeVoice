"use client";

import { useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import EyeMark from "./EyeMark";

const ease = [0.16, 1, 0.3, 1] as const;

export type BillingModalTone = "progress" | "success" | "error" | "warning" | "card";

type Props = {
  open: boolean;
  tone: BillingModalTone;
  eyebrow: string;
  title: string;
  description: string;
  detail?: string | null;
  primaryLabel?: string;
  secondaryLabel?: string;
  onPrimary?: () => void;
  onSecondary?: () => void;
  dismissible?: boolean;
};

export default function BillingModal({
  open,
  tone,
  eyebrow,
  title,
  description,
  detail,
  primaryLabel,
  secondaryLabel,
  onPrimary,
  onSecondary,
  dismissible = true,
}: Props) {
  useEffect(() => {
    if (!open || !dismissible || !onSecondary) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onSecondary();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [dismissible, onSecondary, open]);

  return (
    <AnimatePresence>
      {open ? (
        <motion.div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-bg/78 px-4 backdrop-blur-md"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.22, ease }}
          role="presentation"
          data-testid="billing-modal-backdrop"
        >
          <motion.div
            role="dialog"
            aria-modal="true"
            aria-labelledby="billing-modal-title"
            initial={{ opacity: 0, y: 18, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 10, scale: 0.985 }}
            transition={{ duration: 0.3, ease }}
            className="relative w-full max-w-md overflow-hidden rounded-2xl border border-line bg-panel shadow-[0_28px_90px_rgba(0,0,0,0.48),inset_0_1px_0_rgba(255,255,255,0.06)]"
          >
            <div className="flex items-center justify-between border-b border-line/70 px-5 py-4">
              <span className="text-[8px] uppercase tracking-[0.22em] text-accent">
                {eyebrow}
              </span>
              <div className="flex h-8 w-8 items-center justify-center rounded-lg border border-line bg-bg/70 text-accent">
                <EyeMark size={18} />
              </div>
            </div>

            <div className="px-5 py-5 md:px-6 md:py-6">
              <div className="mb-5 flex items-center gap-3" aria-hidden="true">
                {tone === "progress" ? (
                  <div className="relative h-9 w-9">
                    <motion.span
                      className="absolute inset-0 rounded-full border border-accent/25"
                      animate={{ scale: [0.7, 1.15], opacity: [0.8, 0] }}
                      transition={{ duration: 1.3, repeat: Infinity, ease: "easeOut" }}
                    />
                    <span className="absolute inset-[9px] rounded-full bg-accent" />
                  </div>
                ) : (
                  <div
                    className={`flex h-9 w-9 items-center justify-center rounded-full border text-sm font-bold ${
                      tone === "success"
                        ? "border-accent/55 bg-accent/10 text-accent"
                        : tone === "error"
                          ? "border-red-400/40 bg-red-400/5 text-red-300"
                          : "border-line bg-bg/70 text-ink"
                    }`}
                  >
                    {tone === "success" ? "✓" : tone === "error" ? "×" : "!"}
                  </div>
                )}
                <span className="h-px flex-1 bg-line/70" />
              </div>

              <h2 id="billing-modal-title" className="text-2xl font-bold leading-tight tracking-tight text-ink">
                {title}
              </h2>
              <p className="mt-3 text-[11px] leading-relaxed text-dim md:text-[12px]">
                {description}
              </p>
              {detail ? (
                <div className="mt-4 border-l border-accent/60 bg-bg/55 px-3 py-2.5 text-[9px] leading-relaxed text-faint">
                  {detail}
                </div>
              ) : null}

              {(primaryLabel || secondaryLabel) ? (
                <div className="mt-6 grid gap-2 sm:grid-cols-2">
                  {secondaryLabel ? (
                    <button
                      type="button"
                      onClick={onSecondary}
                      className="btn !py-2.5 !text-[9px] active:translate-y-px"
                    >
                      {secondaryLabel}
                    </button>
                  ) : null}
                  {primaryLabel ? (
                    <button
                      type="button"
                      onClick={onPrimary}
                      className="btn btn-primary btn-accent !py-2.5 !text-[9px] active:translate-y-px"
                    >
                      {primaryLabel}
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>
          </motion.div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}
