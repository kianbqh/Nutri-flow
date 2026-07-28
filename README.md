# Nutri-flow

Nutri-flow is a full-stack AI dietary analysis system. It connects meal-image
upload, food instance segmentation, calorie estimation, and personalized
nutrition advice into one asynchronous workflow.

The project is designed as a graduation-project showcase: the user experience
is visible in Vue and Flutter clients, while the backend demonstrates service
decoupling, queue-based inference, an agent workflow, and model-version
governance.

## Highlights

- Food instance segmentation based on Swin-Tiny, BiFPN, and Coordinate
  Attention.
- Calorie and macro estimates generated from segmented food instances and
  calibrated FoodSeg103 nutrition priors.
- LangGraph agent workflow with user memory, nutrition knowledge retrieval,
  rule-based fallback advice, and LLM-enhanced coaching when an API key is
  configured.
- Spring Boot business service with MySQL persistence, Redis-assisted login,
  RabbitMQ task dispatch, and MinIO/OSS image storage.
- Vue 3 web client and Flutter mobile client with upload, polling, result
  detail, mask visualization, profile, goals, and history views.

## Architecture

```text
Vue / Flutter client
        |
        v
Spring Boot business API  --->  MySQL / Redis / MinIO
        |
        v
RabbitMQ task queue
        |
        v
LangGraph nutri-agent  --->  Chroma nutrition/user memory
        |
        v
FastAPI nutri-ai-mcp segmentation service
        |
        v
RabbitMQ result queue -> Spring Boot -> client polling/history
```

The model service exposes a REST endpoint used by the production workflow and
an MCP SSE tool interface for protocol-level experimentation.

## Repository Layout

```text
contracts/       JSON contracts shared between services
docs/            Software-engineering, experiment, and thesis notes
nutri-agent/     Python LangGraph consumer and nutrition-advice workflow
nutri-ai-mcp/    FastAPI segmentation service and training/inference code
nutri-business/  Spring Boot business API
nutri-mobile/    Flutter mobile client
nutri-web/       Vue 3 web client
scripts/         Windows PowerShell dev orchestration scripts
```

## Default Model

The current application default is:

```text
Stage7S1 Phase A
best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth
```

It is selected by the project gate records as the best released checkpoint in
the current experiment series. Large checkpoint files are intentionally ignored
by Git; configure the local path through `NUTRI_SEG_CHECKPOINT` or use
`scripts/dev-up.ps1`, which sets the default path for the local workspace.

## Local Development

Requirements:

- Windows PowerShell
- Docker Desktop
- Local model weights under `nutri-ai-mcp/weights_by_category/...`
- Bundled tools in `.tools/` or equivalent local Node, Maven, Flutter, and
  Python environments

Start the full local stack:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev-up.ps1
```

If Docker infrastructure is already running:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev-up.ps1 -SkipDocker
```

Run health checks:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev-health.ps1
```

Stop managed services:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev-down.ps1
```

Managed logs are written to `.runtime/logs`.

## Protected Public Deployment

The repository includes a production-oriented Compose profile with multi-stage
application images, Caddy-managed HTTPS, a Basic Auth staging gate, private
infrastructure networking, model fail-fast checks, and persistent volumes.

See [docs/PUBLIC_DEPLOYMENT.md](docs/PUBLIC_DEPLOYMENT.md) for the server,
secrets, model-transfer, startup, verification, backup, and rollback steps.

## Validation

Useful local checks:

```powershell
cd nutri-business
..\.tools\apache-maven-3.9.9\bin\mvn.cmd "-Dmaven.repo.local=..\.tools\m2\repository" -q -DskipTests compile

cd ..\nutri-web
npm run build
```

The Flutter client can be checked with:

```powershell
cd nutri-mobile
..\.tools\flutter_sdk_3.41.6\flutter\bin\flutter.bat analyze
```

## Notes

- Calorie values are estimates for dietary feedback, not medical or clinical
  measurements.
- The demo login flow returns a debug verification code for local testing.
  Production deployment should replace it with a real verification provider
  and authenticated API access.
- Model weights, datasets, local toolchains, caches, and runtime logs are not
  committed to Git.
