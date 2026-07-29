<template>
  <section class="results-stack">
    <section class="surface-card result-hero-card">
      <div class="result-hero-media">
        <div v-if="headerPreviewUrl" class="result-hero-media-inner">
          <img :src="headerPreviewUrl" alt="分析结果预览" class="result-hero-image" />
        </div>
        <div v-else class="result-hero-empty">结果图像暂不可用</div>
      </div>

      <div class="result-hero-body">
        <div class="result-hero-title-row">
          <div>
            <span class="result-kicker">分析结果</span>
            <h3 class="result-title">总热量：{{ Number(totalCalories || 0).toFixed(1) }} 千卡</h3>
            <p class="result-subtitle">查看这次识别到的食物、热量和饮食建议。</p>
          </div>
          <span class="result-status" :class="statusClass">{{ statusLabel }}</span>
        </div>

        <div class="result-summary-grid">
          <article class="result-summary-card">
            <span>识别类别</span>
            <strong>{{ groupedDetectedItems.length }} 类</strong>
            <p>本次共识别 {{ detectedItems.length }} 个区域。</p>
          </article>
          <article class="result-summary-card">
            <span>查看方式</span>
            <strong>点击区域查看详情</strong>
            <p>点击图像中的食物区域，可查看对应信息。</p>
          </article>
          <article class="result-summary-card">
            <span>建议状态</span>
            <strong>{{ adviceSections.main ? '已生成' : '生成中' }}</strong>
            <p>{{ adviceSections.basis ? '本次建议已结合你的目标和历史记录。' : '建议返回后会自动展示在下方。' }}</p>
          </article>
        </div>
      </div>
    </section>

    <section class="surface-card mask-stage">
      <header class="section-head">
        <h3 class="section-title">分割图像</h3>
        <p class="section-subtitle">点击图像中的食物区域，可查看对应详情。</p>
      </header>
      <MaskCanvas
        :image-url="imageUrl"
        :preview-image-url="segmentationPreviewUrl"
        :items="detectedItems"
      />
    </section>

    <section class="surface-card">
      <header class="section-head">
        <h3 class="section-title">识别明细</h3>
        <p class="section-subtitle">按食物类别汇总显示置信度、重量和热量。</p>
      </header>
      <div class="table-wrap">
        <table class="result-table">
          <thead>
            <tr>
              <th>食物</th>
              <th>置信度</th>
              <th>预估重量</th>
              <th>热量</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="group in groupedDetectedItems" :key="group.key">
              <td>
                <div class="food-name-cell">
                  <strong>{{ group.displayLabel }}</strong>
                  <small>{{ group.instanceCount }} 个区域</small>
                  <small v-if="group.isLowConfidence" class="confidence-warning">待确认，不用于具体建议</small>
                </div>
              </td>
              <td>{{ (group.averageConfidence * 100).toFixed(1) }}%</td>
              <td>{{ group.totalWeight > 0 ? `${formatMetric(group.totalWeight)}g` : '—' }}</td>
              <td>{{ formatMetric(group.totalCalories) }} kcal</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <td colspan="3">合计热量</td>
              <td>{{ Number(totalCalories || 0).toFixed(1) }} kcal</td>
            </tr>
          </tfoot>
        </table>
      </div>
      <p v-if="hasLowConfidenceItems" class="confidence-note">
        低于 65% 的类别仅作为待确认线索，不用于生成点名食物的具体建议。
      </p>
    </section>

    <section class="surface-card advice-stage">
      <header class="section-head">
        <h3 class="section-title">饮食建议</h3>
        <p class="section-subtitle">先给可执行建议，再把这次建议主要参考的依据单独放出来。</p>
      </header>

      <div v-if="adviceSections.basis" class="advice-basis">
        <h4>这次建议主要参考</h4>
        <p>{{ adviceSections.basis }}</p>
      </div>

      <div class="advice-main">
        <h4>本次建议正文</h4>
        <p>{{ adviceSections.main || '建议生成中，请稍候…' }}</p>
      </div>
    </section>

    <div v-if="backTo" class="page-actions result-actions">
      <RouterLink :to="backTo" class="button button--secondary">{{ backLabel }}</RouterLink>
    </div>
  </section>
