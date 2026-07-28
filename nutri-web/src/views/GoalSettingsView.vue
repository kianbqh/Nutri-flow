<template>
  <div class="page goal-settings-view">
    <section class="page-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">目标设置</span>
        <h2 class="page-hero__title">{{ heroTitle }}</h2>
        <p class="page-hero__subtitle">
          先描述你的目标，再微调基础信息、热量和饮食限制，让网页端分析建议和 app 保持一致的使用节奏。
        </p>
        <div class="page-actions">
          <RouterLink to="/profile" class="button button--secondary">查看个人主页</RouterLink>
          <button class="button button--secondary" :disabled="loading" @click="loadGoalSettings">
            {{ loading ? '刷新中…' : '刷新设置' }}
          </button>
        </div>
        <p class="soft-note goal-note">{{ goalNote }}</p>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前账号</span>
          <strong>{{ accountLabel }}</strong>
          <p>{{ hasSession ? '当前目标设置会跟随这个手机号账号保存。' : '请先完成账号验证，再保存目标设置。' }}</p>
        </div>
        <div class="metric-card">
          <span>当前目标</span>
          <strong>{{ goalLabel }}</strong>
          <p>{{ goalDescription }}</p>
        </div>
        <div class="metric-card">
          <span>主页称呼</span>
          <strong>{{ displayNickname }}</strong>
          <p>昵称可以在个人主页里单独修改，这里的目标设置不会影响主页称呼。</p>
        </div>
      </aside>
    </section>

    <section v-if="initialLoading" class="surface-card empty-state">
      正在加载目标设置，请稍候…
    </section>

    <section v-else class="goal-layout">
      <div class="goal-main">
        <section class="surface-card">
          <header class="section-head">
            <h3 class="section-title">先说你的目标</h3>
            <p class="section-subtitle">先用一句话描述你最近想调整的方向，系统会帮你整理一版更清晰的建议。</p>
          </header>

          <div v-if="!hasSession" class="locked-panel">
            <h4>先完成账号验证</h4>
            <p>目标设置会和当前账号一起保存。先去个人主页完成手机号验证，再回来继续设置即可。</p>
            <div class="page-actions profile-actions">
              <RouterLink to="/profile" class="button button--primary">去个人主页验证</RouterLink>
            </div>
          </div>

          <template v-else>
            <div class="assistant-toolbar">
              <button
                class="button button--secondary"
                :disabled="pageBusy || !speechSupported"
                @click="toggleSpeech"
              >
                {{ speechSupported ? (listening ? '停止语音输入' : '语音输入目标') : '当前浏览器暂不支持语音输入' }}
              </button>
              <span class="soft-note assistant-hint">
                {{ speechSupported ? '如果更习惯打字，也可以直接在下方输入。' : '你也可以直接在下方手动输入目标描述。' }}
              </span>
            </div>

            <div class="field-stack field-stack--full">
              <label class="field-label" for="assistantGoal">目标描述</label>
              <textarea
                id="assistantGoal"
                v-model.trim="assistantForm.rawText"
                rows="4"
                placeholder="例如：我想减脂，乳糖不耐受，每周运动 3 次，帮我整理一个更适合我的目标"
              />
            </div>

            <div class="note-panel">
              <p>{{ assistantContextSummary }}</p>
            </div>

            <div class="page-actions profile-actions assistant-actions">
              <button class="button button--secondary" :disabled="pageBusy" @click="useAssistant(false)">
                {{ assistantBusy ? '生成中…' : '先看建议' }}
              </button>
              <button class="button button--primary" :disabled="pageBusy" @click="useAssistant(true)">
                应用到目标
              </button>
            </div>

            <p class="soft-note goal-note">先看看建议，合适的话再一键应用到当前目标。</p>
            <p v-if="assistantMessage" class="soft-note profile-success">{{ assistantMessage }}</p>
            <p v-if="assistantError" class="soft-note soft-note--error">{{ assistantError }}</p>

            <div v-if="assistantSummary" class="summary-card">
              <h4>助手建议摘要</h4>
              <p>{{ assistantSummary }}</p>
            </div>
          </template>
        </section>

        <section class="surface-card">
          <header class="section-head">
            <h3 class="section-title">手动调整设置</h3>
            <p class="section-subtitle">如果你已经知道自己的目标，也可以直接在这里修改基础信息、热量和饮食限制。</p>
          </header>

          <div v-if="!hasSession" class="locked-panel">
            <h4>完成账号验证后继续</h4>
            <p>只有已验证的个人账号才能保存目标、基础信息和饮食限制，后续分析结果也会跟随这个账号沉淀。</p>
          </div>

          <template v-else>
            <div class="field-grid">
              <div class="field-stack">
                <label class="field-label" for="goal">健康目标</label>
                <select id="goal" v-model="form.healthGoal">
                  <option value="WEIGHT_LOSS">减脂</option>
                  <option value="MUSCLE_GAIN">增肌</option>
                  <option value="MAINTENANCE">维持</option>
                  <option value="GENERAL_HEALTH">综合健康</option>
                </select>
              </div>

              <div class="field-stack">
                <label class="field-label" for="calorie">每日热量目标（kcal）</label>
                <input id="calorie" v-model.number="form.dailyCalorieTarget" type="number" min="500" max="5000" />
              </div>

              <div class="field-stack">
                <label class="field-label" for="age">年龄（可选）</label>
                <input id="age" v-model.trim="form.age" type="number" min="1" max="120" placeholder="例如 22" />
              </div>

              <div class="field-stack">
                <label class="field-label" for="height">身高 cm（可选）</label>
                <input id="height" v-model.trim="form.heightCm" type="number" min="50" max="260" placeholder="例如 170" />
              </div>

              <div class="field-stack">
                <label class="field-label" for="weight">体重 kg（可选）</label>
                <input id="weight" v-model.trim="form.weightKg" type="number" min="20" max="300" step="0.1" placeholder="例如 65.5" />
              </div>

              <div class="field-stack">
                <label class="field-label" for="gender">性别</label>
                <select id="gender" v-model="form.gender">
                  <option value="FEMALE">女</option>
                  <option value="MALE">男</option>
                </select>
              </div>

              <div class="field-stack field-stack--full">
                <label class="field-label" for="activity">活动水平</label>
                <select id="activity" v-model="form.activityLevel">
                  <option value="LOW">活动量低</option>
                  <option value="MEDIUM">活动量中</option>
                  <option value="HIGH">活动量高</option>
                </select>
              </div>
            </div>

            <div class="restriction-panel">
              <div class="restriction-panel__head">
                <h4>饮食限制</h4>
                <p>可以多选，帮助系统在给建议时避开你明确不希望出现的内容。</p>
              </div>
              <div class="restriction-list">
                <button
                  v-for="item in restrictionOptions"
                  :key="item.code"
                  type="button"
                  class="restriction-toggle"
                  :class="{ 'is-selected': selectedRestrictions.includes(item.code) }"
                  @click="toggleRestriction(item.code)"
                >
                  {{ item.label }}
                </button>
              </div>
            </div>

            <div class="page-actions profile-actions">
              <button class="button button--primary" :disabled="pageBusy" @click="saveGoalSettings">
                {{ saving ? '保存中…' : '保存目标设置' }}
              </button>
            </div>

            <p class="soft-note goal-note">这里保存的是长期目标与资料上下文，后续上传分析会优先参考这些设置。</p>
          </template>

          <p v-if="error" class="soft-note soft-note--error">{{ error }}</p>
          <p v-if="success" class="soft-note profile-success">{{ success }}</p>
        </section>
      </div>

      <aside class="surface-card goal-side">
        <header class="section-head">
          <h3 class="section-title">当前设置概览</h3>
          <p class="section-subtitle">先看清自己现在的目标和限制，再决定下一步要不要继续调整。</p>
        </header>

        <div class="tip-list">
          <article class="tip-card">
            <h4>当前目标</h4>
            <p>{{ goalLabel }} · 每日 {{ form.dailyCalorieTarget || 0 }} kcal</p>
          </article>
          <article class="tip-card">
            <h4>基础信息</h4>
            <p>{{ bodyStatsLabel }}</p>
          </article>
          <article class="tip-card">
            <h4>活动状态</h4>
            <p>{{ activityLabel }}</p>
          </article>
        </div>

        <div class="restriction-box">
          <span class="restriction-box__label">当前限制标签</span>
          <div class="restriction-chips">
            <span v-if="!selectedRestrictions.length" class="restriction-chip is-empty">暂无限制</span>
            <span v-for="item in selectedRestrictions" :key="item" class="restriction-chip">{{ restrictionText(item) }}</span>
          </div>
        </div>

        <div class="page-actions profile-actions side-actions">
          <RouterLink to="/profile" class="button button--secondary">返回个人主页</RouterLink>
        </div>
      </aside>
    </section>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import {
  getStoredWebProfileContext,
  getStoredWebSession,
  getUserProfile,
  parseGoalByAssistant,
  saveStoredWebProfileContext,
  updateUserProfile,
} from '@/api/dietLog'

