<template>
  <div class="page profile-view">
    <section class="page-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">个人主页</span>
        <h2 class="page-hero__title">{{ heroTitle }}</h2>
        <p class="page-hero__subtitle">
          在这里确认手机号账号、查看当前主页称呼，并按需要修改昵称。目标、基础信息和饮食限制已经单独放到目标设置页维护。
        </p>
        <div class="page-actions">
          <RouterLink to="/goals" class="button button--primary">前往目标设置</RouterLink>
          <button class="button button--secondary" :disabled="loading" @click="loadProfile">
            {{ loading ? '刷新中…' : '刷新资料' }}
          </button>
          <button v-if="hasSession" class="button button--secondary" :disabled="pageBusy" @click="switchAccount">
            切换账号
          </button>
        </div>
        <p class="soft-note profile-note">{{ profileNote }}</p>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前账号</span>
          <strong>{{ accountLabel }}</strong>
          <p>{{ hasSession ? '当前网页端已经绑定手机号账号。' : '还没有完成手机号验证。' }}</p>
        </div>
        <div class="metric-card">
          <span>当前昵称</span>
          <strong>{{ displayNickname }}</strong>
          <p>{{ nicknameStatusText }}</p>
        </div>
        <div class="metric-card">
          <span>当前目标</span>
          <strong>{{ goalLabel }}</strong>
          <p>{{ goalDescription }}</p>
        </div>
      </aside>
    </section>

    <section v-if="initialLoading" class="surface-card empty-state">
      正在加载个人主页，请稍候…
    </section>

    <section v-else class="profile-layout">
      <div class="profile-main">
        <section class="surface-card">
          <header class="section-head">
            <h3 class="section-title">手机号验证</h3>
            <p class="section-subtitle">先确认当前账号身份，再继续维护昵称、历史记录和目标设置。</p>
          </header>

          <div class="account-overview">
            <article class="account-tile">
              <span class="account-tile__label">账号状态</span>
              <strong>{{ hasSession ? '已验证手机号' : '未验证' }}</strong>
              <p>{{ hasSession ? maskedPhoneText : '完成验证后，新的分析记录和历史数据才会归到你的个人账号。' }}</p>
            </article>
            <article class="account-tile">
              <span class="account-tile__label">数据归属</span>
              <strong>{{ hasSession ? '跟随当前账号保存' : '验证后开始归档' }}</strong>
              <p>网页端现在只会把上传结果、历史记录和主页资料保存到当前已验证账号，不再回退到默认演示账号。</p>
            </article>
          </div>

          <div class="field-grid account-auth-grid">
            <div class="field-stack">
              <label class="field-label" for="loginPhone">手机号</label>
              <input id="loginPhone" v-model.trim="loginForm.phone" type="tel" placeholder="输入 11 位手机号" />
            </div>

            <div class="field-stack">
              <label class="field-label" for="loginCode">验证码</label>
              <input id="loginCode" v-model.trim="loginForm.code" type="text" placeholder="输入 6 位验证码" />
            </div>
          </div>

          <div class="page-actions profile-actions">
            <button class="button button--secondary" :disabled="authBusy || !loginForm.phone" @click="requestCode">
              {{ authBusy ? '发送中…' : '发送验证码' }}
            </button>
            <button
              class="button button--primary"
              :disabled="authBusy || !loginForm.phone || !loginForm.code"
              @click="bindAccount"
            >
              {{ authBusy ? '验证中…' : '验证并进入个人账号' }}
            </button>
          </div>

          <p v-if="debugCode" class="soft-note">当前可用验证码：{{ debugCode }}</p>
          <p v-if="authError" class="soft-note soft-note--error">{{ authError }}</p>
          <p v-if="authMessage" class="soft-note profile-success">{{ authMessage }}</p>
        </section>

        <section class="surface-card">
          <header class="section-head">
            <h3 class="section-title">主页昵称</h3>
            <p class="section-subtitle">主页称呼单独维护，不会和目标设置页混在一起。</p>
          </header>

          <div v-if="!hasSession" class="locked-panel">
            <h4>完成账号验证后继续</h4>
            <p>只有已验证的个人账号才能保存昵称，后续分析结果和历史记录也会跟随这个账号沉淀。</p>
          </div>

          <template v-else>
            <div class="nickname-overview">
              <article class="account-tile account-tile--wide">
                <span class="account-tile__label">主页当前称呼</span>
                <strong>{{ displayNickname }}</strong>
                <p>{{ nicknameStatusText }}</p>
              </article>
              <article class="account-tile">
                <span class="account-tile__label">当前账号</span>
                <strong>{{ accountLabel }}</strong>
                <p>{{ currentUserId ? `用户 ID #${currentUserId}` : '未验证账号' }}</p>
              </article>
            </div>

            <div v-if="!editingNickname" class="nickname-panel">
              <p>如果你希望网页端和移动端显示更一致的称呼，可以在这里单独修改昵称。</p>
              <div class="page-actions profile-actions">
                <button class="button button--primary" :disabled="pageBusy" @click="startEditingNickname">
                  {{ nicknameActionLabel }}
                </button>
              </div>
            </div>

            <template v-else>
              <div class="field-grid">
                <div class="field-stack">
                  <label class="field-label" for="nickname">昵称</label>
                  <input
                    id="nickname"
                    v-model.trim="form.nickname"
                    type="text"
                    maxlength="24"
                    placeholder="不填写时将继续显示系统默认昵称"
                  />
                </div>

                <div class="field-stack">
                  <label class="field-label">当前账号</label>
                  <div class="readonly-panel">
                    <span>手机号账号</span>
                    <strong>{{ accountLabel }}</strong>
                    <small>{{ currentUserId ? `用户 ID #${currentUserId}` : '未验证账号' }}</small>
                  </div>
                </div>
              </div>

              <div class="page-actions profile-actions">
                <button class="button button--primary" :disabled="pageBusy" @click="saveNickname">
                  {{ savingNickname ? '保存中…' : '保存昵称' }}
                </button>
                <button class="button button--secondary" :disabled="pageBusy" @click="cancelEditingNickname">
                  取消
                </button>
              </div>
            </template>
          </template>

          <p v-if="error" class="soft-note soft-note--error">{{ error }}</p>
          <p v-if="success" class="soft-note profile-success">{{ success }}</p>
        </section>
      </div>

      <aside class="surface-card profile-side">
        <header class="section-head">
          <h3 class="section-title">当前设置概览</h3>
          <p class="section-subtitle">主页只负责账号和昵称，目标、热量、饮食限制已经单独放到目标设置页。</p>
        </header>

        <div class="tip-list">
          <article class="tip-card">
            <h4>当前目标</h4>
            <p>{{ goalLabel }} · 每日 {{ form.dailyCalorieTarget || 0 }} kcal</p>
          </article>
          <article class="tip-card">
            <h4>饮食限制</h4>
            <p>{{ restrictionsSummary }}</p>
          </article>
          <article class="tip-card">
            <h4>身体信息</h4>
            <p>{{ bodyStatsLabel }}</p>
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
          <RouterLink to="/goals" class="button button--primary">去目标设置页继续完善</RouterLink>
        </div>
      </aside>
    </section>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import {
  clearStoredWebSession,
  getStoredWebSession,
  getUserProfile,
  saveStoredWebSession,
  sendLoginCode,
  updateUserProfile,
  verifyLoginCode,
} from '@/api/dietLog'

