"use client";

import Link from "next/link";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import AsciiEye from "@/components/AsciiEye";
import DemoVideoSection from "@/components/DemoVideoSection";
import FAQSection from "@/components/FAQSection";
import HeroSignalField from "@/components/HeroSignalField";
import MobileHome from "@/components/MobileHome";
import {
  ParallaxLayer,
  Reveal,
  ScrollProgressBar,
  Words,
} from "@/components/Reveal";
import { useLang } from "@/lib/i18n";

export default function Home() {
  const { t, lang } = useLang();

  return (
    <>
      <ScrollProgressBar />
      <MobileHome />
      <div className="hidden min-h-screen flex-col md:flex">
        <Nav />

      {/* hero: exactly one viewport tall — the eye is a live backdrop up top,
          text is pinned to the lower part so it's always visible on load */}
      <section className="dot-grid relative flex min-h-[calc(100vh-65px)] flex-col justify-end overflow-hidden pb-14">
        <HeroSignalField />
        <ParallaxLayer
          className="pointer-events-none absolute inset-x-0 -top-32 z-[3] flex justify-center md:-top-48"
          distance={34}
        >
          <AsciiEye
            cols={96}
            rows={52}
            cell={13}
            className="origin-top scale-[0.9] opacity-100 xl:scale-100"
          />
        </ParallaxLayer>
        {/* soft fade so the text stays readable over the eye's lower half */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 z-[2] h-[480px] bg-[radial-gradient(ellipse_55%_65%_at_50%_60%,rgba(5,5,5,0.8),transparent_72%)]" />

        <div className="relative z-10 mx-auto w-full max-w-5xl px-6 text-center">
          <Reveal>
            <div className="mb-4">
              <span className="hero-kicker">{t.hero.kicker}</span>
            </div>
          </Reveal>
          <h1
            key={`h1-${lang}`}
            className="mx-auto max-w-[30ch] text-[clamp(2.35rem,4.5vw,3.4rem)] font-bold leading-[1.02] tracking-[-0.05em]"
          >
            <Words text={t.hero.h1a} delay={0.1} />
            <br />
            <Words text={t.hero.h1b} delay={0.45} />
          </h1>
          <Reveal delay={0.7}>
            <p className="mx-auto mt-4 max-w-lg text-[14px] leading-relaxed text-dim">
              {t.hero.lead}
            </p>
          </Reveal>
          <Reveal delay={0.85}>
            <div className="mt-7 flex flex-wrap items-center justify-center gap-4">
              <a href="#download" className="btn btn-primary btn-accent">
                {t.hero.download}
              </a>
              <Link href="/signup" className="btn">
                {t.hero.createAccount}
              </Link>
            </div>
            <div className="mt-3 text-[11px] uppercase tracking-widest text-faint">
              {t.hero.requirements}
            </div>
            <a
              href="#demo"
              className="hero-scroll-cue"
              aria-label={lang === "ru" ? "Прокрутить к примеру работы" : "Scroll to the product example"}
            >
              <span className="hero-scroll-mouse" aria-hidden="true">
                <i />
              </span>
            </a>
          </Reveal>
        </div>
      </section>

      <DemoVideoSection />

      {/* features */}
      <section id="features" className="border-t border-line/60">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <Reveal>
            <h2 className="mb-3 text-[12px] uppercase tracking-[0.25em] text-faint">
              {t.features.heading}
            </h2>
            <p className="mb-12 text-2xl font-bold tracking-tight md:text-3xl">
              {t.features.subtitle}
            </p>
          </Reveal>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {t.features.items.map((f, i) => (
              <Reveal key={f.tag} delay={i * 0.08}>
                <div className="group h-full rounded-xl border border-line bg-panel/50 p-6 transition-all duration-300 hover:-translate-y-1 hover:border-ink/60">
                  <div className="mb-4 flex items-center justify-between">
                    <span className="text-[11px] text-faint">[{f.tag}]</span>
                    <span className="text-[11px] text-faint opacity-0 transition-opacity duration-300 group-hover:text-accent group-hover:opacity-100">
                      [x]
                    </span>
                  </div>
                  <div className="mb-2 text-sm font-bold tracking-widest">
                    {f.title}
                  </div>
                  <p className="text-[13px] leading-relaxed text-dim">{f.text}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* how it works */}
      <section id="how" className="border-t border-line/60">
        <div className="mx-auto max-w-6xl px-6 py-24">
          <Reveal>
            <h2 className="mb-3 text-[12px] uppercase tracking-[0.25em] text-faint">
              {t.how.heading}
            </h2>
            <p className="mb-12 text-2xl font-bold tracking-tight md:text-3xl">
              {t.how.subtitle}
            </p>
          </Reveal>
          <Reveal delay={0.15}>
            <div className="mx-auto max-w-2xl rounded-xl border border-line bg-panel/50 p-8 text-[14px] leading-loose">
              <div>
                <span className="text-faint">$</span> {t.how.step1}{" "}
                <span className="text-faint">→</span> {t.how.step1val}
              </div>
              <div>
                <span className="text-faint">$</span> {t.how.step2}{" "}
                <span className="text-faint">→</span> {t.how.step2val}
              </div>
              <div>
                <span className="text-faint">$</span>{" "}
                <span className="text-accent">{t.how.step3}</span>{" "}
                <span className="text-faint">→</span> {t.how.step3val}
                <span className="ml-1 inline-block h-4 w-2 animate-pulse bg-ink align-middle" />
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      <FAQSection />

      {/* CTA */}
      <section id="download" className="border-t border-line/60">
        <div className="mx-auto max-w-6xl px-6 py-28 text-center">
          <Reveal>
            <h2 className="text-3xl font-bold tracking-tight md:text-4xl">
              {t.cta.title}
            </h2>
          </Reveal>
          <Reveal delay={0.15}>
            <p className="mx-auto mt-4 max-w-md text-[14px] text-dim">
              {t.cta.text}
            </p>
          </Reveal>
          <Reveal delay={0.3}>
            <div className="mt-10 flex justify-center gap-4">
              <Link href="/download" className="btn btn-primary btn-accent">
                {t.cta.download}
              </Link>
              <Link href="/signup" className="btn">
                {t.cta.signup}
              </Link>
            </div>
          </Reveal>
        </div>
      </section>

      <Footer />
      </div>
    </>
  );
}
