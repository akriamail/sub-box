const BASE = '/api'
let token = localStorage.getItem('dash-token') || ''

export function setToken(t) { token = t; localStorage.setItem('dash-token', t) }
export function getToken() { return token }

async function req(method, path, body) {
  const opts = {
    method,
    headers: { 'X-Dashboard-Token': token, 'Content-Type': 'application/json' },
  }
  if (body) opts.body = JSON.stringify(body)
  const r = await fetch(BASE + path, opts)
  if (!r.ok) {
    const e = await r.json().catch(() => ({}))
    throw new Error(e.detail || r.statusText)
  }
  return r.json()
}

export const api = {
  token:       ()             => req('GET', '/token'),
  nodes:       ()             => req('GET', '/nodes'),
  addNode:     (n)            => req('POST', '/nodes', n),
  delNode:     (id)           => req('DELETE', `/nodes/${id}`),
  tcpCheck:    (host, port)   => req('POST', `/nodes/tcp-check?host=${host}&port=${port}`),
  airport:     ()             => req('GET', '/airport/status'),
  airportAll:  ()             => req('GET', '/airport/all-nodes'),
  airportRefresh: ()          => req('POST', '/airport/refresh'),
  airportSelect: (ids)        => req('POST', '/airport/select', { nodes: ids }),
  subscription: ()            => req('GET', '/subscription'),
  rotateToken: ()             => req('POST', '/subscription/rotate-token'),
  system:      ()             => req('GET', '/system/status'),
  triggerUpdate: ()           => req('POST', '/trigger-update'),
}
