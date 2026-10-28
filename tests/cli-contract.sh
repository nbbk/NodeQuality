#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./NodeQuality.sh
base="$(mktemp -d)"
trap 'rm -rf -- "$base"' EXIT
# Any unintended privileged/network execution fails these mocks.
curl() { echo 'unexpected network call' >&2; return 99; }
mount() { echo 'unexpected mount' >&2; return 99; }
chroot() { echo 'unexpected chroot' >&2; return 99; }
work_base="$base/path with spaces"
mkdir -p "$work_base"
pre_init
[[ -d "$report_dir" && $(stat -c %a "$report_dir") == 700 ]]
mkdir -p "$work_dir/BenchOs/result"
printf 'private ip report\n' > "$work_dir/BenchOs/result/ip_quality.log"
upload_result # Default must never invoke curl.
post_cleanup
[[ $(cat "$report_dir/ip_quality.log") == 'private ip report' ]]
[[ ! -e "$work_dir/BenchOs" ]]
# Cleanup failure keeps rootfs and report; failure is nonzero.
mkdir -p "$work_dir/BenchOs/result"
mount_dev=1
umount() { return 1; }
if post_cleanup; then echo 'cleanup incorrectly succeeded'; exit 1; fi
[[ -d "$work_dir/BenchOs" && -f "$report_dir/ip_quality.log" ]]
mount_dev=0
# Explicit URL alone, plaintext URL, stray consent, unknown flags are rejected.
for args in '--upload-url https://example.org/api/v1/reports' '--upload-url http://example.org --consent-upload' '--consent-upload' '--unknown'; do
    if ( upload_url=''; consent_upload=0; get_opts $args ); then exit 1; fi
done
( get_opts --upload-url https://example.org/api/v1/reports --consent-upload )
# Supported architecture selection without mounting.
uname() { case "$1" in -s) echo Linux;; -m) echo aarch64;; esac; }
select_arch
[[ "$bench_os_url" == *BenchOs-arm.tar.gz && ${#bench_os_sha256} == 64 ]]
[[ "$nexttrace_url" == */v1.7.5/nexttrace_linux_arm64 && ${#nexttrace_sha256} == 64 ]]
uname() { case "$1" in -s) echo Linux;; -m) echo armv7l;; esac; }
if select_arch; then exit 1; fi
# Fetch errors propagate, and extraction is never reached.
fetch_file() { return 23; }
tar() { echo 'unexpected extraction' >&2; exit 99; }
if load_bench_os; then exit 1; else [[ $? == 23 ]]; fi
# Digest failure cannot reach extraction or mounting.
fetch_file() { printf 'not an archive' > "$2"; }
sha256sum() { return 1; }
if load_bench_os; then exit 1; fi
if load_nexttrace; then exit 1; fi
[[ ! -e "$work_dir/BenchOs/usr/local/bin/nexttrace" ]]
# Verified fixture is staged atomically with executable permission, never run.
(
    fetch_file() { printf 'synthetic fixture, not a binary' > "$2"; }
    sha256sum() { cat >/dev/null; return 0; }
    load_nexttrace
    [[ $(stat -c %a "$work_dir/BenchOs/usr/local/bin/nexttrace") == 755 ]]
    [[ $(cat "$work_dir/BenchOs/usr/local/bin/nexttrace") == 'synthetic fixture, not a binary' ]]
)
# EOF is not implicit agreement to run benchmark defaults.
if ask_question < /dev/null > /dev/null; then exit 1; fi
# EXIT cleanup preserves success, failures and signal statuses.
for status in 0 17 130 143; do
    if ( post_cleanup() { return 0; }; sig_cleanup "$status" ); then got=0; else got=$?; fi
    [[ "$got" == "$status" ]]
done
if ( post_cleanup() { return 1; }; sig_cleanup 0 ); then exit 1; fi
# Missing NextTrace refuses the affected stages before any script download.
chroot_run() { return 1; }
fetch_file() { echo 'unexpected dependency download' >&2; exit 99; }
if run_net_quality; then exit 1; fi
if run_net_trace; then exit 1; fi
# Mock optional sharing: validate exact JSON and secret handling; no HTTP is sent.
upload_url='https://reports.example/api/v1/reports'
consent_upload=1
NQ_UPLOAD_KEY='mock-only-upload-key-not-a-real-secret'
curl() {
    local arg output='' last=''
    for arg in "$@"; do
        [[ "$arg" != *"$NQ_UPLOAD_KEY"* ]] || return 98
        [[ "$last" != --output ]] || output="$arg"
        last="$arg"
    done
    [[ -n "$output" ]] || return 97
    printf '%s' '{"id":"mock","url":"https://reports.example/r/mock","delete_token":"private-delete-secret","expires_at":"2026-11-04T00:00:00Z"}' > "$output"
}
output="$(upload_result)"
[[ "$output" == *'https://reports.example/r/mock'* && "$output" != *'private-delete-secret'* ]]
[[ ! -e "$report_dir/.upload-header" && $(stat -c %a "$report_dir/share-response.json") == 600 ]]
python3 - "$report_dir/share-payload.json" <<'PYTEST'
import json, sys
p=json.load(open(sys.argv[1]))
assert p['schema_version']==1
assert any(x['title']=='ip_quality.log' and x['content']=='private ip report\n' for x in p['sections'])
PYTEST
# Failed upload preserves existing report and removes transient authorization file.
curl() { return 22; }
if upload_result; then exit 1; else [[ $? == 22 ]]; fi
[[ -f "$report_dir/ip_quality.log" && ! -e "$report_dir/.upload-header" ]]
printf 'CLI contract tests passed (no benchmarks, mounts, installs or uploads).\n'
