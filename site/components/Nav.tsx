"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import EyeMark from "./EyeMark";
import { useUser } from "@/lib/useUser";
import { useLang, type Lang } from "@/lib/i18n";
import { useProfileSection, type ProfileSection } from "@/lib/profile-section";

export default function Nav({
  className = "",
  profileMode = false,
}: {
  className?: string;
  profileMode?: boolean;
}) {
  const { user, loading } = useUser();
  const { lang, setLang, t } = useLang();
  const { section, setSection } = useProfileSection();

  const profileSections: Array<[ProfileSection, string]> = [
    ["plan", t.profile.tabPlan],
    ["stats", t.profile.tabStats],
    ["history", t.profile.tabHistory],
  ];

  const langButton = (l: Lang, flag: string, label: string) => (
    <button
      onClick={() => setLang(l)}
      aria-label={label}
      title={label}
      className={`text-[16px] leading-none transition-all duration-200 ${
        lang === l
          ? "scale-110"
          : "opacity-35 grayscale hover:opacity-70 hover:grayscale-0"
      }`}
    >
      {flag}
    </button>
  );

  return (
    <motion.header
      initial={{ opacity: 0, y: -12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
      className={`sticky top-0 z-50 border-b border-line/60 bg-bg/80 backdrop-blur-md ${className}`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link
          href="/"
          className="flex items-center gap-2 text-sm font-bold tracking-[0.2em] text-ink"
        >
          <EyeMark size={20} className="text-accent" /> EYEVOICE
        </Link>
        <nav className="hidden items-center gap-8 text-[12px] uppercase tracking-widest text-faint md:flex">
          {profileMode
            ? profileSections.map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setSection(id)}
                  className={`relative py-1.5 transition-colors hover:text-ink ${
                    section === id ? "text-ink" : "text-faint"
                  }`}
                >
                  {label}
                  {section === id ? (
                    <motion.span
                      layoutId="profileHeaderSection"
                      className="absolute inset-x-0 -bottom-1 h-px bg-accent"
                      transition={{ type: "spring", stiffness: 420, damping: 34 }}
                    />
                  ) : null}
                </button>
              ))
            : (
              <>
                <Link href="/#features" className="transition-colors hover:text-ink">
                  {t.nav.features}
                </Link>
                <Link href="/#how" className="transition-colors hover:text-ink">
                  {t.nav.how}
                </Link>
                <Link href="/download" className="transition-colors hover:text-ink">
                  {t.nav.download}
                </Link>
              </>
            )}
        </nav>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            {langButton("ru", "🇷🇺", "Русский")}
            {langButton("en", "🇺🇸", "English")}
          </div>
          {loading ? null : user ? (
            <Link href="/profile" className="btn btn-primary !px-4 !py-2 !text-[11px]">
              {t.nav.profile}
            </Link>
          ) : (
            <>
              <Link
                href="/login"
                className="text-[12px] uppercase tracking-widest text-faint transition-colors hover:text-ink"
              >
                {t.nav.login}
              </Link>
              <Link href="/signup" className="btn btn-primary !px-4 !py-2 !text-[11px]">
                {t.nav.signup}
              </Link>
            </>
          )}
        </div>
      </div>
    </motion.header>
  );
}
