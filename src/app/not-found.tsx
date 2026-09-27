import Link from "next/link";

export default function NotFoundPage() {
  return (
    <main className="centered-page">
      <section className="card auth-card">
        <p className="eyebrow">404</p>
        <h1>Page not found</h1>
        <Link className="button primary" href="/">
          Return home
        </Link>
      </section>
    </main>
  );
}
