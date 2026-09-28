import assert from "node:assert/strict";
import { type Alert, deliverPending, type Deps, type Email, type Outcome, type Push } from "./deliver.ts";
import { childEmail, childPush, parentNudge } from "./wording.ts";

const base: Alert = {
  id: 1,
  step: 2,
  channel: "urgent_push",
  parent_name: "Mom",
  fcm_token: "tok",
  emails: [],
  checked_in: false,
};

function fakeDeps(alerts: Alert[], results: { push?: Outcome; email?: Outcome } = {}) {
  const pushes: Push[] = [], emails: Email[] = [];
  const finished: [Alert["id"], Outcome][] = [];
  const deps: Deps = {
    claim: () => Promise.resolve(alerts),
    finish: (id, outcome) => {
      finished.push([id, outcome]);
      return Promise.resolve();
    },
    push: (p) => (pushes.push(p), Promise.resolve(results.push ?? { kind: "sent" })),
    email: (e) => (emails.push(e), Promise.resolve(results.email ?? { kind: "sent" })),
  };
  return { deps, pushes, emails, finished };
}

Deno.test("urgent push to the child, then marked sent", async () => {
  const f = fakeDeps([base]);
  assert.deepEqual(await deliverPending(f.deps), { sent: 1, retry: 0, failed: 0, skipped: 0 });
  assert.equal(f.pushes.length, 1);
  assert.equal(f.pushes[0].urgent, true);
  assert.equal(f.pushes[0].title, "💛 No word from Mom yet");
  assert.equal(f.pushes[0].tag, "1");
  assert.deepEqual(f.finished, [[1, { kind: "sent" }]]);
});

Deno.test("step 1 is a gentle nudge to the parent", async () => {
  const f = fakeDeps([{ ...base, step: 1, channel: "push" }]);
  await deliverPending(f.deps);
  assert.equal(f.pushes[0].urgent, false);
  assert.deepEqual({ title: f.pushes[0].title, body: f.pushes[0].body }, parentNudge());
});

Deno.test("nothing goes out once the parent has said good morning", async () => {
  const f = fakeDeps([{ ...base, checked_in: true }]);
  assert.deepEqual(await deliverPending(f.deps), { sent: 0, retry: 0, failed: 0, skipped: 1 });
  assert.equal(f.pushes.length, 0);
  assert.deepEqual(f.finished, [[1, { kind: "skipped" }]]);
});

Deno.test("no device token fails for good, not a retry loop", async () => {
  const f = fakeDeps([{ ...base, fcm_token: null }]);
  await deliverPending(f.deps);
  assert.deepEqual(f.finished, [[1, { kind: "failed", error: "no_token" }]]);
});

Deno.test("a temporary FCM error is retried", async () => {
  const f = fakeDeps([base], { push: { kind: "retry", error: "fcm 503" } });
  assert.deepEqual(await deliverPending(f.deps), { sent: 0, retry: 1, failed: 0, skipped: 0 });
  assert.deepEqual(f.finished, [[1, { kind: "retry", error: "fcm 503" }]]);
});

Deno.test("a token FCM says is gone is passed back to be cleared", async () => {
  const gone: Outcome = { kind: "failed", error: "fcm 404", deadToken: "tok" };
  const f = fakeDeps([base], { push: gone });
  await deliverPending(f.deps);
  assert.deepEqual(f.finished, [[1, gone]]);
});

Deno.test("a thrown send error is retried, and the batch moves on", async () => {
  const f = fakeDeps([base, { ...base, id: 2 }]);
  let calls = 0;
  f.deps.push = () => (calls++ === 0 ? Promise.reject(new Error("boom")) : Promise.resolve({ kind: "sent" }));
  assert.deepEqual(await deliverPending(f.deps), { sent: 1, retry: 1, failed: 0, skipped: 0 });
  assert.deepEqual(f.finished, [[1, { kind: "retry", error: "Error: boom" }], [2, { kind: "sent" }]]);
});

Deno.test("a failed finish doesn't stop the rest of the batch", async () => {
  const f = fakeDeps([base, { ...base, id: 2 }]);
  const finish = f.deps.finish;
  f.deps.finish = (id, o) => id === 1 ? Promise.reject(new Error("db down")) : finish(id, o);
  assert.deepEqual(await deliverPending(f.deps), { sent: 2, retry: 0, failed: 0, skipped: 0 });
  assert.equal(f.pushes.length, 2);
  assert.deepEqual(f.finished, [[2, { kind: "sent" }]]);
});

Deno.test("email goes to every child in one call", async () => {
  const f = fakeDeps([{
    ...base,
    step: 4,
    channel: "email",
    fcm_token: null,
    emails: [{ email: "sam@x.test", name: "Sam" }, { email: "lee@x.test", name: "Lee" }],
  }]);
  await deliverPending(f.deps);
  assert.equal(f.emails.length, 1);
  assert.deepEqual(f.emails[0].to.map((t) => t.name), ["Sam", "Lee"]);
  assert.deepEqual(f.emails[0].subject, childEmail("Mom").subject);
  assert.deepEqual(f.finished, [[1, { kind: "sent" }]]);
});

Deno.test("email with no addresses fails for good", async () => {
  const f = fakeDeps([{ ...base, step: 4, channel: "email", emails: [] }]);
  await deliverPending(f.deps);
  assert.deepEqual(f.finished, [[1, { kind: "failed", error: "no_email" }]]);
});

// docs/design-language.md: the parent never sees failure or monitoring words,
// and the child never sees status labels.
const coldWords = /miss|fail|alert|monitor|inactive|status|detect|overdue|late|warning|track/i;

Deno.test("parent words carry no failure or monitoring language", () => {
  const w = parentNudge();
  assert.doesNotMatch(`${w.title} ${w.body}`, coldWords);
});

Deno.test("child words are human, not status labels", () => {
  const p = childPush("Dad");
  const e = childEmail("Dad");
  assert.doesNotMatch(`${p.title} ${p.body} ${e.subject}`, coldWords);
  assert.match(e.text, /not an emergency service/);
});

Deno.test("email html escapes names", () => {
  assert.match(childEmail("<b>Mom</b>").html, /&lt;b&gt;Mom&lt;\/b&gt;/);
});
