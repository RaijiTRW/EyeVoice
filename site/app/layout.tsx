import type { Metadata } from "next";
import { Geist_Mono } from "next/font/google";
import { LangProvider } from "@/lib/i18n";
import "./globals.css";

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin", "cyrillic"],
});

export const metadata: Metadata = {
  title: "EyeVoice — синхронный перевод любого звука на Mac",
  description:
    "EyeVoice слушает микрофон, систему или отдельное приложение и переводит речь голосом в реальном времени. Задержка около секунды.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru" className={`${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <LangProvider>{children}</LangProvider>
      </body>
    </html>
  );
}
