<template>
  <div class="dashboard-page">
    <section v-if="!dashboard" class="access-panel">
      <div>
        <span class="section-kicker">受保护数据</span>
        <h2>输入管理码</h2>
        <p>管理码与公开测试授权码相互独立。</p>
      </div>
      <form class="access-form" @submit.prevent="loadDashboard">
        <label for="dashboard-key">管理码</label>
        <input
          id="dashboard-key"
          v-model.trim="adminKey"
          type="password"
          autocomplete="one-time-code"
          required
        />
        <button type="submit" :disabled="loading">
          {{ loading ? '正在验证…' : '查看数据' }}
        </button>
      </form>
      <p v-if="error" class="error-text">{{ error }}</p>
    </section>

    <template v-else>
      <section class="dashboard-toolbar">
        <div>
          <h2>产品运行概览</h2>
          <p>更新于 {{ formattedGeneratedAt }}</p>
        </div>
        <div class="toolbar-actions">
          <button type="button" :disabled="loading" @click="loadDashboard">
            {{ loading ? '刷新中…' : '刷新数据' }}
          </button>
          <button type="button" class="secondary-button" @click="lockDashboard">锁定看板</button>
        </div>
      </section>

      <p v-if="error" class="error-text dashboard-error">{{ error }}</p>

      <section class="metric-grid" aria-label="核心指标">
        <article v-for="metric in metrics" :key="metric.label" class="metric-tile">
          <span>{{ metric.label }}</span>
          <strong>{{ metric.value }}</strong>
          <p>{{ metric.note }}</p>
        </article>
      </section>

      <section class="dashboard-grid">
        <article class="panel trend-panel">
          <header>
            <div>
              <span class="section-kicker">最近 14 天</span>
              <h3>新增用户与分析次数</h3>
            </div>
            <div class="legend" aria-label="趋势图图例">
              <span><i class="users-swatch"></i>新增用户</span>
              <span><i class="analysis-swatch"></i>分析次数</span>
            </div>
          </header>

          <div class="trend-list">
            <div v-for="item in dashboard.daily" :key="item.date" class="trend-row">
              <time :datetime="item.date">{{ shortDate(item.date) }}</time>
              <div class="bar-track" :aria-label="`${item.date} 新增用户 ${item.newUsers}`">
                <span
                  class="trend-bar users-bar"
                  :style="{ width: barWidth(item.newUsers, maxDailyValue) }"
                ></span>
              </div>
              <strong>{{ item.newUsers }}</strong>
              <div class="bar-track" :aria-label="`${item.date} 分析 ${item.analyses} 次`">
                <span
                  class="trend-bar analysis-bar"
                  :style="{ width: barWidth(item.analyses, maxDailyValue) }"
                ></span>
              </div>
              <strong>{{ item.analyses }}</strong>
            </div>
          </div>
        </article>

        <div class="side-panels">
          <article class="panel">
            <header>
              <div>
                <span class="section-kicker">用户方向</span>
                <h3>健康目标分布</h3>
              </div>
            </header>
            <div class="distribution-list">
              <div v-for="item in dashboard.goalDistribution" :key="item.label">
                <div>
                  <span>{{ goalLabel(item.label) }}</span>
                  <strong>{{ item.count }}</strong>
                </div>
                <progress :value="item.count" :max="maxGoalCount"></progress>
              </div>
            </div>
          </article>

          <article class="panel">
            <header>
              <div>
                <span class="section-kicker">使用场景</span>
                <h3>餐次分布</h3>
              </div>
            </header>
            <div class="distribution-list">
              <div v-for="item in dashboard.mealTypeDistribution" :key="item.label">
                <div>
                  <span>{{ mealLabel(item.label) }}</span>
                  <strong>{{ item.count }}</strong>
                </div>
                <progress :value="item.count" :max="maxMealCount"></progress>
              </div>
            </div>
          </article>

          <article class="privacy-panel">
            <strong>隐私边界</strong>
            <p>{{ dashboard.privacy.notice }}</p>
          </article>
        </div>
      </section>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { getAdminDashboard } from '@/api/dietLog'

const STORAGE_KEY = 'nutriAdminDashboardKey'
const adminKey = ref('')
const dashboard = ref(null)
const loading = ref(false)
const error = ref('')

