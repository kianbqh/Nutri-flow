<template>
  <div class="page upload-view">
    <section class="page-hero upload-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">上传与识别</span>
        <h2 class="page-hero__title">把餐图交给系统，再从结构化结果读懂这顿饭</h2>
        <p class="page-hero__subtitle">
          网页端把拖拽上传、餐次设置、分割结果和建议阅读放在同一页，更适合边调整目标边做结果对照。
        </p>
        <div class="page-actions">
          <button class="button button--primary" :disabled="!selectedFile || foodStore.isLoading" @click="analyse">
            {{ foodStore.isLoading ? '分析中…' : '开始分析' }}
          </button>
          <button class="button button--secondary" type="button" @click="triggerFileSelect">
            选择图片
          </button>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前状态</span>
          <strong>{{ statusLabel }}</strong>
          <p>{{ statusHint }}</p>
        </div>
        <div class="metric-card">
          <span>当前图片</span>
          <strong>{{ selectedFileName }}</strong>
          <p>上传前可以继续替换图片，避免把模糊或裁切过头的餐图送去分析。</p>
        </div>
        <div class="metric-card">
          <span>分析节奏</span>
          <strong>通常 5 到 15 秒</strong>
          <p>系统会轮询任务状态，结果到达后直接在当前页展示分割图、识别表和建议。</p>
        </div>
      </aside>
    </section>

    <section class="upload-layout">
      <section class="surface-card upload-stage">
        <header class="section-head">
          <h3 class="section-title">餐图预览</h3>
          <p class="section-subtitle">支持点击和拖拽上传。尽量保留完整餐盘，减少遮挡和强反光。</p>
        </header>

        <div
          class="drop-zone"
          :class="{ 'is-drag-over': isDragOver, 'has-image': !!foodStore.previewUrl }"
          @dragover.prevent="isDragOver = true"
          @dragleave="isDragOver = false"
          @drop.prevent="onDrop"
          @click="triggerFileSelect"
        >
          <template v-if="!foodStore.previewUrl">
            <div class="drop-placeholder">
              <span class="drop-badge">拖拽上传</span>
              <h4>把餐食图片放到这里</h4>
              <p>支持 JPG / PNG，最大 10 MB。也可以点击当前区域打开文件选择器。</p>
            </div>
          </template>
          <img
            v-else
            :src="foodStore.previewUrl"
            alt="餐食预览"
            class="preview-img"
          />
          <input
            ref="fileInput"
            type="file"
            accept="image/jpeg,image/png"
            hidden
            @change="onFileChange"
          />
        </div>

        <div class="upload-meta">
          <div>
            <span class="upload-meta__label">已选文件</span>
            <strong>{{ selectedFileName }}</strong>
          </div>
          <div>
            <span class="upload-meta__label">建议</span>
            <p>尽量包含餐盘主体和主要配菜，方便模型判断食物区域和份量。</p>
          </div>
        </div>

        <p v-if="foodStore.error" class="soft-note soft-note--error">{{ foodStore.error }}</p>
      </section>

      <aside class="surface-card control-stage">
        <header class="section-head">
          <h3 class="section-title">提交分析</h3>
          <p class="section-subtitle">先确认餐次，再开始这轮营养估算与建议生成。</p>
        </header>

        <div class="field-stack">
          <label class="field-label" for="meal-type">餐次</label>
          <select id="meal-type" v-model="mealType">
            <option value="BREAKFAST">早餐</option>
            <option value="LUNCH">午餐</option>
            <option value="DINNER">晚餐</option>
            <option value="SNACK">加餐</option>
          </select>
        </div>

        <div class="control-wash">
          <span>当前模式</span>
          <strong>上传一张图片，留在当前页等结果返回</strong>
          <p>网页端更偏向连续操作和结果对照，适合在大屏上边看建议边回查识别项。</p>
        </div>

        <ul class="control-list">
          <li>完整餐图优先，局部特写容易让热量估算失真。</li>
          <li>如果结果不理想，先换更清晰的照片再分析一次。</li>
          <li>设置页中的目标会影响后续建议内容。</li>
        </ul>

        <p v-if="foodStore.status === 'PENDING'" class="soft-note control-note">
          AI 正在分析，通常需要 5 到 15 秒。你可以留在当前页直接等待结果返回。
        </p>
      </aside>
    </section>

    <section v-if="foodStore.status === 'COMPLETED'" class="results-stack">
      <div class="metric-grid">
        <div class="metric-card">
          <span>总热量</span>
          <strong>{{ foodStore.totalCalories.toFixed(1) }} kcal</strong>
          <p>这是当前检测到食物项的热量合计，可结合目标页的日摄入设置一起判断。</p>
        </div>
        <div class="metric-card">
          <span>识别项</span>
          <strong>{{ foodStore.detectedItems.length }} 项</strong>
          <p>系统会按识别结果列出主要食物、置信度、重量和单项热量估算。</p>
        </div>
        <div class="metric-card">
          <span>建议状态</span>
          <strong>{{ adviceSections.main ? '已生成' : '生成中' }}</strong>
          <p>{{ adviceSections.basis ? '本次建议包含个性化参考依据。' : '建议文本返回后会自动展示在下方。' }}</p>
        </div>
      </div>

      <section class="surface-card mask-stage">
        <header class="section-head">
          <h3 class="section-title">分割预览</h3>
          <p class="section-subtitle">先看区域划分和类别图例，再往下对照每项热量与建议。</p>
        </header>
        <MaskCanvas
          :image-url="foodStore.previewUrl"
          :masks="foodStore.masks"
          :width="720"
          :height="460"
        />
      </section>

      <section class="surface-card">
        <header class="section-head">
          <h3 class="section-title">识别明细</h3>
          <p class="section-subtitle">把每个识别项的置信度、预估重量和热量拆开看，便于回查判断。</p>
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
              <tr v-for="(item, i) in foodStore.detectedItems" :key="i">
                <td>{{ item.label }}</td>
                <td>{{ (item.confidence * 100).toFixed(1) }}%</td>
                <td>{{ item.estimated_weight_g ? item.estimated_weight_g + 'g' : '—' }}</td>
                <td>{{ item.nutrition?.calories_kcal ?? '—' }} kcal</td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <td colspan="3">合计热量</td>
                <td>{{ foodStore.totalCalories.toFixed(1) }} kcal</td>
              </tr>
            </tfoot>
          </table>
        </div>
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
    </section>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import MaskCanvas from '@/components/MaskCanvas.vue'
