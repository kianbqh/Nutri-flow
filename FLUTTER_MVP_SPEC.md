# Flutter MVP Spec (Nutri-Flow)

## 1. Decision

Use a **new folder** for Flutter app: `nutri-mobile`.
Keep `nutri-web` as a web prototype for API chain debugging.

## 2. Why not reuse nutri-web

- `nutri-web` is Vue + Vite, while Flutter is a different runtime/toolchain.
- Reusing it for Flutter is not technically practical.
- Keeping both lets you iterate backend with web quickly while building true mobile UX in Flutter.

## 3. MVP architecture split

- `nutri-mobile`: primary product client (Flutter)
- `nutri-web`: developer validation UI (optional in demo)
- `nutri-business`: API + task persistence + MQ producer/consumer
- `nutri-agent`: workflow orchestration
- `nutri-ai-mcp`: segmentation inference tool server

## 4. API contract for Flutter (current)

### Upload meal image

- Method: `POST /api/v1/diet-logs/upload`
- Headers:
  - `X-User-Id: 1` (MVP stage)
- Body: `multipart/form-data`
  - `file`: image file
  - `mealType`: `BREAKFAST|LUNCH|DINNER|SNACK`
- Response:
```json
{
  "taskId": "uuid",
  "ossKey": "meals/..",
  "status": "PENDING"
}
```

### Poll task status

- Method: `GET /api/v1/diet-logs/{taskId}/status`
- Response (pending):
```json
{
  "taskId": "uuid",
  "status": "PENDING",
  "analysisResult": null
}
```
- Response (completed):
```json
{
  "taskId": "uuid",
  "status": "COMPLETED",
  "analysisResult": {
    "taskId": "uuid",
    "status": "COMPLETED",
    "segmentationResult": {
      "detected_items": []
    },
    "adviceReport": "..."
  }
}
```

### Get user profile

- Method: `GET /api/v1/users/{userId}/profile`
- Response:
```json
{
  "userId": 1,
  "healthGoal": "WEIGHT_LOSS",
  "dailyCalorieTarget": 1800,
  "dietaryRestrictions": ["high_sugar"]
}
```

### Update user profile

- Method: `PUT /api/v1/users/{userId}/profile`
- Body:
```json
{
  "healthGoal": "WEIGHT_LOSS",
  "dailyCalorieTarget": 1800,
  "dietaryRestrictions": ["high_sugar"]
}
```

### Get user diet history

- Method: `GET /api/v1/diet-logs?userId={userId}&page=0&size=10`
- Response:
```json
{
  "content": [
    {
      "taskId": "uuid",
      "mealType": "LUNCH",
      "loggedAt": "2026-04-06T08:00:00Z",
      "status": "COMPLETED",
      "adviceReport": "...",
      "detectedItemsCount": 3
    }
  ],
  "page": 0,
  "size": 10,
  "totalElements": 12,
  "totalPages": 2,
  "hasNext": true
}
```

## 5. Flutter page data contracts

### CapturePage state

- `File? selectedImage`
- `MealType mealType`
- `bool isUploading`
- `String? error`

### ProcessingPage state

- `String taskId`
- `DateTime startedAt`
- `int pollCount`
- `TaskStatus status` (`pending/completed/failed/timeout`)

### ResultPage state

- `String imageLocalPath`
- `List<DetectedItem> items`
- `double totalCalories`
- `String adviceReport`
- `SegmentationOverlayMode overlayMode` (`bbox` first)

### ProfilePage state

- `HealthGoal healthGoal`
- `int dailyCalorieTarget`
- `List<String> dietaryRestrictions`
- `bool isSaving`

### HistoryPage state

- `List<DietLogSummary> logs`
- `int page`
- `bool hasMore`

## 6. Phase-1 implementation sequence (strict)

1. Bootstrap Flutter app in `nutri-mobile`.
2. Implement API client and error model.
3. Implement Capture -> Upload -> Polling flow.
4. Implement Result page with item list + total calories + advice.
5. Implement Profile page and bind to profile API.
6. Add timeout/retry and network error UX.
7. Add History page after backend history API is added.

## 7. Demo-ready constraints

- Prioritize chain reliability over mask-detail perfection.
- For tiny uncertain classes, allow skip rendering.
- Keep result language concise and actionable.

## 8. Definition of done (mobile MVP)

- User can complete one meal analysis from camera/gallery to advice output.
- Profile edits affect next meal advice context.
- Error states are recoverable (retry works).
- Average perceived wait under target with clear progress feedback.
