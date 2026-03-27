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

  const userId = localStorage.getItem('userId') || 'guest'
  const { data } = await api.post('/diet-logs/upload', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
      'X-User-Id': userId,
    },
  })
  return data
}
