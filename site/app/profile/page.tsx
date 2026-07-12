import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import ProfileView from "@/components/ProfileView";
import { ProfileSectionProvider } from "@/lib/profile-section";

export const metadata: Metadata = {
  title: "Профиль — EyeVoice",
};

export default function ProfilePage() {
  return (
    <ProfileSectionProvider>
      <div className="flex min-h-dvh flex-col md:h-dvh md:overflow-hidden">
        <SiteHeader profileMode />
        <main className="dot-grid flex flex-1 flex-col md:min-h-0 md:overflow-hidden">
          <ProfileView />
        </main>
      </div>
    </ProfileSectionProvider>
  );
}
