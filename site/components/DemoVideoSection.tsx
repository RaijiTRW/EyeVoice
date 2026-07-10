"use client";

import styles from "./DemoVideoSection.module.css";
import { Reveal } from "./Reveal";
import { useLang } from "@/lib/i18n";

export default function DemoVideoSection({ mobile = false }: { mobile?: boolean }) {
  const { t } = useLang();
  const headingId = mobile ? "mobile-demo-title" : "demo-title";

  return (
    <section
      id={mobile ? "mobile-demo" : "demo"}
      className={`${styles.section} ${mobile ? styles.mobile : ""}`}
      aria-labelledby={headingId}
    >
      <div className={styles.inner}>
        <Reveal>
          <div className={styles.headingRow}>
            <div>
              <div className={styles.eyebrow}>
                <span>02</span>
                <span>{t.demo.eyebrow}</span>
              </div>
              <h2 id={headingId}>{t.demo.title}</h2>
            </div>
            <p>{t.demo.description}</p>
          </div>
        </Reveal>

        <Reveal delay={0.14}>
          <div className={styles.playerShell}>
            <div className={styles.playerBar} aria-hidden="true">
              <div className={styles.windowDots}>
                <i />
                <i />
                <i />
              </div>
              <span>EYEVOICE</span>
              <span className={styles.offlineStatus}>{t.demo.status}</span>
            </div>

            <div
              className={styles.videoStage}
              role="img"
              aria-label={`${t.demo.unavailable}. ${t.demo.soon}`}
            >
              <div className={styles.edgeSignal} aria-hidden="true" />
              <div className={styles.placeholderContent}>
                <div className={styles.playMark} aria-hidden="true">
                  <span />
                </div>
                <strong>{t.demo.unavailable}</strong>
                <p>{t.demo.soon}</p>
              </div>
              <div className={styles.timeline} aria-hidden="true">
                <span />
                <i>00:00</i>
                <i>--:--</i>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
