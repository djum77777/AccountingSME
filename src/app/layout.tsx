import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { LanguageSwitcher } from "@/components/language-switcher";
import { getLocale, getTranslations } from "@/lib/i18n/server";

export const metadata: Metadata = {
  title: "Buku Usaha",
  description: "Secure accounting foundation for Indonesian SMEs.",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const [locale, translations] = await Promise.all([
    getLocale(),
    getTranslations(),
  ]);

  return (
    <html lang={locale}>
      <body>
        <header className="site-header">
          <Link className="brand" href="/">
            {translations.appName}
          </Link>
          <LanguageSwitcher locale={locale} />
        </header>
        {children}
      </body>
    </html>
  );
}
