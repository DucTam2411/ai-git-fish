import 'dotenv/config'
import { createTicket, fetchAllSprints, fetchProjects, fetchStatusLabels } from './leantime.js'

// `add-task.ts projects` → "<id>\t<name>" per project, for aitask's fzf project picker.
async function printProjects() {
  const projects = await fetchProjects()
  const lines = projects.map((p) => `${p.id}\t${String(p.name ?? '').replace(/\s+/g, ' ').trim()}`)
  process.stdout.write(lines.length ? `${lines.join('\n')}\n` : '')
}

// `add-task.ts sprints <projectId>` → "<id>\t<label>" per sprint of that project,
// newest first (so fzf defaults to the newest sprint on Enter), then a synthetic
// "0\tNo sprint (backlog)" entry last.
async function printSprints(projectId: string) {
  const sprints = (await fetchAllSprints()).filter((s) => String(s.projectId) === String(projectId))
  sprints.sort((a, b) => String(b.startDate ?? '').localeCompare(String(a.startDate ?? '')))
  const lines: string[] = []
  for (const s of sprints) {
    const start = String(s.startDate ?? '').split(' ')[0]
    const end = String(s.endDate ?? '').split(' ')[0]
    lines.push(`${s.id}\t${s.name}  (${start} → ${end})`)
  }
  lines.push('0\tNo sprint (backlog)')
  process.stdout.write(`${lines.join('\n')}\n`)
}

// `add-task.ts create <projectId> <sprintId> <headline>` → create the ticket,
// print "<id>\t<url>" on success.
async function create(projectId: string, sprintId: string, headline: string) {
  const editorId = process.env.LEANTIME_USER_ID
  if (!editorId) throw new Error('LEANTIME_USER_ID not set')

  let statusId: number | string = 3 // fallback "New"
  try {
    const labels = await fetchStatusLabels()
    const newEntry = Object.entries(labels).find(([, def]) => /^new$/i.test(String(def?.name ?? '')))
    if (newEntry) statusId = newEntry[0]
  } catch {
    // keep fallback
  }

  const id = await createTicket({
    headline,
    projectId,
    editorId,
    type: 'task',
    status: statusId,
    sprint: sprintId,
  })

  const base = (process.env.LEANTIME_BASE_URL ?? '').replace(/\/$/, '')
  const url = `${base}/#/tickets/showTicket/${id}`
  process.stdout.write(`${id}\t${url}\n`)
}

async function main() {
  const [cmd, a1, a2, ...rest] = process.argv.slice(2)
  if (cmd === 'projects') return printProjects()
  if (cmd === 'sprints' && a1) return printSprints(a1)
  if (cmd === 'create' && a1 && a2 && rest.length) return create(a1, a2, rest.join(' '))

  console.error('usage: add-task.ts projects | sprints <projectId> | create <projectId> <sprintId> <headline...>')
  process.exit(1)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
