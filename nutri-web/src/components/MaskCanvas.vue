<template>
  <div class="mask-canvas-wrapper">
    <div class="mask-toolbar">
      <div>
        <span class="mask-toolbar__label">分割交互</span>
        <p class="mask-toolbar__text">{{ helperText }}</p>
      </div>
      <button
        v-if="hasInteractiveOverlay && imageUrl"
        type="button"
        class="mask-toggle"
        @click="showOriginalOnly = !showOriginalOnly"
      >
        {{ showOriginalOnly ? '显示分割轮廓' : '查看原图' }}
      </button>
    </div>

    <div class="mask-stage-shell">
      <canvas
        v-if="hasInteractiveOverlay"
        ref="canvasRef"
        class="mask-canvas"
        :width="canvasSize.width"
        :height="canvasSize.height"
        aria-label="食物分割轮廓交互图"
        @click="handleCanvasClick"
      />

      <div v-else class="mask-fallback-frame">
        <img v-if="fallbackImageUrl" :src="fallbackImageUrl" alt="分割预览" class="mask-fallback-image" />
        <p v-else class="mask-placeholder">上传餐食图片后，这里将显示分割结果。</p>
      </div>
    </div>

    <ul v-if="groups.length" class="mask-legend">
      <li v-for="(group, index) in groups" :key="group.key">
        <button
          type="button"
          class="mask-legend-item"
          :class="{ 'is-active': selectedGroupKey === group.key }"
          :aria-pressed="selectedGroupKey === group.key"
          @click="selectGroup(group)"
        >
          <span class="legend-swatch" :style="{ background: group.color }" />
          <span class="legend-index">{{ index + 1 }}</span>
          <span>{{ group.displayName }}</span>
        </button>
      </li>
    </ul>

    <article v-if="selectedGroup" class="mask-detail-card">
      <div class="mask-detail-card__head">
        <div>
          <span class="mask-detail-card__eyebrow">当前选中</span>
          <h4>{{ selectedGroup.displayName }}</h4>
        </div>
        <span class="mask-detail-card__regions">{{ selectedGroup.instanceCount }} 个区域</span>
      </div>

      <div class="mask-detail-grid">
        <div>
          <span>平均置信度</span>
          <strong>{{ (selectedGroup.averageConfidence * 100).toFixed(1) }}%</strong>
        </div>
        <div>
          <span>总热量</span>
          <strong>{{ selectedGroup.totalCalories.toFixed(1) }} kcal</strong>
        </div>
        <div>
          <span>蛋白质</span>
          <strong>{{ selectedGroup.totalProtein.toFixed(1) }} g</strong>
        </div>
        <div>
          <span>脂肪</span>
          <strong>{{ selectedGroup.totalFat.toFixed(1) }} g</strong>
        </div>
        <div>
          <span>碳水</span>
          <strong>{{ selectedGroup.totalCarbs.toFixed(1) }} g</strong>
        </div>
        <div>
          <span>预估重量</span>
          <strong>{{ selectedGroup.totalWeight > 0 ? `${selectedGroup.totalWeight.toFixed(1)} g` : '—' }}</strong>
        </div>
      </div>
    </article>
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, ref, shallowRef, watch } from 'vue'
import { buildFoodGroupKey, resolveFoodLabel } from '@/utils/foodLabels'

const props = defineProps({
  imageUrl: { type: String, default: null },
  previewImageUrl: { type: String, default: null },
  items: { type: Array, default: () => [] },
})

const DEFAULT_CANVAS_WIDTH = 720
const PALETTE = [
  'rgba(246, 178, 107, 0.42)',
  'rgba(200, 162, 255, 0.42)',
  'rgba(143, 211, 193, 0.42)',
  'rgba(249, 217, 118, 0.42)',
  'rgba(167, 199, 255, 0.42)',
  'rgba(244, 166, 166, 0.42)',
  'rgba(183, 228, 199, 0.42)',
  'rgba(255, 214, 165, 0.42)',
]

