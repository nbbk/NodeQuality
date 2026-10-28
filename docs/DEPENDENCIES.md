# Dependency verification record (2026-10-28 UTC)

BenchOS v0.0.2 release metadata was read through the GitHub connector from:
https://api.github.com/repos/LloydAsp/NodeQuality/releases/tags/v0.0.2

| Asset | GitHub asset ID | SHA-256 reported by GitHub |
|---|---:|---|
| BenchOs.tar.gz | 345686702 | 5f844e73941c3623175c5cdc16b01db34c155d0d1bd9b0cf71f3d72e8b1148e1 |
| BenchOs-arm.tar.gz | 345687500 | a4dd4e55b129157a02dab437b78e41b5797a7a79a0f0b7febdecab8eb2a312c7 |

These values are enforced by NodeQuality.sh before extraction. The release is
not marked immutable; a changed asset will fail verification. The asset bytes
were not downloaded or independently scanned during development. This is an
integrity pin, not proof of security or a reproducible build.

The three Check.Place benchmark scripts remain dynamic. Net.Check.Place was
retrieved read-only to verify NextTrace handling: it tests for a nexttrace
executable and, if absent, runs `curl -s nxtrace.org/nt|bash`. This dependency
path is not pinned and does not explicitly require HTTPS. This CLI now refuses network/route tests if NextTrace is absent inside BenchOS,
before downloading/running NetQuality, avoiding the known fallback path.
Before selected network stages, the launcher now installs a pinned,
architecture-correct NextTrace v1.7.5 binary into temporary BenchOS only after
SHA-256 verification. Actual binary execution/compatibility remains untested. Do not
claim that all dependencies are verified. A fully audited/pinned benchmark
bundle and rootfs recipe remain release-hardening work, requiring trusted
artifacts and real architecture validation.

## NextTrace pinned release

Source: https://api.github.com/repos/nxtrace/NTrace-core/releases/tags/v1.7.5
GitHub release metadata verified 2026-10-28; old v1.3.7 had no asset digests.

| Asset | GitHub asset ID | SHA-256 reported by GitHub |
|---|---:|---|
| nexttrace_linux_amd64 | 643959752 | 7d7fa3bdd967494d1c051766696dea753bc6f4a1d95c2016fdfa078cf1894ff6 |
| nexttrace_linux_arm64 | 643959801 | 820a736c60aca52683b5a4c7fa256d7a4248db37f28f2c16ff6daf76a8b0ee87 |

No NextTrace binary was executed in this development environment. The changed
version needs runtime compatibility validation on disposable x86_64/aarch64 VPSes.
