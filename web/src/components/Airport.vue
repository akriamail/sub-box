<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../api.js'

const status = ref({})
const allNodes = ref([])
const enabledNodes = ref([])
const selected = ref(new Set())
const error = ref('')
const loading = ref(false)
const refreshing = ref(false)
const showAll = ref(false)

const regions = computed(() => {
  const map = {}
  for (const n of allNodes.value) {
    const r = n.region || 'Other'
    if (!map[r]) map[r] = { nodes: [], best: null }
    map[r].nodes.push(n)
    if (n.reachable && (!map[r].best || n.latency_ms < map[r].best.latency_ms)) {
      map[r].best = n
    }
  }
  return Object.entries(map).sort((a, b) => {
    const la = a[1].best?.latency_ms ?? 99999
    const lb = b[1].best?.latency_ms ?? 99999
    return la - lb
  })
})

async function loadStatus() {
  try {
    const s = await api.airport()
    status.value = s
    enabledNodes.value = s.nodes || []
  } catch (e) { error.value = e.message }
}

async function fetchAll() {
  loading.value = true
  try {
    const r = await api.airportAll()
    allNodes.value = r.nodes || []
    status.value.info = r.info || {}
    error.value = ''
    // Preselect currently enabled
    const has = new Set((status.value.nodes || []).map(n => n.id))
    selected.value = new Set(has)
  } catch (e) { error.value = e.message }
  loading.value = false
}

async function doRefresh() {
  refreshing.value = true
  try {
    await api.airportRefresh()
    await loadStatus()
    await fetchAll()
    error.value = ''
  } catch (e) { error.value = e.message }
  refreshing.value = false
}

function toggleRegion(region) {
  const nodes = regions.value.find(r => r[0] === region)?.[1]?.nodes || []
  const allSelected = nodes.every(n => selected.value.has(n.id))
  for (const n of nodes) {
    if (allSelected) selected.value.delete(n.id)
    else selected.value.add(n.id)
  }
}

function toggleNode(id) {
  if (selected.value.has(id)) selected.value.delete(id)
  else selected.value.add(id)
  selected.value = new Set(selected.value)
}

async function applySelection() {
  try {
    await api.airportSelect([...selected.value])
    await loadStatus()
    await api.triggerUpdate()
    error.value = ''
  } catch (e) { error.value = e.message }
}

function fmtLatency(n) {
  if (n.reachable && n.latency_ms != null) return n.latency_ms + 'ms'
  return '—'
}

onMounted(async () => { await loadStatus(); await fetchAll() })
</script>

<template>
  <div v-if="error" class="error">{{ error }}</div>

  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
    <h2>Airport</h2>
    <div style="display:flex;gap:8px">
      <button class="btn" :disabled="loading" @click="fetchAll">{{ loading ? 'Scanning...' : 'Scan All' }}</button>
      <button class="btn primary" :disabled="refreshing" @click="doRefresh">{{ refreshing ? 'Refreshing...' : 'Refresh' }}</button>
    </div>
  </div>

  <!-- Info -->
  <div v-if="status.info" class="card" style="margin-bottom:16px">
    <div style="display:flex;gap:32px;font-size:14px">
      <span v-if="status.info.traffic">Traffic: {{ status.info.traffic }}</span>
      <span v-if="status.info.expiry">Expiry: {{ status.info.expiry }}</span>
      <span>Enabled: {{ enabledNodes.length }} nodes</span>
    </div>
  </div>

  <!-- Region cards -->
  <div v-if="regions.length" class="grid2">
    <div v-for="[name, r] in regions" :key="name" class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
        <h3 style="margin:0">{{ name }}</h3>
        <span class="stat" style="font-size:20px">{{ fmtLatency(r.best) }}</span>
      </div>

      <button class="btn sm" style="margin-bottom:8px" @click="toggleRegion(name)">Toggle All</button>

      <table>
        <thead><tr><th style="width:20px"></th><th>Host</th><th>Port</th><th>Latency</th><th>Remark</th></tr></thead>
        <tbody>
          <tr v-for="n in r.nodes" :key="n.id" @click="toggleNode(n.id)" style="cursor:pointer">
            <td><input type="checkbox" :checked="selected.has(n.id)" style="pointer-events:none" /></td>
            <td><code style="font-size:11px">{{ n.host }}</code></td>
            <td>{{ n.port }}</td>
            <td>
              <span v-if="n.reachable" class="badge green">{{ n.latency_ms }}ms</span>
              <span v-else class="badge red">—</span>
            </td>
            <td style="font-size:12px;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ n.remark }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <div v-else-if="!loading" class="card" style="text-align:center;color:var(--muted);padding:48px">
    No airport nodes loaded. Click "Scan All" to fetch and test.
  </div>

  <!-- Apply button -->
  <div v-if="regions.length" class="mt" style="display:flex;justify-content:center">
    <button class="btn primary" style="padding:12px 32px;font-size:15px" @click="applySelection">
      Apply & Generate Subscription ({{ selected.size }} nodes)
    </button>
  </div>
</template>
