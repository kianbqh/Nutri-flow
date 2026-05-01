<template>
  <div class="page history-view">
    <section class="page-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">历史回看</span>
        <h2 class="page-hero__title">把每一次餐食记录沉淀下来，方便你持续回看和调整</h2>
        <p class="page-hero__subtitle">
          历史记录会跟随你的账号保存。你可以按时间回看餐次、识别结果和建议摘要，持续观察近期饮食变化。
        </p>
        <div class="page-actions">
          <button class="button button--secondary" :disabled="loading" @click="load(true)">
            {{ loading ? '加载中…' : '刷新列表' }}
          </button>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前账号</span>
          <strong>{{ accountLabel }}</strong>
          <p>{{ isAuthenticated ? '这里只会显示当前已验证账号下的历史记录。' : '先完成手机号验证，再查看你的个人历史数据。' }}</p>
        </div>
        <div class="metric-card">
          <span>当前页</span>
          <strong>第 {{ page + 1 }} 页</strong>
          <p>按时间倒序浏览饮食记录，更容易对比近期餐食结构和变化趋势。</p>
        </div>
        <div class="metric-card">
          <span>本页记录</span>
          <strong>{{ records.length }} 条</strong>
          <p>{{ hasNext ? '还有更多记录可继续翻页。' : '当前已经浏览到最新可见范围。' }}</p>
        </div>
        <div class="metric-card">
          <span>长期价值</span>
          <strong>帮助观察饮食变化</strong>
          <p>连续记录能帮助你判断哪些餐次更容易偏高、偏低，后续调整会更有依据。</p>
        </div>
      </aside>
    </section>

    <p v-if="error" class="soft-note soft-note--error">{{ error }}</p>

    <section v-if="!isAuthenticated" class="surface-card empty-state auth-empty-state">
      <h3>先验证手机号账号</h3>
      <p>历史记录、昵称和目标设置都会跟随你的个人账号保存。完成验证后，这里只会显示当前账号下的数据。</p>
      <RouterLink to="/profile" class="button button--primary">去个人主页验证</RouterLink>
    </section>

    <section v-else-if="loading" class="surface-card empty-state">
      正在加载历史记录，请稍候…
    </section>

    <section v-else-if="records.length === 0" class="surface-card empty-state">
      当前账号还没有历史记录。完成第一次分析后，这里会按时间沉淀你的饮食轨迹。
    </section>

    <section v-else class="history-grid">
      <article v-for="item in records" :key="item.taskId" class="surface-card history-card">
        <div class="history-card__top">
          <div>
            <p class="history-card__meal">{{ mealLabel(item.mealType) }}</p>
            <p class="history-card__time">{{ formatDate(item.loggedAt) }}</p>
          </div>
          <span class="status-pill" :class="statusClass(item.status)">{{ statusLabel(item.status) }}</span>
        </div>

        <div class="history-card__stats">
          <div class="history-stat">
            <span>识别项</span>
            <strong>{{ item.detectedItemsCount ?? 0 }}</strong>
          </div>
          <div class="history-stat">
            <span>建议状态</span>
            <strong>{{ item.adviceReport ? '已生成' : '待补充' }}</strong>
          </div>
        </div>

        <p class="history-preview">{{ previewAdvice(item.adviceReport) }}</p>
      </article>
    </section>

    <section v-if="records.length > 0" class="surface-card pager-card">
      <button class="button button--secondary" :disabled="loading || page === 0" @click="prevPage">上一页</button>
      <span class="pager-card__text">第 {{ page + 1 }} 页</span>
      <button class="button button--secondary" :disabled="loading || !hasNext" @click="nextPage">下一页</button>
    </section>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { getDietLogHistory, getStoredWebSession } from '@/api/dietLog'

const session = getStoredWebSession()
const userId = ref(session.userId)
const phone = ref(session.phone)

const loading = ref(false)
const error = ref('')
const records = ref([])
const page = ref(0)
const size = ref(10)
const hasNext = ref(false)

const isAuthenticated = computed(() => Boolean(userId.value && phone.value))
const accountLabel = computed(() => phone.value || (userId.value ? `账号 #${userId.value}` : '未验证账号'))

onMounted(() => {
  if (isAuthenticated.value) {
    load(true)
  }
})

async function load(reset = false) {
  if (!isAuthenticated.value) return
  loading.value = true
  error.value = ''
  try {
    if (reset) page.value = 0
    const data = await getDietLogHistory(userId.value, page.value, size.value)
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

function mealLabel(value) {
  const labels = {
    BREAKFAST: '早餐',
    LUNCH: '午餐',
    DINNER: '晚餐',
    SNACK: '加餐',
  }
  return labels[value] || value || '未分类餐次'
}

function statusLabel(value) {
  const labels = {
    COMPLETED: '已完成',
    PENDING: '分析中',
    FAILED: '失败',
  }
  return labels[value] || (value || '未知状态')
}

function statusClass(value) {
  const normalized = (value || '').toUpperCase()
  if (normalized === 'COMPLETED') return 'status-pill--completed'
  if (normalized === 'PENDING') return 'status-pill--pending'
  return 'status-pill--failed'
}

function previewAdvice(value) {
  if (!value || !value.trim()) {
    return '这条记录暂无建议正文，但仍会作为后续个性化建议的参考上下文。'
  }
  const normalized = value.replace(/\s+/g, ' ').trim()
  if (normalized.length <= 120) return normalized
  return `${normalized.slice(0, 120)}...`
}
</script>

<style scoped>
.hero-aside,
.history-grid {
  display: grid;
  gap: 14px;
}

.auth-empty-state {
  display: grid;
  gap: 14px;
  justify-items: start;
}

.history-grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.history-card {
  display: grid;
  gap: 16px;
}

.history-card__top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
}

.history-card__meal {
  font-size: 1.14rem;
  font-weight: 800;
}

.history-card__time {
  margin-top: 6px;
  color: var(--muted-soft);
}

.history-card__stats {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.history-stat {
  padding: 16px;
  border-radius: 20px;
  background: rgba(255, 248, 242, 0.95);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.history-stat span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 8px;
}

.history-stat strong {
  font-size: 1rem;
}

.history-preview {
  color: var(--muted);
  line-height: 1.75;
}

.pager-card {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 14px;
}

.pager-card__text {
  min-width: 80px;
  text-align: center;
  font-weight: 700;
}

@media (max-width: 960px) {
  .history-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 560px) {
  .history-card__top,
  .pager-card {
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
