import Link from "next/link";
import SiteHeader from "./SiteHeader";
import styles from "./LegalShell.module.css";

type LegalShellProps = {
  eyebrow: string;
  title: string;
  updated: string;
  children: React.ReactNode;
};

export default function LegalShell({ eyebrow, title, updated, children }: LegalShellProps) {
  return (
    <main className={styles.page}>
      <SiteHeader />

      <article className={styles.document}>
        <div className={styles.heading}>
          <p>{eyebrow}</p>
          <h1>{title}</h1>
          <span>Обновлено: {updated}</span>
        </div>

        <aside className={styles.launchNote}>
          <b>Перед публикацией</b>
          <p>
            Укажите полное имя или название оператора, страну регистрации и рабочий email для обращений.
            Это нужно, чтобы документ соответствовал фактической модели работы EyeVoice.
          </p>
        </aside>

        <div className={styles.copy}>{children}</div>
      </article>

      <footer className={styles.footer}>
        <span>EYEVOICE © 2026 · доступно на macOS</span>
        <div>
          <Link href="/privacy">политика</Link>
          <Link href="/terms">условия</Link>
        </div>
      </footer>
    </main>
  );
}
