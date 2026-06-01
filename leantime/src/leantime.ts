export interface LeantimeTicket {
  id: number | string
  headline: string
  status?: string | number
  editorId?: string | number
  editFrom?: string | null
  dateToFinish?: string | null
  projectId?: string | number
  [k: string]: unknown
}

export async function fetchAllTickets(): Promise<LeantimeTicket[]> {
  const base = process.env.LEANTIME_BASE_URL
  const key = process.env.LEANTIME_API_KEY
  if (!base || !key) throw new Error('LEANTIME_BASE_URL / LEANTIME_API_KEY missing')

  const res = await fetch(`${base.replace(/\/$/, '')}/api/jsonrpc`, {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'leantime.rpc.tickets.tickets.getAll',
      params: {},
    }),
  })

  if (!res.ok) throw new Error(`Leantime ${res.status}: ${await res.text()}`)
  const json = (await res.json()) as { result?: LeantimeTicket[]; error?: unknown }
  if (json.error) throw new Error(`Leantime RPC error: ${JSON.stringify(json.error)}`)
  return json.result ?? []
}