const canvasRef = ref(null)
const baseImage = shallowRef(null)
const previewImage = shallowRef(null)
const selectedGroupKey = ref('')
const showOriginalOnly = ref(false)
const lastImageRect = ref({ left: 0, top: 0, width: 0, height: 0 })

const groups = computed(() => buildGroups(props.items))
const interactiveGroups = computed(() => groups.value.filter(group => group.maskBytes && group.maskWidth > 0 && group.maskHeight > 0))
const selectedGroup = computed(() => groups.value.find(group => group.key === selectedGroupKey.value) || null)
const drawableImage = computed(() => baseImage.value || previewImage.value)
const hasInteractiveOverlay = computed(() => Boolean(drawableImage.value && interactiveGroups.value.length))
const fallbackImageUrl = computed(() => props.previewImageUrl || props.imageUrl || '')
const canvasAspectRatio = computed(() => {
  const referenceGroup = interactiveGroups.value[0]
  if (referenceGroup?.maskWidth && referenceGroup?.maskHeight) {
    return referenceGroup.maskWidth / referenceGroup.maskHeight
  }

  const image = drawableImage.value
  if (image?.naturalWidth && image?.naturalHeight) {
    return image.naturalWidth / image.naturalHeight
  }

  return 1
})
const canvasSize = computed(() => {
  const width = DEFAULT_CANVAS_WIDTH
  const ratio = canvasAspectRatio.value > 0 ? canvasAspectRatio.value : 1
  return {
    width,
    height: Math.max(1, Math.round(width / ratio)),
  }
})
const helperText = computed(() => {
  if (!groups.value.length) {
    return '上传餐图并完成分析后，这里会显示分割结果。'
  }
  if (!interactiveGroups.value.length) {
    return '当前结果只返回了静态分割参考图。'
  }
  if (showOriginalOnly.value) {
    return '当前显示原图，你可以切回轮廓视图对照查看。'
  }
  if (selectedGroup.value) {
    return '已高亮当前食物，点击其他轮廓或图例可以切换。'
  }
  return '点击轮廓或下方图例可查看具体食物明细。'
})

watch(
  () => [props.imageUrl, props.previewImageUrl],
  async () => {
    await hydrateImages()
    await nextTick()
    drawCanvas()
  },
  { immediate: true }
)

watch(
  groups,
  async () => {
    if (!groups.value.some(group => group.key === selectedGroupKey.value)) {
      selectedGroupKey.value = ''
    }
    await nextTick()
    drawCanvas()
  },
  { immediate: true }
)

watch([selectedGroupKey, showOriginalOnly, canvasAspectRatio], async () => {
  await nextTick()
  drawCanvas()
})

onMounted(() => {
  drawCanvas()
})

async function hydrateImages() {
  baseImage.value = await loadImageElement(props.imageUrl)
  previewImage.value = await loadImageElement(props.previewImageUrl)
}

function selectGroup(group) {
  selectedGroupKey.value = selectedGroupKey.value === group.key ? '' : group.key
  showOriginalOnly.value = false
}

function handleCanvasClick(event) {
  if (!hasInteractiveOverlay.value || showOriginalOnly.value) {
    return
  }

  const canvas = canvasRef.value
  if (!canvas) {
    return
  }

  const bounds = canvas.getBoundingClientRect()
  if (!bounds.width || !bounds.height) {
    return
  }

  const x = (event.clientX - bounds.left) * (canvas.width / bounds.width)
  const y = (event.clientY - bounds.top) * (canvas.height / bounds.height)
  const hit = [...interactiveGroups.value].reverse().find(group => containsPoint(group, x, y, lastImageRect.value))

  selectedGroupKey.value = hit?.key || ''
}

