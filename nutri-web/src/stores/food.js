import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { uploadMealImage, getTaskStatus, getTaskImageBlob } from '@/api/dietLog'
import { resolveFoodLabel } from '@/utils/foodLabels'

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
  const segmentationPreviewUrl = ref(null)
  const detectedItems = ref([])
  const adviceReport = ref(null)
  const error = ref(null)

  /** Internal polling timer handle */
  let _pollTimer = null
  let _pollStart = 0
  let _pollGeneration = 0
  let _pollInFlight = false
  let _visibilityListener = null
  let _ownedPreviewUrl = null

  // ── Getters ────────────────────────────────────────────────────────────
  const totalCalories = computed(() =>
    detectedItems.value.reduce((sum, item) => sum + (item.nutrition?.calories_kcal ?? item.calories ?? 0), 0)
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
    setOwnedPreviewUrl(URL.createObjectURL(file))

    try {
      const response = await uploadMealImage(file, mealType)
      taskId.value = response.taskId
      status.value = 'PENDING'
      startPolling(response.taskId)
      return response.taskId
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
    const generation = ++_pollGeneration
    _pollStart = Date.now()
    taskId.value = id
    status.value = 'PENDING'

    const poll = async () => {
      if (generation !== _pollGeneration) return
      if (_pollInFlight) return
      if (Date.now() - _pollStart > POLL_TIMEOUT_MS) {
        stopPolling()
        error.value = '分析等待超时，请在历史记录中查看最终状态'
        status.value = 'FAILED'
        return
      }

      _pollInFlight = true
      try {
        const result = await getTaskStatus(id)
        if (generation !== _pollGeneration) return
        if (result.status === 'COMPLETED' && result.analysisResult) {
          stopPolling()
          await loadTaskImage(id)
          applyAnalysisResult(result.analysisResult)
          return
        } else if (result.status === 'FAILED') {
          stopPolling()
          error.value = result.analysisResult?.error || '分析失败'
          status.value = 'FAILED'
          return
        }
      } catch (err) {
        console.warn('[nutri-flow] poll error:', err.message)
      } finally {
        _pollInFlight = false
      }

      if (generation === _pollGeneration) {
        _pollTimer = setTimeout(poll, POLL_INTERVAL_MS)
      }
    }

    if (typeof document !== 'undefined') {
      _visibilityListener = () => {
        if (document.visibilityState !== 'visible' || generation !== _pollGeneration) return
        if (_pollTimer !== null) clearTimeout(_pollTimer)
        _pollTimer = null
        poll()
      }
      document.addEventListener('visibilitychange', _visibilityListener)
    }

    poll()
  }

  /** Cancel any active polling timer. */
  function stopPolling() {
    _pollGeneration += 1
    if (_pollTimer !== null) {
      clearTimeout(_pollTimer)
      _pollTimer = null
    }
    if (_visibilityListener && typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', _visibilityListener)
      _visibilityListener = null
    }
  }

  /**
   * Called when the analysis result arrives from the status endpoint.
   * @param {object} result - full analysisResult JSON
   */
  function applyAnalysisResult(result) {
    const rawItems = result.segmentationResult?.detected_instances ?? result.segmentationResult?.detected_items ?? []

    detectedItems.value = rawItems.map(item => normalizeDetectedItem(item))
    segmentationPreviewUrl.value = toDataUrl(result.segmentationResult?.segmentation_preview_png_base64)
    adviceReport.value = result.adviceReport
    status.value = 'COMPLETED'
  }

  async function loadTaskDetail(id) {
    stopPolling()
    error.value = null
    taskId.value = id
    status.value = 'PENDING'

    try {
      const result = await getTaskStatus(id)
      status.value = result.status || 'PENDING'

      if (result.status === 'COMPLETED' && result.analysisResult) {
        await loadTaskImage(id)

        applyAnalysisResult(result.analysisResult)
        status.value = 'COMPLETED'
        return result
      }

      if (result.status === 'FAILED') {
        detectedItems.value = []
        segmentationPreviewUrl.value = null
        adviceReport.value = ''
        error.value = result.errorMessage || result.analysisResult?.errorMessage || '分析失败'
      } else if (result.status === 'PENDING') {
        startPolling(id)
      }

      return result
    } catch (err) {
      error.value = err?.response?.data?.error || err?.message || '加载任务详情失败'
      status.value = 'FAILED'
      throw err
    }
  }

  function reset() {
    stopPolling()
    taskId.value = null
    status.value = 'IDLE'
    clearOwnedPreviewUrl()
    segmentationPreviewUrl.value = null
    detectedItems.value = []
    adviceReport.value = null
    error.value = null
  }

  async function loadTaskImage(id) {
    try {
      const imageBlob = await getTaskImageBlob(id)
      if (imageBlob && imageBlob.size > 0) {
        setOwnedPreviewUrl(URL.createObjectURL(imageBlob))
      }
    } catch {
      clearOwnedPreviewUrl()
    }
  }

  function setOwnedPreviewUrl(url) {
    clearOwnedPreviewUrl()
    previewUrl.value = url
    _ownedPreviewUrl = url
  }

  function clearOwnedPreviewUrl() {
    if (_ownedPreviewUrl && _ownedPreviewUrl.startsWith('blob:')) {
      URL.revokeObjectURL(_ownedPreviewUrl)
    }
    _ownedPreviewUrl = null
    previewUrl.value = null
  }

  return {
    taskId,
    status,
    previewUrl,
    segmentationPreviewUrl,
    detectedItems,
    adviceReport,
    error,
    totalCalories,
    isLoading,
    uploadAndAnalyse,
    startPolling,
    stopPolling,
    applyAnalysisResult,
    loadTaskDetail,
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

function normalizeDetectedItem(item) {
  const nutrition = normalizeNutrition(item)
  const displayLabel = resolveFoodLabel(item)

  return {
    ...item,
    class_id: item.class_id ?? item.classId ?? null,
    class_name: (item.class_name ?? item.className ?? '').toString(),
    display_name: (item.display_name ?? item.displayName ?? '').toString(),
    label: (item.label ?? item.class_name ?? item.className ?? '').toString(),
    displayLabel,
    confidence: toNumber(item.confidence_score ?? item.confidence),
    estimated_weight_g: toNullableNumber(item.estimated_weight_g ?? item.weight_g ?? item.estimatedWeightG),
    calories: nutrition.calories_kcal,
    bbox: parseBbox(item.bbox),
    mask_rle: (item.mask_rle ?? item.maskRle ?? '').toString(),
    mask_shape: parseMaskShape(item.mask_shape ?? item.maskShape),
    nutrition,
  }
}

function normalizeNutrition(item) {
  const nutrition = item.nutrition ?? {}

  return {
    ...nutrition,
    calories_kcal: toNullableNumber(nutrition.calories_kcal ?? item.calories),
    protein_g: toNullableNumber(nutrition.protein_g ?? item.protein_g),
    fat_g: toNullableNumber(nutrition.fat_g ?? item.fat_g),
    carbs_g: toNullableNumber(nutrition.carbs_g ?? item.carbs_g),
  }
}

function parseBbox(value) {
  if (!Array.isArray(value)) {
    return null
  }

  return value.map(item => toNumber(item))
}

function parseMaskShape(value) {
  if (!Array.isArray(value) || value.length < 2) {
    return null
  }

  const shape = value.slice(0, 2).map(item => Number.parseInt(item, 10))
  return shape.every(Number.isFinite) ? shape : null
}

function toNumber(value) {
  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function toNullableNumber(value) {
  if (value === null || value === undefined || value === '') {
    return null
  }

  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : null
}

function toDataUrl(base64) {
  const normalized = (base64 || '').toString().trim()
  if (!normalized) {
    return null
  }
  if (normalized.startsWith('data:')) {
    return normalized
  }
  return `data:image/png;base64,${normalized}`
}
