// Email through Brevo's free tier (300 a day, and a single verified sender
// address works without owning a domain).
import type { Email, Outcome } from "./deliver.ts";

export function brevoSender(apiKey: string, from: string, fetchFn: typeof fetch = fetch) {
  return async function send(e: Email): Promise<Outcome> {
    // One request with a version per recipient: each child gets their own
    // copy without seeing the others' addresses, and it all goes or none does.
    const res = await fetchFn("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": apiKey, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        sender: { email: from, name: "Morning Wave" },
        subject: e.subject,
        textContent: e.text,
        htmlContent: e.html,
        messageVersions: e.to.map((to) => ({ to: [to] })),
      }),
    });
    if (res.ok) return { kind: "sent" };
    const text = await res.text();
    // Only a bad recipient address is hopeless. Setup mistakes (an unverified
    // sender, a bad key) and rate limits can be fixed, so they're retried
    // until the 12-hour cutoff.
    const error = `brevo ${res.status}: ${text.slice(0, 300)}`;
    return res.status === 400 && isBadRecipient(text) ? { kind: "failed", error } : { kind: "retry", error };
  };
}

function isBadRecipient(body: string): boolean {
  try {
    const { code, message } = JSON.parse(body);
    return code === "invalid_parameter" && /email|recipient|\bto\b/i.test(message) &&
      !/sender/i.test(message);
  } catch {
    return false;
  }
}
