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

      <section class="records-panel">
        <header class="records-header">
          <div>
            <span class="section-kicker">生产数据库</span>
            <h3>数据库记录</h3>
            <p>只读分页查询，敏感字段不会写入浏览器持久存储。</p>
          </div>
          <div class="record-tabs" role="tablist" aria-label="数据库表">
            <button
              type="button"
              role="tab"
              :aria-selected="recordsTable === 'users'"
              :class="{ active: recordsTable === 'users' }"
              @click="selectRecordsTable('users')"
            >
              用户表
            </button>
            <button
              type="button"
              role="tab"
              :aria-selected="recordsTable === 'diet_logs'"
              :class="{ active: recordsTable === 'diet_logs' }"
              @click="selectRecordsTable('diet_logs')"
            >
              餐食记录
            </button>
          </div>
        </header>

        <div class="records-status">
          <span>{{ recordsTable === 'users' ? 'users' : 'diet_logs' }}</span>
          <strong>{{ records?.totalElements ?? 0 }} 条记录</strong>
          <button type="button" class="secondary-button compact-button" :disabled="recordsLoading" @click="loadRecords">
            {{ recordsLoading ? '读取中…' : '重新读取' }}
          </button>
        </div>

        <p v-if="recordsError" class="error-text records-error">{{ recordsError }}</p>

        <div v-if="recordsLoading && !records" class="records-empty">正在读取数据库记录…</div>

        <div v-else-if="recordsTable === 'users'" class="table-scroll">
          <table class="records-table users-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>手机号</th>
                <th>昵称</th>
                <th>健康目标</th>
                <th>每日目标</th>
                <th>身体资料</th>
                <th>性别</th>
                <th>分析数</th>
                <th>注册时间</th>
                <th>最近分析</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in records?.content || []" :key="item.id">
                <td class="mono-cell">{{ item.id }}</td>
                <td class="phone-cell">{{ item.phone || '未填写' }}</td>
                <td>{{ item.nickname || '未设置' }}</td>
                <td>{{ goalLabel(item.healthGoal || 'UNSET') }}</td>
                <td>{{ item.dailyCalorieTarget ? `${item.dailyCalorieTarget} kcal` : '未设置' }}</td>
                <td>{{ bodyProfile(item) }}</td>
                <td>{{ genderLabel(item.gender) }}</td>
                <td>{{ item.analysisCount }}</td>
                <td>{{ formatDateTime(item.createdAt) }}</td>
                <td>{{ formatDateTime(item.lastAnalysisAt) }}</td>
              </tr>
              <tr v-if="!records?.content?.length">
                <td colspan="10" class="records-empty">暂无用户记录</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-else class="table-scroll">
          <table class="records-table logs-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>用户</th>
                <th>手机号</th>
                <th>任务 ID</th>
                <th>餐次</th>
                <th>状态</th>
                <th>识别食物</th>
                <th>总热量</th>
                <th>建议</th>
                <th>记录时间</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in records?.content || []" :key="item.id">
                <td class="mono-cell">{{ item.id }}</td>
                <td class="mono-cell">#{{ item.userId }}</td>
                <td class="phone-cell">{{ item.phone || '未填写' }}</td>
                <td class="mono-cell task-cell" :title="item.taskId">{{ shortTaskId(item.taskId) }}</td>
                <td>{{ mealLabel(item.mealType) }}</td>
                <td><span class="status-tag" :class="statusClass(item.status)">{{ statusLabel(item.status) }}</span></td>
                <td class="food-cell">{{ foodLabelsText(item.foodLabels) }}</td>
                <td>{{ item.totalCalories == null ? '暂无' : `${Number(item.totalCalories).toFixed(1)} kcal` }}</td>
                <td>{{ item.hasAdvice ? '已生成' : '无' }}</td>
                <td>{{ formatDateTime(item.loggedAt) }}</td>
              </tr>
              <tr v-if="!records?.content?.length">
                <td colspan="10" class="records-empty">暂无餐食记录</td>
              </tr>
            </tbody>
          </table>
        </div>

        <footer class="records-footer">
          <p>手机号仅用于管理员核对测试账号；页面不返回密码哈希、验证码、原始分析 JSON 或图片存储地址。</p>
          <div class="pagination">
            <button
              type="button"
              class="secondary-button compact-button"
              :disabled="recordsLoading || recordsPage <= 0"
              @click="changeRecordsPage(recordsPage - 1)"
            >
              上一页
            </button>
            <span>第 {{ recordsPage + 1 }} / {{ Math.max(records?.totalPages || 0, 1) }} 页</span>
            <button
              type="button"
              class="secondary-button compact-button"
              :disabled="recordsLoading || recordsPage + 1 >= (records?.totalPages || 0)"
              @click="changeRecordsPage(recordsPage + 1)"
            >
              下一页
            </button>
          </div>
        </footer>
      </section>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { getAdminDashboard, getAdminRecords } from '@/api/dietLog'

const STORAGE_KEY = 'nutriAdminDashboardKey'
const adminKey = ref('')
const dashboard = ref(null)
const loading = ref(false)
const error = ref('')
const records = ref(null)
const recordsTable = ref('users')
const recordsPage = ref(0)
const recordsLoading = ref(false)
const recordsError = ref('')

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
    await loadRecords()
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
  records.value = null
  recordsPage.value = 0
  recordsError.value = ''
  error.value = ''
}

async function loadRecords() {
  if (!adminKey.value) return
  recordsLoading.value = true
  recordsError.value = ''
  try {
    records.value = await getAdminRecords(
      adminKey.value,
      recordsTable.value,
      recordsPage.value,
      10
    )
  } catch (e) {
    recordsError.value = e?.response?.data?.error || '暂时无法读取数据库记录'
  } finally {
    recordsLoading.value = false
  }
}

