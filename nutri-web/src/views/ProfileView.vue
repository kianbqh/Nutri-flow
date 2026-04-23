<template>
  <div class="profile-view">
    <h2>个人饮食目标</h2>

    <div class="card">
      <div class="row">
        <label for="goal">健康目标</label>
        <select id="goal" v-model="form.healthGoal">
          <option value="WEIGHT_LOSS">减脂</option>
          <option value="MUSCLE_GAIN">增肌</option>
          <option value="MAINTENANCE">维持</option>
          <option value="GENERAL_HEALTH">综合健康</option>
        </select>
      </div>

      <div class="row">
        <label for="calorie">每日热量目标（kcal）</label>
        <input id="calorie" v-model.number="form.dailyCalorieTarget" type="number" min="500" max="5000" />
      </div>

      <div class="row">
        <label for="restrict">饮食限制（英文逗号分隔）</label>
        <input
          id="restrict"
          v-model="restrictionsInput"
          type="text"
          placeholder="e.g. high_sugar, spicy"
        />
      </div>

      <button class="btn" :disabled="loading" @click="save">
        {{ loading ? '保存中…' : '保存设置' }}
      </button>

      <p v-if="error" class="error">{{ error }}</p>
      <p v-if="success" class="success">{{ success }}</p>
    </div>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
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
.profile-view {
  max-width: 720px;
  margin: 0 auto;
}

.profile-view h2 {
  margin-bottom: 1rem;
  color: #2e7d32;
}

.card {
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  padding: 1.25rem;
}

.row {
  display: grid;
  gap: 0.4rem;
  margin-bottom: 1rem;
}

label {
  font-weight: 600;
}

input,
select {
  border: 1px solid #d0d7de;
  border-radius: 8px;
  padding: 0.55rem 0.7rem;
}

.btn {
  border: none;
  border-radius: 20px;
  background: linear-gradient(135deg, #4caf50, #2196f3);
  color: #fff;
  padding: 0.55rem 1.2rem;
  cursor: pointer;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.error {
  color: #c62828;
  margin-top: 0.8rem;
}

.success {
  color: #2e7d32;
  margin-top: 0.8rem;
}
</style>
