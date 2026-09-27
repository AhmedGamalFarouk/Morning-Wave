// send-alerts: delivers the alert rows the missed-morning job inserts.
// A 30-second pg_cron job calls this with pg_net (private.kick_alert_sender)
// whenever rows are ready. Each call claims those rows in the database, so
// two overlapping calls never send the same alert; rows that fail for a
// temporary reason come back after a growing wait (finish_alert).
import { timingSafeEqual } from "node:crypto";
import { deliverPending, type Outcome } from "./deliver.ts";
import { brevoSender } from "./email.ts";
import { fcmSender } from "./fcm.ts";
import { postgrest } from "./db.ts";

const env = (name: string) => {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing secret ${name}`);
  return v;
};

// Built on first use and kept between calls, so the Google token is reused.
// A missing secret only fails the alerts that need it, and they're retried.
let push: ReturnType<typeof fcmSender> | undefined;
let email: ReturnType<typeof brevoSender> | undefined;

Deno.serve(async (req) => {
  if (!safeEqual(req.headers.get("x-alerts-secret") ?? "", env("ALERTS_WEBHOOK_SECRET"))) {
    return new Response("unauthorized", { status: 401 });
  }
  const db = postgrest(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
  const counts = await deliverPending({
    claim: () => db.rpc("claim_alerts", {}),
    finish: (id, outcome) => db.rpc("finish_alert", { p_id: id, ...finishArgs(outcome) }),
    push: (p) => (push ??= fcmSender(JSON.parse(env("FCM_SERVICE_ACCOUNT"))))(p),
    email: (e) => (email ??= brevoSender(env("BREVO_API_KEY"), env("ALERT_EMAIL_FROM")))(e),
  });
  console.log(JSON.stringify(counts));
  return Response.json(counts);
});

function finishArgs(o: Outcome) {
  switch (o.kind) {
    case "sent":
      return { p_error: null, p_permanent: false, p_dead_token: null };
    case "retry":
      return { p_error: o.error, p_permanent: false, p_dead_token: null };
    case "failed":
      return { p_error: o.error, p_permanent: true, p_dead_token: o.deadToken ?? null };
    case "skipped":
      return { p_error: "checked_in", p_permanent: true, p_dead_token: null };
  }
}

function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  return x.length === y.length && timingSafeEqual(x, y);
}
