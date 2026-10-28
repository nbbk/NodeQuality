# Attribution and modification notice

This work is derived from LloydAsp/NodeQuality, by Lloyd@nodeseek.com.
Upstream source: https://github.com/LloydAsp/NodeQuality
Base commit: a92fca6c0067df29ddd03fdc2fee6f3000f64545

The original LICENSE (GNU Affero General Public License, version 3) is retained
unchanged. Existing upstream third-party attribution remains in source files
and README.upstream.md. NB branding identifies this modified version, not sole
authorship of the original project or endorsement by the upstream authors.

Modifications dated 2026-10-28: local-first report retention, explicit optional
self-hosted sharing, corrected exit/cleanup handling, checked downloads and
architecture selection, BenchOS digest pinning, removal of forced amd64 NextTrace
preload in favor of verified architecture-specific v1.7.5 assets, revised safety documentation, mock tests, and a new self-hosted report
service. See the Git diff for the corresponding source changes.

Release preparation must preserve this notice and LICENSE and provide the
corresponding modified source. The maintained public fork is https://github.com/nbbk/NodeQuality. Publishing
source does not deploy the report service or authorize running benchmarks.
