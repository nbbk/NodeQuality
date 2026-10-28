#!/bin/bash

# NB NodeQuality modifications, 2026-10-28. Derived from LloydAsp/NodeQuality.
# Original license and attribution are retained in LICENSE and NOTICE.md.
upstream_commit="a92fca6c0067df29ddd03fdc2fee6f3000f64545"
tool_version="0.1.0-dev"
current_time="$(date -u +%Y_%m_%d_%H_%M_%S)"
work_base="$PWD"
work_dir=""
report_dir=""
upload_url=""
consent_upload=0
mount_proc=0
mount_sys=0
mount_dev=0
bench_os_url=""
bench_os_sha256=""
nexttrace_url=""
nexttrace_sha256=""

header_info_filename=header_info.log
ip_quality_filename=ip_quality.log
ip_quality_json_filename=ip_quality.json
hardware_quality_filename=hardware_quality.log
hardware_quality_json_filename=hardware_quality.json
net_quality_filename=net_quality.log
net_quality_json_filename=net_quality.json
backroute_trace_filename=backroute_trace.log
backroute_trace_json_filename=backroute_trace.json
port_filename=port.log

lang="cn"
opt_ipv=""
opt_lang=""
err_code=0

declare -A LANG
# ===== English =====
LANG[en.err01]="Error: work_dir does not contain 'nodequality'!"
LANG[en.err02]="Error: Unsupported parameters!"
LANG[en.err03]="Error: the specified work_dir does not exist or is not readable/writable!"
LANG[en.cleanup]="Cleaning, please wait a moment."
LANG[en.clean_fail]="An unexpected situation occurred: the BenchOS directory mount was not cleaned up properly. For safety, please reboot and then delete this directory."
LANG[en.ask_hq]="Run HardwareQuality test? (Enter for default 'y', 'f' for fast mode, 'v' for all test details) [y/f/v/n]: "
LANG[en.ask_iq]="Run IPQuality test? (Enter for default 'y') [y/n]: "
LANG[en.ask_nq]="Run NetQuality test? (Enter for default 'y', 'l' for low-data mode) [y/l/n]: "
LANG[en.ask_bt]="Run Backroute Trace test? (Enter for default 'y') [y/n]: "
LANG[en.cleanup_before]="Clean Up before Installation"
LANG[en.loadbench]="Load BenchOs"
LANG[en.basicinfo]="Hardware Info"
LANG[en.run_hq]="Running Hardware Quality Test..."
LANG[en.run_iq]="Running IP Quality Test..."
LANG[en.run_nq]="Running Network Quality Test..."
LANG[en.run_bt]="Running Backroute Trace..."
LANG[en.cleanup_after]="Clean Up after Installation"
# ===== Chinese =====
LANG[cn.err01]="错误：work_dir不包含'nodequality'！"
LANG[cn.err02]="错误：不支持的参数！"
LANG[cn.err03]="错误：指定的 work_dir 不存在，或不可读/不可写！"
LANG[cn.cleanup]="清理中，请稍后。"
LANG[cn.clean_fail]="出现了预料之外的情况，BenchOS目录的挂载未被清理干净，保险起见请重启后删除该目录。"
LANG[cn.ask_hq]="运行 HardwareQuality 测试？（回车默认 'y'，'f' 为快速模式，'v' 为深度模式）[y/f/v/n]："
LANG[cn.ask_iq]="运行 IPQuality 测试？（回车默认 'y'）[y/n]："
LANG[cn.ask_nq]="运行 NetQuality 测试？（回车默认 'y'，'l' 为低流量模式）[y/l/n]："
LANG[cn.ask_bt]="运行 回程路由追踪（Backroute Trace）测试？（回车默认 'y'）[y/n]："
LANG[cn.cleanup_before]="安装前清理"
LANG[cn.loadbench]="加载 BenchOs"
LANG[cn.basicinfo]="硬件信息"
LANG[cn.run_hq]="正在运行硬件质量测试..."
LANG[cn.run_iq]="正在运行 IP 质量测试..."
LANG[cn.run_nq]="正在运行网络质量测试..."
LANG[cn.run_bt]="正在运行回程路由追踪..."
LANG[cn.cleanup_after]="安装后清理"

