import 'dotenv/config'
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { fetchAllTickets, fetchStatusLabels, fetchUsers, type LeantimeTicket } from './leantime.js'

// Shared cache dir. fzf preview reads pre-rendered <id>.txt from here (instant, no re-fetch).
const CACHE_DIR = '/tmp/leantime-pick'
const LEANTIME_BASE_URL = process.env.LEANTIME_BASE_URL ?? 'https://leantime.anymateme.store'

// Leantime's built-in defaults, used only if the dynamic fetch fails. Status ids
// are configurable per instance, so getStatusLabels() is the real source of truth.
const STATUS_LABEL_FALLBACK: Record<string, string> = {
  '0': 'Done',
  '1': 'Blocked',
  '2': 'Waiting for Approval',
  '3': 'New',
  '4': 'In Progress',
  '-1': 'Archived',
}
let statusLabelCache: Record<string, string> | null = null
async function loadStatusLabels(): Promise<Record<string, string>> {
  if (statusLabelCache) return statusLabelCache
  try {
    const raw = await fetchStatusLabels()
    const map: Record<string, string> = {}
    for (const [id, def] of Object.entries(raw)) if (def?.name) map[id] = def.name
    if (Object.keys(map).length) return (statusLabelCache = map)
  } catch {
    // fall through to defaults
  }
  return STATUS_LABEL_FALLBACK
}
function statusLabel(t: any, labels: Record<string, string> = STATUS_LABEL_FALLBACK): string {
  const raw = String(t.status ?? '')
  return labels[raw] ?? STATUS_LABEL_FALLBACK[raw] ?? (raw ? `status ${raw}` : 'unknown')
}

// Common named HTML entities seen in Leantime descriptions. &amp; is decoded last.
const NAMED_ENTITIES: Record<string, string> = {
  nbsp: ' ',
  mdash: '—',
  ndash: '–',
  hellip: '…',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  rsquo: '’',
  lsquo: '‘',
  rdquo: '”',
  ldquo: '“',
  agrave: 'à',
  aacute: 'á',
  egrave: 'è',
  eacute: 'é',
  igrave: 'ì',
  iacute: 'í',
  ograve: 'ò',
  oacute: 'ó',
  ocirc: 'ô',
  ugrave: 'ù',
  uacute: 'ú',
}

function decodeEntities(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&([a-z]+);/gi, (m, name) => NAMED_ENTITIES[name.toLowerCase()] ?? m)
    .replace(/&amp;/gi, '&')
}

function stripHtml(s: string): string {
  return decodeEntities(s.replace(/<[^>]+>/g, ''))
    .replace(/\r/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+/g, ' ')
    .trim()
}

function isZeroDate(s?: string | null): boolean {
  return !s || s.startsWith('0000-00-00')
}
function fmtDate(s?: string | null): string {
  return isZeroDate(s) ? '—' : String(s).split(' ')[0]
}

function previewText(t: any, labels?: Record<string, string>): string {
  const head = String(t.headline ?? '').replace(/\s+/g, ' ').trim()
  const url = `${LEANTIME_BASE_URL.replace(/\/$/, '')}/#/tickets/showTicket/${t.id}`
  const body = stripHtml(String(t.description ?? '')) || '(no description)'
  const lines = [
    `#${t.id}  ${head}`,
    '─'.repeat(48),
    `Project : ${t.projectName ?? '—'}`,
    `Assignee: ${t.editorFirstname ?? '—'} (id ${t.editorId ?? '—'})`,
    `Status  : ${statusLabel(t, labels)}`,
    `Due     : ${fmtDate(t.dateToFinish)}`,
    `Created : ${fmtDate(t.date)}`,
    `Link    : ${url}`,
    '',
    body,
  ]
  return lines.join('\n')
}

async function fetchMine(limit: number): Promise<LeantimeTicket[]> {
  const me = process.env.LEANTIME_USER_ID
  let tickets = await fetchAllTickets()
  if (me) tickets = tickets.filter((t) => String((t as any).editorId) === String(me))
  // Newest first by numeric id (Leantime ids are sequential).
  tickets.sort((a, b) => Number(b.id) - Number(a.id))
  return tickets.slice(0, limit)
}

// `pick-ticket.ts <id>` → resolve one ticket: write its preview cache, print headline.
// Used by aibranch/aipr to label a branch/PR even when the id is outside the newest-30 list.
async function resolveOne(id: string) {
  const [labels, tickets] = await Promise.all([loadStatusLabels(), fetchAllTickets()])
  const t = tickets.find((x) => String(x.id) === String(id)) as any
  if (!t) {
    console.error(`pick-ticket: ticket ${id} not found`)
    process.exit(1)
  }
  mkdirSync(CACHE_DIR, { recursive: true })
  writeFileSync(`${CACHE_DIR}/${id}.txt`, previewText(t, labels))
  process.stdout.write(`${String(t.headline ?? '').replace(/\s+/g, ' ').trim()}\n`)
}

