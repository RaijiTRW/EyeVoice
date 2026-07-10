"use client";

import Link from "next/link";
import AsciiEye from "./AsciiEye";
import DemoVideoSection from "./DemoVideoSection";
import EyeMark from "./EyeMark";
import FAQSection from "./FAQSection";
import HeroSignalField from "./HeroSignalField";
import LivingEyeMark from "./LivingEyeMark";
import MobileNav from "./MobileNav";
import styles from "./MobileHome.module.css";
import { KineticLines, ParallaxLayer, Reveal } from "./Reveal";
import { useLang } from "@/lib/i18n";

const WAVE_BARS = Array.from({ length: 20 }, (_, index) => index);

export default function MobileHome() {
  const { t, lang } = useLang();
  const m = t.mobile;

  return (
    <main className={`${styles.root} mobile-home md:hidden`}>
      <MobileNav />

      <section className="mobile-hero" aria-labelledby="mobile-hero-title">
        <div className="mobile-signal-stage" aria-hidden="true">
          <HeroSignalField />
          <div className="mobile-eye-wrap">
            <ParallaxLayer className="mobile-eye-parallax" distance={14}>
              <AsciiEye cols={42} rows={28} cell={9} />
            </ParallaxLayer>
          </div>
        </div>

        <div className="mobile-hero-copy">
          <Reveal>
            <div className="mobile-section-code">
              <span>01</span>
              <span>{m.heroCode}</span>
            </div>
          </Reveal>
          <KineticLines
            key={`kinetic-${lang}`}
            id="mobile-hero-title"
            className="mobile-display"
            lines={[
              { text: m.lines[0] },
              { text: m.lines[1], accent: true },
              { text: m.lines[2] },
            ]}
          />
          <Reveal delay={0.18}>
            <p className="mobile-lead">{m.lead}</p>
          </Reveal>
          <Reveal delay={0.3}>
            <div className="mobile-hero-actions">
              <Link
                href="/download"
                className="mobile-primary-action rounded-2xl"
              >
                <span>{m.downloadMac}</span>
                <span aria-hidden>↓</span>
              </Link>
              <Link href="/signup" className="mobile-text-action">
                {m.createAccount} <span aria-hidden>→</span>
              </Link>
            </div>
          </Reveal>

          <a
            href="#mobile-demo"
            className="mobile-scroll-signal"
            aria-label={lang === "ru" ? "Прокрутить к примеру работы" : "Scroll to the product example"}
          >
            <svg viewBox="0 0 42 68" role="presentation" aria-hidden="true">
              <rect className="mobile-scroll-frame" x="8" y="3" width="26" height="43" rx="13" />
              <path className="mobile-scroll-path" d="M21 11v24" />
              <circle className="mobile-scroll-dot" cx="21" cy="13" r="2.5" />
              <path className="mobile-scroll-chevron" d="m14 51 7 7 7-7" />
            </svg>
            <span>{lang === "ru" ? "листайте" : "scroll"}</span>
          </a>
        </div>
      </section>

      <DemoVideoSection mobile />

      <section id="mobile-features" className="mobile-feature-section">
        <Reveal>
          <div className="mobile-section-code mobile-section-code-light">
            <span>03</span>
            <span>{m.featuresCode}</span>
          </div>
          <h2 className="mobile-section-title">
            {m.featuresTitle1}
            <br />
            {m.featuresTitle2}
          </h2>
        </Reveal>

        <div className="mobile-feature-list">
          {t.features.items.map((feature, index) => (
            <Reveal key={feature.tag} delay={index * 0.04}>
              <article className="mobile-feature-row">
                <div className="mobile-feature-index">{feature.tag}</div>
                <div>
                  <h3>{feature.title}</h3>
                  <p>{feature.text}</p>
                </div>
              </article>
            </Reveal>
          ))}
        </div>
      </section>

      <section id="mobile-how" className="mobile-process-section">
        <Reveal>
          <div className="mobile-section-code">
            <span>04</span>
            <span>{m.howCode}</span>
          </div>
          <h2 className="mobile-process-title">{m.howTitle}</h2>
        </Reveal>

        <Reveal delay={0.12}>
          <div className="mobile-voice-console">
            <div className="mobile-console-topline">
              <span>INPUT / CHROME</span>
              <span className="mobile-live-dot">REC</span>
            </div>
            <div className="mobile-waveform" aria-hidden="true">
              {WAVE_BARS.map((bar) => (
                <i key={bar} />
              ))}
            </div>
            <div className="mobile-transcript">
              <p>
                <span>EN</span> can you hear me clearly?
              </p>
              <p>
                <span>RU</span> ты меня хорошо слышишь?
              </p>
            </div>
          </div>
        </Reveal>

        <ol className="mobile-steps">
          {m.steps.map((step, i) => (
            <li key={step.title}>
              <span>{String(i + 1).padStart(2, "0")}</span>
              <div>
                <b>{step.title}</b>
                <p>{step.text}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <FAQSection mobile />

      <section id="mobile-download" className="mobile-download-section">
        <LivingEyeMark size={64} className="mobile-download-mark" />
        <Reveal>
          <div className="mobile-section-code mobile-section-code-dark">
            <span>06</span>
            <span>{m.downloadCode}</span>
          </div>
          <h2>{m.downloadTitle}</h2>
          <p>{m.requirements}</p>
        </Reveal>
        <Reveal delay={0.14}>
          <Link href="/download" className="mobile-download-action rounded-2xl">
            <span>{m.downloadBtn}</span>
            <span aria-hidden>↘</span>
          </Link>
        </Reveal>
      </section>

      <footer className="mobile-footer">
        <div>
          <EyeMark size={18} className="text-accent" />
          <span>EYEVOICE © 2026</span>
        </div>
        <div className="mobile-footer-links">
          <Link href="/privacy">{lang === "ru" ? "политика" : "privacy"}</Link>
          <Link href="/terms">{lang === "ru" ? "условия" : "terms"}</Link>
        </div>
        <span>{m.madeFor}</span>
      </footer>
    </main>
  );
}
