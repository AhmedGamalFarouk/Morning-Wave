import { childEmail, childPush, parentNudge } from "./wording.ts";

/** One claimed alert, with everything needed to send it (see claim_alerts). */
export interface Alert {
  id: number | string;
  step: number;
  channel: "push" | "urgent_push" | "email";
  parent_name: string;
  recipient_name: string | null;
  fcm_token: string | null;
  /** For email alerts: every address to write to. */
  emails: { email: string; name: string }[];
  /** The parent already said good morning today, so nothing should go out. */
  checked_in: boolean;
}

export type SendResult =
  | { ok: true }
  | { ok: false; permanent: boolean; error: string };

export interface Push {
  token: string;
  title: string;
  body: string;
  urgent: boolean;
  data: Record<string, string>;
}

export interface Email {
  to: { email: string; name: string }[];
  subject: string;
  text: string;
  html: string;
}

export interface Deps {
  claim(): Promise<Alert[]>;
  /** error null = sent. permanent = don't retry. */
  finish(id: Alert["id"], error: string | null, permanent: boolean): Promise<void>;
  push(p: Push): Promise<SendResult>;
  /** One call per alert, so a retry can't half-repeat it. */
  email(e: Email): Promise<SendResult>;
}

export async function deliverPending(deps: Deps) {
  const alerts = await deps.claim();
  const counts = { sent: 0, failed: 0, skipped: 0 };
  for (const alert of alerts) {
    const result = await deliver(alert, deps).catch(
      (e): SendResult => ({ ok: false, permanent: false, error: String(e) }),
    );
    if (result.ok) counts.sent++;
    else if (result.error === "checked_in") counts.skipped++;
    else counts.failed++;
    await deps.finish(alert.id, result.ok ? null : result.error, !result.ok && result.permanent);
  }
  return counts;
}

function deliver(alert: Alert, deps: Deps): Promise<SendResult> {
  if (alert.checked_in) return fail("checked_in");
  const data = { kind: "morning", step: String(alert.step) };

  if (alert.channel === "email") {
    if (alert.emails.length === 0) return fail("no_email");
    return deps.email({ to: alert.emails, ...childEmail(alert.parent_name) });
  }

  if (!alert.fcm_token) return fail("no_token");
  const words = alert.step === 1 ? parentNudge() : childPush(alert.parent_name);
  return deps.push({ token: alert.fcm_token, ...words, urgent: alert.channel === "urgent_push", data });
}

function fail(error: string): Promise<SendResult> {
  return Promise.resolve({ ok: false, permanent: true, error });
}
