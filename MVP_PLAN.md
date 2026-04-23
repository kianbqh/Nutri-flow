# Nutri-Flow MVP Execution Plan

## 1. MVP Scope (Must Have)

- Mobile-first meal capture flow (Flutter target)
- Upload -> async analysis -> status polling -> result display
- Segmentation overlay (major food items first)
- Total calorie estimate + per-item rough calories
- Personalized advice using user profile context
- User profile editing: health goal, daily calorie target, restrictions
- History list and detail view

## 2. Acceptance Criteria

- End-to-end success rate >= 85% in demo dataset
- Average analysis latency <= 15s under normal local deployment
- Advice references both meal content and user health goal
- Users can complete one analysis without instructor help

## 3. Implemented in This Iteration

### Business Backend

- Added user profile API:
  - GET /api/v1/users/{userId}/profile
  - PUT /api/v1/users/{userId}/profile
- Injected userContext into analysis MQ payload in upload flow
- Added UserRepository for profile read/write
- Seeded demo user (id=1) in DB init script for local MVP testing

### Web Prototype (for early chain validation)

- Default upload user ID changed to 1
- Added profile API wrappers in frontend
- Added profile page for health goal configuration
- Added /profile route and entry from home page

## 4. Next Priority Tasks

1. Build Flutter shell app with 5 pages:
   - Capture/Upload
   - Processing
   - Result
   - Profile
   - History
2. Reuse current backend API semantics:
   - POST /api/v1/diet-logs/upload
   - GET /api/v1/diet-logs/{taskId}/status
   - GET /api/v1/users/{userId}/profile
   - PUT /api/v1/users/{userId}/profile
3. Add diet log history API in business backend:
   - GET /api/v1/diet-logs?userId=...&page=...
4. Add robust status model:
   - PENDING | COMPLETED | FAILED | TIMEOUT (frontend-side)
5. Add graceful fallback strategy:
   - If segmentation lacks small classes, render only confident major items

## 4.1 Client Strategy (Locked)

- `nutri-mobile` is the primary MVP client (Flutter).
- `nutri-web` remains as an internal API debugging and chain-validation prototype.
- Do not mix Flutter source into `nutri-web`.

## 5. Demo Script (Short)

1. Open Profile page and set goal = WEIGHT_LOSS, target kcal = 1800
2. Upload a meal image
3. Show pending state and final segmentation result
4. Highlight total calories and personalized advice text
5. Show profile values are reflected in next analysis advice

## 6. Risks and Mitigation

- Small-class segmentation instability:
  - Mitigate by skipping tiny uncertain classes in visualization
- Message chain breaks:
  - Track by taskId in all logs and expose meaningful frontend errors
- Tight timeline:
  - Prioritize functional closure over UI polish and minor-class perfection