import { useFoodStore } from '@/stores/food'

const foodStore = useFoodStore()
const fileInput = ref(null)
const selectedFile = ref(null)
const mealType = ref('LUNCH')
const isDragOver = ref(false)

const selectedFileName = computed(() => selectedFile.value?.name || '未选择图片')

const statusLabel = computed(() => {
  const labels = {
    IDLE: '等待上传',
    UPLOADING: '上传中',
    PENDING: '分析中',
    COMPLETED: '分析完成',
    FAILED: '分析失败',
  }
  return labels[foodStore.status] || '等待上传'
})

const statusHint = computed(() => {
  const hints = {
    IDLE: '先放入一张餐图，再选择餐次开始分析。',
    UPLOADING: '图片正在发送到后端，上传完成后会自动进入轮询。',
    PENDING: '任务已经提交，系统正在识别食物区域并生成建议。',
    COMPLETED: '结果已经返回，可以直接查看分割区域、表格和饮食建议。',
    FAILED: '这轮分析未完成，可以更换图片或稍后重试。',
  }
  return hints[foodStore.status] || '先放入一张餐图，再选择餐次开始分析。'
})

const adviceSections = computed(() => splitAdvice(foodStore.adviceReport))

function triggerFileSelect() {
  fileInput.value?.click()
}

function onFileChange(event) {
  const file = event.target.files[0]
  if (file) setFile(file)
}

function onDrop(event) {
  isDragOver.value = false
  const file = event.dataTransfer.files[0]
  if (file) setFile(file)
}

