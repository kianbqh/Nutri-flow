<template>
  <div class="page upload-view">
    <section class="page-hero upload-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">上传与识别</span>
        <h2 class="page-hero__title">把餐图交给系统，再从结构化结果读懂这顿饭</h2>
        <p class="page-hero__subtitle">
          上传一张清晰餐图后，系统会返回识别结果、热量估算和饮食建议，帮助你更快判断这顿饭是否符合自己的目标。
        </p>
        <div class="upload-flow-pills">
          <span class="upload-flow-pill">1 选择图片</span>
          <span class="upload-flow-pill">2 确认餐次</span>
          <span class="upload-flow-pill">3 开始分析</span>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>当前账号</span>
          <strong>{{ accountLabel }}</strong>
          <p>{{ isAuthenticated ? '新的分析记录会保存到当前账号下。' : '先完成手机号验证，再把分析结果和历史记录保存到你的账号。' }}</p>
        </div>
        <div class="metric-card">
          <span>拍摄建议</span>
          <strong>尽量拍完整餐盘，减少遮挡和强反光</strong>
          <p>图片越清晰、食物越完整，识别结果通常越稳定。</p>
        </div>
        <div class="metric-card">
          <span>分析结果</span>
          <strong>会返回热量估算、识别明细和饮食建议</strong>
          <p>分析完成后，你可以直接查看这一餐的主要结果。</p>
        </div>
      </aside>
    </section>

    <section v-if="!isAuthenticated" class="surface-card empty-state auth-empty-state">
      <h3>先验证手机号账号</h3>
        <p>完成验证后，新的分析结果、历史记录和个人主页资料都会跟随当前账号一起保存。</p>
        <RouterLink to="/profile" class="button button--primary">去个人主页验证</RouterLink>
    </section>

    <section v-else class="surface-card upload-workbench">
      <div class="upload-workbench__media">
        <header class="section-head">
          <h3 class="section-title">选择并预览餐图</h3>
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
      </div>

      <aside class="upload-workbench__controls">
        <header class="section-head">
          <h3 class="section-title">确认餐次并开始分析</h3>
          <p class="section-subtitle">选择好这顿饭属于哪一餐后，就可以开始分析。</p>
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

        <div class="control-actions">
          <button class="button button--secondary" type="button" @click="triggerFileSelect">
            {{ foodStore.previewUrl ? '重新选择图片' : '选择图片' }}
          </button>
          <button class="button button--primary" :disabled="!selectedFile || foodStore.isLoading" @click="analyse">
            {{ foodStore.isLoading ? '分析中…' : '开始分析' }}
          </button>
        </div>

        <div class="upload-quick-summary">
          <article class="upload-quick-card">
            <span>当前图片</span>
            <strong>{{ selectedFileName }}</strong>
            <p>上传前可以继续替换图片，避免把模糊或裁切过头的餐图送去分析。</p>
          </article>
          <article class="upload-quick-card">
            <span>当前状态</span>
            <strong>{{ statusLabel }}</strong>
            <p>{{ statusHint }}</p>
          </article>
          <article class="upload-quick-card">
            <span>当前账号</span>
            <strong>{{ accountLabel }}</strong>
            <p>新的分析记录会保存到当前账号下，方便后续在历史页回看。</p>
          </article>
        </div>

        <div class="control-wash">
          <span>开始前确认</span>
          <strong>图片清晰、餐次正确，结果会更稳定</strong>
          <p>如果这次识别不理想，可以换一张更清晰的图片再试一次。</p>
        </div>

        <ul class="control-list">
          <li>完整餐图优先，局部特写容易让热量估算失真。</li>
          <li>如果结果不理想，先换更清晰的照片再分析一次。</li>
          <li>设置页中的目标会影响后续建议内容。</li>
        </ul>

        <p v-if="foodStore.error" class="soft-note soft-note--error">{{ foodStore.error }}</p>

        <p v-if="foodStore.status === 'PENDING'" class="soft-note control-note">
          AI 正在分析，通常需要 5 到 15 秒。你可以留在当前页直接等待结果返回。
        </p>
      </aside>
    </section>

    <AnalysisResultPanel
      v-if="foodStore.status === 'COMPLETED'"
      :status="foodStore.status"
      :image-url="foodStore.previewUrl"
      :segmentation-preview-url="foodStore.segmentationPreviewUrl"
      :detected-items="foodStore.detectedItems"
      :total-calories="foodStore.totalCalories"
      :advice-report="foodStore.adviceReport || ''"
    />
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import { RouterLink } from 'vue-router'
import AnalysisResultPanel from '@/components/AnalysisResultPanel.vue'
import { useFoodStore } from '@/stores/food'
import { getStoredWebSession } from '@/api/dietLog'

