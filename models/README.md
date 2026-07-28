# Runtime model directory

Production deployment mounts this directory into the inference container as
`/models` in read-only mode.

Place the release checkpoint here as:

```text
models/stage7s1.pth
```

Model binaries are intentionally ignored by Git and must be transferred to the
server separately.