const storedSession = getStoredWebSession()
const currentUserId = ref(storedSession.userId)
const currentPhone = ref(storedSession.phone)
const profilePhone = ref('')
const profileNickname = ref('')
const loading = ref(false)
const saving = ref(false)
const assistantBusy = ref(false)
const loadedOnce = ref(false)
const listening = ref(false)
const speechSupported = ref(false)
const error = ref('')
const success = ref('')
const assistantError = ref('')
const assistantMessage = ref('')
const assistantSummary = ref('')
const assistantForm = reactive({
  rawText: '',
})
const form = reactive({
  healthGoal: 'WEIGHT_LOSS',
  dailyCalorieTarget: 1800,
  age: '',
  heightCm: '',
  weightKg: '',
  gender: 'FEMALE',
  activityLevel: 'MEDIUM',
})
const selectedRestrictions = ref([])

const restrictionOptions = [
  { code: 'high_sugar', label: '控糖' },
  { code: 'spicy', label: '少辣' },
  { code: 'dairy', label: '乳制品限制' },
  { code: 'lactose', label: '乳糖不耐' },
  { code: 'gluten', label: '麸质限制' },
  { code: 'seafood', label: '海鲜限制' },
  { code: 'nuts', label: '坚果过敏' },
]

let speechRecognition = null

