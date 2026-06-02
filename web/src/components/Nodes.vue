<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api.js'

const nodes = ref([])
const error = ref('')
const loading = ref(false)
const showAdd = ref(false)
const checking = ref({})

const form = ref({
  protocol: 'trojan',
  host: '',
  port: 8443,
  secret: '',
  remark: '',
})

async function load() {
  try {
    const r = await api.nodes()
    nodes.value = r.nodes || []
    error.value = ''
  } catch (e) { error.value = e.message }
}

async function addNode() {
  try {
    await api.addNode({...form.value, port: Number(form.value.port)})
    showAdd.value = false
    form.value = { protocol: 'trojan', host: '', port: 8443, secret: '', remark: '' }
    await load()
  } catch (e) { error.value = e.message }
}

async function delNode(id) {
  if (!confirm('Delete this node?')) return
  try { await api.delNode(id); await load() } catch (e) { error.value = e.message }
}

async function checkNode(host, port, id) {
  checking.value[id] = true
  try {
    const r = await api.tcpCheck(host, port)
    const n = nodes.value.find(x => x.id === id)
    if (n) { n._latency = r.latency_ms; n._reachable = r.reachable }
  } catch (e) {}
  checking.value[id] = false
}

function protoLabel(p) {
  const m = { trojan: 'Trojan', vmess: 'VMess', vless: 'VLESS', hysteria2: 'Hysteria2', hy2: 'Hysteria2', ss: 'SS' }
  return m[p] || p
}

onMounted(load)
</script>

<template>
  <div v-if="error" class="error">{{ error }}</div>

  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
    <h2>Nodes ({{ nodes.length }})</h2>
    <button class="btn primary" @click="showAdd = true">+ Add Node</button>
  </div>

  <div class="card">
    <table v-if="nodes.length">
      <thead><tr>
        <th>Protocol</th><th>Host</th><th>Port</th><th>Remark</th><th>Latency</th><th></th>
      </tr></thead>
      <tbody>
        <tr v-for="n in nodes" :key="n.id">
          <td><span class="badge">{{ protoLabel(n.protocol) }}</span></td>
          <td><code style="font-size:12px">{{ n.host }}</code></td>
          <td>{{ n.port }}</td>
          <td>{{ n.remark }}</td>
          <td>
            <span v-if="n._reachable === true" class="badge green">{{ n._latency }}ms</span>
            <span v-else-if="n._reachable === false" class="badge red">timeout</span>
            <button v-else class="btn sm" :disabled="checking[n.id]" @click="checkNode(n.host, n.port, n.id)">
              {{ checking[n.id] ? '...' : 'Test' }}
            </button>
          </td>
          <td><button class="btn danger sm" @click="delNode(n.id)">Del</button></td>
        </tr>
      </tbody>
    </table>
    <p v-else style="color:var(--muted)">No nodes configured. Add one to get started.</p>
  </div>

  <!-- Add Modal -->
  <div v-if="showAdd" class="modal-mask" @click.self="showAdd = false">
    <div class="modal">
      <h3>Add Node</h3>
      <div class="form-group">
        <label>Protocol</label>
        <select v-model="form.protocol">
          <option value="trojan">Trojan</option>
          <option value="vmess">VMess</option>
          <option value="vless">VLESS (Reality)</option>
          <option value="hysteria2">Hysteria2</option>
          <option value="ss">Shadowsocks</option>
        </select>
      </div>
      <div class="form-row">
        <div class="form-group">
          <label>Host</label>
          <input v-model="form.host" placeholder="node.example.com" />
        </div>
        <div class="form-group" style="max-width:100px">
          <label>Port</label>
          <input v-model.number="form.port" placeholder="443" />
        </div>
      </div>
      <div class="form-group">
        <label>{{ form.protocol === 'vmess' || form.protocol === 'vless' ? 'UUID' : 'Password' }}</label>
        <input v-model="form.secret" :placeholder="form.protocol === 'vmess' ? 'UUID...' : 'password...'" />
      </div>
      <div class="form-group">
        <label>Remark</label>
        <input v-model="form.remark" placeholder="My Node" />
      </div>
      <div class="actions">
        <button class="btn" @click="showAdd = false">Cancel</button>
        <button class="btn primary" @click="addNode">Add</button>
      </div>
    </div>
  </div>
</template>
