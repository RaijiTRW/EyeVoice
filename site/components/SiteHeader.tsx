import MobileNav from "./MobileNav";
import Nav from "./Nav";
import styles from "./SiteHeader.module.css";

export default function SiteHeader({ profileMode = false }: { profileMode?: boolean }) {
  return (
    <>
      <Nav className={styles.desktop} profileMode={profileMode} />
      <MobileNav className={styles.mobile} profileMode={profileMode} />
    </>
  );
}
