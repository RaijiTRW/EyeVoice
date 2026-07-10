"use client";

import Link from "next/link";
import { useSyncExternalStore } from "react";
import LivingEyeMark from "./LivingEyeMark";
import HeroSignalField from "./HeroSignalField";
import SiteHeader from "./SiteHeader";
import styles from "./DownloadPage.module.css";
import { useLang } from "@/lib/i18n";

const subscribeDesktop = (callback: () => void) => {
  const media = window.matchMedia("(min-width: 701px)");
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
};

const getDesktopSnapshot = () => window.matchMedia("(min-width: 701px)").matches;
const getDesktopServerSnapshot = () => false;

function PlatformGlyph({ platform }: { platform: "mac" | "windows" | "linux" }) {
  if (platform === "windows") {
    return (
      <svg viewBox="0 0 36 36" aria-hidden="true">
        <path d="M4 6.5 16.5 4v13.3H4V6.5Zm15.5-2.7L32 1.5v15.8H19.5V3.8ZM4 19.3h12.5v13.1L4 29.9V19.3Zm15.5 0H32v15.2l-12.5-2.1V19.3Z" fill="currentColor" />
      </svg>
    );
  }

  if (platform === "linux") {
    return (
      <svg viewBox="0 0 64 72" fill="none" aria-hidden="true" className={styles.tuxIcon}>
        <path d="M32 3C20.3 3 16 14.1 16.6 25.2c.2 4.2-2.1 8.3-4.6 12.7C8.8 43.5 7.2 49.8 9.6 55c2.7 5.7 10.4 8.7 22.4 8.7S51.7 60.7 54.4 55c2.4-5.2.8-11.5-2.4-17.1-2.5-4.4-4.8-8.5-4.6-12.7C48 14.1 43.7 3 32 3Z" fill="#151515" stroke="#727272" strokeWidth="1.5" />
        <path d="M15.5 34.1C9.1 36.7 4.1 41.8 3.1 48.8c-.4 2.9 1.5 4.7 4.1 3.8 4.5-1.5 8.5-6.1 11.7-11.6l-3.4-6.9ZM48.5 34.1c6.4 2.6 11.4 7.7 12.4 14.7.4 2.9-1.5 4.7-4.1 3.8-4.5-1.5-8.5-6.1-11.7-11.6l3.4-6.9Z" fill="#151515" stroke="#727272" strokeWidth="1.5" />
        <ellipse cx="32" cy="42.5" rx="15.3" ry="18.2" fill="#F1F1F1" />
        <ellipse cx="26" cy="20.2" rx="6.8" ry="8.7" fill="#F1F1F1" />
        <ellipse cx="38" cy="20.2" rx="6.8" ry="8.7" fill="#F1F1F1" />
        <ellipse cx="27.8" cy="21.5" rx="2.2" ry="3.3" fill="#161616" />
        <ellipse cx="36.2" cy="21.5" rx="2.2" ry="3.3" fill="#161616" />
        <circle cx="28.5" cy="20.6" r=".7" fill="white" />
        <circle cx="36.9" cy="20.6" r=".7" fill="white" />
        <path d="m24.7 27.4 7.3-4.2 7.3 4.2-7.3 5.8-7.3-5.8Z" fill="#F2B134" stroke="#B77C13" strokeWidth="1" strokeLinejoin="round" />
        <path d="M12.1 60.5c-5.6 2.2-8.6 6.1-6.7 8.1 2.1 2.2 11.8.4 18-4.9l-11.3-3.2ZM51.9 60.5c5.6 2.2 8.6 6.1 6.7 8.1-2.1 2.2-11.8.4-18-4.9l11.3-3.2Z" fill="#F2B134" stroke="#B77C13" strokeWidth="1.2" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 40 40" aria-hidden="true">
      <path d="M24.4 8.7c1.7-2 1.5-4.2 1.5-4.2s-2.4.1-4.2 2.1c-1.6 1.7-1.4 4-1.4 4s2.4.2 4.1-1.9Z" fill="currentColor" />
      <path d="M29.4 21c0-4.7 3.9-7 4.1-7.1-2.2-3.3-5.7-3.7-6.9-3.8-2.9-.3-5.7 1.7-7.2 1.7-1.5 0-3.8-1.7-6.3-1.6-3.2 0-6.2 1.9-7.8 4.8-3.4 5.9-.9 14.8 2.5 19.6 1.6 2.4 3.5 5 6 4.9 2.4-.1 3.3-1.6 6.2-1.6 2.9 0 3.7 1.6 6.2 1.5 2.6 0 4.3-2.4 5.8-4.7 1.9-2.8 2.7-5.5 2.8-5.7-.1 0-5.3-2.1-5.4-8Z" fill="currentColor" />
    </svg>
  );
}

export default function DownloadPage() {
  const { lang } = useLang();
  const isRussian = lang === "ru";
  const isDesktop = useSyncExternalStore(
    subscribeDesktop,
    getDesktopSnapshot,
    getDesktopServerSnapshot,
  );

  const text = isRussian
    ? {
        eyebrow: "версия для macOS",
        mobileTitle: "Скачать EyeVoice",
        subtitle: "Выберите платформу. Сейчас доступна версия для компьютеров Mac с Apple Silicon.",
        available: "доступно сейчас",
        coming: "скоро",
        mac: "macOS",
        windows: "Windows",
        linux: "Linux",
        requirement: "macOS 14+ · Apple Silicon",
        note: "Версии для Windows и Linux находятся в разработке.",
        account: "создать аккаунт",
        footer: "Доступно на macOS",
        desktopEyebrow: "EyeVoice для macOS",
        desktopTitleA: "Скачать EyeVoice.",
        desktopTitleB: "Выберите платформу.",
        desktopLead: "EyeVoice для Apple Silicon переводит речь из микрофона, системного звука и выбранных приложений в реальном времени.",
        selector: "выберите платформу",
        release: "системные требования",
        desktopFoot: "Версии для Windows и Linux находятся в разработке",
      }
    : {
        eyebrow: "version for macOS",
        mobileTitle: "Download EyeVoice",
        subtitle: "Choose a platform. The version for Mac computers with Apple Silicon is available now.",
        available: "available now",
        coming: "coming soon",
        mac: "macOS",
        windows: "Windows",
        linux: "Linux",
        requirement: "macOS 14+ · Apple Silicon",
        note: "Windows and Linux versions are currently in development.",
        account: "create account",
        footer: "Available on macOS",
        desktopEyebrow: "EyeVoice for macOS",
        desktopTitleA: "Download EyeVoice.",
        desktopTitleB: "Choose a platform.",
        desktopLead: "EyeVoice for Apple Silicon translates speech from the microphone, system audio and selected applications in real time.",
        selector: "choose a platform",
        release: "system requirements",
        desktopFoot: "Windows and Linux versions are currently in development",
      };

  return (
    <main className={styles.page}>
      <SiteHeader />
      <div className={styles.desktopPage}>
        <section className={styles.desktopStage} aria-labelledby="desktop-download-title">
          <div className={styles.desktopSignal} aria-hidden="true">
            {isDesktop ? <HeroSignalField /> : null}
          </div>
          <div className={styles.desktopScanlines} aria-hidden="true" />

          <div className={styles.desktopLayout}>
            <div className={styles.desktopIntro}>
              <p>{text.desktopEyebrow}</p>
              <h1 id="desktop-download-title">
                <span>{text.desktopTitleA}</span>
                <span>{text.desktopTitleB}</span>
              </h1>
              <div className={styles.desktopLeadRow}>
                <span>EV / 01</span>
                <p>{text.desktopLead}</p>
              </div>
            </div>

            <aside className={styles.desktopSelector} aria-label={isRussian ? "Выбор платформы" : "Platform selection"}>
              <div className={styles.selectorHeader}>
                <span>{text.selector}</span>
                <span>01 / 03</span>
              </div>
              <a href="#desktop-release-details" className={styles.desktopMac}>
                <span className={styles.selectorIndex}>01</span>
                <PlatformGlyph platform="mac" />
                <span className={styles.selectorName}>
                  <b>{text.mac}</b>
                  <small>{text.requirement}</small>
                </span>
                <span className={styles.selectorState}>{text.available}</span>
                <i aria-hidden>↘</i>
              </a>
              {([
                ["windows", text.windows, "02"],
                ["linux", text.linux, "03"],
              ] as const).map(([platform, name, index]) => (
                <div className={styles.desktopDisabled} key={platform} aria-disabled="true">
                  <span className={styles.selectorIndex}>{index}</span>
                  <PlatformGlyph platform={platform} />
                  <span className={styles.selectorName}><b>{name}</b></span>
                  <span className={styles.selectorState}>{text.coming}</span>
                  <span className={styles.desktopComing}>{text.coming}</span>
                </div>
              ))}
              <div className={styles.selectorFooter}>{text.desktopFoot}</div>
            </aside>
          </div>

          <div id="desktop-release-details" className={styles.desktopBottomBar}>
            <div>
              <span>{text.release}</span>
              <b>{text.requirement}</b>
            </div>
            <div>
              <span>ACCOUNT</span>
              <Link href="/signup">{text.account} ↗</Link>
            </div>
          </div>
        </section>
      </div>

      <div className={styles.mobilePage}>
        <section className={styles.mobileHero} aria-labelledby="download-title">
          <LivingEyeMark size={56} className={styles.mobileEye} />
          <p>{text.eyebrow}</p>
          <h1 id="download-title">{text.mobileTitle}</h1>
          <span>{text.subtitle}</span>
        </section>

        <section className={styles.mobilePlatformPicker} aria-label={isRussian ? "Выбор платформы" : "Platform selection"}>
          <a href="#mobile-macos-details" className={styles.mobilePlatformActive} aria-label={`${text.mac}: ${text.available}`}>
            <PlatformGlyph platform="mac" />
            <i aria-hidden="true" />
          </a>

          {(["windows", "linux"] as const).map((platform) => (
            <div
              className={styles.mobilePlatformDisabled}
              key={platform}
              aria-label={`${platform === "windows" ? text.windows : text.linux}: ${text.coming}`}
              aria-disabled="true"
            >
              <PlatformGlyph platform={platform} />
              <span>{text.coming}</span>
            </div>
          ))}
        </section>

        <section id="mobile-macos-details" className={styles.mobileMacInfo}>
          <div>
            <span>{text.available}</span>
            <h2>{text.mac}</h2>
            <p>{text.requirement}</p>
          </div>
          <Link href="/signup">{text.account} ↗</Link>
        </section>

        <footer className={styles.mobileFooter}>
          <span>{text.note}</span>
          <span>{text.footer}</span>
        </footer>
      </div>
    </main>
  );
}
