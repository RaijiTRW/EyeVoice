"use client";

import Link from "next/link";
import { AnimatePresence, motion } from "framer-motion";
import type { Variants } from "framer-motion";
import { useEffect, useId, useRef, useState } from "react";
import EyeMark from "./EyeMark";
import styles from "./MobileNav.module.css";
import { useLang } from "@/lib/i18n";

const drawerMotion: Variants = {
  closed: {
    opacity: 0,
    y: -8,
    scale: 0.98,
    transition: { duration: 0.18, ease: [0.7, 0, 0.84, 0] },
  },
  open: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: { duration: 0.28, ease: [0.16, 1, 0.3, 1], staggerChildren: 0.045, delayChildren: 0.04 },
  },
};

const itemMotion: Variants = {
  closed: { opacity: 0, x: 8 },
  open: { opacity: 1, x: 0, transition: { duration: 0.22, ease: [0.16, 1, 0.3, 1] } },
};

export default function MobileNav({ className = "" }: { className?: string }) {
  const { lang, setLang, t } = useLang();
  const [open, setOpen] = useState(false);
  const drawerId = useId();
  const headerRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, []);

  useEffect(() => {
    if (!open) return;

    const closeOnOutsideClick = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Node && !headerRef.current?.contains(target)) {
        setOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeOnOutsideClick);
    return () => document.removeEventListener("pointerdown", closeOnOutsideClick);
  }, [open]);

  const routes = [
    ["02", t.demo.eyebrow, "/#mobile-demo"],
    ["03", t.nav.features, "/#mobile-features"],
    ["04", t.nav.how, "/#mobile-how"],
    ["05", t.faq.eyebrow, "/#mobile-faq"],
    ["06", t.nav.download, "/download"],
  ];

  return (
    <header ref={headerRef} className={`${styles.root} ${className}`}>
      <Link href="/" className={styles.brand} aria-label="EyeVoice">
        <EyeMark size={28} />
      </Link>

      <div className={styles.actions}>
        <button
          type="button"
          onClick={() => setLang(lang === "ru" ? "en" : "ru")}
          className={styles.language}
          aria-label={lang === "ru" ? "Switch to English" : "Переключить на русский"}
          style={{ fontSize: 16, lineHeight: 1 }}
        >
          {lang === "ru" ? "🇺🇸" : "🇷🇺"}
        </button>
        <button
          type="button"
          className={`${styles.toggle} ${open ? styles.isOpen : ""}`}
          onClick={() => setOpen((value) => !value)}
          aria-expanded={open}
          aria-controls={drawerId}
        >
          <span className={styles.toggleLabel}>{open ? "close" : "menu"}</span>
          <span className={styles.glyph} aria-hidden="true">
            <i />
            <i />
          </span>
        </button>
      </div>

      <div className={styles.accountLinks}>
        <Link href="/login">{t.nav.login}</Link>
        <Link href="/signup" className={styles.signupLink}>{t.nav.signup}</Link>
      </div>

      <AnimatePresence>
        {open ? (
          <motion.nav
            id={drawerId}
            className={styles.popover}
            aria-label={lang === "ru" ? "Навигация" : "Navigation"}
            initial="closed"
            animate="open"
            exit="closed"
            variants={drawerMotion}
          >
            {routes.map(([index, label, href]) => (
              <motion.div key={href} variants={itemMotion}>
                <Link href={href} onClick={() => setOpen(false)} className={styles.link}>
                  <span>{index}</span>
                  <b>{label}</b>
                  <i aria-hidden>↘</i>
                </Link>
              </motion.div>
            ))}
          </motion.nav>
        ) : null}
      </AnimatePresence>
    </header>
  );
}
