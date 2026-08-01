<template>
  <div class="page task-result-view">
    <section class="page-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">结果详情</span>
        <h2 class="page-hero__title">查看这一次分析的热量结果、分割区域和饮食建议</h2>
        <p class="page-hero__subtitle">
          可以在这里查看这次分析的图片、热量、识别明细和饮食建议。
        </p>
        <div class="page-actions">
          <RouterLink to="/history" class="button button--secondary">返回历史记录</RouterLink>
          <RouterLink to="/upload" class="button button--soft">返回上传分析</RouterLink>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>来源</span>
          <strong>来自历史记录</strong>
          <p>从历史记录进入后，可以继续查看这一餐的图片、热量和饮食建议。</p>
        </div>
        <div class="metric-card">
          <span>当前状态</span>
          <strong>{{ statusSummary }}</strong>
          <p v-if="statusHint">{{ statusHint }}</p>
        </div>
      </aside>
    </section>

    <section v-if="loading" class="surface-card empty-state">正在加载结果详情，请稍候…</section>
    <section v-else-if="error" class="surface-card empty-state empty-state--error">
      <h3>结果详情加载失败</h3>
      <p>{{ error }}</p>
      <div class="page-actions">
        <button class="button button--secondary" type="button" @click="loadResult">重新加载</button>
      </div>
    </section>
    <section v-else-if="foodStore.status === 'FAILED'" class="surface-card empty-state empty-state--error">
      <h3>分析失败</h3>
      <p>{{ foodStore.error || '这次分析未成功完成，请稍后重试。' }}</p>
    </section>
    <AnalysisResultPanel
      v-else-if="foodStore.status === 'COMPLETED'"
      :status="foodStore.status"
      :image-url="foodStore.previewUrl"
      :segmentation-preview-url="foodStore.segmentationPreviewUrl"
      :detected-items="foodStore.detectedItems"
      :total-calories="foodStore.totalCalories"
      :advice-report="foodStore.adviceReport || ''"
      :back-to="'/history'"
      back-label="返回历史记录"
    />
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import AnalysisResultPanel from '@/components/AnalysisResultPanel.vue'
import { useFoodStore } from '@/stores/food'

const route = useRoute()
const foodStore = useFoodStore()
const loading = ref(false)
const error = ref('')

const taskId = computed(() => String(route.params.taskId || ''))
const statusLabel = computed(() => {
  const normalized = (foodStore.status || '').toString().toUpperCase()
  if (normalized === 'COMPLETED') return '分析完成'
  if (normalized === 'PENDING') return '分析中'
  if (normalized === 'FAILED') return '分析失败'
  return '等待加载'
})
const statusSummary = computed(() => (
  foodStore.status === 'PENDING'
    ? '分析中，通常约 10-20 秒完成。'
    : statusLabel.value
))
const statusHint = computed(() => {
  const normalized = (foodStore.status || '').toString().toUpperCase()
  if (normalized === 'COMPLETED') return '结果已经可以查看。'
  if (normalized === 'PENDING') return ''
  if (normalized === 'FAILED') return '这次分析未成功完成，请稍后重试。'
  return '结果准备后会显示在这里。'
})

watch(taskId, () => {
  loadResult()
}, { immediate: true })

onBeforeUnmount(() => foodStore.stopPolling())

async function loadResult() {
  if (!taskId.value) {
    error.value = '缺少结果标识，暂时无法打开详情'
    return
  }

  loading.value = true
  error.value = ''
  try {
    await foodStore.loadTaskDetail(taskId.value)
  } catch {
    error.value = foodStore.error || '加载结果详情失败'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.hero-aside {
  display: grid;
  gap: 14px;
}

.empty-state {
  display: grid;
  gap: 14px;
  justify-items: start;
}

.empty-state--error p {
  color: var(--danger);
}

</style>