const hasSession = computed(() => Boolean(currentUserId.value && currentPhone.value))
const pageBusy = computed(() => loading.value || saving.value || assistantBusy.value)
const initialLoading = computed(() => hasSession.value && loading.value && !loadedOnce.value)

const goalLabel = computed(() => {
  const labels = {
    WEIGHT_LOSS: '减脂',
    MUSCLE_GAIN: '增肌',
    MAINTENANCE: '维持',
    GENERAL_HEALTH: '综合健康',
  }
  return labels[form.healthGoal] || '综合健康'
})

const goalDescription = computed(() => {
  const descriptions = {
    WEIGHT_LOSS: '更关注总热量、饱腹感和餐次结构的稳定性。',
    MUSCLE_GAIN: '更关注蛋白质补足、恢复需求和摄入不要偏低。',
    MAINTENANCE: '更关注结构平衡，避免长期过高或过低的摄入波动。',
    GENERAL_HEALTH: '更关注整体均衡、饮食多样性和长期可持续性。',
  }
  return descriptions[form.healthGoal] || '更关注整体均衡、饮食多样性和长期可持续性。'
})

const displayNickname = computed(() => {
  const nickname = profileNickname.value.trim()
  if (nickname) {
    return nickname
  }
  return hasSession.value ? '食迹用户' : '未验证账号'
})

const heroTitle = computed(() =>
  hasSession.value ? `${displayNickname.value}，继续调整你的目标设置` : '先验证手机号，再开始设置你的目标'
)

const goalNote = computed(() =>
  hasSession.value
    ? '这里保存的是会长期影响分析建议的目标与资料上下文。'
    : '完成手机号验证后，目标设置和后续分析结果才会归到你的账号下。'
)

const accountLabel = computed(() => currentPhone.value || profilePhone.value || '未验证账号')