function drawCanvas() {
  const canvas = canvasRef.value
  if (!canvas) {
    return
  }

  const ctx = canvas.getContext('2d')
  if (!ctx) {
    return
  }

  ctx.clearRect(0, 0, canvas.width, canvas.height)
  ctx.fillStyle = '#0f1014'
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  const image = drawableImage.value
  if (!image) {
    drawPlaceholder(ctx, canvas.width, canvas.height)
    lastImageRect.value = { left: 0, top: 0, width: canvas.width, height: canvas.height }
    return
  }

  const maskSpaceRect = computeMaskSpaceRect(canvas.width, canvas.height)
  const imageRect = computeContainRectWithin(
    image.naturalWidth || image.width,
    image.naturalHeight || image.height,
    maskSpaceRect
  )
  lastImageRect.value = maskSpaceRect

  ctx.imageSmoothingEnabled = true
  ctx.drawImage(image, imageRect.left, imageRect.top, imageRect.width, imageRect.height)

  if (showOriginalOnly.value) {
    return
  }

  interactiveGroups.value.forEach((group, index) => {
    drawGroupOverlay(ctx, group, index, maskSpaceRect)
  })
}

function drawGroupOverlay(ctx, group, index, imageRect) {
  const isSelected = selectedGroupKey.value === group.key
  const fillCanvas = buildMaskFillCanvas(group, isSelected ? 0.34 : 0.24)
  if (fillCanvas) {
    ctx.save()
    ctx.imageSmoothingEnabled = false
    ctx.drawImage(fillCanvas, imageRect.left, imageRect.top, imageRect.width, imageRect.height)
    ctx.restore()
  }

  const edgePath = buildMaskEdgePath(group.maskBytes, group.maskWidth, group.maskHeight, imageRect)
  if (edgePath) {
    ctx.save()
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'

    if (isSelected) {
      ctx.shadowColor = withAlpha(group.color, 0.46)
      ctx.shadowBlur = 12
      ctx.strokeStyle = withAlpha(group.color, 0.88)
      ctx.lineWidth = 7
      ctx.stroke(edgePath)
      ctx.shadowBlur = 0
    }

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.96)'
    ctx.lineWidth = isSelected ? 4.8 : 3.4
    ctx.stroke(edgePath)

    ctx.strokeStyle = withAlpha(group.color, isSelected ? 0.96 : 0.82)
    ctx.lineWidth = isSelected ? 2.4 : 1.6
    ctx.stroke(edgePath)
    ctx.restore()
  }

  drawBadge(ctx, group, index, imageRect, isSelected)
}

function drawBadge(ctx, group, index, imageRect, isSelected) {
  if (!group.badgeAnchor || !group.maskWidth || !group.maskHeight) {
    return
  }

  const x = imageRect.left + group.badgeAnchor.x / group.maskWidth * imageRect.width
  const y = imageRect.top + group.badgeAnchor.y / group.maskHeight * imageRect.height
  const width = 38
  const height = 28
  const left = clamp(x - width / 2, imageRect.left + 8, imageRect.left + imageRect.width - width - 8)
  const top = clamp(y - height - 8, imageRect.top + 8, imageRect.top + imageRect.height - height - 8)

  ctx.save()
  roundedRectPath(ctx, left, top + 2, width, height, 9)
  ctx.fillStyle = isSelected ? 'rgba(0, 0, 0, 0.24)' : 'rgba(0, 0, 0, 0.14)'
  ctx.fill()

  roundedRectPath(ctx, left, top, width, height, 9)
  ctx.fillStyle = isSelected ? 'rgba(255, 255, 255, 0.98)' : 'rgba(255, 255, 255, 0.94)'
  ctx.fill()
  ctx.strokeStyle = withAlpha(group.color, isSelected ? 0.98 : 0.88)
  ctx.lineWidth = isSelected ? 1.8 : 1.4
  ctx.stroke()

  ctx.font = '700 14px "Segoe UI", "PingFang SC", sans-serif'
  ctx.fillStyle = 'rgba(69, 54, 43, 0.96)'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText(String(index + 1), left + width / 2, top + height / 2 + 0.5)
  ctx.restore()
}

