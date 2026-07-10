"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import styles from "./FAQSection.module.css";
import { Reveal } from "./Reveal";
import { useLang } from "@/lib/i18n";

export default function FAQSection({ mobile = false }: { mobile?: boolean }) {
  const { t } = useLang();
  const [openItems, setOpenItems] = useState<number[]>([]);
  const headingId = mobile ? "mobile-faq-title" : "faq-title";

  const toggleItem = (index: number) => {
    setOpenItems((current) =>
      current.includes(index)
        ? current.filter((item) => item !== index)
        : [...current, index],
    );
  };

  return (
    <section
      id={mobile ? "mobile-faq" : "faq"}
      className={`${styles.section} ${mobile ? styles.mobile : ""}`}
      aria-labelledby={headingId}
    >
      <div className={styles.inner}>
        <Reveal>
          <div className={styles.heading}>
            <div className={styles.eyebrow}>
              <span>{mobile ? "05" : "FAQ"}</span>
              <span>{t.faq.eyebrow}</span>
            </div>
            <h2 id={headingId}>{t.faq.title}</h2>
            <p>{t.faq.intro}</p>
          </div>
        </Reveal>

        <div className={styles.list}>
          {t.faq.items.map((item, index) => (
            <Reveal key={item.question} delay={index * 0.04}>
              <div
                className={styles.item}
                data-open={openItems.includes(index)}
              >
                <button
                  type="button"
                  className={styles.summary}
                  aria-expanded={openItems.includes(index)}
                  aria-controls={`${headingId}-answer-${index}`}
                  onClick={() => toggleItem(index)}
                >
                  <span>{String(index + 1).padStart(2, "0")}</span>
                  <strong>{item.question}</strong>
                  <i aria-hidden="true" />
                </button>
                <AnimatePresence initial={false}>
                  {openItems.includes(index) ? (
                    <motion.div
                      id={`${headingId}-answer-${index}`}
                      className={styles.answerClip}
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: "auto", opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{
                        height: { duration: 0.3, ease: [0.22, 1, 0.36, 1] },
                        opacity: { duration: 0.2, ease: "easeOut" },
                      }}
                    >
                      <div className={styles.answer}>
                        <p>{item.answer}</p>
                      </div>
                    </motion.div>
                  ) : null}
                </AnimatePresence>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