const storedSession = getStoredWebSession()
const currentUserId = ref(storedSession.userId)
const currentPhone = ref(storedSession.phone)
const profilePhone = ref('')
const loading = ref(false)
const savingNickname = ref(false)
const authBusy = ref(false)
const loadedOnce = ref(false)
const editingNickname = ref(false)
const error = ref('')
const success = ref('')
const authError = ref('')
const authMessage = ref('')
const debugCode = ref('')
const loginForm = reactive({
  phone: currentPhone.value,
  code: '',
})
const form = reactive({
  nickname: '',
  healthGoal: 'WEIGHT_LOSS',
  dailyCalorieTarget: 1800,
  dietaryRestrictions: [],
  heightCm: '',
  weightKg: '',
  gender: '',
})

const restrictionOptions = [
  { code: 'high_sugar', label: '控糖' },
  { code: 'spicy', label: '少辣' },
  { code: 'dairy', label: '乳制品限制' },
  { code: 'lactose', label: '乳糖不耐' },
  { code: 'gluten', label: '麸质限制' },
  { code: 'seafood', label: '海鲜限制' },
  { code: 'nuts', label: '坚果过敏' },
]

const hasSession = computed(() => Boolean(currentUserId.value && currentPhone.value))
const pageBusy = computed(() => loading.value || savingNickname.value || authBusy.value)
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

const selectedRestrictions = computed(() => (Array.isArray(form.dietaryRestrictions) ? form.dietaryRestrictions : []))

