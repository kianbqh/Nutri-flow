<template>
  <div class="page profile-view">
    <section class="page-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">目标与约束</span>
        <h2 class="page-hero__title">先把目标讲清楚，后续每次建议才会有稳定方向</h2>
        <p class="page-hero__subtitle">
          网页端把目标设置拆成更清楚的表单和说明区，方便在大屏上连续调整，再回到分析页验证结果有没有贴近预期。
        </p>
        <div class="page-actions">
          <button class="button button--primary" :disabled="loading" @click="save">
            {{ loading ? '保存中…' : '保存设置' }}
          </button>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前目标</span>
          <strong>{{ goalLabel }}</strong>
          <p>{{ goalDescription }}</p>
        </div>
        <div class="metric-card">
          <span>每日热量</span>
          <strong>{{ form.dailyCalorieTarget }} kcal</strong>
          <p>这会作为后续建议和提示语中的默认参照，不等于每餐都必须平均切分。</p>
        </div>
        <div class="metric-card">
          <span>饮食限制</span>
          <strong>{{ selectedRestrictions.length }} 项</strong>
          <p>{{ selectedRestrictions.length ? selectedRestrictions.join(' / ') : '当前没有额外限制。' }}</p>
        </div>
      </aside>
    </section>

    <section v-if="loading && !success && !error" class="surface-card empty-state">
      正在加载你的目标设置，请稍候…
    </section>

    <section v-else class="profile-layout">
      <section class="surface-card">
        <header class="section-head">
          <h3 class="section-title">目标设置</h3>
          <p class="section-subtitle">这些内容会影响后续热量判断、建议语气和风险提醒。</p>
        </header>

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

          <div class="field-stack field-stack--full">
            <label class="field-label" for="restrict">饮食限制（英文逗号分隔）</label>
            <input
              id="restrict"
              v-model="restrictionsInput"
              type="text"
              placeholder="例如 high_sugar, spicy"
            />
          </div>
        </div>

        <div class="page-actions profile-actions">
          <button class="button button--primary" :disabled="loading" @click="save">
            {{ loading ? '保存中…' : '保存设置' }}
          </button>
        </div>

        <p v-if="error" class="soft-note soft-note--error">{{ error }}</p>
        <p v-if="success" class="soft-note profile-success">{{ success }}</p>
      </section>

      <aside class="surface-card profile-side">
        <header class="section-head">
          <h3 class="section-title">这些设置会怎样影响分析</h3>
          <p class="section-subtitle">网页端把说明放在右侧，方便你边改边理解后续结果会往哪里偏。</p>
        </header>

        <div class="tip-list">
          <article class="tip-card">
            <h4>热量判断</h4>
            <p>每日目标会成为后续建议中的默认参照，帮助系统判断这顿饭更适合收敛还是补足。</p>
          </article>
          <article class="tip-card">
            <h4>建议语气</h4>
            <p>减脂、增肌和维持目标会改变建议重心，比如控制总量、补蛋白或维持结构稳定。</p>
          </article>
          <article class="tip-card">
            <h4>饮食限制</h4>
            <p>限制项会直接进入建议上下文，避免系统继续推荐你明确要规避的食物方向。</p>
          </article>
        </div>

        <div class="restriction-box">
          <span class="restriction-box__label">当前限制标签</span>
          <div class="restriction-chips">
            <span v-if="!selectedRestrictions.length" class="restriction-chip is-empty">暂无限制</span>
            <span v-for="item in selectedRestrictions" :key="item" class="restriction-chip">{{ item }}</span>
          </div>
        </div>
      </aside>
    </section>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { getUserProfile, updateUserProfile } from '@/api/dietLog'

const userId = localStorage.getItem('userId') || '1'

const loading = ref(false)
const error = ref('')
const success = ref('')
const restrictionsInput = ref('')
const form = reactive({
  healthGoal: 'WEIGHT_LOSS',
  dailyCalorieTarget: 1800,
})

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
    WEIGHT_LOSS: '更关注总热量、饱腹感和进食结构的稳定性。',
    MUSCLE_GAIN: '更关注蛋白质补足、恢复需求和热量不要吃得过低。',
    MAINTENANCE: '更关注结构平衡，避免长期偏高或偏低的摄入波动。',
    GENERAL_HEALTH: '更关注整体均衡、饮食多样性和长期可持续性。',
  }
  return descriptions[form.healthGoal] || '更关注整体均衡、饮食多样性和长期可持续性。'
})

const selectedRestrictions = computed(() =>
  restrictionsInput.value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
)

onMounted(async () => {
  loading.value = true
  error.value = ''
  try {
    const profile = await getUserProfile(userId)
    form.healthGoal = profile.healthGoal ?? 'GENERAL_HEALTH'
    form.dailyCalorieTarget = profile.dailyCalorieTarget ?? 2000
    restrictionsInput.value = (profile.dietaryRestrictions ?? []).join(', ')
  } catch (e) {
    error.value = e?.response?.data?.error || '加载用户配置失败'
  } finally {
    loading.value = false
  }
})

async function save() {
  loading.value = true
  error.value = ''
  success.value = ''
  try {
    const dietaryRestrictions = restrictionsInput.value
      .split(',')
      .map(s => s.trim())
      .filter(Boolean)

    await updateUserProfile(userId, {
      healthGoal: form.healthGoal,
      dailyCalorieTarget: form.dailyCalorieTarget,
      dietaryRestrictions,
    })

    success.value = '设置已保存，下一次分析将应用新目标。'
  } catch (e) {
    error.value = e?.response?.data?.error || '保存失败，请稍后重试'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.hero-aside,
.tip-list {
  display: grid;
  gap: 14px;
}

.profile-layout {
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

.profile-actions {
  margin-top: 18px;
}

.profile-success {
  color: var(--success);
  background: rgba(238, 248, 242, 0.92);
  border-color: rgba(65, 113, 91, 0.18);
}

.profile-side {
  display: grid;
  align-content: start;
  gap: 18px;
}

.tip-card {
  padding: 18px;
  border-radius: 22px;
  background: linear-gradient(180deg, rgba(255, 248, 242, 0.98), rgba(255, 255, 255, 0.98));
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.tip-card h4 {
  font-size: 1rem;
  font-weight: 800;
  margin-bottom: 8px;
}

.tip-card p {
  color: var(--muted);
  line-height: 1.7;
}

.restriction-box {
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 246, 237, 0.92);
  border: 1px solid rgba(242, 200, 168, 0.76);
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
  justify-content: center;
  min-height: 36px;
  padding: 8px 12px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.76);
  border: 1px solid rgba(233, 215, 202, 0.95);
  color: var(--text);
  font-weight: 700;
}

.restriction-chip.is-empty {
  color: var(--muted);
  font-weight: 600;
}

@media (max-width: 1024px) {
  .profile-layout,
  .field-grid {
    grid-template-columns: 1fr;
  }
}
</style>
