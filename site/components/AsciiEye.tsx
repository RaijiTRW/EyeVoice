"use client";

import { useEffect, useRef } from "react";

// deterministic per-cell noise so the pattern is stable between frames
function hash(x: number, y: number) {
  const h = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return h - Math.floor(h);
}

/**
 * The EyeVoice mark, alive: ASCII 4-point star with an eye whose pupil
 * follows the cursor, blinks and softly shimmers.
 */
export default function AsciiEye({
  className,
  cols = 62,
  rows = 36,
  cell = 13,
}: {
  className?: string;
  cols?: number;
  rows?: number;
  cell?: number;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const mouse = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const W = cols * cell;
    const H = rows * cell;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    canvas.style.width = `${W}px`;
    canvas.style.height = `${H}px`;
    ctx.scale(dpr, dpr);
    ctx.font = `600 ${cell - 1}px ui-monospace, monospace`;
    ctx.textBaseline = "top";

    const onMove = (e: MouseEvent) => {
      const r = canvas.getBoundingClientRect();
      mouse.current.x = ((e.clientX - r.left) / r.width) * 2 - 1;
      mouse.current.y = ((e.clientY - r.top) / r.height) * 2 - 1;
    };
    window.addEventListener("mousemove", onMove);

    let raf = 0;
    const draw = (tms: number) => {
      const t = tms / 1000;
      ctx.clearRect(0, 0, W, H);

      // blink: quick close-and-open every ~4.6s
      const phase = t % 4.6;
      const blink =
        phase < 0.28
          ? Math.max(0.06, Math.abs(Math.cos(Math.PI * (phase / 0.28))))
          : 1;

      // pupil drifts toward the cursor
      const px = Math.max(-1, Math.min(1, mouse.current.x)) * 0.13;
      const py = Math.max(-1, Math.min(1, mouse.current.y)) * 0.1;

      for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols; col++) {
          // both axes scale from the grid height so the eye keeps the icon's
          // proportions regardless of how wide the canvas is
          const nx = (col - cols / 2) / (rows * 0.42);
          const ny = (row - rows / 2) / (rows * 0.36);
          const r1 = hash(col, row);
          const r2 = hash(col + 91, row + 17);
          const flicker = 0.75 + 0.25 * Math.sin(t * 2.2 + r1 * 6.28);

          const star = Math.pow(Math.abs(nx), 0.7) + Math.pow(Math.abs(ny), 0.7);
          const lensHalfW = 0.72;
          const lensY =
            Math.abs(nx) < lensHalfW
              ? 0.38 *
                blink *
                Math.pow(Math.max(0, 1 - (nx / lensHalfW) ** 2), 0.72)
              : 0;
          const inLens = Math.abs(ny) < lensY;
          const ix = nx - px;
          const iy = ny - py;
          const r = Math.sqrt(ix * ix + iy * iy * 1.15);

          let char = "";
          let color = "";

          if (inLens) {
            if (r < 0.12 * blink) continue; // pupil — pure black
            if (r < 0.3) {
              if (r1 < 0.88) {
                char = r2 > 0.5 ? "#" : "+";
                const a = (0.5 + 0.5 * r2) * flicker;
                color = `rgba(255,79,163,${a})`;
                if (ix < -0.05 && iy < -0.06 && r < 0.22 && r2 > 0.72) {
                  color = `rgba(255,255,255,${a})`;
                }
              }
            } else {
              const edge = lensY - Math.abs(ny);
              if (edge < 0.05) {
                if (r1 < 0.85) {
                  char = ":";
                  color = `rgba(240,240,240,${0.8 * flicker})`;
                }
              } else if (r1 < 0.1) {
                char = r2 < 0.5 ? "." : ":";
                color = `rgba(160,160,160,${0.5 * flicker})`;
              }
            }
          } else if (star < 1.0) {
            const base = Math.min(1, (1 - star) * 2.2);
            if (r1 < 0.72 + base * 0.28) {
              const d = base * (0.55 + 0.45 * r2);
              char = d > 0.6 ? "#" : d > 0.38 ? "+" : d > 0.2 ? ":" : ".";
              const b = Math.min(1, 0.55 + base * 0.35) * flicker;
              color = `rgba(235,235,235,${b * 0.9})`;
            }
          } else if (star < 1.5 && r1 < 0.04) {
            char = ".";
            color = `rgba(150,150,150,${0.4 * flicker})`;
          }

          if (char) {
            ctx.fillStyle = color;
            ctx.fillText(char, col * cell, row * cell);
          }
        }
      }
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("mousemove", onMove);
    };
  }, [cols, rows, cell]);

  return <canvas ref={canvasRef} className={className} aria-hidden />;
}
