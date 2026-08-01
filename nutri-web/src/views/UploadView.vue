<template>
  <div class="page upload-view">
    <section v-if="!isAuthenticated" class="surface-card empty-state auth-empty-state">
      <h2>请先验证手机号</h2>
      <p>验证后即可保存分析结果和历史记录。</p>
      <RouterLink to="/profile" class="button button--primary">去验证</RouterLink>
    </section>

    <section v-else class="surface-card upload-workbench">
      <div class="upload-workbench__media">
        <div class="upload-heading">
          <div>
            <span>拍餐分析</span>
            <h2>上传一张餐食照片</h2>
          </div>
          <p>尽量拍完整餐盘，减少遮挡和强反光。</p>
        </div>

        <div
          class="drop-zone"
          :class="{ 'is-drag-over': isDragOver, 'has-image': !!foodStore.previewUrl }"
          @dragover.prevent="isDragOver = true"
          @dragleave="isDragOver = false"
          @drop.prevent="onDrop"
          @click="triggerFileSelect"
        >
          <div v-if="!foodStore.previewUrl" class="drop-placeholder">
            <strong>选择或拖入图片</strong>
            <span>JPG / PNG，最大 10 MB</span>
          </div>
          <img v-else :src="foodStore.previewUrl" alt="餐食预览" class="preview-img" />
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
        <label class="field-stack" for="meal-type">
          <span>餐次</span>
          <select id="meal-type" v-model="mealType">
            <option value="BREAKFAST">早餐</option>
            <option value="LUNCH">午餐</option>
            <option value="DINNER">晚餐</option>
            <option value="SNACK">加餐</option>
          </select>
        </label>

        <p v-if="foodStore.error" class="soft-note soft-note--error">{{ foodStore.error }}</p>

        <div class="control-actions">
          <button class="button button--secondary" type="button" @click="triggerFileSelect">
            {{ foodStore.previewUrl ? '更换图片' : '选择图片' }}
          </button>
          <button class="button button--primary" :disabled="!selectedFile || foodStore.isLoading" @click="analyse">
            {{ foodStore.isLoading ? '正在提交...' : '开始分析' }}
          </button>
        </div>
      </aside>
    </section>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useFoodStore } from '@/stores/food'
import { getStoredWebSession } from '@/api/dietLog'

const foodStore = useFoodStore()
const router = useRouter()
const fileInput = ref(null)
const selectedFile = ref(null)
const mealType = ref('LUNCH')
const isDragOver = ref(false)
const session = getStoredWebSession()
const ACCEPTED_IMAGE_TYPES = ['image/jpeg', 'image/png']

const isAuthenticated = computed(() => Boolean(session.userId && session.phone))

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
    foodStore.error = '仅支持 JPG 或 PNG 图片'
    clearFileInput()
    return
  }

  selectedFile.value = file
  foodStore.reset()
  foodStore.previewUrl = URL.createObjectURL(file)
  clearFileInput()
}

function isSupportedImage(file) {
  if (ACCEPTED_IMAGE_TYPES.includes(file.type)) return true
  const fileName = file.name?.toLowerCase() || ''
  return fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png')
}

function clearFileInput() {
  if (fileInput.value) fileInput.value.value = ''
}

async function analyse() {
  if (!selectedFile.value) return
  if (!isAuthenticated.value) {
    foodStore.error = '请先完成手机号验证'
    return
  }

  const taskId = await foodStore.uploadAndAnalyse(selectedFile.value, mealType.value)
  if (taskId) router.push(`/results/${taskId}`)
}

onBeforeUnmount(() => foodStore.stopPolling())
</script>

<style scoped>
.auth-empty-state {
  display: grid;
  gap: 14px;
  justify-items: center;
}

.upload-workbench {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 280px;
  gap: 24px;
  align-items: end;
}

.upload-workbench__media,
.upload-workbench__controls {
  display: grid;
  gap: 18px;
}

.upload-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 20px;
}

.upload-heading span {
  color: var(--accent);
  font-size: 0.82rem;
  font-weight: 800;
}

.upload-heading h2 {
  margin-top: 5px;
  font-size: 1.65rem;
}

.upload-heading p {
  max-width: 300px;
  color: var(--muted);
  font-size: 0.9rem;
  text-align: right;
}

.drop-zone {
  min-height: 420px;
  display: grid;
  place-items: center;
  overflow: hidden;
  cursor: pointer;
  border: 1px dashed rgba(155, 91, 46, 0.45);
  border-radius: 8px;
  background: #faf8f5;
}

.drop-zone:hover,
.drop-zone.is-drag-over {
  border-color: var(--accent);
  background: #fff7ee;
}

.drop-placeholder {
  display: grid;
  gap: 8px;
  text-align: center;
}

.drop-placeholder span {
  color: var(--muted);
  font-size: 0.9rem;
}

.preview-img {
  width: 100%;
  height: 100%;
  max-height: 580px;
  object-fit: contain;
  background: #111217;
}

.field-stack {
  display: grid;
  gap: 8px;
  font-weight: 700;
}

.control-actions {
  display: grid;
  gap: 10px;
}

@media (max-width: 820px) {
  .upload-workbench {
    grid-template-columns: 1fr;
    align-items: stretch;
  }

  .upload-heading {
    align-items: start;
    flex-direction: column;
  }

  .upload-heading p {
    text-align: left;
  }

  .drop-zone {
    min-height: 320px;
  }
}
</style>
