/**
 * Minimal Slack Incoming Webhook client. One env var: SLACK_WEBHOOK_URL.
 * The webhook is bound to a single channel on the Slack side — nothing to pick here.
 */

function webhookUrl(): string | null {
  const url = process.env.SLACK_WEBHOOK_URL
  return url && url.trim() ? url : null
}

// No-op (resolves) when SLACK_WEBHOOK_URL isn't set, so callers can fire-and-forget.
export async function sendMessage(text: string): Promise<void> {
  const url = webhookUrl()
  if (!url) return
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  })
  if (!res.ok) throw new Error(`Slack webhook HTTP ${res.status}: ${await res.text()}`)
}
