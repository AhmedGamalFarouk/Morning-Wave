// Email through Brevo's free tier (300 a day, and a single verified sender
// address works without owning a domain).
import type { Email, SendResult } from "./deliver.ts";

export function brevoSender(apiKey: string, from: string, fetchFn: typeof fetch = fetch) {
  return async function send(e: Email): Promise<SendResult> {
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
    if (res.ok) return { ok: true };
    const text = await res.text();
    // A 400 means this email itself is wrong (a bad address). Anything else,
    // like a bad key or rate limiting, can be fixed, so it's retried.
    const permanent = res.status === 400;
    return { ok: false, permanent, error: `brevo ${res.status}: ${text.slice(0, 300)}` };
  };
}
