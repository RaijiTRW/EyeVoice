"use client";

import Link from "next/link";
import EyeMark from "./EyeMark";
import { useLang } from "@/lib/i18n";

export default function Footer() {
  const { t } = useLang();

  return (
    <footer className="border-t border-line/60">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-6 py-10 text-[11px] uppercase tracking-widest text-faint md:flex-row">
        <div className="flex items-center gap-2">
          <EyeMark size={18} className="text-accent" />
          <span className="text-dim">EYEVOICE</span>
          <span>© 2026</span>
        </div>
        <div>{t.footer.made}</div>
        <div className="flex gap-6">
          <Link href="/privacy" className="transition-colors hover:text-ink">
            {t.footer.privacy}
          </Link>
          <Link href="/terms" className="transition-colors hover:text-ink">
            {t.footer.terms}
          </Link>
        </div>
      </div>
    </footer>
  );
}
