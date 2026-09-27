// send-alerts: delivers the alert rows the every-minute job inserts.
// The job calls this with pg_net (see private.kick_alert_sender) whenever
// rows are waiting. Each call claims the waiting rows in the database, so
// two overlapping calls never send the same alert, and rows that fail are
// released to be retried on the next minute.
import { deliverPending } from "./deliver.ts";
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
    finish: (id, error, permanent, deadToken) =>
      db.rpc("finish_alert", {
        p_id: id,
        p_error: error,
        p_permanent: permanent,
        p_dead_token: deadToken ?? null,
      }),
    push: (p) => (push ??= fcmSender(JSON.parse(env("FCM_SERVICE_ACCOUNT"))))(p),
    email: (e) => (email ??= brevoSender(env("BREVO_API_KEY"), env("ALERT_EMAIL_FROM")))(e),
  });
  console.log(JSON.stringify(counts));
  return Response.json(counts);
});

function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