function buildMaskFillCanvas(group, alpha) {
  if (!group.maskBytes || !group.maskWidth || !group.maskHeight) {
    return null
  }

  const offscreen = document.createElement('canvas')
  offscreen.width = group.maskWidth
  offscreen.height = group.maskHeight
  const offscreenCtx = offscreen.getContext('2d')
  if (!offscreenCtx) {
    return null
  }

  const imageData = offscreenCtx.createImageData(group.maskWidth, group.maskHeight)
  const rgba = parseRgba(group.color, alpha)
  for (let index = 0; index < group.maskBytes.length; index += 1) {
    if (!group.maskBytes[index]) {
      continue
    }
    const offset = index * 4
    imageData.data[offset] = rgba.r
    imageData.data[offset + 1] = rgba.g
    imageData.data[offset + 2] = rgba.b
    imageData.data[offset + 3] = Math.round(rgba.a * 255)
  }

  offscreenCtx.putImageData(imageData, 0, 0)
  return offscreen
}

function buildMaskEdgePath(maskBytes, maskWidth, maskHeight, imageRect) {
  if (!maskBytes || !maskWidth || !maskHeight) {
    return null
  }

  const path = new Path2D()
  const cellWidth = imageRect.width / maskWidth
  const cellHeight = imageRect.height / maskHeight

  for (let y = 0; y < maskHeight; y += 1) {
    for (let x = 0; x < maskWidth; x += 1) {
      const index = y * maskWidth + x
      if (!maskBytes[index]) {
        continue
      }

      const x0 = imageRect.left + x * cellWidth
      const y0 = imageRect.top + y * cellHeight
      const x1 = x0 + cellWidth
      const y1 = y0 + cellHeight

      if (y === 0 || !maskBytes[index - maskWidth]) {
        path.moveTo(x0, y0)
        path.lineTo(x1, y0)
      }
      if (x === maskWidth - 1 || !maskBytes[index + 1]) {
        path.moveTo(x1, y0)
        path.lineTo(x1, y1)
      }
      if (y === maskHeight - 1 || !maskBytes[index + maskWidth]) {
        path.moveTo(x0, y1)
        path.lineTo(x1, y1)
      }
      if (x === 0 || !maskBytes[index - 1]) {
        path.moveTo(x0, y0)
        path.lineTo(x0, y1)
      }
    }
  }

  return path
}

function containsPoint(group, x, y, imageRect) {
  if (!group.maskBytes || !group.maskWidth || !group.maskHeight || imageRect.width <= 0 || imageRect.height <= 0) {
    return false
  }

  if (x < imageRect.left || x > imageRect.left + imageRect.width || y < imageRect.top || y > imageRect.top + imageRect.height) {
    return false
  }

  const px = clamp(Math.floor((x - imageRect.left) / imageRect.width * group.maskWidth), 0, group.maskWidth - 1)
  const py = clamp(Math.floor((y - imageRect.top) / imageRect.height * group.maskHeight), 0, group.maskHeight - 1)
  const index = py * group.maskWidth + px
  return Boolean(group.maskBytes[index])
}

