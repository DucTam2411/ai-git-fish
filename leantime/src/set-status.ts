import 'dotenv/config'
import { fetchAllTickets, fetchStatusLabels, updateTicketStatus } from './leantime.js'

// `set-status.ts <id> [statusName]` → resolve statusName (case-insensitive, default
// "Done") against the instance's real status labels, patch the ticket, print the
// resolved label. Status ids are configurable per instance, so never hardcode them.
async function main() {
  const [id, statusNameArg] = process.argv.slice(2)
  if (!id) {
    console.error('usage: set-status.ts <ticketId> [statusName]')
    process.exit(1)
  }
  const statusName = statusNameArg ?? 'Done'

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
