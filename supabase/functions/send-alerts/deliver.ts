import { childEmail, childPush, parentNudge } from "./wording.ts";

/** One claimed alert, with everything needed to send it (see claim_alerts). */
export interface Alert {
  id: number | string;
  step: number;
  channel: "push" | "urgent_push" | "email";
  parent_name: string;
  fcm_token: string | null;
  /** For email alerts: every address to write to. */
  emails: { email: string; name: string }[];
  /** The parent already said good morning that day, or someone acknowledged it. */
  checked_in: boolean;
}

/** What happened to one alert. */
export type Outcome =
  | { kind: "sent" }
  /** Worth trying again later (outage, rate limit, setup mistake). */
  | { kind: "retry"; error: string }
  /** Can't ever work. deadToken: a phone token to clear from the member. */
  | { kind: "failed"; error: string; deadToken?: string }
  /** Nothing to say any more: the parent already said good morning. */
  | { kind: "skipped" };

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
  finish(id: Alert["id"], outcome: Outcome): Promise<void>;
  push(p: Push): Promise<Outcome>;
  /** One call per alert, so a retry can't half-repeat it. */
  email(e: Email): Promise<Outcome>;
}

export async function deliverPending(deps: Deps) {
  const alerts = await deps.claim();
  const counts = { sent: 0, retry: 0, failed: 0, skipped: 0 };
  for (const alert of alerts) {
    const outcome = await deliver(alert, deps).catch((e): Outcome => ({ kind: "retry", error: String(e) }));
    counts[outcome.kind]++;
    // One row failing to record must not stop the rest of the batch. The row
    // keeps its lease and comes back after it lapses.
    await deps.finish(alert.id, outcome).catch((e) => console.error(`finish ${alert.id}: ${e}`));
  }
  return counts;
}

async function deliver(alert: Alert, deps: Deps): Promise<Outcome> {
  if (alert.checked_in) return { kind: "skipped" };
  const data = { kind: "morning", step: String(alert.step) };

  if (alert.channel === "email") {
    if (alert.emails.length === 0) return { kind: "failed", error: "no_email" };
    return await deps.email({ to: alert.emails, ...childEmail(alert.parent_name) });
  }

  if (!alert.fcm_token) return { kind: "failed", error: "no_token" };
  const words = alert.step === 1 ? parentNudge() : childPush(alert.parent_name);
  return await deps.push({ token: alert.fcm_token, ...words, urgent: alert.channel === "urgent_push", data });
}
