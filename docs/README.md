# Documentation Guide

This folder keeps both stable engineering documents and longer research notes.
For a GitHub reviewer, start with the stable documents first and treat the
development logs as supporting evidence.

## Recommended Reading Order

1. `软件工程文档包/`
   Stable software-engineering documents: requirements, architecture, database
   design, API contracts, UI flow, test plan, agent workflow, model baseline,
   and release notes.

2. `开发与优化记录/`
   Chronological engineering and experiment logs. These files are useful for
   tracing why a decision was made, but they are intentionally more verbose.

3. `毕业论文/`
   Thesis drafts, chapter material, experiment summaries, and reference notes.

## Current Showcase Baseline

- Default released model: Stage7S1 Phase A.
- Main application path: client upload -> Spring Boot API -> RabbitMQ ->
  LangGraph agent -> FastAPI segmentation REST endpoint -> RabbitMQ result ->
  client polling/history.
- MCP interface: available as an additional SSE tool surface for protocol
  experiments.

## Maintenance Notes

- Keep README and stable engineering docs concise.
- Keep long chronological logs under `开发与优化记录/` instead of duplicating
  their full content in the root README.
- Do not commit model weights, datasets, runtime logs, or local toolchains.
