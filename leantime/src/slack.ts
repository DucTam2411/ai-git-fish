/**
 * Slack Incoming Webhook client + PR message builder.
 * Ported from khanhld2109/ai-git-mcp. One channel per webhook — nothing to pick here.
 *
 * Env vars:
 *   SLACK_WEBHOOK_URL  - required to send anything
 *   SLACK_USER_MAP     - JSON: name/login -> Slack member id (U…/W…) or subteam id (S…)
 *   SLACK_PR_REVIEWERS - default comma-separated mention spec for aipr notifications
 */

function webhookUrl(): string | null {
  const url = process.env.SLACK_WEBHOOK_URL
  return url && url.trim() ? url : null
}

async function post(payload: Record<string, unknown>): Promise<void> {
  const url = webhookUrl()
  if (!url) return
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) throw new Error(`Slack webhook HTTP ${res.status}: ${await res.text()}`)
}

// No-op when SLACK_WEBHOOK_URL isn't set, so callers can fire-and-forget.
export async function sendMessage(text: string): Promise<void> {
  await post({ text })
}

function jsonObjectEnv(name: string): Record<string, string> {
  try {
    const m = JSON.parse(process.env[name] || '{}')
    if (!m || typeof m !== 'object') return {}
    return Object.fromEntries(Object.entries(m).filter(([, v]) => typeof v === 'string')) as Record<
      string,
      string
    >
  } catch {
    return {}
  }
}

function loadUserMap(): Record<string, string> {
  return jsonObjectEnv('SLACK_USER_MAP')
}

// Accepts: "here"/"channel", a raw `<@…>` mention, a Slack id (U…/W…/S…), or a
// name/login looked up in SLACK_USER_MAP. Returns null for unknown tokens (skip
// rather than post dead @text).
function resolveToken(token: string, map: Record<string, string>): string | null {
  const t = token.trim()
  if (!t) return null
  const low = t.toLowerCase()
  if (low === 'here') return '<!here>'
  if (low === 'channel') return '<!channel>'
  if (/^<[!@]/.test(t)) return t
  if (/^[UW][A-Z0-9]{6,}$/.test(t)) return `<@${t}>`
  if (/^S[A-Z0-9]{6,}$/.test(t)) return `<!subteam^${t}>`
  const id = map[t] ?? map[low]
  if (id) return /^S/.test(id) ? `<!subteam^${id}>` : `<@${id}>`
  return null
}

export function resolveMentions(spec: string | undefined, map = loadUserMap()): string[] {
  if (!spec) return []
  return spec
    .split(',')
    .map((s) => resolveToken(s, map))
    .filter((v): v is string => Boolean(v))
}

export interface PrMessageInput {
  title: string
  url: string
  action?: 'created' | 'updated'
  author?: string
}

export interface PrTicketRef {
  url: string
  id: string | number
  headline: string
}

export function formatPrMessage(
  input: PrMessageInput,
  ticket?: PrTicketRef | null,
  mentions: string[] = []
): string {
  const feat = ticket?.headline || input.title
  const lines: string[] = []
  lines.push(`*Author:* ${input.author ?? '—'}`)
  lines.push(`*PR:* <${input.url}>`)
  if (ticket) lines.push(`*Ticket:* <${ticket.url}|#${ticket.id} ${ticket.headline}>`)
  lines.push(`*Feat:* ${feat}`)
  if (mentions.length) lines.push(`*Reviewers:* ${mentions.join(' ')}`)
  return lines.join('\n')
}

// Build + send a PR notification. mention overrides SLACK_PR_REVIEWERS when given.
export async function postPr(input: PrMessageInput, ticket: PrTicketRef | null, mention?: string): Promise<void> {
  const mentions = resolveMentions(mention ?? process.env.SLACK_PR_REVIEWERS)
  const text = formatPrMessage(input, ticket, mentions)
  await post({ text, blocks: [{ type: 'section', text: { type: 'mrkdwn', text } }] })
}