const foodStore = useFoodStore()
const fileInput = ref(null)
const selectedFile = ref(null)
const mealType = ref('LUNCH')
const isDragOver = ref(false)
const session = getStoredWebSession()
const ACCEPTED_IMAGE_TYPES = ['image/jpeg', 'image/png']

const isAuthenticated = computed(() => Boolean(session.userId && session.phone))
const accountLabel = computed(() => session.phone || '未验证账号')

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
    UPLOADING: '图片正在上传，请稍候。',
    PENDING: '正在识别食物并生成这次分析结果。',
    COMPLETED: '结果已经返回，可以直接查看分割区域、表格和饮食建议。',
    FAILED: '这轮分析未完成，可以更换图片或稍后重试。',
  }
  return hints[foodStore.status] || '先放入一张餐图，再选择餐次开始分析。'
})

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
  if (!isSupportedImage(file)) {
    selectedFile.value = null
    foodStore.reset()
    foodStore.error = '仅支持 JPG 或 PNG 图片，请重新选择餐食图片'
    clearFileInput()
    return
  }

  selectedFile.value = file
  foodStore.reset()
  foodStore.previewUrl = URL.createObjectURL(file)
  clearFileInput()
}

function isSupportedImage(file) {
  if (ACCEPTED_IMAGE_TYPES.includes(file.type)) {
    return true
  }

  const fileName = file.name?.toLowerCase() || ''
  return fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png')
}

function clearFileInput() {
  if (fileInput.value) {
    fileInput.value.value = ''
  }
}

async function analyse() {
  if (!selectedFile.value) return
  if (!isAuthenticated.value) {
    foodStore.error = '请先完成手机号验证，再开始分析并保存个人记录'
    return
  }
  await foodStore.uploadAndAnalyse(selectedFile.value, mealType.value)
}

onBeforeUnmount(() => foodStore.stopPolling())
</script>

<style scoped>
.upload-flow-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 18px;
}

.upload-flow-pill {
  display: inline-flex;
  align-items: center;
  min-height: 38px;
  padding: 0 14px;
  border-radius: 999px;
  background: rgba(255, 248, 241, 0.96);
  border: 1px solid rgba(238, 224, 213, 0.95);
  color: var(--accent-strong);
  font-size: 0.86rem;
  font-weight: 800;
}

.hero-aside {
  display: grid;
  gap: 14px;
}

.auth-empty-state {
  display: grid;
  gap: 14px;
  justify-items: start;
}

.upload-workbench {
  display: grid;
  grid-template-columns: minmax(0, 1.08fr) minmax(320px, 0.92fr);
  gap: 20px;
  align-items: start;
}

.upload-workbench__media,
.upload-workbench__controls {
  display: grid;
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
  object-fit: contain;
  background: #111217;
}

.upload-quick-summary {
  display: grid;
  gap: 14px;
}

.upload-quick-card {
  padding: 16px 18px;
  border-radius: 20px;
  background: rgba(255, 248, 242, 0.94);
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.upload-quick-card span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.84rem;
  margin-bottom: 8px;
}

.upload-quick-card strong {
  font-size: 1rem;
}

.upload-quick-card p {
  margin-top: 8px;
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

.control-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.control-actions .button {
  flex: 1 1 180px;
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

@media (max-width: 1024px) {
  .upload-workbench {
    grid-template-columns: 1fr;
  }
}
</style>
