import type { Metadata } from "next";
import SiteHeader from "@/components/SiteHeader";
import Footer from "@/components/Footer";
import AuthForm from "@/components/AuthForm";

export const metadata: Metadata = {
  title: "Регистрация — EyeVoice",
};

export default function SignupPage() {
  return (
    <div className="flex min-h-screen flex-col">
      <SiteHeader />
      <main className="dot-grid flex flex-1 items-center justify-center px-6 py-10 md:py-12">
        <AuthForm mode="signup" />
      </main>
      <Footer />
    </div>
  );
}
