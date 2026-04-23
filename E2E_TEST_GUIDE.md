# Nutri-Flow E2E Test Guide (Current MVP)

## 1. Prerequisites

- Docker services ready: mysql, rabbitmq, minio, chroma
- `nutri-business` running on `http://localhost:8080/api`
- `nutri-agent` running and consuming queue
- `nutri-ai-mcp` running and reachable by agent MCP call
- `nutri-web` running for quick validation UI

## 2. Fixed demo account

- Use user id: `1`
- Frontend default is already set to `1`

## 3. Verify profile APIs first

### GET profile

`GET /api/v1/users/1/profile`

Expected fields:
- `healthGoal`
- `dailyCalorieTarget`
- `dietaryRestrictions`

### PUT profile

`PUT /api/v1/users/1/profile`

Body example:
```json
{
  "healthGoal": "WEIGHT_LOSS",
  "dailyCalorieTarget": 1800,
  "dietaryRestrictions": ["high_sugar"]
}
```

Expected: response echoes updated values.

## 4. Run meal analysis chain

1. Open web home page.
2. Go to profile page and set a distinct goal (e.g. `MUSCLE_GAIN`).
3. Go to upload page, select image, choose meal type, submit.
4. Wait for `PENDING -> COMPLETED`.
5. Confirm result page shows:
   - segmentation visualization
   - detected items
   - calorie summary
   - advice report text

## 5. Verify status and history APIs

### Poll status

`GET /api/v1/diet-logs/{taskId}/status`

- Pending response should be `status=PENDING`
- Completed response should include `analysisResult`
- Failed task should be surfaced as `status=FAILED` (not forced to COMPLETED)

### History list

`GET /api/v1/diet-logs?userId=1&page=0&size=10`

Expected fields per item:
- `taskId`
- `mealType`
- `loggedAt`
- `status`
- `detectedItemsCount`
- `adviceReport`

## 6. UI paths now available

- `/upload` : upload and analysis
- `/profile` : health goal config
- `/history` : analysis history pagination

## 7. Known limitations in current MVP

- Tiny classes may be skipped for visual clarity.
- Weight and calories are rough estimates.
- Flutter app shell is planned in `nutri-mobile`, web currently acts as test harness.
