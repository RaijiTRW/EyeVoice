"use client";

import {
  motion,
  useReducedMotion,
  useScroll,
  useSpring,
  useTransform,
} from "framer-motion";
import type { ReactNode } from "react";
import { useRef } from "react";

const ease = [0.16, 1, 0.3, 1] as const;

export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  const reducedMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={
        reducedMotion
          ? false
          : { opacity: 0, y: 34, scale: 0.985, filter: "blur(10px)" }
      }
      whileInView={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
      viewport={{ once: true, margin: "-72px" }}
      transition={{ duration: 0.82, delay, ease }}
    >
      {children}
    </motion.div>
  );
}

/** Headline that reveals word by word. */
export function Words({
  text,
  className,
  delay = 0,
}: {
  text: string;
  className?: string;
  delay?: number;
}) {
  const reducedMotion = useReducedMotion();
  const words = text.split(" ");

  return (
    <span className={className} aria-label={text}>
      {words.map((word, i) => (
        <span key={i} className="inline-block overflow-hidden pb-1 align-bottom">
          <motion.span
            className="inline-block"
            initial={
              reducedMotion
                ? false
                : {
                    y: "115%",
                    opacity: 0,
                    rotate: 2,
                    filter: "blur(8px)",
                  }
            }
            animate={{ y: 0, opacity: 1, rotate: 0, filter: "blur(0px)" }}
            transition={{ duration: 0.78, delay: delay + i * 0.075, ease }}
          >
            {word}
            {i < words.length - 1 ? " " : ""}
          </motion.span>
        </span>
      ))}
    </span>
  );
}

export function KineticLines({
  id,
  className,
  lines,
  delay = 0.08,
}: {
  id?: string;
  className?: string;
  lines: Array<{ text: string; accent?: boolean }>;
  delay?: number;
}) {
  const reducedMotion = useReducedMotion();

  return (
    <h1 id={id} className={className}>
      {lines.map((line, index) => (
        <motion.span
          key={line.text}
          className={line.accent ? "mobile-display-accent" : undefined}
          initial={
            reducedMotion
              ? false
              : {
                  y: "112%",
                  opacity: 0,
                  rotate: index % 2 === 0 ? 2 : -2,
                  filter: "blur(8px)",
                }
          }
          animate={{ y: 0, opacity: 1, rotate: 0, filter: "blur(0px)" }}
          transition={{
            duration: 0.82,
            delay: delay + index * 0.12,
            ease,
          }}
        >
          {line.text}
        </motion.span>
      ))}
    </h1>
  );
}

export function ParallaxLayer({
  children,
  className,
  distance = 40,
}: {
  children: ReactNode;
  className?: string;
  distance?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const reducedMotion = useReducedMotion();
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  const rawY = useTransform(scrollYProgress, [0, 1], [-distance, distance]);
  const y = useSpring(rawY, { stiffness: 110, damping: 24, mass: 0.45 });

  return (
    <motion.div
      ref={ref}
      className={className}
      style={{ y: reducedMotion ? 0 : y }}
    >
      {children}
    </motion.div>
  );
}

export function ScrollProgressBar() {
  const reducedMotion = useReducedMotion();
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, {
    stiffness: 130,
    damping: 28,
    mass: 0.35,
  });

  if (reducedMotion) return null;

  return <motion.div className="scroll-progress" style={{ scaleX }} />;
}