</template>

<script setup>
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import MaskCanvas from '@/components/MaskCanvas.vue'
import { buildFoodGroupKey } from '@/utils/foodLabels'

const props = defineProps({
  status: { type: String, default: 'COMPLETED' },
  imageUrl: { type: String, default: '' },
  segmentationPreviewUrl: { type: String, default: '' },
  detectedItems: { type: Array, default: () => [] },
  totalCalories: { type: Number, default: 0 },
  adviceReport: { type: String, default: '' },
  backTo: { type: [String, Object], default: null },
  backLabel: { type: String, default: '返回继续上传' },
})

const headerPreviewUrl = computed(() => props.imageUrl || props.segmentationPreviewUrl || '')
const statusLabel = computed(() => {
  const normalized = (props.status || '').toString().toUpperCase()
  if (normalized === 'COMPLETED') return '分析完成'
  if (normalized === 'PENDING') return '分析中'
  if (normalized === 'FAILED') return '分析失败'
  return normalized || '未知状态'
})
const statusClass = computed(() => {
  const normalized = (props.status || '').toString().toUpperCase()
  if (normalized === 'COMPLETED') return 'is-completed'
  if (normalized === 'PENDING') return 'is-pending'
  return 'is-failed'
})
const groupedDetectedItems = computed(() => {
  const grouped = new Map()

  props.detectedItems.forEach(item => {
    const key = buildFoodGroupKey(item)
    if (!grouped.has(key)) {
      grouped.set(key, {
        key,
        displayLabel: item.displayLabel || item.label || '未知食物',
        instanceCount: 0,
        confidenceSum: 0,
        totalWeight: 0,
        totalCalories: 0,
      })
    }

    const group = grouped.get(key)
    group.instanceCount += 1
    group.confidenceSum += toNumber(item.confidence)
    group.totalWeight += toNumber(item.estimated_weight_g)
    group.totalCalories += toNumber(item.nutrition?.calories_kcal ?? item.calories)
  })

  return Array.from(grouped.values())
    .map(group => ({
      ...group,
      averageConfidence: group.instanceCount ? group.confidenceSum / group.instanceCount : 0,
      isLowConfidence: group.instanceCount ? group.confidenceSum / group.instanceCount < 0.65 : true,
    }))
    .sort((left, right) => {
      const calorieCompare = right.totalCalories - left.totalCalories
      if (calorieCompare !== 0) {
        return calorieCompare
      }
      return right.averageConfidence - left.averageConfidence
    })
})
const hasLowConfidenceItems = computed(() => groupedDetectedItems.value.some(group => group.isLowConfidence))
const adviceSections = computed(() => splitAdvice(props.adviceReport || ''))

function splitAdvice(report) {
  const normalized = report.replace(/\r\n/g, '\n').trim()
  const sections = normalized.split(/\n{2,}/).map(section => section.trim()).filter(Boolean)

  if (!normalized) {
    return { basis: '', main: '' }
  }

  if (sections.length > 0 && sections[0].startsWith('个性化参考依据')) {
    const basis = sections[0].replace(/^个性化参考依据[:：]?\s*/, '').trim()
    const main = sections.slice(1).join('\n\n').trim()
    return {
      basis,
      main: main || '系统已结合本次识别结果和你的目标生成建议。',
    }
  }

  return {
    basis: '',
    main: normalized,
  }
}

