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
Default focus is editor paths; CLI (`--version`, `--help`) is off by default.

## Mini-Buffer Focus

```sh
make perf-mini
```

This runs a lighter snapshot with extra command-dispatch (`M-x` style) load.

## A/B Compare

```sh
make perf-ab PERF_AB_B=codex/test-framework
```

This runs paired medians for A/B refs and prints deltas for core metrics.
If a ref does not export a metric, that row shows `n/a`.

Use `PERF_AB_A=<ref>` to override A (default is current `HEAD`).

## Baseline and Compare

```sh
make perf-baseline
make perf-compare
```

`perf-compare` fails if selected metrics regress past the threshold.
It now reports warnings and hard-fail thresholds separately.

## Self-Check (Detector Wiring)

```sh
make perf-selfcheck
```

This confirms the perf checker catches an injected slowdown.

## CI Notes

CI runs `make test` on Linux, macOS, FreeBSD, and Cygwin.
CI also runs a lightweight perf snapshot on Linux and uploads the result as
an artifact.