const formattedGeneratedAt = computed(() => {
  if (!dashboard.value?.generatedAt) return '刚刚'
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(dashboard.value.generatedAt))
})

const metrics = computed(() => {
  const summary = dashboard.value?.summary || {}
  return [
    { label: '总用户', value: summary.totalUsers ?? 0, note: `近 7 天新增 ${summary.users7d ?? 0}` },
    { label: '今日新增', value: summary.usersToday ?? 0, note: '按账号注册时间统计' },
    { label: '分析用户', value: summary.usersWithMeals ?? 0, note: `近 7 天活跃 ${summary.activeUsers7d ?? 0}` },
    { label: '累计分析', value: summary.totalAnalyses ?? 0, note: `今日 ${summary.analysesToday ?? 0}` },
    { label: '近 7 天分析', value: summary.analyses7d ?? 0, note: '包含所有餐次类型' },
    { label: '分析完成率', value: `${summary.completionRate ?? 0}%`, note: `已返回 ${summary.finishedAnalyses ?? 0} 条` },
  ]
})

const maxDailyValue = computed(() => {
  const values = (dashboard.value?.daily || []).flatMap(item => [item.newUsers, item.analyses])
  return Math.max(1, ...values)
})
const maxGoalCount = computed(() => Math.max(1, ...(dashboard.value?.goalDistribution || []).map(item => item.count)))
const maxMealCount = computed(() => Math.max(1, ...(dashboard.value?.mealTypeDistribution || []).map(item => item.count)))

onMounted(() => {
  adminKey.value = sessionStorage.getItem(STORAGE_KEY) || ''
  if (adminKey.value) loadDashboard()
})

async function loadDashboard() {
  if (!adminKey.value) {
    error.value = '请输入管理码'
    return
  }
  loading.value = true
  error.value = ''
  try {
    dashboard.value = await getAdminDashboard(adminKey.value)
    sessionStorage.setItem(STORAGE_KEY, adminKey.value)
  } catch (e) {
    dashboard.value = null
    error.value = e?.response?.data?.error || '暂时无法加载看板数据'
  } finally {
    loading.value = false
  }
}

function lockDashboard() {
  sessionStorage.removeItem(STORAGE_KEY)
  adminKey.value = ''
  dashboard.value = null
  error.value = ''
}

function shortDate(value) {
  const [, month, day] = value.split('-')
  return `${month}/${day}`
}

function barWidth(value, max) {
  if (!value) return '0%'
  return `${Math.max(8, Math.round((value / max) * 100))}%`
}

function goalLabel(value) {
  return {
    WEIGHT_LOSS: '减脂',
    MUSCLE_GAIN: '增肌',
    MAINTENANCE: '维持',
    GENERAL_HEALTH: '综合健康',
    UNSET: '未设置',
  }[value] || value
}

function mealLabel(value) {
  return {
    BREAKFAST: '早餐',
    LUNCH: '午餐',
    DINNER: '晚餐',
    SNACK: '加餐',
    UNKNOWN: '未标记',
  }[value] || value
}
</script>

<style scoped>
.dashboard-page {
  min-width: 0;
  color: #243229;
}

.access-panel {
  width: min(620px, 100%);
  margin: 80px auto 0;
  padding: 28px;
  border: 1px solid #d8dfda;
  border-radius: 8px;
  background: #fff;
  box-shadow: 0 14px 32px rgba(46, 62, 51, 0.08);
}

.access-panel h2,
.dashboard-toolbar h2,
.panel h3 {
  letter-spacing: 0;
}

.access-panel h2 {
  margin-top: 5px;
  font-size: 1.45rem;
}

.access-panel p {
  margin-top: 7px;
  color: #68766d;
}

.access-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 9px 12px;
  align-items: end;
  margin-top: 24px;
}

.access-form label {
  grid-column: 1 / -1;
  font-size: 0.84rem;
  font-weight: 700;
}

.access-form input {
  border-radius: 6px;
}

button {
  min-height: 44px;
  padding: 0 16px;
  border: 1px solid #2e5d44;
  border-radius: 6px;
  color: #fff;
  background: #2e5d44;
  cursor: pointer;
  font-weight: 700;
}

