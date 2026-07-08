import 'dotenv/config'
import { fetchAllTickets } from './leantime.js'
import { postPr } from './slack.js'

// `notify-pr.ts <url> <action:created|updated> <author> <ticketId|-> <title...>`
// Best-effort: prints nothing on success, exits nonzero + logs on failure so the
// caller (aipr) can choose to ignore it.
async function main() {
  const [url, action, author, ticketArg, ...titleParts] = process.argv.slice(2)
  if (!url || !titleParts.length) {
    console.error('usage: notify-pr.ts <url> <created|updated> <author> <ticketId|-> <title...>')
    process.exit(1)
  }
  const title = titleParts.join(' ')

  let ticket: { url: string; id: string | number; headline: string } | null = null
  if (ticketArg && ticketArg !== '-') {
    const t = (await fetchAllTickets()).find((x) => String(x.id) === String(ticketArg)) as any
    if (t) {
      const base = (process.env.LEANTIME_BASE_URL ?? '').replace(/\/$/, '')
      ticket = { url: `${base}/#/tickets/showTicket/${t.id}`, id: t.id, headline: String(t.headline ?? '').trim() }
    }
  }

  await postPr({ title, url, action: action === 'updated' ? 'updated' : 'created', author }, ticket)
}

main().catch((err) => {
  console.error(`notify-pr: ${err}`)
  process.exit(1)
})
