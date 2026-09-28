// Every word a family member reads from an alert lives here, so it can be
// checked against docs/design-language.md in one place. The parent never
// reads failure or monitoring words; the child reads human language.

export interface Words {
  title: string;
  body: string;
}

/** Step 1: a soft nudge to the parent. Nothing here says anything was missed. */
export function parentNudge(): Words {
  return {
    title: "Good morning ☀️",
    body: "Whenever you're ready, tap the sun to say good morning to your family.",
  };
}

/**
 * Steps 2 and 3: the child, then the second contact. The title stays short
 * enough that the parent's name reads on one line even when collapsed; the
 * full sentence is in the body, which an expandable notification can show.
 */
export function childPush(parentName: string): Words {
  return {
    title: `💛 No word from ${parentName} yet`,
    body: `No good morning from ${parentName} yet today. A quick call might be nice.`,
  };
}

/** Step 4: one email, sent to every child with an address. */
export function childEmail(parentName: string) {
  const subject = `Haven't heard from ${parentName} yet today`;
  const lines = [
    `Hello,`,
    `${parentName} usually says good morning in Morning Wave, and it hasn't come through yet today. A quick call might be a good idea.`,
    `With warmth,\nMorning Wave`,
    `Morning Wave is not an emergency service. If you think someone is in danger, call 911.`,
  ];
  const text = lines.join("\n\n");
  const html = lines
    .map((l) => `<p>${escapeHtml(l).replaceAll("\n", "<br>")}</p>`)
    .join("");
  return { subject, text, html };
}

function escapeHtml(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
