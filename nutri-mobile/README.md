# Nutri-Flow Mobile (Flutter)

This folder is reserved for the Flutter mobile app MVP.

## Why separate from nutri-web

- Flutter app needs independent build system, dependencies, and platform folders.
- Keep `nutri-web` as a fast API validation prototype.
- Reduce coupling and avoid cross-framework config conflicts.

## Planned pages

1. Capture/Upload
2. Processing
3. Result
4. Profile
5. History

## API base

- Local business backend: `http://<host>:8080/api/v1`

## Immediate next steps

1. Run `flutter create .` in this folder.
2. Add API client + state management.
3. Implement upload -> polling -> result chain first.
