import type { Metadata } from "next";
import DownloadPage from "@/components/DownloadPage";

export const metadata: Metadata = {
  title: "Скачать EyeVoice",
  description: "Выберите платформу для EyeVoice.",
};

export default function Download() {
  return <DownloadPage />;
}
