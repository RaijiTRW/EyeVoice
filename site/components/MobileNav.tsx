"use client";

import Link from "next/link";
import { AnimatePresence, motion } from "framer-motion";
import type { Variants } from "framer-motion";
import { useEffect, useId, useRef, useState } from "react";
import EyeMark from "./EyeMark";
import styles from "./MobileNav.module.css";
import { useLang } from "@/lib/i18n";
import { useProfileSection, type ProfileSection } from "@/lib/profile-section";
import { useUser } from "@/lib/useUser";
import { useAdminAccess } from "@/lib/admin-access";

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

function ProfileIcon({ section }: { section: ProfileSection }) {
  if (section === "admin") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M4 19V9M10 19V5M16 19v-7M22 19V3" />
        <path d="M2.5 19.5h20" />
      </svg>
    );
  }

  if (section === "support") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M5 16.5A7 7 0 1 1 19 16v2.5a2 2 0 0 1-2 2h-3" />
        <path d="M5 12.5H3.5v4H6M19 12.5h1.5v4H18" />
      </svg>
    );
  }
  if (section === "plan") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M5 7.5h14M7 4.5h10a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-11a2 2 0 0 1 2-2Z" />
        <path d="M8 12h5M8 15.5h8" />
      </svg>
    );
  }

  if (section === "stats") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M5 19V9.5M12 19V5M19 19v-6.5" />
        <path d="M3.5 19.5h17" />
      </svg>
    );
  }

  if (section === "limits") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M4 17.5V9.75A2.75 2.75 0 0 1 6.75 7h10.5A2.75 2.75 0 0 1 20 9.75v7.75" />
        <path d="M7 14.5h10M8.5 11.5h7M4 17.5h16" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4.5 8h15v10.5a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8Z" />
      <path d="M7.5 8V5.5a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2V8M4.5 12h15M15.5 15.5h1" />
    </svg>
  );
}

export default function MobileNav({
  className = "",
  profileMode = false,
}: {
  className?: string;
  profileMode?: boolean;
}) {
  const { lang, setLang, t } = useLang();
  const { user, loading } = useUser();
  const { section, setSection } = useProfileSection();
  const { isAdmin } = useAdminAccess();
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
  const profileSections: Array<[ProfileSection, string, string]> = [
    ["plan", "01", t.profile.tabPlan],
    ["limits", "02", t.profile.tabLimits],
    ["stats", "03", t.profile.tabStats],
    ["history", "04", t.profile.tabHistory],
    ...(isAdmin
      ? ([
          ["admin", "05", t.profile.tabAdmin],
          ["support", "06", t.profile.tabSupport],
        ] as Array<[ProfileSection, string, string]>)
      : []),
  ];

  return (
    <>
      <header
        ref={headerRef}
        className={`${styles.root} ${profileMode ? styles.profileRoot : ""} ${className}`}
      >
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
          {!profileMode && (
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
          )}
        </div>

        <div className={styles.accountLinks}>
          {loading ? null : user ? (
            <Link href="/profile" className={styles.profileLink}>
              {t.nav.profile}
            </Link>
          ) : (
            <>
              <Link href="/login">{t.nav.login}</Link>
              <Link href="/signup" className={styles.signupLink}>{t.nav.signup}</Link>
            </>
          )}
        </div>

        <AnimatePresence>
          {!profileMode && open ? (
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

      {profileMode && (
        <nav
          className={`${styles.profileDock} ${isAdmin ? styles.profileDockAdmin : ""}`}
          aria-label={lang === "ru" ? "Разделы профиля" : "Profile sections"}
        >
          <svg
            className={styles.profileDockRefraction}
            viewBox="0 0 800 200"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <defs>
              <filter id="profileDockDistortion" x="-8%" y="-24%" width="116%" height="148%">
                <feTurbulence
                  type="fractalNoise"
                  baseFrequency="0.008"
                  numOctaves="3"
                  seed="7"
                  result="noise"
                />
                <feDisplacementMap
                  in="SourceGraphic"
                  in2="noise"
                  scale="7.7"
                  xChannelSelector="R"
                  yChannelSelector="B"
                  result="displaced"
                />
                <feGaussianBlur in="displaced" stdDeviation="3" />
              </filter>
              <radialGradient id="profileDockLight" cx="50%" cy="0%" r="90%">
                <stop offset="0%" stopColor="#ff4fa3" stopOpacity="0.16" />
                <stop offset="48%" stopColor="#ff8dc5" stopOpacity="0.035" />
                <stop offset="100%" stopColor="#ff4fa3" stopOpacity="0" />
              </radialGradient>
            </defs>
            <rect
              x="6"
              y="6"
              width="788"
              height="188"
              rx="28"
              fill="url(#profileDockLight)"
              filter="url(#profileDockDistortion)"
            />
          </svg>
          {profileSections.map(([id, , label]) => {
            const active = section === id;
            return (
              <motion.button
                key={id}
                type="button"
                whileTap={{ scale: 0.96 }}
                onClick={() => setSection(id)}
                className={`${styles.profileDockItem} ${active ? styles.profileDockItemActive : ""}`}
                aria-current={active ? "page" : undefined}
              >
                {active && (
                  <motion.span
                    layoutId="mobileProfileGlassLens"
                    className={styles.profileDockLens}
                    transition={{ type: "spring", stiffness: 430, damping: 38 }}
                  />
                )}
                <span className={styles.profileDockIcon}>
                  <ProfileIcon section={id} />
                </span>
                <span className={styles.profileDockLabel}>{label}</span>
              </motion.button>
            );
          })}
        </nav>
      )}
    </>
  );
}
