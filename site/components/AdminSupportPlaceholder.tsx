"use client";

import { useLang } from "@/lib/i18n";

export default function AdminSupportPlaceholder() {
  const { lang } = useLang();
  return (
    <div className="flex h-full min-h-[20rem] items-center justify-center">
      <div className="w-full max-w-xl border-l border-accent bg-gradient-to-r from-accent/[0.055] to-transparent px-6 py-5">
        <div className="text-[8px] uppercase tracking-[0.24em] text-accent">EyeVoice / support desk</div>
        <h2 className="mt-3 text-2xl font-bold tracking-[-0.055em]">
          {lang === "ru" ? "Очередь поддержки" : "Support queue"}
        </h2>
        <p className="mt-3 max-w-md text-[10px] leading-6 text-faint md:text-[11px]">
          {lang === "ru"
            ? "Раздел уже защищён ролью администратора. В следующем обновлении здесь появятся обращения пользователей, статусы и история ответов."
            : "This section is already protected by the admin role. User requests, statuses and reply history will appear here in the next update."}
        </p>
        <div className="mt-5 text-[8px] uppercase tracking-[0.18em] text-dim">[ queue / not connected ]</div>
      </div>
    </div>
  );
}

