import axios from 'axios'

const runtimeApiBaseUrl = (import.meta.env.VITE_API_BASE_URL || '').trim().replace(/\/+$/, '')

const api = axios.create({
  baseURL: runtimeApiBaseUrl || '/api/v1',
  timeout: 30_000,
})

const WEB_PROFILE_CONTEXT_PREFIX = 'webProfileContext:'

function getProfileContextKey(userId) {
  return `${WEB_PROFILE_CONTEXT_PREFIX}${userId || 'anonymous'}`
}

export function getStoredWebSession() {
  const userId = localStorage.getItem('userId') || ''
  const phone = localStorage.getItem('authPhone') || ''

  if (!userId || !phone) {
    localStorage.removeItem('userId')
    localStorage.removeItem('authPhone')
    return {
      userId: '',
      phone: '',
    }
  }

  return { userId, phone }
}

export function saveStoredWebSession(session) {
  if (session?.userId) {
    localStorage.setItem('userId', String(session.userId))
  }
  if (session?.phone) {
    localStorage.setItem('authPhone', session.phone)
  }
}

export function clearStoredWebSession() {
  localStorage.removeItem('userId')
  localStorage.removeItem('authPhone')
}

export function getStoredWebProfileContext(userId) {
  const raw = localStorage.getItem(getProfileContextKey(userId))
  if (!raw) {
    return {
      age: '',
      heightCm: '',
      weightKg: '',
      gender: '',
      activityLevel: 'MEDIUM',
    }
  }

  try {
    const parsed = JSON.parse(raw)
    return {
      age: parsed?.age ?? '',
      heightCm: parsed?.heightCm ?? '',
      weightKg: parsed?.weightKg ?? '',
      gender: parsed?.gender ?? '',
      activityLevel: parsed?.activityLevel ?? 'MEDIUM',
    }
  } catch {
    localStorage.removeItem(getProfileContextKey(userId))
    return {
      age: '',
      heightCm: '',
      weightKg: '',
      gender: '',
      activityLevel: 'MEDIUM',
    }
  }
}

export function saveStoredWebProfileContext(userId, payload) {
  if (!userId) return
  localStorage.setItem(
    getProfileContextKey(userId),
    JSON.stringify({
      age: payload?.age ?? '',
      heightCm: payload?.heightCm ?? '',
      weightKg: payload?.weightKg ?? '',
      gender: payload?.gender ?? '',
      activityLevel: payload?.activityLevel ?? 'MEDIUM',
    })
  )
}

function requireStoredUserId() {
  const { userId, phone } = getStoredWebSession()
  if (!userId || !phone) {
    throw new Error('请先绑定手机号账号后再继续')
  }
  return userId
}

/**
 * Upload a meal image to the business backend.
 * @param {File} file
 * @param {string} mealType
 * @returns {Promise<{taskId: string, ossKey: string, status: string}>}
 */
export async function uploadMealImage(file, mealType) {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('mealType', mealType)

  const userId = requireStoredUserId()
  const profileContext = getStoredWebProfileContext(userId)

  if (profileContext.age !== '' && profileContext.age !== null && profileContext.age !== undefined) {
    formData.append('age', String(profileContext.age))
  }
  if (profileContext.heightCm !== '' && profileContext.heightCm !== null && profileContext.heightCm !== undefined) {
    formData.append('heightCm', String(profileContext.heightCm))
  }
  if (profileContext.weightKg !== '' && profileContext.weightKg !== null && profileContext.weightKg !== undefined) {
    formData.append('weightKg', String(profileContext.weightKg))
  }
  if (profileContext.gender) {
    formData.append('gender', profileContext.gender)
  }
  if (profileContext.activityLevel) {
    formData.append('activityLevel', profileContext.activityLevel)
  }

  const { data } = await api.post('/diet-logs/upload', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
      'X-User-Id': userId,
    },
  })
  return data
}

/**
 * Poll the analysis status for a given task.
 * @param {string} taskId
 * @returns {Promise<{taskId: string, status: 'PENDING'|'COMPLETED'|'FAILED', analysisResult: object|null}>}
 */
export async function getTaskStatus(taskId) {
  const { data } = await api.get(`/diet-logs/${taskId}/status`)
  return data
}

export async function getTaskImageBlob(taskId) {
  const { data } = await api.get(`/diet-logs/${taskId}/image`, {
    responseType: 'blob',
  })
  return data
}

/**
 * Fetch user nutrition profile.
 * @param {string|number} userId
 */
export async function getUserProfile(userId) {
  const { data } = await api.get(`/users/${userId}/profile`)
  return data
}

/**
 * Update user nutrition profile.
 * @param {string|number} userId
 * @param {{nickname?: string|null, healthGoal: string, dailyCalorieTarget: number, dietaryRestrictions: string[], heightCm?: number|null, weightKg?: number|null, gender?: string|null}} payload
 */
export async function updateUserProfile(userId, payload) {
  const { data } = await api.put(`/users/${userId}/profile`, payload)
  return data
}

/**
 * Parse natural language goal text and optionally apply it to profile.
 * @param {string|number} userId
 * @param {{rawText: string, age?: number|null, heightCm?: number|null, weightKg?: number|null, gender?: string|null, activityLevel?: string|null, applyToProfile?: boolean}} payload
 */
export async function parseGoalByAssistant(userId, payload) {
  const { data } = await api.post(`/users/${userId}/profile/assistant-parse`, payload)
  return data
}

/**
 * Send a login code to a phone number.
 * @param {string} phone
 */
export async function sendLoginCode(phone) {
  const { data } = await api.post('/auth/send-code', { phone })
  return data
}

/**
 * Verify a login code and return a lightweight session payload.
 * @param {string} phone
 * @param {string} code
 */
export async function verifyLoginCode(phone, code) {
  const { data } = await api.post('/auth/verify-code', { phone, code })
  return data
}

/**
 * Query paged diet log history for a user.
 * @param {string|number} userId
 * @param {number} page
 * @param {number} size
 */
export async function getDietLogHistory(userId, page = 0, size = 10) {
  const { data } = await api.get('/diet-logs', {
    params: { userId, page, size },
  })
  return data
}
