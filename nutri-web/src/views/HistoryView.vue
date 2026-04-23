<template>
  <div class="history-view">
    <h2>历史记录</h2>

    <div class="actions">
      <button class="btn" :disabled="loading" @click="load(true)">
        {{ loading ? '加载中…' : '刷新' }}
      </button>
    </div>

    <p v-if="error" class="error">{{ error }}</p>

    <div v-if="!loading && records.length === 0" class="empty">暂无记录</div>

    <div v-for="item in records" :key="item.taskId" class="card">
      <div class="row">
        <strong>{{ item.mealType }}</strong>
        <span :class="['status', item.status?.toLowerCase()]">{{ item.status }}</span>
      </div>
      <p class="meta">任务ID: {{ item.taskId }}</p>
      <p class="meta">时间: {{ formatDate(item.loggedAt) }}</p>
      <p class="meta">识别项数量: {{ item.detectedItemsCount }}</p>
      <p class="advice" v-if="item.adviceReport">{{ item.adviceReport }}</p>
    </div>

    <div class="pager" v-if="records.length > 0">
      <button class="btn" :disabled="loading || page === 0" @click="prevPage">上一页</button>
      <span>第 {{ page + 1 }} 页</span>
      <button class="btn" :disabled="loading || !hasNext" @click="nextPage">下一页</button>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { getDietLogHistory } from '@/api/dietLog'

const userId = localStorage.getItem('userId') || '1'

const loading = ref(false)
const error = ref('')
const records = ref([])
const page = ref(0)
const size = ref(10)
const hasNext = ref(false)

onMounted(() => load(true))

async function load(reset = false) {
  loading.value = true
  error.value = ''
  try {
    if (reset) page.value = 0
    const data = await getDietLogHistory(userId, page.value, size.value)
    records.value = data.content || []
    hasNext.value = !!data.hasNext
  } catch (e) {
    error.value = e?.response?.data?.error || '加载历史记录失败'
  } finally {
    loading.value = false
  }
}

function nextPage() {
  page.value += 1
  load(false)
}

function prevPage() {
  if (page.value === 0) return
  page.value -= 1
  load(false)
}

function formatDate(value) {
  if (!value) return '—'
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return value
  return d.toLocaleString()
}
</script>

<style scoped>
.history-view {
  max-width: 760px;
  margin: 0 auto;
}

.actions {
  margin: 0.8rem 0;
}

.btn {
  border: none;
  border-radius: 18px;
  padding: 0.45rem 1rem;
  background: linear-gradient(135deg, #4caf50, #2196f3);
  color: #fff;
  cursor: pointer;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.card {
  background: #fff;
  border-radius: 10px;
  padding: 0.9rem 1rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  margin-bottom: 0.8rem;
}

.row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.meta {
  color: #606b77;
  margin-top: 0.35rem;
  font-size: 0.92rem;
}

.advice {
  margin-top: 0.6rem;
  line-height: 1.5;
}

.status {
  font-size: 0.85rem;
  padding: 0.2rem 0.5rem;
  border-radius: 12px;
  color: #fff;
}

.status.completed {
  background: #2e7d32;
}

.status.pending {
  background: #ff9800;
}

.status.failed {
  background: #d32f2f;
}

.empty {
  margin: 1rem 0;
  color: #8a9199;
}

.error {
  color: #c62828;
  margin-bottom: 0.6rem;
}

.pager {
  display: flex;
  gap: 0.8rem;
  align-items: center;
  justify-content: center;
  margin-top: 0.5rem;
}
</style>
