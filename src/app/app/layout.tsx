import Link from "next/link";
import { logout } from "@/app/actions/auth";
import { getTranslations } from "@/lib/i18n/server";

export default async function AuthenticatedLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const t = await getTranslations();
  return (
    <div className="app-frame">
      <aside className="app-sidebar">
        <div>
          <p className="eyebrow">Phase 2</p>
          <nav>
            <Link href="/app">{t.dashboard}</Link>
            <Link href="/setup">{t.createOrganization}</Link>
          </nav>
        </div>
        <form action={logout}>
          <button className="button secondary full" type="submit">
            {t.logout}
          </button>
        </form>
      </aside>
      <main className="app-content">{children}</main>
    </div>
  );
}
