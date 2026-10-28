#!/usr/bin/env bash
# End-to-end CLI serialization -> in-process WSGI -> CLI response parsing.
# Synthetic data only; curl is replaced, so no HTTP request is sent.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./NodeQuality.sh
root="$PWD"
base="$(mktemp -d)"
trap 'rm -rf -- "$base"' EXIT
umask 077
report_dir="$base/reports"
mkdir "$report_dir"
printf 'Synthetic CPU: 4 cores\n' > "$report_dir/hardware_quality.log"
printf 'IP: 192.0.2.1 (documentation fixture)\n' > "$report_dir/ip_quality.log"
printf '{"test": true}\n' > "$report_dir/ip_quality.json"
upload_url='https://reports.example.test/api/v1/reports'
consent_upload=1
NQ_UPLOAD_KEY='synthetic-fixture-key-12345678901234567890'
export NQ_UPLOAD_KEY
curl() {
    local payload='' output='' previous='' arg
    for arg in "$@"; do
        [[ "$previous" != --data-binary ]] || payload="${arg#@}"
        [[ "$previous" != --output ]] || output="$arg"
        previous="$arg"
    done
    python3 - "$root" "$base" "$payload" "$output" <<'PY'
import io,json,os,pathlib,sys
root,base,payload,output=sys.argv[1:]
sys.path.insert(0,root+'/service')
from app import ReportApp
app=ReportApp(db=base+'/fixture.db',base_url='https://reports.example.test',upload_key=os.environ['NQ_UPLOAD_KEY'])
body=pathlib.Path(payload).read_bytes()
env={'REQUEST_METHOD':'POST','PATH_INFO':'/api/v1/reports','CONTENT_TYPE':'application/json','CONTENT_LENGTH':str(len(body)),'wsgi.input':io.BytesIO(body),'HTTP_AUTHORIZATION':'Bearer '+os.environ['NQ_UPLOAD_KEY']}
state={}
def start(status,headers): state['status']=int(status[:3])
response=b''.join(app(env,start))
assert state['status']==201,(state,response)
pathlib.Path(output).write_bytes(response)
r=json.loads(response)
env.update(REQUEST_METHOD='GET',PATH_INFO='/r/'+r['id'],CONTENT_LENGTH='0')
html=b''.join(app(env,start))
assert state['status']==200
assert b'192.0.2.1' in html and b'Synthetic CPU' in html
assert r['delete_token'].encode() not in html
PY
}
output="$(upload_result)"
[[ "$output" == *'https://reports.example.test/r/'* ]]
[[ $(stat -c %a "$report_dir/share-response.json") == 600 ]]
[[ ! -e "$report_dir/.upload-header" ]]
printf 'CLI/service contract passed (synthetic in-process data; no network).\n'