function L(){
    local key="${lang}.${1}"
    echo "${LANG[$key]:-${LANG[en.$1]}}"
}


function start_ascii() {
    echo -e "\e[1;36m"
    cat <<'EOF'

███╗   ██╗ ██████╗ ██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██╗     ██╗████████╗██╗   ██╗
████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔═══██╗██║   ██║██╔══██╗██║     ██║╚══██╔══╝╚██╗ ██╔╝
██╔██╗ ██║██║   ██║██║  ██║█████╗  ██║   ██║██║   ██║███████║██║     ██║   ██║    ╚████╔╝ 
██║╚██╗██║██║   ██║██║  ██║██╔══╝  ██║▄▄ ██║██║   ██║██╔══██║██║     ██║   ██║     ╚██╔╝  
██║ ╚████║╚██████╔╝██████╔╝███████╗╚██████╔╝╚██████╔╝██║  ██║███████╗██║   ██║      ██║   
╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝   

EOF
    cat <<'EOF'
NB NodeQuality — locally retained VPS benchmark reports
Based on Lloyd@nodeseek.com / github.com/LloydAsp/NodeQuality (AGPL-3.0).
BenchOS uses chroot, NOT a security sandbox. Tests run as root, access host
resources and contact third-party services. Review code before running.
Reports may contain IP addresses and hardware/network identifiers.
Local reports are preserved; sharing requires explicit upload consent.
EOF
    echo -e "\033[0m"
}

function _red() {
    echo -e "\033[0;31m$1\033[0m"
}

function _yellow() {
    echo -e "\033[0;33m$1\033[0m"
}

function _blue() {
    echo -e "\033[0;36m$1\033[0m"
}

function _green() {
    echo -e "\033[0;32m$1\033[0m"
}

function _red_bold() {
    echo -e "\033[1;31m$1\033[0m"
}

function _yellow_bold() {
    echo -e "\033[1;33m$1\033[0m"
}

function _blue_bold() {
    echo -e "\033[1;36m$1\033[0m"
}

function _green_bold() {
    echo -e "\033[1;32m$1\033[0m"
}

function usage() {
    cat <<'EOF'
Usage: bash NodeQuality.sh [-4|-6] [-E] [-D existing-directory]
       [--upload-url https://your-host/api/v1/reports --consent-upload]
Default: retain local reports; never upload to the original NodeQuality API.
Upload shares potentially identifying reports with the configured server.
EOF
}

function get_opts(){
    while (( $# )); do
        case "$1" in
            -4|-6) opt_ipv="$1" ;;
            -E|-e) lang="en"; opt_lang="-E" ;;
            -D|-d)
                (( $# >= 2 )) || return 2
                [[ -d "$2" && -r "$2" && -w "$2" ]] || return 2
                work_base="$(cd -- "$2" && pwd -P)" || return
                shift ;;
            --upload-url)
                (( $# >= 2 )) || return 2
                upload_url="$2"; shift ;;
            --consent-upload) consent_upload=1 ;;
            -h|--help) usage; return 10 ;;
            *) echo "Unsupported argument: $1" >&2; return 2 ;;
        esac
        shift
    done
    if [[ -n "$upload_url" ]]; then
        [[ "$upload_url" =~ ^https://[^/?#@[:space:]]+(/[^[:space:]#]*)?$ ]] || {
            echo "Upload requires an HTTPS URL without credentials or fragments." >&2; return 2;
        }
        (( consent_upload == 1 )) || {
            echo "Sharing requires --consent-upload; reports can identify this server." >&2; return 2;
        }
    elif (( consent_upload )); then
        echo "--consent-upload requires --upload-url." >&2; return 2
    fi
}

function select_arch(){
    [[ "$(uname -s)" == Linux ]] || { echo "Linux required." >&2; return 1; }
    case "$(uname -m)" in
        x86_64)
            bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.2/BenchOs.tar.gz"
            bench_os_sha256="5f844e73941c3623175c5cdc16b01db34c155d0d1bd9b0cf71f3d72e8b1148e1"
            nexttrace_url="https://github.com/nxtrace/NTrace-core/releases/download/v1.7.5/nexttrace_linux_amd64"
            nexttrace_sha256="7d7fa3bdd967494d1c051766696dea753bc6f4a1d95c2016fdfa078cf1894ff6" ;;
        aarch64|arm64)
            bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.2/BenchOs-arm.tar.gz"
            bench_os_sha256="a4dd4e55b129157a02dab437b78e41b5797a7a79a0f0b7febdecab8eb2a312c7"
            nexttrace_url="https://github.com/nxtrace/NTrace-core/releases/download/v1.7.5/nexttrace_linux_arm64"
            nexttrace_sha256="820a736c60aca52683b5a4c7fa256d7a4248db37f28f2c16ff6daf76a8b0ee87" ;;
        *) echo "Unsupported architecture; only x86_64 and aarch64 are supported." >&2; return 1 ;;
    esac
}

