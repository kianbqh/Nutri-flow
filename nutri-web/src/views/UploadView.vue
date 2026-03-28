<template>
  <div class="upload-view">
    <h2>上传餐食照片</h2>

    <!-- Upload form -->
    <div class="upload-card">
      <div
        class="drop-zone"
        :class="{ 'drag-over': isDragOver }"
        @dragover.prevent="isDragOver = true"
        @dragleave="isDragOver = false"
        @drop.prevent="onDrop"
        @click="fileInput.click()"
      >
        <template v-if="!foodStore.previewUrl">
          <span class="drop-icon">📷</span>
          <p>点击或拖拽上传餐食图片</p>
          <p class="hint">支持 JPG / PNG，最大 10 MB</p>
        </template>
        <img
          v-else
          :src="foodStore.previewUrl"
          alt="预览"
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

      <div class="form-row">
        <label for="meal-type">餐次</label>
        <select id="meal-type" v-model="mealType">
          <option value="BREAKFAST">早餐</option>
          <option value="LUNCH">午餐</option>
          <option value="DINNER">晚餐</option>
          <option value="SNACK">加餐</option>
        </select>
      </div>

      <button
        class="btn-analyse"
        :disabled="!selectedFile || foodStore.isLoading"
        @click="analyse"
      >
        {{ foodStore.isLoading ? '分析中…' : '开始分析' }}
      </button>

      <!-- Polling progress indicator -->
      <p v-if="foodStore.status === 'PENDING'" class="polling-hint">
        ⏳ AI 正在分析，通常需要 5–15 秒，请稍候…
      </p>

      <p v-if="foodStore.error" class="error-msg">{{ foodStore.error }}</p>
    </div>

    <!-- Results -->
    <div v-if="foodStore.status === 'COMPLETED'" class="results">
      <h3>分析结果</h3>

      <!-- Canvas mask visualisation -->
      <MaskCanvas
        :image-url="foodStore.previewUrl"
        :masks="foodStore.masks"
        :width="480"
        :height="360"
      />

      <!-- Detected food items table -->
      <table class="items-table">
        <thead>
          <tr>
            <th>食物</th>
            <th>置信度</th>
            <th>预估重量</th>
            <th>热量 (kcal)</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(item, i) in foodStore.detectedItems" :key="i">
            <td>{{ item.label }}</td>
            <td>{{ (item.confidence * 100).toFixed(1) }}%</td>
            <td>{{ item.estimated_weight_g ? item.estimated_weight_g + 'g' : '—' }}</td>
            <td>{{ item.nutrition?.calories_kcal ?? '—' }}</td>
          </tr>
        </tbody>
        <tfoot>
          <tr>
            <td colspan="3"><strong>合计热量</strong></td>
            <td><strong>{{ foodStore.totalCalories.toFixed(1) }} kcal</strong></td>
          </tr>
        </tfoot>
      </table>

      <!-- AI advice -->
      <div class="advice-panel">
        <h4>🤖 AI 膳食建议</h4>
        <p class="advice-text">{{ foodStore.adviceReport ?? '建议生成中，请稍候…' }}</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onBeforeUnmount } from 'vue'
import MaskCanvas from '@/components/MaskCanvas.vue'
import { useFoodStore } from '@/stores/food'

const foodStore = useFoodStore()
const fileInput = ref(null)
const selectedFile = ref(null)
const mealType = ref('LUNCH')
const isDragOver = ref(false)

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
  // uploadAndAnalyse now automatically starts polling after a successful upload
  await foodStore.uploadAndAnalyse(selectedFile.value, mealType.value)
}

// Stop polling if the user navigates away before the result arrives
onBeforeUnmount(() => foodStore.stopPolling())
</script>

<style scoped>
.upload-view {
  max-width: 720px;
  margin: 0 auto;
}

.upload-view h2 {
  margin-bottom: 1.5rem;
  color: #2e7d32;
}

.upload-card {
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  margin-bottom: 2rem;
}

.drop-zone {
  border: 2px dashed #a5d6a7;
  border-radius: 8px;
  height: 200px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: background 0.2s;
  overflow: hidden;
  margin-bottom: 1rem;
}

.drop-zone.drag-over,
.drop-zone:hover {
  background: #f1f8e9;
}

.drop-icon {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
}

.hint {
  font-size: 0.8rem;
  color: #aaa;
}

.preview-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.form-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1rem;
}

.form-row select {
  padding: 0.4rem 0.75rem;
  border-radius: 6px;
  border: 1px solid #ccc;
}

.btn-analyse {
  background: linear-gradient(135deg, #4caf50, #2196f3);
  color: white;
  border: none;
  padding: 0.6rem 2rem;
  border-radius: 20px;
  font-size: 1rem;
  cursor: pointer;
  transition: opacity 0.2s;
}

.btn-analyse:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.error-msg {
  color: #e53935;
  margin-top: 0.5rem;
  font-size: 0.9rem;
}

.polling-hint {
  color: #ff8f00;
  margin-top: 0.5rem;
  font-size: 0.9rem;
}

.results h3 {
  margin-bottom: 1rem;
  color: #2e7d32;
}

.items-table {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
  background: white;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 1px 6px rgba(0,0,0,0.07);
}

.items-table th,
.items-table td {
  padding: 0.6rem 1rem;
  text-align: left;
  border-bottom: 1px solid #f0f0f0;
}

.items-table th {
  background: #e8f5e9;
  font-weight: 600;
}

.advice-panel {
  background: #fff8e1;
  border-left: 4px solid #ffc107;
  border-radius: 8px;
  padding: 1rem 1.5rem;
  margin-top: 1.5rem;
}

.advice-panel h4 {
  margin-bottom: 0.5rem;
}

.advice-text {
  white-space: pre-wrap;
  line-height: 1.7;
  color: #555;
}
</style>
