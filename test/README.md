# Test Framework

This project includes a small POSIX-shell test framework with no new
dependencies.

## Quick Start

```sh
make test
```

This runs all `test/t_*.sh` scripts.

## Performance Check

```sh
make perf
```

This runs a quick qualitative perf check and writes the snapshot to
`build/perf-current.txt`.

## Full Perf Snapshot

```sh
make test-perf
```

This runs the fuller perf profile. It is slower than `make perf`.

## Baseline and Compare

```sh
make perf-baseline
make perf-compare
```

`perf-compare` fails if selected metrics regress past the threshold.
It now reports warnings and hard-fail thresholds separately.
By default, baseline and history files are kept under `build/`.

## Self-Check (Detector Wiring)

```sh
make perf-selfcheck
```

This confirms the perf checker catches an injected slowdown.

## A/B Compare (Optional)

`make perf-ab` is disabled by default because it is expensive.
Enable it explicitly:

```sh
PERF_AB_ENABLE=1 make perf-ab PERF_AB_B=<ref>
```

## CI Notes

CI runs `make test` on Linux, macOS, FreeBSD, and Cygwin.
CI also runs a lightweight perf snapshot on Linux and uploads the result as
an artifact.