function toNumber(value) {
  if (value === null || value === undefined || value === '') {
    return 0
  }

  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function formatMetric(value) {
  const rounded = Math.round(toNumber(value) * 10) / 10
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
}
</script>

<style scoped>
.results-stack {
  display: grid;
  gap: 14px;
  width: 100%;
  min-width: 0;
}

.result-hero-card,
.result-summary-grid,
.result-actions {
  display: grid;
  gap: 14px;
  min-width: 0;
}

.result-hero-card {
  grid-template-columns: minmax(320px, 0.96fr) minmax(0, 1.04fr);
  align-items: stretch;
}

.result-hero-media {
  min-width: 0;
  border-radius: 24px;
  background: #121318;
  border: 1px solid rgba(234, 215, 202, 0.95);
  display: grid;
  place-items: center;
  padding: 18px;
  min-height: 320px;
}

.result-hero-media-inner {
  display: grid;
  place-items: center;
  width: 100%;
}

.result-hero-image {
  display: block;
  width: auto;
  max-width: 100%;
  max-height: 420px;
  object-fit: contain;
}

.result-hero-empty {
  min-height: 280px;
  display: grid;
  place-items: center;
  color: rgba(255, 255, 255, 0.84);
  font-weight: 600;
}

.result-hero-body {
  display: grid;
  gap: 18px;
  min-width: 0;
}

.result-hero-title-row {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: start;
}

.result-kicker {
  display: inline-flex;
  align-items: center;
  min-height: 28px;
  padding: 0 12px;
  border-radius: 999px;
  background: rgba(255, 241, 227, 0.94);
  color: var(--accent-strong);
  font-size: 0.8rem;
  font-weight: 800;
}

.result-title {
  margin-top: 10px;
  font-size: 1.65rem;
  font-weight: 800;
  letter-spacing: -0.03em;
}

.result-subtitle {
  margin-top: 12px;
  color: var(--muted);
  line-height: 1.7;
}

.result-status {
  flex: none;
  display: inline-flex;
  align-items: center;
  min-height: 42px;
  padding: 0 16px;
  border-radius: 999px;
  font-weight: 800;
}

.result-status.is-completed {
  background: rgba(226, 243, 234, 0.94);
  color: var(--success);
}

.result-status.is-pending {
  background: rgba(255, 244, 222, 0.96);
  color: var(--warning);
}

.result-status.is-failed {
  background: rgba(252, 234, 229, 0.96);
  color: var(--danger);
}

.result-summary-grid {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.result-summary-card {
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 249, 243, 0.9);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.result-summary-card span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.82rem;
  margin-bottom: 8px;
}

.result-summary-card strong {
  display: block;
  font-size: 1rem;
  line-height: 1.5;
  font-weight: 800;
}

.result-summary-card p {
  margin-top: 8px;
  color: var(--muted);
  line-height: 1.65;
}

.mask-stage,
.advice-stage {
  display: grid;
  gap: 16px;
}

.table-wrap {
  width: 100%;
  max-width: 100%;
  min-width: 0;
  overflow-x: auto;
  overscroll-behavior-inline: contain;
}

.result-table {
  width: 100%;
  min-width: 520px;
  border-collapse: collapse;
}

.result-table th,
.result-table td {
  padding: 14px 16px;
  text-align: left;
  border-bottom: 1px solid rgba(238, 224, 213, 0.95);
}

.result-table th {
  color: var(--muted-soft);
  font-size: 0.84rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.food-name-cell {
  display: grid;
  gap: 4px;
}

.food-name-cell strong {
  font-size: 0.98rem;
}

.food-name-cell small {
  color: var(--muted-soft);
  font-size: 0.8rem;
}

.result-table tfoot td {
  font-weight: 800;
  color: var(--accent-strong);
  border-bottom: none;
}

.advice-basis {
  padding: 18px;
  border-radius: 22px;
  background: rgba(255, 245, 236, 0.92);
  border: 1px solid rgba(242, 200, 168, 0.74);
}

.advice-main {
  padding: 22px;
  border-radius: 24px;
  background: linear-gradient(180deg, rgba(255, 252, 247, 0.98), rgba(255, 248, 242, 0.98));
  border: 1px solid rgba(234, 215, 202, 0.96);
}

.advice-basis h4,
.advice-main h4 {
  margin-bottom: 10px;
  font-size: 1rem;
  font-weight: 800;
}

.advice-basis p,
.advice-main p {
  white-space: pre-wrap;
  color: var(--muted);
  line-height: 1.8;
}

@media (max-width: 1100px) {
  .result-hero-card,
  .result-summary-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .result-hero-title-row {
    flex-direction: column;
  }

  .result-hero-media {
    min-height: 220px;
    padding: 10px;
  }

  .result-summary-card,
  .advice-basis,
  .advice-main {
    border-radius: 16px;
  }
}

.food-name-cell .confidence-warning {
  color: var(--warning);
  font-weight: 700;
}

.confidence-note {
  margin-top: 12px;
  color: var(--warning);
  line-height: 1.65;
}
</style>