const activityLabel = computed(() => {
  const labels = {
    LOW: '活动量低，更需要留意总热量和基础摄入。',
    MEDIUM: '活动量中，适合维持相对均衡的饮食结构。',
    HIGH: '活动量高，更要关注恢复和能量补给是否充足。',
  }
  return labels[form.activityLevel] || '活动量中，适合维持相对均衡的饮食结构。'
})

const bodyStatsLabel = computed(() => {
  const parts = []
  if (form.age) parts.push(`年龄 ${form.age} 岁`)
  if (form.heightCm) parts.push(`身高 ${form.heightCm} cm`)
  if (form.weightKg) parts.push(`体重 ${form.weightKg} kg`)
  if (form.gender) parts.push(form.gender === 'MALE' ? '男' : '女')
  return parts.length ? parts.join(' / ') : '还没有补充基础身体信息'
})

const assistantContextSummary = computed(() => {
  const parts = []
  if (form.age) parts.push(`年龄 ${form.age} 岁`)
  if (form.heightCm) parts.push(`身高 ${form.heightCm} cm`)
  if (form.weightKg) parts.push(`体重 ${form.weightKg} kg`)
  parts.push(`性别 ${form.gender === 'MALE' ? '男' : '女'}`)
  parts.push(`活动量 ${form.activityLevel === 'LOW' ? '低' : form.activityLevel === 'HIGH' ? '高' : '中'}`)
  return `当前解析会参考：${parts.join(' / ')}。如果有缺失项，可以先在下方补充后再重新生成建议。`
})

onMounted(() => {
  setupSpeechRecognition()
  if (hasSession.value) {
    loadGoalSettings()
    return
  }
  loadedOnce.value = true
})

onBeforeUnmount(() => {
  if (speechRecognition && listening.value) {
    speechRecognition.stop()
  }
})

function setupSpeechRecognition() {
  if (typeof window === 'undefined') return
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
  if (!SpeechRecognition) {
    speechSupported.value = false
    return
  }

  speechSupported.value = true
  speechRecognition = new SpeechRecognition()
  speechRecognition.lang = 'zh-CN'
  speechRecognition.interimResults = true
  speechRecognition.continuous = false
  speechRecognition.onresult = event => {
    assistantForm.rawText = Array.from(event.results)
      .map(result => result[0]?.transcript || '')
      .join('')
      .trim()
  }
  speechRecognition.onerror = () => {
    listening.value = false
    assistantError.value = '当前浏览器暂时无法使用语音输入，请改用手动输入。'
  }
  speechRecognition.onend = () => {
    listening.value = false
  }
}

function parseOptionalInt(value) {
  if (value === '' || value === null || value === undefined) return null
  const parsed = Number.parseInt(value, 10)
  return Number.isNaN(parsed) ? null : parsed
}

function parseOptionalFloat(value) {
  if (value === '' || value === null || value === undefined) return null
  const parsed = Number.parseFloat(value)
  return Number.isNaN(parsed) ? null : parsed
}

function normalizeRestrictionList(list) {
  return Array.isArray(list) ? list.map(item => item.toString()) : []
}

function restrictionText(code) {
  return restrictionOptions.find(item => item.code === code)?.label || code
}

function toggleRestriction(code) {
  if (selectedRestrictions.value.includes(code)) {
    selectedRestrictions.value = selectedRestrictions.value.filter(item => item !== code)
    return
  }
  selectedRestrictions.value = [...selectedRestrictions.value, code]
}

function persistProfileContext() {
  if (!currentUserId.value) return
  saveStoredWebProfileContext(currentUserId.value, {
    age: parseOptionalInt(form.age),
    heightCm: parseOptionalInt(form.heightCm),
    weightKg: parseOptionalFloat(form.weightKg),
    gender: form.gender,
    activityLevel: form.activityLevel,
  })
}

