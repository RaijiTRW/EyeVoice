"use client";

import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import { supabase } from "@/lib/supabase";

const SESSION_KEY = "eyevoice_analytics_session";

function getSessionId() {
  const saved = window.sessionStorage.getItem(SESSION_KEY);
  if (saved) return saved;
  const created = crypto.randomUUID();
  window.sessionStorage.setItem(SESSION_KEY, created);
  return created;
}

function cleanLabel(value: string) {
  return value.replace(/\s+/g, " ").trim().slice(0, 120);
}

function referrerHost() {
  if (!document.referrer) return null;
  try {
    const host = new URL(document.referrer).host;
    return host === window.location.host ? null : host;
  } catch {
    return null;
  }
}

export default function AnalyticsTracker() {
  const pathname = usePathname();
  const lastClick = useRef({ key: "", at: 0 });

  useEffect(() => {
    if (!pathname) return;
    const dedupeKey = `eyevoice_page_view:${pathname}`;
    if (window.sessionStorage.getItem(dedupeKey)) return;
    window.sessionStorage.setItem(dedupeKey, "1");

    void supabase.rpc("track_site_event", {
      p_session_id: getSessionId(),
      p_event_type: "page_view",
      p_event_name: pathname,
      p_page_path: pathname,
      p_referrer_host: referrerHost(),
      p_metadata: {
        language: document.documentElement.lang,
        viewport: window.innerWidth < 768 ? "mobile" : "desktop",
      },
    });
  }, [pathname]);

  useEffect(() => {
    const trackClick = (event: MouseEvent) => {
      const origin = event.target;
      if (!(origin instanceof Element)) return;
      const target = origin.closest<HTMLElement>("a,button,[data-analytics-event]");
      if (!target || target.closest("[data-analytics-ignore]")) return;

      const explicit = target.dataset.analyticsEvent;
      const href = target instanceof HTMLAnchorElement ? target.getAttribute("href") : null;
      const label = cleanLabel(
        explicit || target.getAttribute("aria-label") || target.textContent || href || "interaction",
      );
      if (!label) return;

      const key = `${pathname}:${label}`;
      const now = Date.now();
      if (lastClick.current.key === key && now - lastClick.current.at < 750) return;
      lastClick.current = { key, at: now };

      void supabase.rpc("track_site_event", {
        p_session_id: getSessionId(),
        p_event_type: "click",
        p_event_name: label,
        p_page_path: pathname || window.location.pathname,
        p_referrer_host: null,
        p_metadata: {
          element: target.tagName.toLowerCase(),
          destination: href?.startsWith("/") ? href.slice(0, 180) : null,
        },
      });
    };

    document.addEventListener("click", trackClick, { capture: true });
    return () => document.removeEventListener("click", trackClick, { capture: true });
  }, [pathname]);

  return null;
}

