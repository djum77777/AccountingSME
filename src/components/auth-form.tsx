"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/browser";
import { getPublicEnvironment } from "@/lib/env/public";

type Mode = "login" | "signup" | "forgot" | "update";

export function AuthForm({
  mode,
  labels,
}: {
  mode: Mode;
  labels: {
    email: string;
    password: string;
    submit: string;
    google?: string;
  };
}) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");

    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "");
    const password = String(form.get("password") ?? "");
    const supabase = createClient();
    const appUrl = getPublicEnvironment().NEXT_PUBLIC_APP_URL;

    let error: Error | null = null;
    if (mode === "login") {
      ({ error } = await supabase.auth.signInWithPassword({ email, password }));
    } else if (mode === "signup") {
      ({ error } = await supabase.auth.signUp({
        email,
        password,
        options: { emailRedirectTo: `${appUrl}/auth/callback` },
      }));
    } else if (mode === "forgot") {
      ({ error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${appUrl}/auth/callback?next=/update-password`,
      }));
    } else {
      ({ error } = await supabase.auth.updateUser({ password }));
    }

    setBusy(false);
    if (error) {
      setMessage(error.message);
      return;
    }

    if (mode === "forgot" || mode === "signup") {
      setMessage("Check your email to continue.");
      return;
    }
    router.push("/app");
    router.refresh();
  }

  async function signInWithGoogle() {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${getPublicEnvironment().NEXT_PUBLIC_APP_URL}/auth/callback`,
      },
    });
    if (error) {
      setMessage(error.message);
      setBusy(false);
    }
  }

  return (
    <div className="auth-panel">
      <form onSubmit={submit}>
        {mode !== "update" ? (
          <label>
            {labels.email}
            <input autoComplete="email" name="email" required type="email" />
          </label>
        ) : null}
        {mode !== "forgot" ? (
          <label>
            {labels.password}
            <input
              autoComplete={
                mode === "login" ? "current-password" : "new-password"
              }
              minLength={10}
              name="password"
              required
              type="password"
            />
          </label>
        ) : null}
        <button className="button primary full" disabled={busy} type="submit">
          {labels.submit}
        </button>
      </form>
      {labels.google && mode !== "forgot" && mode !== "update" ? (
        <button
          className="button secondary full"
          disabled={busy}
          onClick={signInWithGoogle}
          type="button"
        >
          {labels.google}
        </button>
      ) : null}
      {message ? <p className="form-message">{message}</p> : null}
    </div>
  );
}
