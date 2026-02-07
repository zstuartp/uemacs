# Test Framework

This project includes a small POSIX-shell test framework with no new
dependencies.

## Quick Start

```sh
make test
```

This runs all `test/t_*.sh` scripts.

## Performance Snapshot

```sh
make test-perf
```

This writes a current snapshot to `build/perf-current.txt` and prints it.

## Baseline and Compare

```sh
make perf-baseline
make perf-compare
```

`perf-compare` fails if selected metrics regress past the threshold.

## Self-Check (Detector Wiring)

```sh
make perf-selfcheck
```

This confirms the perf checker catches an injected slowdown.

## CI Notes

CI runs `make test` on Linux, macOS, FreeBSD, and Cygwin.
CI also runs a lightweight perf snapshot on Linux and uploads the result as
an artifact.
