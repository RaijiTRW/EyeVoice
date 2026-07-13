"use client";

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

export type ProfileSection = "plan" | "limits" | "stats" | "history" | "admin" | "support";

type ProfileSectionState = {
  section: ProfileSection;
  setSection: (section: ProfileSection) => void;
};

const ProfileSectionContext = createContext<ProfileSectionState>({
  section: "plan",
  setSection: () => undefined,
});

export function ProfileSectionProvider({ children }: { children: ReactNode }) {
  const [section, setSection] = useState<ProfileSection>("plan");

  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get("section");
    if (
      requested === "limits" || requested === "stats" || requested === "history" ||
      requested === "admin" || requested === "support"
    ) {
      const timer = window.setTimeout(() => setSection(requested), 0);
      return () => window.clearTimeout(timer);
    }
  }, []);

  const value = useMemo(() => ({ section, setSection }), [section]);

  return (
    <ProfileSectionContext.Provider value={value}>
      {children}
    </ProfileSectionContext.Provider>
  );
}

export function useProfileSection() {
  return useContext(ProfileSectionContext);
}
