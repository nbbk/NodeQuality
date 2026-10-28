# 自托管报告服务

这是为维护自己的 NodeQuality 分支新增的原始实现，不是上游网站的源码。基于 [LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality)，保留 AGPL-3.0 许可证和原项目署名。服务代码及修改应依许可证向远程用户提供对应源码；本站 `/source.tar.gz` 提供部署的服务源码（不含密钥/数据）。如另有构建或修改步骤，请同步维护源码包。

## 运行前须知

- **默认不部署、不上传**。CLI 当前上传的是原始日志，不自动脱敏；交互流程列出文件并要求明确确认，非交互模式也须显式同意上传原始数据。上传前请自行查看和脱敏文件：姓名、IP、域名、主机名、路由、运营商、地理位置、凭据等都可能暴露。服务端也不提供匿名化保证。
- 报告链接为 192-bit 随机标识，**持有链接的任何人均能阅读**；无登录权限控制。链接不可公开列举，robots/noindex 只是搜索引擎提示，不是安全边界。
- 上传需要独立的 32+ 字符密钥。删除令牌只在创建响应返回一次，服务仅存 SHA-256；保存本地 `share-response.json`，不要分享或将令牌放入 URL。
- 不执行报告、不解压文件、不渲染 Markdown/HTML；纯文本转义并去除 ANSI 和方向控制字符。不加载 CDN、分析追踪或外部字体。

## 本机开发（不运行任何 VPS 测试）

```bash
cd service
python3 -m unittest discover -s tests -v
export PUBLIC_BASE_URL=http://127.0.0.1:8080 ALLOW_HTTP_LOCALHOST=1
export REPORT_UPLOAD_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
export REPORT_DB=/tmp/nodequality-dev.sqlite3
python3 app.py
```

仅 localhost 开发允许 HTTP。内置 WSGI 服务不可直接用于公网。

## 一条命令引导配置与部署

前提：安装 **Python 3、Docker Engine 和 Docker Compose 插件**，准备自己的 HTTPS 域名及 TLS 反向代理。工具不安装 Docker、不更改 DNS、证书、防火墙，也不自动上传测试数据。

在仓库根目录运行：

```bash
bash setup.sh docker
# 或直接：bash service/setup.sh --url https://reports.example.com
```

只需提供 HTTPS 域名；自动生成随机上传密钥，私密写入 `service/.env` 和 `service/client.env`（0600，忽略 Git 与 Docker build context）。默认仅监听 `127.0.0.1:8080`，可加 `--port 18080`。首次启动要求输入 `START`；非交互部署必须明确传 `--yes`。只生成配置不启动用 `--configure-only`。重复运行复用现有密钥与数据，不覆盖不同的域名/端口/客户端配置。已有手写 `.env` 如含不支持的引号或密钥格式会拒绝自动处理，请手动检查而不是删除数据。

完成后在仓库根目录使用：

```bash
bash setup.sh run
# 或传私密配置路径：bash setup.sh run --config service/client.env
```

根启动器只解析允许的配置字段，不执行文件内容；客户端配置仅供自己保管，异机使用需自行安全复制。上传仍需明确同意，原始日志不自动脱敏。脚本不会在终端打印密钥，也不会把密钥放入 Docker 命令行参数。`--yes` 仅授权启动容器，不代表 DNS/TLS/公网可达性已经验证。

## Docker 生产准备

准备域名、服务器、TLS 反向代理后才执行部署。Docker 环境尚未在本交付环境实际构建/部署验证。

```bash
cd service
umask 077
# .env 不得提交；PUBLIC_BASE_URL 必须是你拥有的 HTTPS 源站，不含路径
printf 'PUBLIC_BASE_URL=https://reports.example.com\nREPORT_UPLOAD_KEY=%s\n' \
  "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" > .env
docker compose up -d --build
curl -f http://127.0.0.1:8080/healthz
```

容器为非 root，只读文件系统，持久化 SQLite volume，端口仅绑定主机 localhost。反代需终止 TLS、限制请求体和速率、设置读写超时；关闭报告路径/凭据访问日志，不信任任意 `X-Forwarded-For`。服务不记录访问 URL，不信任代理头。可用 Nginx 配置片段：

```nginx
# 放入已配置证书的 HTTPS server 内，域名和证书路径由部署者配置。
client_max_body_size 1m;
client_body_timeout 15s;
location / {
    access_log off;
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_read_timeout 35s;
    proxy_send_timeout 15s;
}
```

反代另行配置针对所有请求的 `limit_req`/连接限制和防火墙。应用级上传限额是**全服务全局**窗口，不按 IP，防止伪造代理头绕过，适合个人工具箱而不是开放匿名上传服务。未授权请求、GET/DELETE 的抗滥用依赖反代。上传密钥应通过秘密管理设置，定期轮换；不能放进公开仓库或网页。

## 配置

