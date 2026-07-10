import MobileNav from "./MobileNav";
import Nav from "./Nav";
import styles from "./SiteHeader.module.css";

export default function SiteHeader() {
  return (
    <>
      <Nav className={styles.desktop} />
      <MobileNav className={styles.mobile} />
    </>
  );
}
