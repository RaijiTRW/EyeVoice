import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import Footer from "@/components/Footer";
import AuthForm from "@/components/AuthForm";

export const metadata: Metadata = {
  title: "Вход — EyeVoice",
};

export default function LoginPage() {
  return (
    <div className="flex min-h-screen flex-col">
      <SiteHeader />
      <main className="dot-grid flex flex-1 items-center justify-center px-6 py-10 md:py-12">
        <AuthForm mode="login" />
      </main>
      <Footer />
    </div>
  );
}