| 变量 | 默认 | 说明 |
|---|---|---|
| `LOCAL_PORT` | `8080` | Compose 主机 localhost 端口；引导脚本接受1024–65535 |
| `PUBLIC_BASE_URL` | 必填 | HTTPS origin，不接受路径、用户信息、查询/片段 |
| `REPORT_UPLOAD_KEY` | 必填 | 至少 32 字符，建议随机 256-bit |
| `REPORT_DB` | `/data/reports.sqlite3` | SQLite 路径；目录须可写 |
| `RETENTION_DAYS` | `7` | 1–365 天，所有新报告适用 |
| `MAX_UPLOAD_BYTES` | `1048576` | JSON 请求字节上限，范围 1KiB–10MiB |
| `MAX_REPORTS` | `10000` | 最大未过期报告数；满时返回 503 |
| `UPLOADS_PER_HOUR` | `30` | 全局滚动 1 小时已成功上传上限；429 |
| `ALLOW_HTTP_LOCALHOST` | 未设置 | 仅开发设 `1`，只允许 localhost/127.0.0.1 |

报告到期立即不可读，运行中的每个服务进程每 60 秒清理一次，并在报告请求时清理。停机期间不执行清理，重启恢复。SQLite 使用 `secure_delete`；这不保证 SSD、卷快照、宿主日志、复制或备份的安全擦除，管理员须单独限制备份保留期。报告可能包含敏感信息；默认不建立备份。实际存储上界随 `MAX_REPORTS × MAX_UPLOAD_BYTES` 增长，部署时还应设置磁盘告警/配额。

## API v1（无 Cookie / 无 CORS）

`POST /api/v1/reports`，`Content-Type: application/json`，`Authorization: Bearer <REPORT_UPLOAD_KEY>`：

```json
{"schema_version":1,"title":"我的节点测试","sections":[{"title":"hardware_quality.log","content":"CPU: synthetic fixture"}]}
```

严格字段校验：title 1–160 字符；sections 1–32 条；每条恰好 `title`（1–100字符）、`content`（最多262144字符）。可选 `generated_at`、`tool_version`、`upstream_commit` 各为最多100字符字符串，仅作为不可信元数据存储。未知字段拒绝。上传总 JSON 不超过请求字节上限；不支持压缩或 chunked 直传。

201 响应：

```json
{"id":"<32字符随机ID>","url":"https://reports.example.com/r/<id>","delete_token":"<仅返回一次的秘密>","expires_at":"2026-11-04T00:00:00Z"}
```

`GET /r/<id>` 返回响应式中文 HTML 报告。删除：`DELETE /api/v1/reports/<id>`，`Authorization: Bearer <delete_token>`；成功204，再次删除/已过期404。不要将删除命令中的实际令牌保留到 shell history。错误用 JSON，400校验失败、401未授权、413过大、415类型不符、429限速、503容量或存储不可用。

## 验证与边界

`python3 -m unittest discover -s service/tests -v`（仓库根目录）覆盖校验、XSS/ANSI、鉴权、散列删除令牌、过期、跨 worker 限速、容量、无目录和源码下载。`node service/tests/browser.cjs` 使用本地 Chromium + Playwright，仅合成数据，在 390×844 和 1440×1000 视口验证导航、刷新/前进后退、XSS、无横向溢出；生成截图到临时路径。不是渗透测试或生产负载测试。

### 仅合成数据的本地 HTTP 验证

```bash
# 自行启动临时 localhost 服务，上传/读取/删除内置合成 fixture 后立即关闭
python3 service/tests/smoke.py
```

本地服务已按上文启动时，可以另开终端（复制同一个测试密钥到环境）执行：

```bash
cd service
umask 077
header_file=$(mktemp)
printf 'Authorization: Bearer %s\n' "$REPORT_UPLOAD_KEY" > "$header_file"
curl --fail-with-body --silent --show-error --max-time 20 \
  -H @"$header_file" -H 'Content-Type: application/json' \
  --data-binary @api-contract.json \
  http://127.0.0.1:8080/api/v1/reports > /tmp/nq-synthetic-response.json
rm -f "$header_file"
# 该 JSON 含删除秘密，不应粘贴到聊天或公开日志。
```

当前交付验证记录：Python 10 项单元测试与 localhost HTTP 创建/读取/删除烟雾测试通过；Docker 构建未执行（无 Docker）；Chromium 视觉测试被执行环境 socket 权限与提升包装器错误阻断，因此手机/桌面视觉效果尚未实际截图验证。浏览器测试脚本已提供，部署前请在具备 Chromium 的环境运行。

生产依赖固定 Gunicorn 26.2.0（[PyPI 项目发布信息](https://pypi.org/project/gunicorn/)，交付时核对）；依赖安装与 Docker 构建仍需部署环境验证。

引导部署测试：`python3 -m unittest discover -s service/tests -v` 额外覆盖7项配置/权限/幂等/符号链接/模拟Docker/确认门槛测试，不执行真实Docker部署。