function pre_init(){
    umask 077
    work_dir="$(mktemp -d "$work_base/.nodequality-$current_time-XXXXXX")" || return
    report_dir="$work_dir/reports"
    mkdir -m 700 -- "$report_dir"
}

function clear_mount(){
    local failed=0
    if (( mount_dev )); then
        umount -R "$work_dir/BenchOs/dev" && mount_dev=0 || failed=1
    fi
    if (( mount_sys )); then
        umount "$work_dir/BenchOs/sys" && mount_sys=0 || failed=1
    fi
    if (( mount_proc )); then
        umount "$work_dir/BenchOs/proc" && mount_proc=0 || failed=1
    fi
    return "$failed"
}

function fetch_file(){
    curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 600 --output "$2" "$1"
}

function load_bench_os(){
    fetch_file "$bench_os_url" "$work_dir/BenchOs.tar.gz" || return
    printf '%s  %s\n' "$bench_os_sha256" "$work_dir/BenchOs.tar.gz" | sha256sum -c - || return
    tar -xzf "$work_dir/BenchOs.tar.gz" -C "$work_dir" || return
    [[ -d "$work_dir/BenchOs" && ! -L "$work_dir/BenchOs" ]] || return 1
    mount -t proc /proc "$work_dir/BenchOs/proc" || return
    mount_proc=1
    mount --bind /sys "$work_dir/BenchOs/sys" || return
    mount_sys=1
    mount --rbind /dev "$work_dir/BenchOs/dev" || return
    mount_dev=1
    mount --make-rslave "$work_dir/BenchOs/dev" || return
    rm -f -- "$work_dir/BenchOs/etc/resolv.conf" || return
    cp -- /etc/resolv.conf "$work_dir/BenchOs/etc/resolv.conf"
}

function chroot_run(){
    env -u NQ_UPLOAD_KEY chroot "$work_dir/BenchOs" /bin/bash -c "$*"
}

function run_header(){
    printf 'NB NodeQuality %s\nUTC: %s\nOriginal: LloydAsp/NodeQuality @ %s\n' \
        "$tool_version" "$(date -u +%FT%TZ)" "$upstream_commit"
}

function detect_virt() {
    if [[ -f /run/systemd/container ]]; then
        cat /run/systemd/container
        return
    fi
    if [[ -f /.dockerenv ]]; then
        echo docker
        return
    fi
    if [[ -f /run/.containerenv ]]; then
        echo podman
        return
    fi
    if grep -qa 'lxc' /proc/1/cgroup 2>/dev/null; then
        echo lxc
        return
    fi
    if grep -qa 'hypervisor' /proc/cpuinfo 2>/dev/null; then
        echo kvm
        return
    fi
    echo none
}

