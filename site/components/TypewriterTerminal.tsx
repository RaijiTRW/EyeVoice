"use client";

import { useEffect, useMemo, useState } from "react";
import { useReducedMotion } from "framer-motion";

type Segment = {
  text: string;
  className?: string;
};

export type TypewriterLine = {
  segments: Segment[];
};

export default function TypewriterTerminal({ lines }: { lines: TypewriterLine[] }) {
  const reducedMotion = useReducedMotion();
  const signature = lines.map((line) => line.segments.map((segment) => segment.text).join("")).join("\n");
  const { lineEnds, totalCharacters } = useMemo(() => {
    let total = 0;
    const ends = lines.map((line) => {
      total += line.segments.reduce((sum, segment) => sum + segment.text.length, 0);
      return total;
    });

    return { lineEnds: ends, totalCharacters: total };
  }, [signature]);
  const [visibleCharacters, setVisibleCharacters] = useState(0);

  useEffect(() => {
    setVisibleCharacters(reducedMotion ? totalCharacters : 0);
  }, [reducedMotion, signature, totalCharacters]);

  useEffect(() => {
    if (reducedMotion || totalCharacters === 0) return;

    const atLineEnd = lineEnds.includes(visibleCharacters) && visibleCharacters < totalCharacters;
    const delay = visibleCharacters >= totalCharacters ? 1500 : atLineEnd ? 420 : 28;
    const timer = window.setTimeout(() => {
      setVisibleCharacters((current) => (current >= totalCharacters ? 0 : current + 1));
    }, delay);

    return () => window.clearTimeout(timer);
  }, [lineEnds, reducedMotion, totalCharacters, visibleCharacters]);

  const activeLine = Math.min(
    lines.length - 1,
    lineEnds.findIndex((end) => visibleCharacters <= end) === -1
      ? lines.length - 1
      : lineEnds.findIndex((end) => visibleCharacters <= end),
  );

  return (
    <div aria-label={signature}>
      {lines.map((line, lineIndex) => {
        const lineStart = lineIndex === 0 ? 0 : lineEnds[lineIndex - 1];
        let remaining = Math.max(0, visibleCharacters - lineStart);

        return (
          <div key={`${signature}-${lineIndex}`} aria-hidden="true" className="min-h-[1.95em]">
            {line.segments.map((segment, segmentIndex) => {
              const visibleText = segment.text.slice(0, remaining);
              remaining = Math.max(0, remaining - segment.text.length);

              return (
                <span key={`${segment.text}-${segmentIndex}`} className={segment.className}>
                  {visibleText}
                </span>
              );
            })}
            {!reducedMotion && activeLine === lineIndex ? (
              <span className="ml-1 inline-block h-4 w-2 animate-pulse bg-ink align-middle" />
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
