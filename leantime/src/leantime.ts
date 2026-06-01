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

export interface LeantimeUser {
  id: number | string
  firstname?: string
  lastname?: string
  username?: string
  [k: string]: unknown
}

// One JSON-RPC call to Leantime. Throws on transport/HTTP/RPC error.
async function rpc<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
  const base = process.env.LEANTIME_BASE_URL
  const key = process.env.LEANTIME_API_KEY
  if (!base || !key) throw new Error('LEANTIME_BASE_URL / LEANTIME_API_KEY missing')

  const res = await fetch(`${base.replace(/\/$/, '')}/api/jsonrpc`, {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  })

  if (!res.ok) throw new Error(`Leantime ${res.status}: ${await res.text()}`)
  const json = (await res.json()) as { result?: T; error?: unknown }
  if (json.error) throw new Error(`Leantime RPC error: ${JSON.stringify(json.error)}`)
  return json.result as T
}

export async function fetchAllTickets(): Promise<LeantimeTicket[]> {
  return (await rpc<LeantimeTicket[]>('leantime.rpc.tickets.tickets.getAll')) ?? []
}

// Used by the installer to pick a LEANTIME_USER_ID. Tries a few known method
// names so it survives minor Leantime version differences.
export async function fetchUsers(): Promise<LeantimeUser[]> {
  const methods = [
    'leantime.rpc.users.users.getAll',
    'leantime.rpc.users.getAll',
    'leantime.rpc.users.users.getAllUsers',
  ]
  let lastErr: unknown
  for (const m of methods) {
    try {
      const out = await rpc<LeantimeUser[]>(m)
      if (Array.isArray(out)) return out
    } catch (err) {
      lastErr = err
    }
  }
  throw lastErr ?? new Error('no users method succeeded')
}
