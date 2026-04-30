<template>
  <!--
    MaskCanvas – overlays segmentation masks on top of the meal image.

    Props
    ─────
    imageUrl    : URL of the meal image (background)
    masks       : Array of mask descriptors from the food store:
                    { label, color, bbox: [x0,y0,x1,y1], rleData? }
    width       : Canvas display width  (default: 480)
    height      : Canvas display height (default: 360)
  -->
  <div class="mask-canvas-wrapper">
    <canvas
      ref="canvasRef"
      :width="width"
      :height="height"
      class="mask-canvas"
      aria-label="食物分割蒙版预览"
    />

    <!-- Legend -->
    <ul v-if="masks.length" class="mask-legend">
      <li v-for="(mask, i) in masks" :key="i" class="mask-legend-item">
        <span class="legend-swatch" :style="{ background: mask.color }" />
        {{ mask.label }}
      </li>
    </ul>
  </div>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'

const props = defineProps({
  imageUrl: { type: String, default: null },
  masks: { type: Array, default: () => [] },
  width: { type: Number, default: 480 },
  height: { type: Number, default: 360 },
})

const canvasRef = ref(null)

// Re-draw whenever inputs change
watch(
  () => [props.imageUrl, props.masks, props.width, props.height],
  () => draw(),
  { deep: true }
)

onMounted(() => draw())

// ── Drawing logic ─────────────────────────────────────────────────────────────

async function draw() {
  const canvas = canvasRef.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  ctx.clearRect(0, 0, canvas.width, canvas.height)

  // 1. Draw the background image
  if (props.imageUrl) {
    await drawImage(ctx, props.imageUrl, canvas.width, canvas.height)
  } else {
    drawPlaceholder(ctx, canvas.width, canvas.height)
  }

  // 2. Overlay each mask
  for (const mask of props.masks) {
    if (mask.rleData) {
      drawRleMask(ctx, mask, canvas.width, canvas.height)
    } else if (mask.bbox) {
      drawBboxMask(ctx, mask, canvas.width, canvas.height)
    }
  }
}

/**
 * Draw the meal image stretched to fill the canvas.
 */
function drawImage(ctx, url, canvasW, canvasH) {
  return new Promise((resolve) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => {
      ctx.drawImage(img, 0, 0, canvasW, canvasH)
      resolve()
    }
    img.onerror = () => {
      drawPlaceholder(ctx, canvasW, canvasH)
      resolve()
    }
    img.src = url
  })
}

/**
 * Draw a filled semi-transparent rectangle over the bounding box area.
 * Used as a fallback when RLE mask data is unavailable.
 *
 * The bbox is expected in the model's native pixel space (e.g. 224×224).
 * We scale it to the canvas size.
 */
function drawBboxMask(ctx, mask, canvasW, canvasH) {
  const [x0, y0, x1, y1] = mask.bbox
  // Assume model output space is 224×224
  const modelW = 224
  const modelH = 224
  const scaleX = canvasW / modelW
  const scaleY = canvasH / modelH

  const rx = x0 * scaleX
  const ry = y0 * scaleY
  const rw = (x1 - x0) * scaleX
  const rh = (y1 - y0) * scaleY

  // Fill semi-transparent mask
  ctx.fillStyle = mask.color
  ctx.fillRect(rx, ry, rw, rh)

  // Draw border
  ctx.strokeStyle = mask.color.replace('0.45', '0.9')
  ctx.lineWidth = 2
  ctx.strokeRect(rx, ry, rw, rh)

  // Label
  ctx.font = 'bold 13px sans-serif'
  ctx.fillStyle = 'white'
  ctx.shadowColor = 'rgba(0,0,0,0.7)'
  ctx.shadowBlur = 4
  ctx.fillText(mask.label, rx + 4, ry + 16)
  ctx.shadowBlur = 0
}

/**
 * Decode a COCO RLE mask and paint it onto the canvas using ImageData.
 *
 * RLE format expected: a flat array string "counts" as used by pycocotools,
 * e.g. "10 5 3 8 ..."  (alternating background/foreground run lengths).
 *
 * This is a client-side reference implementation; for production consider
 * pre-computing PNG masks on the server.
 */
function drawRleMask(ctx, mask, canvasW, canvasH) {
  // Parse run-length encoding
  const counts = mask.rleData.trim().split(/\s+/).map(Number)
  const totalPixels = canvasW * canvasH
  const pixels = new Uint8Array(totalPixels)

  let pixelIndex = 0
  let isForeground = false
  for (const runLength of counts) {
    const fill = isForeground ? 1 : 0
    for (let i = 0; i < runLength && pixelIndex < totalPixels; i++, pixelIndex++) {
      pixels[pixelIndex] = fill
    }
    isForeground = !isForeground
  }

  // Parse the RGBA color from the mask color string
  const rgba = parseRgba(mask.color)
  const imageData = ctx.createImageData(canvasW, canvasH)
  for (let i = 0; i < totalPixels; i++) {
    if (pixels[i]) {
      const offset = i * 4
      imageData.data[offset] = rgba.r
      imageData.data[offset + 1] = rgba.g
      imageData.data[offset + 2] = rgba.b
      imageData.data[offset + 3] = Math.round(rgba.a * 255)
    }
  }
  ctx.putImageData(imageData, 0, 0)
}

/**
 * Draw a placeholder when no image is available.
 */
function drawPlaceholder(ctx, canvasW, canvasH) {
  ctx.fillStyle = '#f8efe6'
  ctx.fillRect(0, 0, canvasW, canvasH)
  ctx.fillStyle = '#8b7663'
  ctx.font = '16px sans-serif'
  ctx.textAlign = 'center'
  ctx.fillText('上传餐食图片后，这里将显示食物分割蒙版', canvasW / 2, canvasH / 2)
  ctx.textAlign = 'left'
}

/**
 * Parse "rgba(r, g, b, a)" string into { r, g, b, a }.
 */
function parseRgba(colorStr) {
  const m = colorStr.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/)
  if (!m) return { r: 128, g: 128, b: 128, a: 0.45 }
  return {
    r: parseInt(m[1]),
    g: parseInt(m[2]),
    b: parseInt(m[3]),
    a: m[4] !== undefined ? parseFloat(m[4]) : 1.0,
  }
}
</script>

<style scoped>
.mask-canvas-wrapper {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 0.9rem;
}

.mask-canvas {
  max-width: 100%;
  border-radius: 24px;
  border: 1px solid rgba(234, 215, 202, 0.95);
  background: #f8efe6;
  box-shadow: 0 14px 28px rgba(86, 53, 26, 0.1);
}

.mask-legend {
  list-style: none;
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem;
}

.mask-legend-item {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  min-height: 36px;
  padding: 7px 12px;
  border-radius: 999px;
  background: rgba(255, 252, 248, 0.92);
  border: 1px solid rgba(234, 215, 202, 0.95);
  color: #5f5247;
  font-size: 0.84rem;
  font-weight: 600;
}

.legend-swatch {
  display: inline-block;
  width: 14px;
  height: 14px;
  border-radius: 999px;
  border: 1px solid rgba(0, 0, 0, 0.18);
}
</style>
