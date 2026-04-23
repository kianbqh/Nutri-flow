import axios from 'axios'

const api = axios.create({
  baseURL: '/api/v1',
  timeout: 30_000,
})

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

  const userId = localStorage.getItem('userId') || '1'
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
 * @param {{healthGoal: string, dailyCalorieTarget: number, dietaryRestrictions: string[]}} payload
 */
export async function updateUserProfile(userId, payload) {
  const { data } = await api.put(`/users/${userId}/profile`, payload)
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