async function selectRecordsTable(table) {
  if (recordsTable.value === table) return
  recordsTable.value = table
  recordsPage.value = 0
  records.value = null
  await loadRecords()
}

async function changeRecordsPage(page) {
  if (page < 0 || page >= (records.value?.totalPages || 0)) return
  recordsPage.value = page
  await loadRecords()
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

function genderLabel(value) {
  return {
    MALE: '男',
    FEMALE: '女',
    OTHER: '其他',
  }[value] || '未设置'
}

function bodyProfile(item) {
  const parts = []
  if (item.heightCm) parts.push(`${item.heightCm} cm`)
  if (item.weightKg) parts.push(`${Number(item.weightKg).toFixed(1)} kg`)
  return parts.join(' / ') || '未设置'
}

function formatDateTime(value) {
  if (!value) return '暂无'
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))
}

function shortTaskId(value) {
  if (!value) return '暂无'
  return value.length > 13 ? `${value.slice(0, 8)}…${value.slice(-4)}` : value
}

function foodLabelsText(labels) {
  return Array.isArray(labels) && labels.length ? labels.join('、') : '暂无'
}

function statusLabel(value) {
  return {
    COMPLETED: '已完成',
    PENDING: '处理中',
    FAILED: '失败',
  }[value] || value || '未知'
}

function statusClass(value) {
  return {
    COMPLETED: 'status-completed',
    PENDING: 'status-pending',
    FAILED: 'status-failed',
  }[value] || ''
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

.records-panel {
  min-width: 0;
  margin-top: 12px;
  padding: 18px;
  border: 1px solid #d9e0db;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.96);
}

.records-header,
.records-status,
.records-footer,
.pagination {
  display: flex;
  align-items: center;
}

.records-header {
  justify-content: space-between;
  gap: 18px;
}

.records-header h3 {
  margin-top: 3px;
  font-size: 1.05rem;
  letter-spacing: 0;
}

.records-header p,
.records-footer p {
  color: #6c786f;
  font-size: 0.78rem;
  line-height: 1.5;
}

.records-header p {
  margin-top: 4px;
}

.record-tabs {
  display: inline-grid;
  grid-template-columns: repeat(2, minmax(88px, 1fr));
  padding: 3px;
  border: 1px solid #d4dcd6;
  border-radius: 7px;
  background: #f1f4f2;
}

.record-tabs button {
  min-height: 36px;
  padding: 0 13px;
  border: 0;
  color: #526158;
  background: transparent;
}

.record-tabs button.active {
  color: #fff;
  background: #2e5d44;
}

.records-status {
  gap: 10px;
  min-height: 46px;
  margin-top: 12px;
  padding: 8px 0;
  border-top: 1px solid #e3e8e4;
}

.records-status span {
  padding: 4px 7px;
  border-radius: 4px;
  color: #4e5f55;
  background: #edf2ef;
  font-family: Consolas, 'SFMono-Regular', monospace;
  font-size: 0.76rem;
}

.records-status strong {
  font-size: 0.8rem;
}

.records-status .compact-button {
  margin-left: auto;
}

.compact-button {
  min-height: 34px;
  padding: 0 11px;
  font-size: 0.76rem;
}

.records-error {
  margin: 0 0 10px;
}

.table-scroll {
  width: 100%;
  overflow-x: auto;
  border: 1px solid #e0e5e1;
  border-radius: 6px;
}

.records-table {
  width: 100%;
  min-width: 1080px;
  border-collapse: collapse;
  color: #334139;
  font-size: 0.78rem;
  white-space: nowrap;
}

.records-table th,
.records-table td {
  padding: 11px 12px;
  border-bottom: 1px solid #e6eae7;
  text-align: left;
  vertical-align: middle;
}

.records-table th {
  position: sticky;
  top: 0;
  color: #607067;
  background: #f5f7f6;
  font-size: 0.73rem;
  font-weight: 800;
}

.records-table tbody tr:last-child td {
  border-bottom: 0;
}

.records-table tbody tr:hover {
  background: #fafcfb;
}

.phone-cell {
  color: #21372a;
  font-weight: 750;
}

.mono-cell {
  font-family: Consolas, 'SFMono-Regular', monospace;
  font-size: 0.74rem;
}

.task-cell {
  max-width: 150px;
}

.food-cell {
  max-width: 260px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.status-tag {
  display: inline-block;
  padding: 4px 7px;
  border-radius: 4px;
  font-size: 0.7rem;
  font-weight: 800;
}

.status-completed {
  color: #245b3d;
  background: #e4f2e9;
}

.status-pending {
  color: #78521f;
  background: #fff2d9;
}

.status-failed {
  color: #8b3832;
  background: #fae7e5;
}

.records-empty {
  padding: 28px;
  color: #718078;
  text-align: center;
}

.records-footer {
  justify-content: space-between;
  gap: 16px;
  margin-top: 12px;
}

.records-footer p {
  max-width: 720px;
}

.pagination {
  flex: 0 0 auto;
  gap: 9px;
}

.pagination span {
  color: #59685f;
  font-size: 0.76rem;
  white-space: nowrap;
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

  .records-footer {
    align-items: flex-start;
    flex-direction: column;
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

  .records-panel {
    padding: 14px;
  }

  .records-header {
    align-items: stretch;
    flex-direction: column;
  }

  .record-tabs {
    width: 100%;
  }

  .records-status {
    flex-wrap: wrap;
  }

  .records-status .compact-button {
    margin-left: 0;
  }

  .pagination {
    width: 100%;
    justify-content: space-between;
  }
}
</style>