function applyProfile(profile, context = {}) {
  profilePhone.value = profile.phone ?? ''
  profileNickname.value = profile.nickname ?? ''
  form.healthGoal = profile.healthGoal ?? 'GENERAL_HEALTH'
  form.dailyCalorieTarget = profile.dailyCalorieTarget ?? 2000
  selectedRestrictions.value = normalizeRestrictionList(profile.dietaryRestrictions)

  const heightCm = profile.heightCm ?? context.heightCm ?? ''
  const weightKg = profile.weightKg ?? context.weightKg ?? ''
  const gender = (profile.gender ?? context.gender ?? 'FEMALE').toUpperCase()
  const activityLevel = (context.activityLevel ?? 'MEDIUM').toUpperCase()

  form.age = context.age === '' || context.age === null || context.age === undefined ? '' : String(context.age)
  form.heightCm = heightCm === '' || heightCm === null || heightCm === undefined ? '' : String(heightCm)
  form.weightKg = weightKg === '' || weightKg === null || weightKg === undefined ? '' : String(weightKg)
  form.gender = gender === 'MALE' ? 'MALE' : 'FEMALE'
  form.activityLevel = ['LOW', 'MEDIUM', 'HIGH'].includes(activityLevel) ? activityLevel : 'MEDIUM'

  if (!currentPhone.value && profilePhone.value) {
    currentPhone.value = profilePhone.value
  }
}

async function loadGoalSettings() {
  if (!hasSession.value) {
    loadedOnce.value = true
    return
  }
  loading.value = true
  error.value = ''
  success.value = ''
  try {
    const profile = await getUserProfile(currentUserId.value)
    const context = getStoredWebProfileContext(currentUserId.value)
    applyProfile(profile, context)
  } catch (e) {
    error.value = e?.response?.data?.error || '加载目标设置失败'
  } finally {
    loading.value = false
    loadedOnce.value = true
  }
}

async function saveGoalSettings() {
  if (!hasSession.value) {
    error.value = '请先完成手机号验证，再保存目标设置'
    return
  }
  saving.value = true
  error.value = ''
  success.value = ''
  try {
    const profile = await updateUserProfile(currentUserId.value, {
      nickname: profileNickname.value.trim() || null,
      healthGoal: form.healthGoal,
      dailyCalorieTarget: form.dailyCalorieTarget,
      dietaryRestrictions: selectedRestrictions.value,
      heightCm: parseOptionalInt(form.heightCm),
      weightKg: parseOptionalFloat(form.weightKg),
      gender: form.gender || null,
    })
    persistProfileContext()
    applyProfile(profile, getStoredWebProfileContext(currentUserId.value))
    success.value = '目标设置已保存，后续分析会优先参考这份设置。'
  } catch (e) {
    error.value = e?.response?.data?.error || '保存目标设置失败，请稍后重试'
  } finally {
    saving.value = false
  }
}

async function useAssistant(apply) {
  if (!hasSession.value) {
    assistantError.value = '请先完成手机号验证，再使用目标助手。'
    return
  }
  if (!assistantForm.rawText.trim()) {
    assistantError.value = '请先输入或语音描述你的目标。'
    return
  }

  assistantBusy.value = true
  assistantError.value = ''
  assistantMessage.value = ''
  assistantSummary.value = ''
  success.value = ''

  try {
    const parsed = await parseGoalByAssistant(currentUserId.value, {
      rawText: assistantForm.rawText.trim(),
      age: parseOptionalInt(form.age),
      heightCm: parseOptionalInt(form.heightCm),
      weightKg: parseOptionalFloat(form.weightKg),
      gender: form.gender,
      activityLevel: form.activityLevel,
      applyToProfile: apply,
    })

    form.healthGoal = (parsed.healthGoal || form.healthGoal).toString()
    form.dailyCalorieTarget = Number(parsed.dailyCalorieTarget ?? form.dailyCalorieTarget)
    selectedRestrictions.value = normalizeRestrictionList(parsed.dietaryRestrictions)
    assistantSummary.value = (parsed.summary || '').toString()
    assistantMessage.value = apply ? '已应用到当前目标，你也可以继续微调后再保存。' : '建议已经生成，你可以先看看再决定是否采用。'

    if (apply) {
      persistProfileContext()
      success.value = '助手建议已应用到当前目标设置。'
    }
  } catch (e) {
    assistantError.value = e?.response?.data?.error || '生成目标建议失败，请稍后重试'
  } finally {
    assistantBusy.value = false
  }
}

