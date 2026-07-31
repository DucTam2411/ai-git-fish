import 'dotenv/config'
import { fetchAllTickets, fetchStatusLabels, updateTicketStatus } from './leantime.js'

// `set-status.ts labels` → "<id>\t<name>" per status, numeric id ascending, for
// aistatus's fzf status picker. Status ids/names are configurable per instance.
async function printLabels() {
  const labels = await fetchStatusLabels()
  const lines = Object.entries(labels)
    .sort(([a], [b]) => Number(a) - Number(b))
    .map(([id, def]) => `${id}\t${(def as any)?.name ?? `status ${id}`}`)
  process.stdout.write(lines.length ? `${lines.join('\n')}\n` : '')
}

// `set-status.ts <id> [statusName...]` → resolve statusName (case-insensitive, default
// "Done", words rejoined since fish splits unquoted multi-word args) against the
// instance's real status labels, patch the ticket, print the resolved label. Status
// ids are configurable per instance, so never hardcode them.
async function main() {
  const [id, ...rest] = process.argv.slice(2)
  if (!id) {
    console.error('usage: set-status.ts <ticketId> [statusName...] | set-status.ts labels')
    process.exit(1)
  }
  if (id === 'labels') return printLabels()
  const statusName = rest.length ? rest.join(' ') : 'Done'

  const [labels, tickets] = await Promise.all([fetchStatusLabels(), fetchAllTickets()])
  const ticket = tickets.find((t) => String(t.id) === String(id)) as any
  if (!ticket) {
    console.error(`set-status: ticket ${id} not found`)
    process.exit(1)
  }

  const entry = Object.entries(labels).find(
    ([, def]) => String((def as any)?.name ?? '').toLowerCase() === statusName.toLowerCase()
  )
  if (!entry) {
    console.error(`set-status: no status named "${statusName}" on this instance`)
    process.exit(1)
  }
  const [statusId, def] = entry

  await updateTicketStatus(id, ticket.projectId, statusId)
  process.stdout.write(`${(def as any).name}\n`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
