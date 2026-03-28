import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { uploadMealImage, getTaskStatus } from '@/api/dietLog'

// ── Polling configuration ─────────────────────────────────────────────────────
const POLL_INTERVAL_MS = 3_000    // check every 3 s
const POLL_TIMEOUT_MS  = 300_000  // give up after 5 min

/**
 * Pinia store for food analysis state.
 *
 * Responsibilities:
 *  - track upload / analysis status
 *  - store segmentation masks and detected food items
 *  - expose computed totals (calories, macros)
 *  - manage status polling lifecycle
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

  /** Internal polling timer handle */
  let _pollTimer = null
  let _pollStart = 0

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
   * Automatically starts polling for the result.
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
      startPolling(response.taskId)
    } catch (err) {
      error.value = err.message || 'Upload failed'
      status.value = 'FAILED'
    }
  }

  /**
   * Begin polling the status endpoint every POLL_INTERVAL_MS milliseconds.
   * Stops automatically when status becomes COMPLETED or FAILED, or after
   * POLL_TIMEOUT_MS to prevent memory leaks.
   * @param {string} id - taskId to poll
   */
  function startPolling(id) {
    stopPolling()
    _pollStart = Date.now()

    _pollTimer = setInterval(async () => {
      if (Date.now() - _pollStart > POLL_TIMEOUT_MS) {
        stopPolling()
        error.value = '分析超时，请稍后刷新页面重试'
        status.value = 'FAILED'
        return
      }

      try {
        const result = await getTaskStatus(id)
        if (result.status === 'COMPLETED' && result.analysisResult) {
          stopPolling()
          applyAnalysisResult(result.analysisResult)
        } else if (result.status === 'FAILED') {
          stopPolling()
          error.value = result.analysisResult?.error || '分析失败'
          status.value = 'FAILED'
        }
      } catch (err) {
        // Network hiccup – keep polling; persistent errors will hit the timeout
        console.warn('[nutri-flow] poll error:', err.message)
      }
    }, POLL_INTERVAL_MS)
  }

  /** Cancel any active polling timer. */
  function stopPolling() {
    if (_pollTimer !== null) {
      clearInterval(_pollTimer)
      _pollTimer = null
    }
  }

  /**
   * Called when the analysis result arrives from the status endpoint.
   * @param {object} result - full analysisResult JSON
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
    stopPolling()
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
    startPolling,
    stopPolling,
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
