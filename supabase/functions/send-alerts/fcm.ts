// FCM HTTP v1: trade the service account for a Google access token, then
// send one message per call.
import type { Outcome, Push } from "./deliver.ts";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

type Fetch = typeof fetch;

export function fcmSender(account: ServiceAccount, fetchFn: Fetch = fetch) {
  let cached: { token: string; expires: number } | null = null;

  async function accessToken(): Promise<string> {
    if (cached && cached.expires > Date.now() + 60_000) return cached.token;
    const res = await fetchFn("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: await signedJwt(account),
      }),
    });
    if (!res.ok) throw new Error(`google token ${res.status}: ${await res.text()}`);
    const json = await res.json();
    cached = { token: json.access_token, expires: Date.now() + json.expires_in * 1000 };
    return cached.token;
  }

  return async function send(p: Push): Promise<Outcome> {
    const res = await fetchFn(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${await accessToken()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: p.token,
            notification: { title: p.title, body: p.body },
            data: p.data,
            android: {
              // High priority wakes a dozing phone; the app's "urgent"
              // channel can pass Do Not Disturb. The parent's nudge uses a
              // quieter channel.
              priority: "HIGH",
              notification: { channel_id: p.urgent ? "urgent" : "gentle", tag: p.tag },
            },
          },
        }),
      },
    );
    if (res.ok) return { kind: "sent" };
    const text = await res.text();
    // A token that's gone (app removed, data cleared) won't come back by retrying.
    const gone = res.status === 404 || text.includes("UNREGISTERED") ||
      (res.status === 400 && text.includes("registration token"));
    const error = `fcm ${res.status}: ${text.slice(0, 300)}`;
    return gone ? { kind: "failed", error, deadToken: p.token } : { kind: "retry", error };
  };
}

async function signedJwt(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(new Uint8Array(sig))}`;
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
