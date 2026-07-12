"use client";

import Link from "next/link";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import LivingEyeMark from "./LivingEyeMark";
import HeroSignalField from "./HeroSignalField";
import SiteHeader from "./SiteHeader";
import styles from "./DownloadPage.module.css";
import { useLang } from "@/lib/i18n";

const MAC_DOWNLOAD_URL =
  "https://seexmgivktuycodxrjhs.supabase.co/storage/v1/object/public/eyevoice-releases/EyeVoice-latest.dmg";

const subscribeDesktop = (callback: () => void) => {
  const media = window.matchMedia("(min-width: 701px)");
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
};

const getDesktopSnapshot = () => window.matchMedia("(min-width: 701px)").matches;
const getDesktopServerSnapshot = () => false;

function PlatformGlyph({ platform }: { platform: "mac" | "windows" | "linux" | "ios" | "android" }) {
  if (platform === "ios") {
    return (
      <svg viewBox="0 0 40 40" aria-hidden="true">
        <path d="M24.4 8.7c1.7-2 1.5-4.2 1.5-4.2s-2.4.1-4.2 2.1c-1.6 1.7-1.4 4-1.4 4s2.4.2 4.1-1.9Z" fill="currentColor" />
        <path d="M29.4 21c0-4.7 3.9-7 4.1-7.1-2.2-3.3-5.7-3.7-6.9-3.8-2.9-.3-5.7 1.7-7.2 1.7-1.5 0-3.8-1.7-6.3-1.6-3.2 0-6.2 1.9-7.8 4.8-3.4 5.9-.9 14.8 2.5 19.6 1.6 2.4 3.5 5 6 4.9 2.4-.1 3.3-1.6 6.2-1.6 2.9 0 3.7 1.6 6.2 1.5 2.6 0 4.3-2.4 5.8-4.7 1.9-2.8 2.7-5.5 2.8-5.7-.1 0-5.3-2.1-5.4-8Z" fill="currentColor" />
      </svg>
    );
  }

  if (platform === "android") {
    return (
      <svg viewBox="0 0 40 40" fill="none" aria-hidden="true">
        <path d="m13.2 8-2.6-3.6M26.8 8l2.6-3.6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
        <path d="M9.5 17.2C9.5 11.3 14.2 7 20 7s10.5 4.3 10.5 10.2H9.5Z" stroke="currentColor" strokeWidth="1.8" />
        <path d="M10 20h20v12.3a3.2 3.2 0 0 1-3.2 3.2H13.2a3.2 3.2 0 0 1-3.2-3.2V20Z" stroke="currentColor" strokeWidth="1.8" />
        <circle cx="15.2" cy="13.5" r="1.2" fill="currentColor" />
        <circle cx="24.8" cy="13.5" r="1.2" fill="currentColor" />
        <path d="M6.5 21v9M33.5 21v9M15 35.5V38M25 35.5V38" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
      </svg>
    );
  }

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
  const [desktopMobileOpen, setDesktopMobileOpen] = useState(false);
  const desktopMobileRef = useRef<HTMLElement>(null);
  const desktopCueRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!desktopMobileOpen) return;

    const scrollTimer = window.setTimeout(() => {
      desktopMobileRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 140);

    return () => window.clearTimeout(scrollTimer);
  }, [desktopMobileOpen]);

  const toggleDesktopMobile = () => {
    const nextOpen = !desktopMobileOpen;
    setDesktopMobileOpen(nextOpen);

    if (!nextOpen) {
      window.setTimeout(() => {
        desktopCueRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
      }, 40);
    }
  };

  const text = isRussian
    ? {
        eyebrow: "версия для macOS",
        mobileTitle: "Скачать EyeVoice",
        subtitle: "Версии для iPhone и Android уже в работе. Скоро они появятся на этой странице.",
        phoneEyebrow: "EyeVoice для телефона",
        phoneTitle: "iPhone и Android.",
        phoneLead: "Мобильные версии готовятся к запуску. Пока оставляем место для будущей загрузки из App Store и Google Play.",
        phoneStatus: "скоро на телефонах",
        computerEyebrow: "версия для компьютера",
        computerLead: "Для Mac с Apple Silicon EyeVoice уже доступен. Windows и Linux находятся в разработке.",
        ios: "iPhone",
        android: "Android",
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
        betaLabel: "инструкция · beta 1.2.0",
        betaTitle: "Как открыть EyeVoice в первый раз",
        betaLead: "EyeVoice пока проходит бета-тестирование. На этом этапе при первом запуске macOS может попросить подтвердить открытие приложения — это потребуется сделать только один раз.",
        betaSteps: [
          "Перетащите EyeVoice в папку Applications.",
          "Откройте приложение один раз — macOS покажет предупреждение.",
          "Откройте Системные настройки → Конфиденциальность и безопасность и нажмите «Всё равно открыть».",
        ],
      }
    : {
        eyebrow: "version for macOS",
        mobileTitle: "Download EyeVoice",
        subtitle: "The iPhone and Android versions are already in development and will appear here soon.",
        phoneEyebrow: "EyeVoice for mobile",
        phoneTitle: "iPhone and Android.",
        phoneLead: "Mobile versions are being prepared for launch. This space is reserved for future App Store and Google Play downloads.",
        phoneStatus: "coming to mobile",
        computerEyebrow: "desktop version",
        computerLead: "EyeVoice is available now for Apple Silicon Macs. Windows and Linux are in development.",
        ios: "iPhone",
        android: "Android",
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
        betaLabel: "install guide · beta 1.2.0",
        betaTitle: "How to open EyeVoice for the first time",
        betaLead: "EyeVoice is currently in beta testing. At this stage, macOS may ask you to confirm opening the app on first launch — you will only need to do this once.",
        betaSteps: [
          "Drag EyeVoice into the Applications folder.",
          "Open the app once — macOS will show a warning.",
          "Open System Settings → Privacy & Security and click “Open Anyway”.",
        ],
      };

  return (
    <main className={styles.page}>
      <SiteHeader />
      <aside className={styles.betaNotice} aria-labelledby="beta-install-title">
        <div className={styles.betaNoticeHeader}>
          <span aria-hidden="true">❗</span>
          <p>{text.betaLabel}</p>
          <b>BETA</b>
        </div>
        <div className={styles.betaNoticeBody}>
          <div>
            <h2 id="beta-install-title">{text.betaTitle}</h2>
            <p>{text.betaLead}</p>
          </div>
          <ol>
            {text.betaSteps.map((step, index) => (
              <li key={step}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                <p>{step}</p>
              </li>
            ))}
          </ol>
        </div>
      </aside>
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
              <a href={MAC_DOWNLOAD_URL} className={styles.desktopMac} download>
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

          <button
            ref={desktopCueRef}
            type="button"
            className={styles.desktopNextCue}
            aria-controls="desktop-mobile-downloads"
            aria-expanded={desktopMobileOpen}
            aria-label={
              desktopMobileOpen
                ? isRussian
                  ? "Скрыть версии для iPhone и Android"
                  : "Hide iPhone and Android versions"
                : isRussian
                  ? "Показать версии для iPhone и Android"
                  : "Show iPhone and Android versions"
            }
            data-open={desktopMobileOpen}
            onClick={toggleDesktopMobile}
          >
            <span>{desktopMobileOpen ? (isRussian ? "скрыть" : "hide") : isRussian ? "дальше" : "next"}</span>
            <b>iPhone + Android</b>
            <i aria-hidden="true" />
          </button>

        </section>

        <div className={styles.desktopMobileDrawer} data-open={desktopMobileOpen} aria-hidden={!desktopMobileOpen}>
          <div>
            <section
              ref={desktopMobileRef}
              id="desktop-mobile-downloads"
              className={styles.desktopMobileSection}
              aria-labelledby="desktop-mobile-title"
            >
              <div className={styles.flowDivider} aria-hidden="true" />
              <div className={styles.desktopMobileInner}>
                <div className={styles.desktopMobileCopy}>
                  <span>EV / MOBILE / 02</span>
                  <h2 id="desktop-mobile-title">{text.phoneTitle}</h2>
                  <p>{text.phoneLead}</p>
                </div>
                <div className={styles.desktopPhoneGrid}>
                  {(["ios", "android"] as const).map((platform, index) => (
                    <div className={styles.desktopPhoneCard} key={platform} aria-disabled="true">
                      <span>{String(index + 1).padStart(2, "0")}</span>
                      <PlatformGlyph platform={platform} />
                      <div>
                        <b>{platform === "ios" ? text.ios : text.android}</b>
                        <small>{text.coming}</small>
                      </div>
                      <i aria-hidden="true" />
                    </div>
                  ))}
                </div>
              </div>
            </section>
          </div>
        </div>

        <footer id="desktop-release-details" className={styles.desktopBottomBar}>
          <div>
            <span>{text.release}</span>
            <b>{text.requirement}</b>
          </div>
          <div>
            <span>ACCOUNT</span>
            <Link href="/signup">{text.account} ↗</Link>
          </div>
        </footer>
      </div>

      <div className={styles.mobilePage}>
        <section className={styles.mobileHero} aria-labelledby="download-title">
          <LivingEyeMark size={56} className={styles.mobileEye} />
          <p>{text.phoneEyebrow}</p>
          <h1 id="download-title">{text.mobileTitle}</h1>
          <span>{text.subtitle}</span>
        </section>

        <section className={styles.mobilePhonePicker} aria-label={isRussian ? "Загрузка для телефона" : "Mobile downloads"}>
          {(["ios", "android"] as const).map((platform, index) => (
            <div className={styles.mobilePhoneCard} key={platform} aria-disabled="true">
              <span>{String(index + 1).padStart(2, "0")}</span>
              <PlatformGlyph platform={platform} />
              <div>
                <b>{platform === "ios" ? text.ios : text.android}</b>
                <small>{text.coming}</small>
              </div>
              <i aria-hidden="true" />
            </div>
          ))}
        </section>

        <div className={styles.mobilePhoneStatus}>
          <span>{text.phoneStatus}</span>
          <span>APP STORE / GOOGLE PLAY</span>
        </div>

        <div className={`${styles.flowDivider} ${styles.mobileFlowDivider}`} aria-hidden="true" />

        <section className={styles.mobileComputerIntro}>
          <span>{text.computerEyebrow}</span>
          <h2>{text.mac}</h2>
          <p>{text.computerLead}</p>
        </section>

        <section className={styles.mobilePlatformPicker} aria-label={isRussian ? "Выбор платформы" : "Platform selection"}>
          <a href={MAC_DOWNLOAD_URL} className={styles.mobilePlatformActive} aria-label={`${text.mac}: ${text.available}`} download>
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
