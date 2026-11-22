export async function deliverAccessPasswordEmail({
  toEmail,
  recipientName,
  tier,
  base38Password,
  ndaReceiptHash = null,
}) {
  const tierLabel = tier === 2 ? "Level 2 (Signed NDA)" : "Level 1 (Registered)";
  const subject = `Your Twisted23.com ${tierLabel} Base-38 Access Password: ${base38Password}`;
  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 560px; margin: 0 auto; color: #111827;">
      <h2 style="color: #b45309;">Twisted23.com &middot; Photo Naming Demo</h2>
      <p>Hi ${escapeHtml(recipientName)},</p>
      <p>Your <strong>${escapeHtml(tierLabel)}</strong> exact-time Base-38 access password is ready:</p>
      <div style="padding: 14px 18px; border-radius: 10px; background: #fef3c7; border: 1px solid #f59e0b; font-family: ui-monospace, SFMono-Regular, monospace; font-size: 20px; font-weight: 700; letter-spacing: 0.04em; text-align: center;">
        ${escapeHtml(base38Password)}
      </div>
      <p style="margin-top: 16px;">Enter this 10-character Base-38 code at <strong>Twisted23.com</strong> to verify your email and unlock ${tierLabel} features.</p>
      ${ndaReceiptHash ? `<p style="font-size: 12px; color: #4b5563;">Signed NDA Receipt SHA-256: <code>${escapeHtml(ndaReceiptHash)}</code></p>` : ""}
      <p style="font-size: 12px; color: #6b7280;">100% pure lowercase Base-38 math &bull; Zero ambiguous symbols &bull; Exact UTC second encoded.</p>
    </div>
  `.trim();

  const text = [
    `Twisted23.com — ${tierLabel} Access`,
    ``,
    `Hi ${recipientName},`,
    ``,
    `Your ${tierLabel} Base-38 access password: ${base38Password}`,
    ``,
    `Paste this 10-character code into Twisted23.com to sign in and unlock ${tierLabel}.`,
    ndaReceiptHash ? `Signed NDA SHA-256: ${ndaReceiptHash}` : "",
  ]
    .filter(Boolean)
    .join("\n");

  const resendKey = process.env.RESEND_API_KEY;
  const fromEmail = process.env.TWISTED23_FROM_EMAIL || "Twisted23 Access <access@twisted23.com>";

  if (resendKey) {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [toEmail],
        subject,
        html,
        text,
      }),
    });
    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      throw new Error(`Email delivery failed (${res.status}): ${errBody}`);
    }
    return {
      mode: "resend",
      delivered: true,
      outboxEntry: null,
    };
  }

  return {
    mode: "dev-outbox",
    delivered: false,
    outboxEntry: {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      toEmail,
      recipientName,
      tier,
      subject,
      base38Password,
      ndaReceiptHash,
      sentAtIso: new Date().toISOString(),
    },
  };
}

function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