function buildGroups(items) {
  const grouped = new Map()

  items.forEach((item, index) => {
    const key = buildFoodGroupKey(item)
    const instance = buildInstance(item, index)

    if (!grouped.has(key)) {
      grouped.set(key, {
        key,
        displayName: instance.displayName,
        instances: [],
      })
    }

    grouped.get(key).instances.push(instance)
  })

  const groups = Array.from(grouped.values()).map(group => {
    const merged = mergeMask(group.instances)
    const totalCalories = group.instances.reduce((sum, instance) => sum + instance.calories, 0)
    const totalProtein = group.instances.reduce((sum, instance) => sum + instance.proteinG, 0)
    const totalFat = group.instances.reduce((sum, instance) => sum + instance.fatG, 0)
    const totalCarbs = group.instances.reduce((sum, instance) => sum + instance.carbsG, 0)
    const totalWeight = group.instances.reduce((sum, instance) => sum + instance.estimatedWeightG, 0)
    const averageConfidence = group.instances.length
      ? group.instances.reduce((sum, instance) => sum + instance.confidence, 0) / group.instances.length
      : 0

    return {
      ...group,
      ...merged,
      totalCalories,
      totalProtein,
      totalFat,
      totalCarbs,
      totalWeight,
      averageConfidence,
      instanceCount: group.instances.length,
    }
  })

  groups.sort((left, right) => {
    const calorieCompare = right.totalCalories - left.totalCalories
    if (calorieCompare !== 0) {
      return calorieCompare
    }
    return right.averageConfidence - left.averageConfidence
  })

  return groups.map((group, index) => ({
    ...group,
    color: PALETTE[index % PALETTE.length],
  }))
}

function buildInstance(item, index) {
  const decodedMask = decodeRleMask(item.mask_rle ?? item.maskRle, item.mask_shape ?? item.maskShape)

  return {
    index,
    displayName: item.displayLabel || resolveFoodLabel(item),
    confidence: toNumber(item.confidence),
    estimatedWeightG: toNumber(item.estimated_weight_g ?? item.weight_g),
    calories: toNumber(item.nutrition?.calories_kcal ?? item.calories),
    proteinG: toNumber(item.nutrition?.protein_g ?? item.protein_g),
    fatG: toNumber(item.nutrition?.fat_g ?? item.fat_g),
    carbsG: toNumber(item.nutrition?.carbs_g ?? item.carbs_g),
    maskBytes: decodedMask?.maskBytes || null,
    maskWidth: decodedMask?.maskWidth || 0,
    maskHeight: decodedMask?.maskHeight || 0,
  }
}

function mergeMask(instances) {
  const candidates = instances.filter(instance => instance.maskBytes && instance.maskWidth > 0 && instance.maskHeight > 0)
  if (!candidates.length) {
    return {
      maskBytes: null,
      maskWidth: 0,
      maskHeight: 0,
      badgeAnchor: null,
      areaPixels: 0,
    }
  }

  const maskWidth = candidates[0].maskWidth
  const maskHeight = candidates[0].maskHeight
  const merged = new Uint8Array(maskWidth * maskHeight)
  let areaPixels = 0
  let minX = maskWidth
  let minY = maskHeight
  let maxX = -1
  let maxY = -1

  candidates.forEach(instance => {
    if (instance.maskWidth !== maskWidth || instance.maskHeight !== maskHeight) {
      return
    }

    instance.maskBytes.forEach((value, index) => {
      if (!value || merged[index]) {
        return
      }

      merged[index] = 1
      areaPixels += 1

      const y = Math.floor(index / maskWidth)
      const x = index % maskWidth
      minX = Math.min(minX, x)
      minY = Math.min(minY, y)
      maxX = Math.max(maxX, x)
      maxY = Math.max(maxY, y)
    })
  })

  if (!areaPixels) {
    return {
      maskBytes: null,
      maskWidth: 0,
      maskHeight: 0,
      badgeAnchor: null,
      areaPixels: 0,
    }
  }

  return {
    maskBytes: merged,
    maskWidth,
    maskHeight,
    badgeAnchor: {
      x: (minX + maxX + 1) / 2,
      y: Math.max(0, minY + 1),
    },
    areaPixels,
  }
}

function decodeRleMask(rleData, maskShape) {
  const shape = parseMaskShape(maskShape)
  const raw = (rleData || '').toString().trim()
  if (!shape || !raw) {
    return null
  }

  const [maskHeight, maskWidth] = shape
  const counts = raw.split(/\s+/).map(value => Number.parseInt(value, 10)).filter(Number.isFinite)
  const maskBytes = new Uint8Array(maskWidth * maskHeight)
  let outputIndex = 0
  let currentValue = 0

  counts.forEach(count => {
    for (let cursor = 0; cursor < count && outputIndex < maskBytes.length; cursor += 1) {
      if (currentValue === 1) {
        maskBytes[outputIndex] = 1
      }
      outputIndex += 1
    }
    currentValue = currentValue === 1 ? 0 : 1
  })

  return {
    maskBytes,
    maskWidth,
    maskHeight,
  }
}

