<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api.js'

const agents = ref([])
const error = ref('')
const command = ref('')
const form = ref({
  name: '',
  domain: '',
  protocol: 'vmess',
  port: 443,
  remark: '',
})

async function load() {
  try {
    const r = await api.agents()
    agents.value = r.agents || []
    error.value = ''
  } catch (e) { error.value = e.message }
}

async function createInstall() {
  try {
    const r = await api.createAgentInstall({...form.value, port: Number(form.value.port)})
    command.value = r.command
    await load()
  } catch (e) { error.value = e.message }
}

function metric(agent, key) {
  return agent.reported?.metrics?.[key] ?? '-'
}

function service(agent, key) {
  return agent.reported?.services?.[key] ?? '-'
}

onMounted(load)
</script>

<template>
  <div v-if="error" class="error">{{ error }}</div>

  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
    <h2>Agents</h2>
    <button class="btn" @click="load">Refresh</button>
  </div>

  <div class="card">
    <h3>Add Agent</h3>
    <div class="form-row">
      <input v-model="form.name" placeholder="lax" />
      <input v-model="form.domain" placeholder="lax.akria.net" />
      <select v-model="form.protocol">
        <option value="trojan">Trojan</option>
        <option value="vmess">VMess</option>
        <option value="hysteria2">Hysteria2</option>
        <option value="vless">VLESS</option>
      </select>
      <input v-model.number="form.port" placeholder="443" />
      <input v-model="form.remark" placeholder="自建.LAX" />
      <button class="btn primary" @click="createInstall">Generate</button>
    </div>
    <div v-if="command" class="subbox" style="margin-top:14px">
      <code class="url">{{ command }}</code>
      <div class="url-tools">
        <button class="btn sm" @click="navigator.clipboard.writeText(command)">Copy</button>
      </div>
    </div>
  </div>

  <div class="card mt">
    <table v-if="agents.length">
      <thead><tr>
        <th>Name</th><th>Status</th><th>Protocol</th><th>Port</th><th>CPU</th><th>Memory</th><th>Net</th><th>Cert</th><th>Last Seen</th>
      </tr></thead>
      <tbody>
        <tr v-for="a in agents" :key="a.id">
          <td>{{ a.name }}</td>
          <td><span class="badge green" v-if="a.reported?.last_seen">Online</span><span v-else class="badge amber">Pending</span></td>
          <td>{{ a.desired?.protocol }}</td>
          <td>{{ a.desired?.port }}</td>
          <td>{{ metric(a, 'cpu_percent') }}%</td>
          <td>{{ metric(a, 'mem_used_mb') }} / {{ metric(a, 'mem_total_mb') }} MB</td>
          <td>{{ metric(a, 'net_rx_bps') }} / {{ metric(a, 'net_tx_bps') }} B/s</td>
          <td>{{ service(a, 'cert_days_left') }}d</td>
          <td>{{ a.reported?.last_seen || '-' }}</td>
        </tr>
      </tbody>
    </table>
    <p v-else style="color:var(--muted)">No agents yet. Generate an install command first.</p>
  </div>
</template>
