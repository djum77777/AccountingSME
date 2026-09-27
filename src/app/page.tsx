import Link from "next/link";
import { redirect } from "next/navigation";
import { getTranslations } from "@/lib/i18n/server";
import { createClient } from "@/lib/supabase/server";

export default async function HomePage() {
  const [translations, supabase] = await Promise.all([
    getTranslations(),
    createClient(),
  ]);
  const { data } = await supabase.auth.getClaims();
  if (data?.claims) redirect("/app");

  return (
    <main className="hero page-shell">
      <div>
        <p className="eyebrow">UMKM · Secure by design</p>
        <h1>{translations.tagline}</h1>
        <p className="lede">{translations.phaseNotice}</p>
        <div className="button-row">
          <Link className="button primary" href="/login">
            {translations.login}
          </Link>
          <Link className="button secondary" href="/signup">
            {translations.signup}
          </Link>
        </div>
      </div>
      <aside className="hero-card" aria-label="Phase 2 scope">
        <span>01</span>
        <strong>{translations.onboarding}</strong>
        <span>02</span>
        <strong>{translations.recommendedTemplate}</strong>
        <span>03</span>
        <strong>{translations.customization}</strong>
      </aside>
    </main>
  );
}