function parseMaskShape(shape) {
  if (!Array.isArray(shape) || shape.length < 2) {
    return null
  }

  const values = shape.slice(0, 2).map(item => Number.parseInt(item, 10))
  return values.every(Number.isFinite) ? values : null
}

function computeContainRect(imageWidth, imageHeight, canvasWidth, canvasHeight) {
  const scale = Math.min(canvasWidth / imageWidth, canvasHeight / imageHeight)
  const width = imageWidth * scale
  const height = imageHeight * scale
  return {
    left: (canvasWidth - width) / 2,
    top: (canvasHeight - height) / 2,
    width,
    height,
  }
}

function computeContainRectWithin(imageWidth, imageHeight, containerRect) {
  const rect = computeContainRect(imageWidth, imageHeight, containerRect.width, containerRect.height)
  return {
    left: containerRect.left + rect.left,
    top: containerRect.top + rect.top,
    width: rect.width,
    height: rect.height,
  }
}

function computeMaskSpaceRect(canvasWidth, canvasHeight) {
  const referenceGroup = interactiveGroups.value[0]
  if (referenceGroup?.maskWidth && referenceGroup?.maskHeight) {
    return computeContainRect(referenceGroup.maskWidth, referenceGroup.maskHeight, canvasWidth, canvasHeight)
  }

  return {
    left: 0,
    top: 0,
    width: canvasWidth,
    height: canvasHeight,
  }
}

function drawPlaceholder(ctx, width, height) {
  ctx.fillStyle = '#f4ece3'
  ctx.fillRect(0, 0, width, height)
  ctx.fillStyle = '#7d6c5d'
  ctx.font = '16px "Segoe UI", "PingFang SC", sans-serif'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText('分割图像暂不可用', width / 2, height / 2)
}

function loadImageElement(url) {
  return new Promise(resolve => {
    if (!url) {
      resolve(null)
      return
    }

    const image = new Image()
    image.crossOrigin = 'anonymous'
    image.onload = () => resolve(image)
    image.onerror = () => resolve(null)
    image.src = url
  })
}

function parseRgba(color, alphaOverride = null) {
  const match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/)
  if (!match) {
    return { r: 128, g: 128, b: 128, a: alphaOverride ?? 0.45 }
  }

  return {
    r: Number.parseInt(match[1], 10),
    g: Number.parseInt(match[2], 10),
    b: Number.parseInt(match[3], 10),
    a: alphaOverride ?? Number.parseFloat(match[4] ?? '1'),
  }
}

function withAlpha(color, alpha) {
  const rgba = parseRgba(color, alpha)
  return `rgba(${rgba.r}, ${rgba.g}, ${rgba.b}, ${rgba.a})`
}

function roundedRectPath(ctx, x, y, width, height, radius) {
  ctx.beginPath()
  ctx.moveTo(x + radius, y)
  ctx.lineTo(x + width - radius, y)
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius)
  ctx.lineTo(x + width, y + height - radius)
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  ctx.lineTo(x + radius, y + height)
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius)
  ctx.lineTo(x, y + radius)
  ctx.quadraticCurveTo(x, y, x + radius, y)
  ctx.closePath()
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function toNumber(value) {
  if (value === null || value === undefined || value === '') {
    return 0
  }

  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : 0
}
</script>

<style scoped>
.mask-canvas-wrapper {
  display: grid;
  gap: 16px;
  width: 100%;
  min-width: 0;
}

.mask-toolbar {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 14px;
}

.mask-toolbar__label {
  display: block;
  color: var(--muted-soft);
  font-size: 0.82rem;
  font-weight: 700;
  margin-bottom: 6px;
}

