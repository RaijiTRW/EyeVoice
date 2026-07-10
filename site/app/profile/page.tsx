import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import Footer from "@/components/Footer";
import ProfileView from "@/components/ProfileView";

export const metadata: Metadata = {
  title: "Профиль — EyeVoice",
};

export default function ProfilePage() {
  return (
    <div className="flex min-h-screen flex-col">
      <SiteHeader />
      <main className="dot-grid flex flex-1 flex-col">
        <ProfileView />
      </main>
      <Footer />
    </div>
  );
}
