import "server-only";

import { cookies } from "next/headers";
import { getDictionary, isLocale, type Locale } from "./dictionaries";

export async function getLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  const value = cookieStore.get("locale")?.value;
  return isLocale(value) ? value : "id";
}

export async function getTranslations() {
  return getDictionary(await getLocale());
}