function toggleSpeech() {
  if (!speechSupported.value || !speechRecognition) {
    assistantError.value = '当前浏览器暂时无法使用语音输入，请改用手动输入。'
    return
  }

  assistantError.value = ''
  if (listening.value) {
    speechRecognition.stop()
    listening.value = false
    return
  }

  speechRecognition.start()
  listening.value = true
}
</script>

<style scoped>
.hero-aside,
.tip-list,
.goal-main {
  display: grid;
  gap: 14px;
}

.goal-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.08fr) minmax(300px, 0.92fr);
  gap: 18px;
}

.field-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.field-stack {
  display: grid;
  gap: 8px;
}

.field-stack--full {
  grid-column: 1 / -1;
}

.field-label {
  font-weight: 700;
}

.goal-note {
  margin-top: 14px;
}

.assistant-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
  margin-bottom: 16px;
}

.assistant-hint {
  margin-top: 0;
}

textarea {
  min-height: 132px;
  resize: vertical;
}

.note-panel {
  margin-top: 16px;
  padding: 16px 18px;
  border-radius: 22px;
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.96), rgba(255, 255, 255, 0.96));
  border: 1px solid rgba(234, 215, 202, 0.95);
}

.note-panel p {
  color: var(--muted);
  line-height: 1.7;
}

.assistant-actions {
  margin-top: 16px;
}

.assistant-actions .button {
  min-width: 0;
}

.summary-card {
  margin-top: 16px;
  padding: 18px;
  border-radius: 22px;
  background: rgba(244, 252, 247, 0.92);
  border: 1px solid rgba(183, 219, 197, 0.95);
}

.summary-card h4 {
  font-size: 1rem;
  font-weight: 800;
  color: var(--success);
}

.summary-card p {
  margin-top: 10px;
  color: var(--muted);
  line-height: 1.7;
}

.profile-actions {
  margin-top: 18px;
}

.locked-panel {
  display: grid;
  gap: 10px;
  padding: 22px;
  border-radius: 24px;
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.96), rgba(255, 253, 249, 0.96));
  border: 1px solid rgba(234, 215, 202, 0.96);
}

.locked-panel h4,
.tip-card h4,
.restriction-panel__head h4 {
  font-size: 1rem;
  font-weight: 800;
}

.locked-panel p,
.tip-card p,
.restriction-panel__head p {
  color: var(--muted);
  line-height: 1.65;
}

.restriction-panel {
  margin-top: 18px;
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 249, 243, 0.86);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.restriction-list {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 14px;
}

.restriction-toggle {
  border: 1px solid rgba(240, 210, 189, 0.98);
  border-radius: 999px;
  padding: 10px 16px;
  background: rgba(255, 255, 255, 0.94);
  color: var(--accent-strong);
  font-weight: 700;
  cursor: pointer;
  transition: transform 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
}

.restriction-toggle:hover {
  transform: translateY(-1px);
  box-shadow: var(--shadow-soft);
}

.restriction-toggle.is-selected {
  background: rgba(255, 235, 217, 0.98);
  border-color: rgba(214, 134, 73, 0.52);
}

.tip-card {
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 251, 247, 0.94);
  border: 1px solid rgba(238, 224, 213, 0.94);
}

.restriction-box {
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 248, 242, 0.94);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.restriction-box__label {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 10px;
}

.restriction-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.restriction-chip {
  display: inline-flex;
  align-items: center;
  min-height: 34px;
  padding: 0 14px;
  border-radius: 999px;
  background: rgba(255, 241, 227, 0.95);
  color: var(--accent-strong);
  font-size: 0.86rem;
  font-weight: 700;
}

.restriction-chip.is-empty {
  background: rgba(244, 239, 232, 0.92);
  color: var(--muted);
}

.profile-success {
  color: var(--success);
}

.side-actions {
  margin-top: 20px;
}

@media (max-width: 980px) {
  .goal-layout {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 720px) {
  .field-grid,
  .assistant-toolbar,
  .assistant-actions {
    grid-template-columns: 1fr;
  }

  .assistant-toolbar {
    display: grid;
  }

  .assistant-actions {
    display: grid;
  }
}
</style>