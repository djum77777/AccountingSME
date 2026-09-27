"use client";

export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="centered-page">
      <section className="card auth-card">
        <p className="eyebrow">Request failed</p>
        <h1>Something went wrong</h1>
        <p>
          The request was not completed. No partial financial operation was
          created.
        </p>
        <button className="button primary" onClick={reset} type="button">
          Try again
        </button>
      </section>
    </main>
  );
}
