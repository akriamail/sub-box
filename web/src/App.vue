<script setup>
import { ref, onMounted } from 'vue'
import { api, setToken, getToken } from './api.js'
import Dashboard from './components/Dashboard.vue'
import Agents from './components/Agents.vue'
import Nodes from './components/Nodes.vue'
import Airport from './components/Airport.vue'

const tab = ref('dashboard')
const authed = ref(false)
const loading = ref(true)
const tokInput = ref('')

async function tryAuth() {
  loading.value = true
  try {
    if (!getToken()) throw new Error('missing token')
    await api.system()
    authed.value = true
  } catch (e) {
    authed.value = false
    console.error('Auth check:', e.message)
  }
  loading.value = false
}

function saveToken() {
  setToken(tokInput.value)
  tryAuth()
}

onMounted(tryAuth)
</script>

<template>
  <div v-if="loading" class="loading">Connecting...</div>

  <div v-else-if="!authed" class="auth-box">
    <h2>sub-box Dashboard</h2>
    <p>Token: <code>{{ getToken() ? getToken().slice(0,12)+'...' : 'required' }}</code></p>
    <div class="auth-form">
      <input v-model="tokInput" :placeholder="getToken()" />
      <button @click="saveToken">Connect</button>
    </div>
    <p class="hint">Token is stored on the server in /opt/subscribe/.dashboard-token.</p>
  </div>

  <div v-else class="app">
    <header>
      <h1>sub-box</h1>
      <nav>
        <button :class="{ active: tab === 'dashboard' }" @click="tab = 'dashboard'">Dashboard</button>
        <button :class="{ active: tab === 'agents' }"    @click="tab = 'agents'">Agents</button>
        <button :class="{ active: tab === 'nodes' }"     @click="tab = 'nodes'">Nodes</button>
        <button :class="{ active: tab === 'airport' }"   @click="tab = 'airport'">Airport</button>
      </nav>
    </header>
    <main>
      <Dashboard v-if="tab === 'dashboard'" />
      <Agents    v-if="tab === 'agents'"    />
      <Nodes     v-if="tab === 'nodes'"     />
      <Airport   v-if="tab === 'airport'"   />
    </main>
  </div>
</template>

<style>
:root {
  --bg: #f5f7fb;
  --panel: #fff;
  --text: #1a1a2e;
  --muted: #6b7280;
  --blue: #2563eb;
  --green: #16a34a;
  --red: #dc2626;
  --amber: #d97706;
  --border: #e5e7eb;
  --radius: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'PingFang SC', 'Microsoft YaHei', sans-serif; background: var(--bg); color: var(--text); }
.loading, .auth-box { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 60vh; gap: 16px; }
.auth-box h2 { font-size: 28px; }
.auth-box code { background: #e5e7eb; padding: 4px 8px; border-radius: 4px; font-size: 13px; }
.auth-form { display: flex; gap: 8px; }
.auth-form input { width: 320px; padding: 10px 12px; border: 1px solid var(--border); border-radius: var(--radius); font-size: 14px; }
.auth-form button { padding: 10px 20px; background: var(--blue); color: #fff; border: none; border-radius: var(--radius); cursor: pointer; font-weight: 600; }
.hint { color: var(--muted); font-size: 13px; }
.app { max-width: 1200px; margin: 0 auto; padding: 0 16px 48px; }
header { display: flex; align-items: center; justify-content: space-between; padding: 16px 0; border-bottom: 1px solid var(--border); margin-bottom: 24px; }
header h1 { font-size: 20px; font-weight: 700; }
nav { display: flex; gap: 4px; }
nav button { padding: 8px 16px; border: none; background: transparent; border-radius: var(--radius); cursor: pointer; font-size: 14px; color: var(--muted); font-weight: 500; }
nav button.active { background: var(--blue); color: #fff; }
.card { background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); padding: 20px; }
.card h3 { font-size: 15px; margin-bottom: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.grid3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 16px; }
.stat { font-size: 28px; font-weight: 700; }
.stat-label { font-size: 13px; color: var(--muted); }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); font-size: 14px; }
th { color: var(--muted); font-weight: 600; font-size: 12px; text-transform: uppercase; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 99px; font-size: 12px; font-weight: 600; }
.badge.green { background: #dcfce7; color: #166534; }
.badge.red { background: #fef2f2; color: #991b1b; }
.badge.amber { background: #fffbeb; color: #92400e; }
.btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border: 1px solid var(--border); border-radius: var(--radius); background: var(--panel); cursor: pointer; font-size: 13px; font-weight: 500; color: var(--text); }
.btn:hover { background: #f9fafb; }
.btn.primary { background: var(--blue); color: #fff; border-color: var(--blue); }
.btn.danger { color: var(--red); border-color: #fecaca; }
.btn.sm { padding: 4px 10px; font-size: 12px; }
.btn:disabled { opacity: .4; cursor: not-allowed; }
input, select { padding: 8px 12px; border: 1px solid var(--border); border-radius: var(--radius); font-size: 14px; }
input:focus, select:focus { outline: none; border-color: var(--blue); }
.modal-mask { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,.4); display: flex; align-items: center; justify-content: center; z-index: 100; }
.modal { background: var(--panel); border-radius: 12px; padding: 24px; width: 480px; max-width: 90vw; }
.modal h3 { margin-bottom: 16px; }
.form-group { margin-bottom: 14px; }
.form-group label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 4px; font-weight: 600; }
.form-row { display: flex; gap: 8px; }
.form-row > * { flex: 1; }
.actions { display: flex; gap: 8px; margin-top: 18px; justify-content: flex-end; }
.error { background: #fef2f2; color: #991b1b; padding: 12px; border-radius: var(--radius); font-size: 14px; margin-bottom: 12px; }
.mt { margin-top: 20px; }
</style>