button:disabled {
  cursor: wait;
  opacity: 0.6;
}

.secondary-button {
  color: #33463a;
  border-color: #ccd5cf;
  background: #fff;
}

.error-text {
  margin-top: 12px;
  color: #aa3f36;
  font-weight: 700;
}

.dashboard-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 14px;
}

.dashboard-toolbar h2 {
  font-size: 1.35rem;
}

.dashboard-toolbar p {
  margin-top: 3px;
  color: #6c786f;
  font-size: 0.86rem;
}

.toolbar-actions {
  display: flex;
  gap: 8px;
}

.dashboard-error {
  margin: 0 0 12px;
}

.metric-grid {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 10px;
}

.metric-tile,
.panel {
  border: 1px solid #d9e0db;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.95);
}

.metric-tile {
  min-width: 0;
  padding: 16px;
}

.metric-tile span {
  color: #68766d;
  font-size: 0.8rem;
  font-weight: 700;
}

.metric-tile strong {
  display: block;
  margin-top: 7px;
  font-size: 1.65rem;
}

.metric-tile p {
  margin-top: 6px;
  color: #7a877f;
  font-size: 0.76rem;
  line-height: 1.4;
}

.dashboard-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.65fr) minmax(300px, 0.75fr);
  gap: 12px;
  margin-top: 12px;
}

.panel {
  min-width: 0;
  padding: 18px;
}

.panel > header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 16px;
}

.section-kicker {
  color: #708078;
  font-size: 0.72rem;
  font-weight: 800;
  text-transform: uppercase;
}

.panel h3 {
  margin-top: 3px;
  font-size: 1rem;
}

.legend {
  display: flex;
  gap: 12px;
  color: #68766d;
  font-size: 0.76rem;
}

.legend span {
  display: flex;
  align-items: center;
  gap: 5px;
}

.legend i {
  width: 10px;
  height: 10px;
  border-radius: 2px;
}

.users-swatch,
.users-bar {
  background: #4f8b68;
}

.analysis-swatch,
.analysis-bar {
  background: #d38349;
}

.trend-list {
  display: grid;
  gap: 8px;
}

.trend-row {
  display: grid;
  grid-template-columns: 48px minmax(80px, 1fr) 28px minmax(80px, 1fr) 28px;
  gap: 8px;
  align-items: center;
  min-height: 26px;
}

.trend-row time,
.trend-row strong {
  font-size: 0.74rem;
}

.trend-row strong {
  text-align: right;
}

.bar-track {
  height: 8px;
  overflow: hidden;
  border-radius: 3px;
  background: #eef1ef;
}

.trend-bar {
  display: block;
  height: 100%;
  border-radius: inherit;
}

.side-panels {
  display: grid;
  align-content: start;
  gap: 12px;
}

.distribution-list {
  display: grid;
  gap: 13px;
}

.distribution-list > div > div {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 5px;
  font-size: 0.82rem;
}

progress {
  display: block;
  width: 100%;
  height: 7px;
  border: 0;
  border-radius: 3px;
  accent-color: #4f8b68;
}

.privacy-panel {
  padding: 15px 16px;
  border: 1px solid #d9e0db;
  border-radius: 8px;
  color: #536159;
  background: #f4f7f5;
}

.privacy-panel strong {
  color: #304238;
  font-size: 0.82rem;
}

.privacy-panel p {
  margin-top: 5px;
  font-size: 0.78rem;
  line-height: 1.55;
}

@media (max-width: 1100px) {
  .metric-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .dashboard-grid {
    grid-template-columns: 1fr;
  }

  .side-panels {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .privacy-panel {
    grid-column: 1 / -1;
  }
}

@media (max-width: 640px) {
  .access-panel {
    margin-top: 24px;
    padding: 20px;
  }

  .access-form {
    grid-template-columns: 1fr;
  }

  .dashboard-toolbar {
    align-items: flex-start;
  }

  .metric-grid,
  .side-panels {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .privacy-panel {
    grid-column: 1 / -1;
  }

  .trend-row {
    grid-template-columns: 42px minmax(54px, 1fr) 22px minmax(54px, 1fr) 22px;
    gap: 5px;
  }

  .legend {
    display: grid;
    gap: 3px;
  }
}
</style>
