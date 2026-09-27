import { OnboardingForm } from "@/components/onboarding-form";
import { getOnboardingData } from "@/data/customization";
import { getTranslations } from "@/lib/i18n/server";

export default async function OnboardingPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, data] = await Promise.all([
    getTranslations(),
    getOnboardingData(organizationId),
  ]);
  return (
    <section className="onboarding-shell">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Phase 2</p>
          <h1>{t.onboarding}</h1>
        </div>
      </div>
      <p className="notice">{t.configurationNotice}</p>
      <div className="card onboarding-card">
        <OnboardingForm
          initialCurrency={data.organization.currency}
          initialLocale={data.organization.locale}
          initialName={data.organization.name}
          labels={t}
          organizationId={organizationId}
          templates={data.templates}
        />
      </div>
    </section>
  );
}