// `pick-ticket.ts context <id>` → print the ticket as LLM context for aicommit/aipr prompts:
//   line 1   = "#<id> <headline>"
//   line 3.. = HTML-stripped description (truncated)
// Falls back silently (exit 0, no output) if the ticket isn't found, so callers stay diff-only.
async function printContext(id: string) {
  const t = (await fetchAllTickets()).find((x) => String(x.id) === String(id)) as any
  if (!t) return
  const head = String(t.headline ?? '').replace(/\s+/g, ' ').trim()
  let desc = stripHtml(String(t.description ?? ''))
  const MAX = 1500
  if (desc.length > MAX) desc = `${desc.slice(0, MAX)}…`
  process.stdout.write(`#${id} ${head}\n\n${desc}\n`)
}

// `pick-ticket.ts markdown <id>` → print a GitHub-PR-ready ticket block:
//   a linked heading + the description inside a collapsible <details>, so reviewers
//   see the ticket inline on GitHub AND get a click-through link to Leantime.
// Prints nothing (exit 0) if the ticket isn't found, so aipr degrades gracefully.
async function printMarkdown(id: string) {
  const [labels, tickets] = await Promise.all([loadStatusLabels(), fetchAllTickets()])
  const t = tickets.find((x) => String(x.id) === String(id)) as any
  if (!t) return
  const head = String(t.headline ?? '').replace(/\s+/g, ' ').trim()
  const url = `${LEANTIME_BASE_URL.replace(/\/$/, '')}/#/tickets/showTicket/${id}`
  let desc = stripHtml(String(t.description ?? '')) || '_No description._'
  const MAX = 4000
  if (desc.length > MAX) desc = `${desc.slice(0, MAX)}…`
  const quoted = desc
    .split('\n')
    .map((l) => (l.trim() ? `> ${l}` : '>'))
    .join('\n')
  const meta = `> **Status:** ${statusLabel(t, labels)}  •  **Assignee:** ${t.editorFirstname ?? '—'}  •  **Due:** ${fmtDate(t.dateToFinish)}`
  const block = [
    `### 🎫 Leantime ticket`,
    ``,
    `**[#${id} — ${head}](${url})**`,
    ``,
    `<details open>`,
    `<summary>📋 Ticket details</summary>`,
    ``,
    meta,
    `>`,
    quoted,
    ``,
    `</details>`,
    ``,
  ].join('\n')
  process.stdout.write(block)
}

// `pick-ticket.ts users` → print "<id>\t<name> <username>" per user, for the
// installer to fzf-pick LEANTIME_USER_ID. Errors bubble up (exit 1) so the
// installer can fall back to manual id entry.
async function printUsers() {
  const users = await fetchUsers()
  const lines = users
    .map((u) => {
      const name = [u.firstname, u.lastname].filter(Boolean).join(' ').trim()
      const uname = u.username ? `<${u.username}>` : ''
      const label = [name, uname].filter(Boolean).join(' ') || `user ${u.id}`
      return `${u.id}\t${label}`
    })
    .filter((l) => l.split('\t')[0])
  process.stdout.write(lines.length ? `${lines.join('\n')}\n` : '')
}

async function main() {
  const arg = process.argv[2]
  if (arg === 'users') {
    await printUsers()
    return
  }
  if (arg === 'markdown' && process.argv[3] && /^\d+$/.test(process.argv[3])) {
    await printMarkdown(process.argv[3])
    return
  }
  if (arg === 'context' && process.argv[3] && /^\d+$/.test(process.argv[3])) {
    await printContext(process.argv[3])
    return
  }
  if (arg && /^\d+$/.test(arg)) {
    await resolveOne(arg)
    return
  }

  const limit = Number(process.env.LEANTIME_PICK_LIMIT ?? 30)
  const [labels, tickets] = await Promise.all([loadStatusLabels(), fetchMine(limit)])

  rmSync(CACHE_DIR, { recursive: true, force: true })
  mkdirSync(CACHE_DIR, { recursive: true })

  // Pad status labels into a fixed-width column so headlines line up in fzf.
  const statuses = tickets.map((t) => statusLabel(t, labels))
  const statusWidth = Math.max(0, ...statuses.map((s) => s.length))

  const lines: string[] = []
  tickets.forEach((t, i) => {
    writeFileSync(`${CACHE_DIR}/${t.id}.txt`, previewText(t, labels))
    const head = String(t.headline ?? '').replace(/\s+/g, ' ').trim()
    const status = `[${statuses[i].padEnd(statusWidth)}]`
    // fzf list line: "<id>\t<status column> <headline>". Field 1 = id (used by preview + caller).
    lines.push(`${t.id}\t${status} ${head}`)
  })

  process.stdout.write(lines.length ? `${lines.join('\n')}\n` : '')
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