############ 以下内容为HQ预处理部分 ############
function detect_testdev_type(){
    local dev="$1"
    dev="$(readlink -f "$dev" 2>/dev/null)"
    if [[ "$dev" == /dev/md* ]]; then
        local lvl
        lvl=$(
            awk -v md="$(basename "$dev")" '
                $1 == md {
                    for (i=1;i<=NF;i++)
                        if ($i ~ /^raid[0-9]+$/) {
                            print toupper($i)
                            exit
                        }
                }
            ' /proc/mdstat
        )
        [[ -n "$lvl" ]] && echo "$lvl" || echo "RAID"
        return
    fi
    if [[ "$dev" == /dev/mapper/* || "$dev" == /dev/dm-* ]]; then
        echo "LVM"
        return
    fi
    if lsblk -no TYPE "$dev" 2>/dev/null | grep -qE 'disk|part'; then
        echo "DISK"
        return
    fi
    echo ""
}

function get_testdev_members_from_diskinfo(){
    local dev="$1"
    local i
    for ((i=1; i<=diskinfo[raid_count]; i++)); do
        if [[ "${diskinfo[raid$i.name]}" == "$dev" ]]; then
            echo "${diskinfo[raid$i.devs]}"
            return
        fi
    done
}

function get_testdev_mount_from_diskinfo(){
    local dev="$1"
    local i
    for ((i=1; i<=diskinfo[raid_count]; i++)); do
        if [[ "${diskinfo[raid$i.name]}" == "$dev" ]]; then
            echo "${diskinfo[raid$i.mount]}"
            return
        fi
    done
}

function get_md_mount(){
    local md="$1"
    local mp=""
    mp="$(findmnt -n -o TARGET "/dev/$md" 2>/dev/null)"
    [[ -n "$mp" ]] && { echo "$mp"; return; }
    mp="$(
        lsblk -o NAME,PKNAME,TYPE,MOUNTPOINT -r 2>/dev/null \
        | awk -v md="$md" '$2==md && $4!="" {print $4}' \
        | sort -u | paste -sd "," -
    )"
    [[ -n "$mp" ]] && echo "$mp"
}

function pre_fetch_info(){
    local virt_type="$(detect_virt)"
    declare -gA osinfo
    osinfo[proc]=$(ps -e 2>/dev/null | wc -l | tr -d ' ')
    if command -v loginctl >/dev/null 2>&1; then
        tmpuc="$(loginctl list-users 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
        [[ "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        tmpuc="$(stat -f '%Su' /dev/console 2>/dev/null | wc -l | tr -d ' ')"
        [[ "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
    else
        tmpuc="$(who 2>/dev/null | wc -l | tr -d ' ')"
        [[ "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
    fi
    if [[ "${virt_type}" =~ ^(docker|podman|lxc|container)$ ]] && [[ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]]; then
        osinfo[svcr]=""
        osinfo[svct]=""
    elif command -v systemctl >/dev/null 2>&1; then
        osinfo[svcr]=$(systemctl list-units --type=service --state=running 2>/dev/null | grep '\.service' | wc -l | tr -d ' ')
        osinfo[svct]=$(systemctl list-unit-files --type=service 2>/dev/null | grep '\.service' | wc -l | tr -d ' ')
    elif command -v rc-service >/dev/null 2>&1; then
        osinfo[svcr]=$(rc-service -r 2>/dev/null | wc -l | tr -d ' ')
        osinfo[svct]=$(rc-service -l 2>/dev/null | wc -l | tr -d ' ')
    elif [[ "$(uname -s)" == "Darwin" ]] && command -v launchctl >/dev/null 2>&1; then
        osinfo[svcr]=$(launchctl list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        osinfo[svct]="${osinfo[svcr]}"
    fi
    declare -gA meminfo
    case "${virt_type}" in
        kvm)
            if lsmod 2>/dev/null | grep -q '^virtio_balloon'; then
                meminfo[balloon]=1
            else
                meminfo[balloon]=0
            fi
            if [[ -r /sys/kernel/mm/ksm/run ]] && [[ "$(cat /sys/kernel/mm/ksm/run)" == "1" ]]; then
                meminfo[ksm]=1
            else
                meminfo[ksm]=0
            fi
            ;;
        lxc)
            meminfo[neighbor]=$(ls /sys/devices/virtual/block 2>/dev/null | grep -c '^dm')
            ;;
    esac
    declare -gA diskinfo
    local ridx=0
    if [[ -r /proc/mdstat ]]; then
        while read -r line; do
            if [[ "$line" =~ ^(md[0-9]+)[[:space:]]*:[[:space:]]*active[[:space:]]+([a-z0-9]+)[[:space:]]+(.*)$ ]]; then
                ((ridx++))
                local rname="${BASH_REMATCH[1]}"
                local rlevel="${BASH_REMATCH[2]}"
                local rdevs="${BASH_REMATCH[3]}"
                rlevel="${rlevel^^}"
                rdevs="$(awk '{for(i=1;i<=NF;i++) if ($i ~ /\[[0-9]+\]/) printf "%s ", $i}' <<<"$rdevs")"
                rdevs="${rdevs% }"
                diskinfo["raid$ridx.name"]="$rname"
                diskinfo["raid$ridx.level"]="$rlevel"
                diskinfo["raid$ridx.devs"]="$rdevs"
                diskinfo["raid$ridx.mount"]="$(get_md_mount "$rname")"
            fi
        done < /proc/mdstat
    fi
    diskinfo[raid_count]="$ridx"
    diskinfo[testdir]="${work_dir%/*}"
    diskinfo[testdev]=$(df --output=source "$work_dir" | awk 'NR==2')
    diskinfo[testdev_type]=$(detect_testdev_type "${diskinfo[testdev]}")
    diskinfo[testdev]="${diskinfo[testdev]#/dev/}"
    if [[ "${diskinfo[testdev_type]}" == RAID* ]]; then
        diskinfo[testdev_members]=$(get_testdev_members_from_diskinfo "${diskinfo[testdev]}")
        diskinfo[testdev_mount]=$(get_testdev_mount_from_diskinfo "${diskinfo[testdev]}")
    fi
}
############ 以上内容为HQ预处理部分 ############

function run_HardwareQuality(){
    local params=""
    [[ "$run_hardware_quality_test" =~ ^[Ff]$ ]] && params=" -F"
    [[ "$run_hardware_quality_test" =~ ^[Vv]$ ]] && params=" -V"
    pre_fetch_info # HQ预处理
    payload=$(declare -p osinfo meminfo diskinfo) # HQ预处理
    fetch_file https://Hardware.Check.Place "$work_dir/hardware.sh" || return
    cat "$work_dir/hardware.sh" | chroot_run "env NQENV=$(printf '%q' "$payload") bash -s -- $opt_lang $params -y -o /result/$hardware_quality_json_filename" # HQ预处理
    # 原始语句为：chroot_run bash <(curl -Ls https://Hardware.Check.Place) $opt_lang -y -o /result/$hardware_quality_json_filename
}


function run_ip_quality(){
    fetch_file https://IP.Check.Place "$work_dir/ip.sh" || return
    chroot_run "bash -s -- $opt_ipv $opt_lang -y -o /result/$ip_quality_json_filename" < "$work_dir/ip.sh"
}

function load_nexttrace(){
    fetch_file "$nexttrace_url" "$work_dir/nexttrace" || return
    [[ -s "$work_dir/nexttrace" ]] || return 1
    printf '%s  %s\n' "$nexttrace_sha256" "$work_dir/nexttrace" | sha256sum -c - || return
    mkdir -p -- "$work_dir/BenchOs/usr/local/bin" || return
    local staged
    staged="$(mktemp "$work_dir/BenchOs/usr/local/bin/.nexttrace-XXXXXX")" || return
    cp -- "$work_dir/nexttrace" "$staged" || return
    chmod 755 -- "$staged" || return
    mv -fT -- "$staged" "$work_dir/BenchOs/usr/local/bin/nexttrace"
}

function require_nexttrace(){
    # Do not let the current NetQuality fallback execute a plaintext installer.
    chroot_run 'command -v nexttrace >/dev/null 2>&1' || {
        echo "NextTrace is absent in BenchOS; refusing NetQuality's unverified installer. Supply an audited BenchOS with architecture-correct NextTrace before running network/route tests." >&2
        return 1
    }
}

function run_net_quality(){
    require_nexttrace || return
    local params=""
    [[ "$run_net_quality_test" =~ ^[Ll]$ ]] && params=" -L"
    fetch_file https://Net.Check.Place "$work_dir/net.sh" || return
    chroot_run "bash -s -- $opt_ipv $opt_lang $params -y -o /result/$net_quality_json_filename" < "$work_dir/net.sh"
}

function run_net_trace(){
    require_nexttrace || return
    fetch_file https://Net.Check.Place "$work_dir/trace.sh" || return
    chroot_run "bash -s -- $opt_ipv $opt_lang -R -n -S 123 -o /result/$backroute_trace_json_filename" < "$work_dir/trace.sh"
}

function preserve_result(){
    [[ -n "$work_dir" && -d "$work_dir/BenchOs/result" ]] || return 0
    cp -a -- "$work_dir/BenchOs/result/." "$report_dir/"
}

function upload_result(){
    [[ -n "$upload_url" ]] || return 0
    (( consent_upload == 1 )) || return 2
    [[ -n "${NQ_UPLOAD_KEY:-}" ]] || { echo "NQ_UPLOAD_KEY is required for sharing." >&2; return 2; }
    printf 'Sharing RAW reports from %s (IP/hardware/network identifiers may be included; no automatic redaction).\n' "$report_dir" >&2
    local review_file review_name review_suffix
    for review_name in header_info hardware_quality ip_quality net_quality backroute_trace; do
        for review_suffix in log json; do
            review_file="$report_dir/$review_name.$review_suffix"
            [[ ! -f "$review_file" ]] || printf '  %s\n' "${review_file##*/}" >&2
        done
    done
    if [[ -t 0 ]]; then
        local confirmation
        read -r -p 'Inspect these local files first. Type SHARE to upload, anything else cancels: ' confirmation || return 1
        [[ "$confirmation" == SHARE ]] || { echo 'Sharing cancelled; local reports retained.' >&2; return 0; }
    fi
    command -v python3 >/dev/null || { echo "Python3 is required only for optional sharing." >&2; return 1; }
    python3 - "$report_dir" <<'PY'
import datetime, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
names = ('header_info', 'hardware_quality', 'ip_quality', 'net_quality', 'backroute_trace')
sections = []
for name in names:
    for suffix in ('.log', '.json'):
        path = root / (name + suffix)
        if path.is_file():
            content = path.read_text(encoding='utf-8', errors='replace')
            if len(content) > 262144:
                raise SystemExit('A report section exceeds 262144 characters; local reports are retained.')
            sections.append({'title': path.name, 'content': content})
payload = json.dumps({'schema_version': 1, 'title': 'NB NodeQuality', 'sections': sections, 'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'tool_version': '0.1.0-dev', 'upstream_commit': 'a92fca6c0067df29ddd03fdc2fee6f3000f64545'}, ensure_ascii=False).encode()
if len(payload) > 1024 * 1024:
    raise SystemExit('Report exceeds 1 MiB upload limit; local reports are retained.')
(root / 'share-payload.json').write_bytes(payload)
PY
    local status=$?
    (( status == 0 )) || return "$status"
    # Keep the key out of process arguments and reject header injection.
    [[ "$NQ_UPLOAD_KEY" != *$'\n'* && "$NQ_UPLOAD_KEY" != *$'\r'* ]] || return 2
    printf 'Authorization: Bearer %s\n' "$NQ_UPLOAD_KEY" > "$report_dir/.upload-header" || return
    # No redirects: never forward private report data to a different endpoint.
    curl --fail --show-error --silent --proto '=https' --connect-timeout 20 \
        --max-time 120 --header "@$report_dir/.upload-header" \
        --header 'Content-Type: application/json' --data-binary "@$report_dir/share-payload.json" \
        --output "$report_dir/share-response.json" "$upload_url"
    status=$?
    rm -f -- "$report_dir/.upload-header"
    (( status == 0 )) || return "$status"
    python3 - "$report_dir/share-response.json" <<'PY'
import json, sys
from urllib.parse import urlsplit
response = json.load(open(sys.argv[1]))
url = response.get('url', '')
if urlsplit(url).scheme != 'https' or any(ord(c) < 32 or ord(c) == 127 for c in url):
    raise SystemExit('Server did not return a safe HTTPS share URL. Inspect private response locally.')
print('Share URL:', url)
print('Deletion token and expiry are saved in the private local share-response.json.')
PY
}

function post_check_mount(){
    # mountinfo encodes whitespace/backslashes; decode before comparing exact paths.
    local id parent device root target rest decoded
    while read -r id parent device root target rest; do
        printf -v decoded '%b' "$target"
        if [[ "$decoded" == "$work_dir" || "$decoded" == "$work_dir/"* ]]; then
            echo "Mount remains at $decoded; refusing deletion." >&2
            return 1
        fi
    done < /proc/self/mountinfo
}

function post_cleanup(){
    [[ -n "$work_dir" ]] || return 0
    rm -f -- "$report_dir/.upload-header"
    # Never delete a rootfs with uncertain mount state or an unsaved report.
    preserve_result || { echo "Report copy failed; retained $work_dir" >&2; return 1; }
    clear_mount || { echo "Unmount failed; retained $work_dir for recovery." >&2; return 1; }
    post_check_mount || return
    rm -rf -- "$work_dir/BenchOs" || return
    rm -f -- "$work_dir/BenchOs.tar.gz"
    printf 'Local reports retained: %s\n' "$report_dir"
}

function sig_cleanup(){
    local status="$1"
    trap - EXIT INT TERM HUP
    post_cleanup || { (( status != 0 )) || status=1; }
    exit "$status"
}

function ask_question(){
    local yellow='\033[1;33m'  # Set yellow color
    local reset='\033[0m'      # Reset to default color

    echo -en "${yellow}$(L ask_hq)${reset}"
    read -r run_hardware_quality_test || return 1
    run_hardware_quality_test=${run_hardware_quality_test:-y}

    echo -en "${yellow}$(L ask_iq)${reset}"
    read -r run_ip_quality_test || return 1
    run_ip_quality_test=${run_ip_quality_test:-y}

    echo -en "${yellow}$(L ask_nq)${reset}"
    read -r run_net_quality_test || return 1
    run_net_quality_test=${run_net_quality_test:-y}

    echo -en "${yellow}$(L ask_bt)${reset}"
    read -r run_net_trace_test || return 1
    run_net_trace_test=${run_net_trace_test:-y}
}

function main(){
    set -o pipefail
    select_arch || return
    (( EUID == 0 )) || { echo "Root is required for BenchOS mounts/chroot." >&2; return 1; }
    local dependency
    for dependency in curl sha256sum tar mount umount chroot mktemp cp chmod mv env; do
        command -v "$dependency" >/dev/null || { echo "Missing: $dependency" >&2; return 1; }
    done
    trap 'sig_cleanup $?' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    start_ascii

    ask_question || return

    _green_bold "$(L cleanup_before)"
    pre_init || return
    _green_bold "$(L loadbench)"
    load_bench_os || return
    if [[ "$run_net_quality_test" =~ ^[YyLl]$ || "$run_net_trace_test" =~ ^[Yy]$ ]]; then
        load_nexttrace || return
    fi

    _green_bold "$(L basicinfo)"

    result_directory="$work_dir/BenchOs/result"
    mkdir -p -- "$result_directory" || return
    run_header > "$result_directory/$header_info_filename" || return

    if [[ "$run_hardware_quality_test" =~ ^[YyFfVv]$ ]]; then
        _green_bold "$(L run_hq)"
        run_HardwareQuality | tee "$result_directory/$hardware_quality_filename" || return
    fi

    if [[ "$run_ip_quality_test" =~ ^[Yy]$ ]]; then
        _green_bold "$(L run_iq)"
        run_ip_quality | tee "$result_directory/$ip_quality_filename" || return
    fi

    if [[ "$run_net_quality_test" =~ ^[YyLl]$ ]]; then
        _green_bold "$(L run_nq)"
        run_net_quality | tee "$result_directory/$net_quality_filename" || return
    fi

    if [[ "$run_net_trace_test" =~ ^[Yy]$ ]]; then
        _green_bold "$(L run_bt)"
        run_net_trace | tee "$result_directory/$backroute_trace_filename" || return
    fi

    preserve_result || return
    upload_result || return
    _green_bold "$(L cleanup_after)"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    get_opts "$@"
    status=$?
    (( status != 10 )) || exit 0
    (( status == 0 )) || exit "$status"
    main
fi