const displayNickname = computed(() => {
  const nickname = form.nickname.trim()
  if (nickname) {
    return nickname
  }
  return hasSession.value ? '食迹用户' : '未验证账号'
})

const heroTitle = computed(() =>
  hasSession.value ? `${displayNickname.value}，这是你的个人主页` : '先验证手机号，再进入你的个人主页'
)

const profileNote = computed(() =>
  hasSession.value
    ? '当前账号下的主页昵称、历史记录和目标设置都会持续同步保存。'
    : '完成手机号验证后，个人主页、历史记录和目标设置才会归到你的账号下。'
)

const nicknameStatusText = computed(() =>
  form.nickname.trim()
    ? '当前正在使用你设置的昵称。'
    : '当前仍在使用系统默认昵称，你可以随时改成自己更习惯的称呼。'
)

const nicknameActionLabel = computed(() => (form.nickname.trim() ? '修改昵称' : '设置昵称'))

const accountLabel = computed(() => currentPhone.value || profilePhone.value || '未验证账号')
const maskedPhoneText = computed(() => maskPhone(currentPhone.value || profilePhone.value))

const restrictionsSummary = computed(() => {
  if (!selectedRestrictions.value.length) {
    return '还没有添加限制标签。'
  }
  return selectedRestrictions.value.map(item => restrictionText(item)).join('、')
})

const bodyStatsLabel = computed(() => {
  const parts = []
  if (form.heightCm) parts.push(`身高 ${form.heightCm} cm`)
  if (form.weightKg) parts.push(`体重 ${form.weightKg} kg`)
  if (form.gender) parts.push(form.gender === 'MALE' ? '男' : '女')
  return parts.length ? parts.join(' / ') : '还没有同步到身体信息。'
})

onMounted(() => {
  if (hasSession.value) {
    loadProfile()
    return
  }
  loadedOnce.value = true
})

function maskPhone(phone) {
  if (!phone || phone.length < 7) {
    return phone || '暂未绑定手机号'
  }
  return `${phone.slice(0, 3)}****${phone.slice(-4)}`
}

function restrictionText(code) {
  return restrictionOptions.find(item => item.code === code)?.label || code
}

function resetProfileForm() {
  profilePhone.value = ''
  form.nickname = ''
  form.healthGoal = 'WEIGHT_LOSS'
  form.dailyCalorieTarget = 1800
  form.dietaryRestrictions = []
  form.heightCm = ''
  form.weightKg = ''
  form.gender = ''
  editingNickname.value = false
}

