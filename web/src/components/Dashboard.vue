<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { api, getToken } from '../api.js'

const status = ref({})
const subs = ref({})
const nodes = ref([])
const error = ref('')

let timer

async function refresh() {
  try {
    const [s, sub, n] = await Promise.all([api.system(), api.subscription(), api.nodes()])
    status.value = s
    subs.value = sub
    nodes.value = n.nodes || []
    error.value = ''
  } catch (e) {
    error.value = e.message
  }
}

onMounted(() => { refresh(); timer = setInterval(refresh, 10000) })
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div v-if="error" class="error">{{ error }}</div>

  <div class="grid3">
    <div class="card">
      <h3>Sing-Box</h3>
      <div class="stat">{{ status.singbox === 'running' ? 'Running' : 'Stopped' }}</div>
      <span :class="['badge', status.singbox === 'running' ? 'green' : 'red']">{{ status.singbox === 'running' ? '● Active' : '● Down' }}</span>
    </div>
    <div class="card">
      <h3>Certificate</h3>
      <div class="stat">{{ typeof status.cert_days === 'number' ? status.cert_days : '?' }}d</div>
      <span :class="['badge', status.cert_days > 30 ? 'green' : 'amber']">{{ status.cert_domain || '-' }}</span>
    </div>
    <div class="card">
      <h3>Nodes</h3>
      <div class="stat">{{ nodes.length }}</div>
      <span class="stat-label">total configured</span>
    </div>
  </div>

  <div class="grid2 mt">
    <div class="card">
      <h3>Subscription</h3>
      <code style="word-break:break-all;font-size:13px">{{ subs.url }}</code>
      <div class="mt" style="display:flex;gap:8px">
        <button class="btn sm" @click="navigator.clipboard.writeText(subs.url)">Copy</button>
      </div>
    </div>
    <div class="card">
      <h3>System</h3>
      <table>
        <tr><td>Memory</td><td>{{ status.mem_used_mb }} / {{ status.mem_total_mb }} MB</td></tr>
        <tr><td>Disk</td><td>{{ status.disk_used }} / {{ status.disk_total }} ({{ status.disk_pct }})</td></tr>
        <tr><td>Nginx</td><td><span :class="['badge', status.nginx === 'running' ? 'green' : 'red']">{{ status.nginx }}</span></td></tr>
        <tr><td>Dashboard Token</td><td><code style="font-size:12px">{{ getToken().slice(0,16) }}...</code></td></tr>
      </table>
    </div>
  </div>
</template>
