"use client";

import { createContext, useContext, useMemo, useState, type ReactNode } from "react";

export type ProfileSection = "plan" | "stats" | "history";

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