.mask-toolbar__text {
  color: var(--muted);
  line-height: 1.65;
}

.mask-toggle {
  flex: none;
  min-height: 42px;
  padding: 0 16px;
  border-radius: 999px;
  border: 1px solid rgba(226, 204, 189, 0.95);
  background: rgba(255, 252, 248, 0.96);
  color: var(--accent-strong);
  font-weight: 700;
  cursor: pointer;
}

.mask-stage-shell {
  width: 100%;
  max-width: 100%;
  min-width: 0;
  border-radius: 26px;
  overflow: hidden;
  border: 1px solid rgba(234, 215, 202, 0.95);
  background: #0f1014;
  box-shadow: 0 16px 36px rgba(57, 37, 19, 0.12);
}

.mask-canvas {
  display: block;
  width: 100%;
  max-width: 100%;
  height: auto;
  cursor: crosshair;
}

.mask-fallback-frame {
  min-height: 320px;
  display: grid;
  place-items: center;
  background: #0f1014;
}

.mask-fallback-image {
  display: block;
  width: 100%;
  height: auto;
  object-fit: contain;
}

.mask-placeholder {
  color: rgba(255, 255, 255, 0.82);
  font-weight: 600;
}

.mask-legend {
  list-style: none;
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  padding: 0;
  margin: 0;
}

.mask-legend-item {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 38px;
  padding: 7px 13px;
  border-radius: 999px;
  border: 1px solid rgba(234, 215, 202, 0.95);
  background: rgba(255, 252, 248, 0.96);
  color: #5f5247;
  font-size: 0.86rem;
  font-weight: 600;
  cursor: pointer;
}

.mask-legend-item.is-active {
  border-color: rgba(195, 135, 92, 0.7);
  background: rgba(255, 243, 231, 0.96);
  box-shadow: 0 10px 20px rgba(164, 113, 72, 0.1);
}

.mask-legend-item:focus-visible,
.mask-toggle:focus-visible {
  outline: 3px solid rgba(155, 91, 46, 0.35);
  outline-offset: 2px;
}

.legend-swatch {
  width: 14px;
  height: 14px;
  border-radius: 999px;
  border: 1px solid rgba(0, 0, 0, 0.16);
}

.legend-index {
  display: inline-grid;
  place-items: center;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: rgba(115, 82, 56, 0.09);
  font-size: 0.75rem;
  font-weight: 800;
}

.mask-detail-card {
  padding: 18px;
  border-radius: 24px;
  border: 1px solid rgba(234, 215, 202, 0.95);
  background: linear-gradient(180deg, rgba(255, 250, 245, 0.98), rgba(255, 245, 236, 0.98));
}

.mask-detail-card__head {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 16px;
}

.mask-detail-card__eyebrow {
  display: block;
  color: var(--muted-soft);
  font-size: 0.82rem;
  font-weight: 700;
  margin-bottom: 4px;
}

.mask-detail-card h4 {
  font-size: 1.15rem;
  font-weight: 800;
}

.mask-detail-card__regions {
  display: inline-flex;
  align-items: center;
  min-height: 34px;
  padding: 0 12px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.8);
  color: var(--accent-strong);
  font-weight: 700;
}

.mask-detail-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}

.mask-detail-grid > div {
  padding: 14px 16px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.8);
  border: 1px solid rgba(234, 215, 202, 0.92);
}

.mask-detail-grid span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.8rem;
  margin-bottom: 6px;
}

.mask-detail-grid strong {
  font-size: 1rem;
  font-weight: 800;
}

@media (max-width: 820px) {
  .mask-toolbar {
    flex-direction: column;
  }

  .mask-toggle {
    width: 100%;
    justify-content: center;
  }

  .mask-detail-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 560px) {
  .mask-detail-card__head {
    flex-direction: column;
  }

  .mask-detail-grid {
    grid-template-columns: 1fr;
  }
}
</style>
