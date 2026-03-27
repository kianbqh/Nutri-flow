import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { uploadMealImage } from '@/api/dietLog'

/**
 * Pinia store for food analysis state.
 *
 * Responsibilities:
 *  - track upload / analysis status
 *  - store segmentation masks and detected food items
 *  - expose computed totals (calories, macros)
 */
export const useFoodStore = defineStore('food', () => {
  // ── State ──────────────────────────────────────────────────────────────
  const taskId = ref(null)
  const status = ref('IDLE') // IDLE | UPLOADING | PENDING | COMPLETED | FAILED
  const previewUrl = ref(null)
  const detectedItems = ref([])
  const masks = ref([])        // array of { label, color, rleData, bbox }
  const adviceReport = ref(null)
  const error = ref(null)

  // ── Getters ────────────────────────────────────────────────────────────
  const totalCalories = computed(() =>
    detectedItems.value.reduce((sum, item) => sum + (item.nutrition?.calories_kcal ?? 0), 0)
  )

  const isLoading = computed(() =>
    status.value === 'UPLOADING' || status.value === 'PENDING'
  )

  // ── Actions ────────────────────────────────────────────────────────────

  /**
   * Upload a meal image and dispatch an analysis task.
   * @param {File} file
   * @param {string} mealType - BREAKFAST | LUNCH | DINNER | SNACK
   */
  async function uploadAndAnalyse(file, mealType) {
    reset()
    status.value = 'UPLOADING'
    previewUrl.value = URL.createObjectURL(file)

    try {
      const response = await uploadMealImage(file, mealType)
      taskId.value = response.taskId
      status.value = 'PENDING'
    } catch (err) {
      error.value = err.message || 'Upload failed'
      status.value = 'FAILED'
    }
  }

  /**
   * Called when the analysis result arrives (e.g. via polling or WebSocket).
   * @param {object} result
   */
  function applyAnalysisResult(result) {
    detectedItems.value = result.segmentationResult?.detected_items ?? []
    masks.value = detectedItems.value.map((item, i) => ({
      label: item.label,
      color: _paletteColor(i),
      bbox: item.bbox,
      rleData: item.mask_rle,
    }))
    adviceReport.value = result.adviceReport
    status.value = 'COMPLETED'
  }

  function reset() {
    taskId.value = null
    status.value = 'IDLE'
    previewUrl.value = null
    detectedItems.value = []
    masks.value = []
    adviceReport.value = null
    error.value = null
  }

  return {
    taskId,
    status,
    previewUrl,
    detectedItems,
    masks,
    adviceReport,
    error,
    totalCalories,
    isLoading,
    uploadAndAnalyse,
    applyAnalysisResult,
    reset,
  }
})

// ── Helpers ──────────────────────────────────────────────────────────────────
const PALETTE = [
  'rgba(255, 99, 132, 0.45)',
  'rgba(54, 162, 235, 0.45)',
  'rgba(255, 206, 86, 0.45)',
  'rgba(75, 192, 192, 0.45)',
  'rgba(153, 102, 255, 0.45)',
  'rgba(255, 159, 64, 0.45)',
]

function _paletteColor(index) {
  return PALETTE[index % PALETTE.length]
}
