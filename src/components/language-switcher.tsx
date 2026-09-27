import { setLocale } from "@/lib/i18n/actions";
import type { Locale } from "@/lib/i18n/dictionaries";

export function LanguageSwitcher({ locale }: { locale: Locale }) {
  return (
    <form action={setLocale} className="language-switcher">
      <button
        aria-label="Gunakan Bahasa Indonesia"
        className={locale === "id" ? "active" : ""}
        name="locale"
        type="submit"
        value="id"
      >
        ID
      </button>
      <span aria-hidden="true">/</span>
      <button
        aria-label="Use English"
        className={locale === "en" ? "active" : ""}
        name="locale"
        type="submit"
        value="en"
      >
        EN
      </button>
    </form>
  );
}
