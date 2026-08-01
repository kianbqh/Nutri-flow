# Changelog

## 1.1.0 - 2026-08-02

### Added

- Protected task-trace dashboard with a seven-stage visual pipeline.
- Structured task lifecycle events for upload, queues, agent, inference,
  advice generation, and database persistence.
- Automatic trace refresh and direct task lookup from diet-log records.

### Changed

- Analysis result pages update automatically when background work completes.
- Segmentation regions are visible by default on Web and Flutter.
- Internal trace ingestion is blocked at the public gateway and accepts only
  authenticated container-network events.

### Operations

- Trace events contain only task stage, state, service, timing, and a short
  diagnostic message; no image, phone number, access code, or model input is
  stored.