function applyProfile(profile) {
  profilePhone.value = profile.phone ?? ''
  form.nickname = profile.nickname ?? ''
  form.healthGoal = profile.healthGoal ?? 'GENERAL_HEALTH'
  form.dailyCalorieTarget = profile.dailyCalorieTarget ?? 2000
  form.dietaryRestrictions = Array.isArray(profile.dietaryRestrictions)
    ? profile.dietaryRestrictions.map(item => item.toString())
    : []
  form.heightCm = profile.heightCm === null || profile.heightCm === undefined ? '' : String(profile.heightCm)
  form.weightKg = profile.weightKg === null || profile.weightKg === undefined ? '' : String(profile.weightKg)
  form.gender = profile.gender?.toUpperCase?.() || ''
  if (!currentPhone.value && profilePhone.value) {
    currentPhone.value = profilePhone.value
  }
  if (!loginForm.phone && (currentPhone.value || profilePhone.value)) {
    loginForm.phone = currentPhone.value || profilePhone.value
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

async function loadProfile() {
  if (!hasSession.value) {
    loadedOnce.value = true
    return
  }
  loading.value = true
  error.value = ''
  try {
    const profile = await getUserProfile(currentUserId.value)
    applyProfile(profile)
  } catch (e) {
    error.value = e?.response?.data?.error || '加载个人主页失败'
  } finally {
    loading.value = false
    loadedOnce.value = true
  }
}

function startEditingNickname() {
  editingNickname.value = true
  success.value = ''
  error.value = ''
}

function cancelEditingNickname() {
  editingNickname.value = false
  success.value = ''
  error.value = ''
}

async function saveNickname() {
  if (!hasSession.value) {
    error.value = '请先完成手机号验证，再保存昵称'
    return
  }
  savingNickname.value = true
  error.value = ''
  success.value = ''
  try {
    const profile = await updateUserProfile(currentUserId.value, {
      nickname: form.nickname.trim() || null,
      healthGoal: form.healthGoal,
      dailyCalorieTarget: form.dailyCalorieTarget,
      dietaryRestrictions: selectedRestrictions.value,
      heightCm: parseOptionalInt(form.heightCm),
      weightKg: parseOptionalFloat(form.weightKg),
      gender: form.gender || null,
    })
    applyProfile(profile)
    editingNickname.value = false
    success.value = '昵称已保存，个人主页会使用新的称呼。'
  } catch (e) {
    error.value = e?.response?.data?.error || '保存昵称失败，请稍后重试'
  } finally {
    savingNickname.value = false
  }
}

async function requestCode() {
  authBusy.value = true
  authError.value = ''
  authMessage.value = ''
  try {
    const data = await sendLoginCode(loginForm.phone)
    debugCode.value = data.debugCode || ''
    if (debugCode.value) {
      loginForm.code = debugCode.value
      authMessage.value = '验证码已生成，可直接填写下方验证码完成验证。'
    } else {
      authMessage.value = data.message || '验证码已发送。'
    }
  } catch (e) {
    authError.value = e?.response?.data?.error || '发送验证码失败'
  } finally {
    authBusy.value = false
  }
}

async function bindAccount() {
  authBusy.value = true
  authError.value = ''
  authMessage.value = ''
  error.value = ''
  success.value = ''
  try {
    const session = await verifyLoginCode(loginForm.phone, loginForm.code)
    saveStoredWebSession(session)
    currentUserId.value = String(session.userId)
    currentPhone.value = session.phone || loginForm.phone
    loginForm.phone = currentPhone.value
    loginForm.code = ''
    authMessage.value = session.isNewUser ? '已创建并进入新的个人账号。' : '已进入当前手机号对应的个人账号。'
    await loadProfile()
  } catch (e) {
    authError.value = e?.response?.data?.error || '账号验证失败'
  } finally {
    authBusy.value = false
  }
}

function switchAccount() {
  clearStoredWebSession()
  currentUserId.value = ''
  currentPhone.value = ''
  loginForm.phone = ''
  loginForm.code = ''
  debugCode.value = ''
  error.value = ''
  success.value = ''
  authError.value = ''
  authMessage.value = '已退出当前网页账号，请重新验证手机号。'
  resetProfileForm()
  loadedOnce.value = true
}
</script>

<style scoped>
.hero-aside,
.tip-list,
.profile-main {
  display: grid;
  gap: 14px;
}

.profile-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.08fr) minmax(300px, 0.92fr);
  gap: 18px;
}

.field-grid,
.account-overview,
.nickname-overview {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.field-stack {
  display: grid;
  gap: 8px;
}

.field-label {
  font-weight: 700;
}

.profile-note {
  margin-top: 14px;
}

.account-overview {
  margin-bottom: 18px;
}

.account-tile,
.nickname-panel,
.tip-card,
.restriction-box,
.readonly-panel,
.locked-panel {
  border-radius: 22px;
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.account-tile {
  padding: 18px;
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.98), rgba(255, 255, 255, 0.98));
}

.account-tile--wide {
  grid-column: 1 / -1;
}

.account-tile__label,
.restriction-box__label,
.readonly-panel span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 10px;
}

.account-tile strong,
.readonly-panel strong {
  display: block;
  font-size: 1.2rem;
  line-height: 1.3;
  font-weight: 800;
}

.account-tile p,
.readonly-panel small,
.tip-card p,
.locked-panel p,
.nickname-panel p {
  margin-top: 8px;
  color: var(--muted);
  line-height: 1.65;
}

.readonly-panel {
  display: grid;
  gap: 6px;
  min-height: 100%;
  padding: 16px 18px;
  background: rgba(255, 249, 243, 0.86);
}

.nickname-panel {
  margin-top: 18px;
  padding: 18px;
  background: rgba(255, 249, 243, 0.86);
}

.account-auth-grid {
  margin-top: 4px;
}

.profile-actions {
  margin-top: 18px;
}

.locked-panel {
  display: grid;
  gap: 10px;
  padding: 22px;
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.96), rgba(255, 253, 249, 0.96));
  border-color: rgba(234, 215, 202, 0.96);
}

.locked-panel h4,
.tip-card h4 {
  font-size: 1rem;
  font-weight: 800;
}

.tip-card {
  padding: 18px;
  background: rgba(255, 251, 247, 0.94);
}

.restriction-box {
  padding: 18px;
  background: rgba(255, 248, 242, 0.94);
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
  .profile-layout {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 720px) {
  .field-grid,
  .account-overview,
  .nickname-overview {
    grid-template-columns: 1fr;
  }
}
</style>