function setFile(file) {
  if (!file.type.startsWith('image/')) return
  selectedFile.value = file
  foodStore.reset()
  foodStore.previewUrl = URL.createObjectURL(file)
}

async function analyse() {
  if (!selectedFile.value) return
  await foodStore.uploadAndAnalyse(selectedFile.value, mealType.value)
}

function splitAdvice(report) {
  if (!report || !report.trim()) {
    return { basis: '', main: '' }
  }

  const normalized = report.replace(/\r\n/g, '\n').trim()
  const sections = normalized.split(/\n{2,}/).map((section) => section.trim()).filter(Boolean)

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

onBeforeUnmount(() => foodStore.stopPolling())
</script>

<style scoped>
.hero-aside,
.results-stack {
  display: grid;
  gap: 14px;
}

.upload-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.15fr) minmax(300px, 0.85fr);
  gap: 18px;
}

.drop-zone {
  min-height: 360px;
  border-radius: 26px;
  border: 1.5px dashed rgba(155, 91, 46, 0.32);
  background: linear-gradient(180deg, rgba(255, 247, 240, 0.98), rgba(255, 255, 255, 0.98));
  display: grid;
  place-items: center;
  cursor: pointer;
  overflow: hidden;
  transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease;
}

.drop-zone:hover,
.drop-zone.is-drag-over {
  transform: translateY(-1px);
  border-color: rgba(155, 91, 46, 0.56);
  box-shadow: 0 18px 36px rgba(124, 71, 35, 0.08);
}

.drop-zone.has-image {
  background: #f8efe7;
}

.drop-placeholder {
  display: grid;
  gap: 14px;
  padding: 32px;
  text-align: center;
  max-width: 440px;
}

.drop-badge {
  justify-self: center;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 110px;
  padding: 10px 14px;
  border-radius: 999px;
  background: rgba(255, 241, 227, 0.94);
  color: var(--accent-strong);
  font-size: 0.82rem;
  font-weight: 800;
}

.drop-placeholder h4 {
  font-size: 1.52rem;
  font-weight: 800;
  letter-spacing: -0.03em;
}

.drop-placeholder p {
  color: var(--muted);
  line-height: 1.7;
}

.preview-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.upload-meta {
  margin-top: 16px;
  display: grid;
  grid-template-columns: minmax(0, 0.55fr) minmax(0, 1fr);
  gap: 14px;
}

.upload-meta > div {
  padding: 16px 18px;
  border-radius: 20px;
  background: rgba(255, 248, 242, 0.94);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.upload-meta__label {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 8px;
}

.upload-meta strong {
  font-size: 1rem;
}

.upload-meta p {
  color: var(--muted);
  line-height: 1.6;
}

.field-stack {
  display: grid;
  gap: 8px;
}

.field-label {
  font-weight: 700;
}

.control-stage {
  display: grid;
  align-content: start;
  gap: 18px;
}

.control-wash {
  padding: 18px;
  border-radius: 22px;
  background: linear-gradient(180deg, rgba(255, 243, 232, 0.96), rgba(255, 250, 245, 0.96));
  border: 1px solid rgba(242, 200, 168, 0.76);
}

.control-wash span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 8px;
}

.control-wash strong {
  display: block;
  font-size: 1.04rem;
  line-height: 1.45;
}

.control-wash p {
  margin-top: 10px;
  color: var(--muted);
  line-height: 1.65;
}

.control-list {
  display: grid;
  gap: 10px;
  padding-left: 18px;
  color: var(--muted);
  line-height: 1.65;
}

.control-note {
  color: var(--warning);
}

.mask-stage :deep(.mask-canvas-wrapper) {
  width: 100%;
}

.mask-stage :deep(.mask-canvas) {
  width: 100%;
  height: auto;
}

.table-wrap {
  overflow-x: auto;
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

.result-table tfoot td {
  font-weight: 800;
  color: var(--accent-strong);
  border-bottom: none;
}

.advice-stage {
  display: grid;
  gap: 16px;
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

@media (max-width: 1024px) {
  .upload-layout,
  .upload-meta {
    grid-template-columns: 1fr;
  }
}
</style>
