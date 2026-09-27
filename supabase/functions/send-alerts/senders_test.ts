import assert from "node:assert/strict";
import { fcmSender } from "./fcm.ts";
import { brevoSender } from "./email.ts";
import { postgrest } from "./db.ts";

type Call = { url: string; init: RequestInit };

function mockFetch(respond: (url: string) => Response) {
  const calls: Call[] = [];
  const fn = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(respond(url));
  }) as unknown as typeof fetch;
  return { fn, calls };
}

async function testAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...der))
  }\n-----END PRIVATE KEY-----\n`;
  return {
    account: { project_id: "mw-test", client_email: "fcm@mw-test.iam", private_key: pem },
    publicKey: pair.publicKey,
  };
}

const push = { token: "tok", title: "t", body: "b", urgent: true, tag: "a1", data: { step: "2" } };
const tokenOk = () => Response.json({ access_token: "ya29.test", expires_in: 3600 });

Deno.test("fcm: signs a valid JWT, sends a high-priority urgent message, reuses the token", async () => {
  const { account, publicKey } = await testAccount();
  const m = mockFetch((url) => url.includes("oauth2") ? tokenOk() : Response.json({ name: "x" }));
  const send = fcmSender(account, m.fn);

  assert.deepEqual(await send(push), { kind: "sent" });
  assert.deepEqual(await send({ ...push, urgent: false }), { kind: "sent" });
  assert.equal(m.calls.filter((c) => c.url.includes("oauth2")).length, 1);

  const assertion = new URLSearchParams(m.calls[0].init.body as URLSearchParams).get("assertion")!;
  const [h, c, s] = assertion.split(".");
  const b64 = (x: string) =>
    Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/")), (ch) => ch.charCodeAt(0));
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    b64(s),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert.ok(valid);
  const claims = JSON.parse(new TextDecoder().decode(b64(c)));
  assert.equal(claims.iss, "fcm@mw-test.iam");
  assert.equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");

  const [first, second] = m.calls.filter((c) => c.url.includes("fcm.googleapis.com"));
  assert.equal(first.url, "https://fcm.googleapis.com/v1/projects/mw-test/messages:send");
  assert.equal((first.init.headers as Record<string, string>).authorization, "Bearer ya29.test");
  const msg = JSON.parse(first.init.body as string).message;
  assert.equal(msg.token, "tok");
  assert.equal(msg.android.priority, "HIGH");
  assert.equal(msg.android.notification.channel_id, "urgent");
  assert.equal(msg.android.notification.tag, "a1");
  assert.equal(JSON.parse(second.init.body as string).message.android.notification.channel_id, "gentle");
});

Deno.test("fcm: an unregistered token is permanent, a 503 is retried", async () => {
  const { account } = await testAccount();
  const m = mockFetch((url) =>
    url.includes("oauth2")
      ? tokenOk()
      : new Response('{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}', { status: 404 })
  );
  const gone = await fcmSender(account, m.fn)(push);
  assert.equal(gone.kind, "failed");
  assert.equal(gone.kind === "failed" && gone.deadToken, "tok");
  const m2 = mockFetch((url) =>
    url.includes("oauth2") ? tokenOk() : new Response("unavailable", { status: 503 })
  );
  const retry = await fcmSender(account, m2.fn)(push);
  assert.equal(retry.kind, "retry");
});

Deno.test("fcm: a failed Google token exchange throws, so the alert is retried", async () => {
  const { account } = await testAccount();
  const m = mockFetch(() => new Response("invalid_grant", { status: 400 }));
  await assert.rejects(fcmSender(account, m.fn)(push), /google token 400/);
});

const email = { to: [{ email: "sam@x.test", name: "Sam" }], subject: "s", text: "t", html: "<p>t</p>" };

Deno.test("brevo: one request, one version per recipient", async () => {
  const m = mockFetch(() => Response.json({ messageIds: ["a", "b"] }, { status: 201 }));
  const res = await brevoSender("key", "hello@mw.test", m.fn)({
    ...email,
    to: [...email.to, { email: "lee@x.test", name: "Lee" }],
  });
  assert.deepEqual(res, { kind: "sent" });
  assert.equal(m.calls.length, 1);
  assert.equal((m.calls[0].init.headers as Record<string, string>)["api-key"], "key");
  const body = JSON.parse(m.calls[0].init.body as string);
  assert.deepEqual(body.sender, { email: "hello@mw.test", name: "Morning Wave" });
  assert.equal(body.subject, "s");
  assert.deepEqual(body.messageVersions, [
    { to: [{ email: "sam@x.test", name: "Sam" }] },
    { to: [{ email: "lee@x.test", name: "Lee" }] },
  ]);
});

Deno.test("brevo: only a bad recipient address is permanent", async () => {
  const bad = (message: string) => JSON.stringify({ code: "invalid_parameter", message });
  const cases: [number, string, boolean][] = [
    [400, bad("email is not valid in to"), true],
    [400, bad("sender is not valid"), false],
    [400, "not json", false],
    [401, JSON.stringify({ code: "unauthorized", message: "Key not found" }), false],
    [429, "{}", false],
    [500, "{}", false],
  ];
  for (const [status, body, permanent] of cases) {
    const m = mockFetch(() => new Response(body, { status }));
    const res = await brevoSender("key", "hello@mw.test", m.fn)(email);
    assert.equal(res.kind, permanent ? "failed" : "retry", `${status} ${body}`);
  }
});

Deno.test("postgrest: calls the rpc with the right key headers", async () => {
  const m = mockFetch(() => Response.json([{ id: 1 }]));
  assert.deepEqual(await postgrest("https://p.supabase.co", "sb_secret_x", m.fn).rpc("claim_alerts", {}), [{
    id: 1,
  }]);
  assert.equal(m.calls[0].url, "https://p.supabase.co/rest/v1/rpc/claim_alerts");
  const h = m.calls[0].init.headers as Record<string, string>;
  assert.equal(h.apikey, "sb_secret_x");
  assert.equal(h.authorization, undefined);

  const m2 = mockFetch(() => new Response(null, { status: 204 }));
  assert.equal(
    await postgrest("https://p.supabase.co", "eyJabc", m2.fn).rpc("finish_alert", { p_id: 1 }),
    undefined,
  );
  assert.equal((m2.calls[0].init.headers as Record<string, string>).authorization, "Bearer eyJabc");

  const m3 = mockFetch(() => new Response("nope", { status: 500 }));
  await assert.rejects(postgrest("https://p", "k", m3.fn).rpc("claim_alerts", {}), /claim_alerts 500/);
});
