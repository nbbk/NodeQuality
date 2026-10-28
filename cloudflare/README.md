# Cloudflare Workers + D1 报告分享服务

与 `../service/` 容器版使用同一 API、中文移动端样式和隐私约定。**这是代码与部署包，不是已经上线的服务。没有创建 Cloudflare 资源、修改 DNS、设置线上秘密或执行远程部署。** 域名 DNS 托管在 CF 不代表 Workers/D1 已开通。运行成本及配额取决于你的账号，请部署前核对 Cloudflare 当前方案。

## 架构与安全边界

- Worker 负责 JSON 上传、无脚本 HTML 分享页、删除；D1 保存报告及 SHA-256 删除令牌摘要。24 随机字节分享 ID，32 随机字节删除令牌。
- 上传必须 `Authorization: Bearer <REPORT_UPLOAD_KEY>`，密钥至少 32 字符；配置不完整时关闭业务接口。密钥绝不放在浏览器、仓库或公开 HTML。秘密由部署者自行生成/保管。
- 不存在公开报告目录。分享 URL 是可转发的阅读凭据，不是身份验证；任何得到链接的人都能读取。不要上传密码、私钥、个人信息。**服务不会匿名化上传内容**：原始日志不自动脱敏，上传前必须自行审阅和脱敏。
- 所有标题/日志作为转义纯文本显示；剥除 ANSI、控制及双向文本控制符。无第三方 JS/CDN/追踪。no-store、noindex、CSP、无 referrer；这些不阻止收件人复制报告。
- 默认请求体 1 MiB（Cloudflare版 MAX_UPLOAD_BYTES 仅允许1024–1048576，以适配D1行大小限制），最多 32 节、每节 262144 Unicode 字符、标题160/节标题100字符。全站成功上传滚动一小时最多30份，最多10000未过期报告；D1 单条条件写入 + 触发器防止并发绕过配额。不是抗 DDoS/WAF；无效请求和读取仍可能消耗平台资源，按需由账号所有者配置预算、告警及 CF 边缘限制。
- 默认7天过期，读取即时拒绝过期报告；每15分钟 Cron 清理，上传时也清理。可配置1–365天。删除后备份/Cloudflare D1 Time Travel 可能仍保留历史，不能承诺立即物理擦除，需遵循账号备份政策。
- 不记录请求正文、令牌或报告内容，Wrangler Observability 默认关闭。CF 自身仍处理请求及托管数据，访问日志政策由账号控制。

## 本地安装与验证（不会部署）

需要当前 Wrangler 支持的 Node.js（建议22或24 LTS）、npm、Python3（仅构建源码下载包）。

```sh
cd cloudflare
npm ci
npm run check
npm test                   # 合成数据，真实本地 workerd + D1 模拟；无需账号
npm run build              # 生成 public/source.tar.gz：部署源码许可证下载
npx wrangler d1 migrations apply nodequality-reports --local
```

本地运行时自行创建被 git 忽略的 `.dev.vars`，只填本地测试秘密：

```text
REPORT_UPLOAD_KEY="replace-with-at-least-32-random-characters"
```

`npm run dev` 仅启动本地 Worker。`PUBLIC_BASE_URL` 只决定响应分享 URL；本地测试返回的 `https://reports.example.com/r/…` 应将 origin 换为本地终端显示地址访问，不要上传实际主机日志。自动测试不需要此文件，注入的是明确的合成测试密钥。D1 本地状态在 `.wrangler/`，不要把它作为生产备份上传。

## 推荐：连接 GitHub 自动部署

快速初始化：在仓库根目录运行 `bash cloudflare/setup.sh`，逐步确认安装、账号登录、D1、秘密和发布；`--dry-run` 只看计划。GitHub App授权仍需本人在控制台完成。

已提供 Cloudflare **Workers Builds 原生 GitHub 集成**配置，根目录 `cloudflare/`，构建 `npm ci && npm run build:ci`，部署 `npm run deploy:ci`。首次仍需本人授权GitHub App、创建D1、填绑定ID并设置运行时秘密。详见 [GitHub 自动部署完整步骤](GITHUB_DEPLOY.md)。这不是GitHub Actions Token方案，也没有替你连接或上线。

## 手动生产部署（仅由账号所有者在明确确认后执行）

**以下命令会修改真实云资源，不属于本包已执行操作。** 先审阅源码、账号计费和域名，并准备回滚/备份。不要在含其他项目配置的目录执行。

1. `npm ci`，随后 `npx wrangler login` 授权你自己的账号。
2. `npx wrangler d1 create nodequality-reports` 创建 D1，将输出的真实 `database_id` 写入 `wrangler.jsonc`，替换全零占位值。不要复用未知数据库。
3. 修改 `PUBLIC_BASE_URL` 为专属 HTTPS origin（例如 `https://reports.your-domain.example`；不得带路径、账号、查询串）。按需要修改保留期/配额。源码中不使用请求 Host 推导分享域名。
4. 配置域名：使用 Workers Custom Domain，并确认该主机名没有现有业务冲突。可在 Wrangler 配置增加 `"routes": [{"pattern":"reports.your-domain.example","custom_domain":true}]`。你也可先使用自己的 `workers.dev` 地址并相应设置 `PUBLIC_BASE_URL`。若只要自定义域名，可设 `workers_dev:false`；这会禁用 workers.dev 入口。不要凭 DNS 托管状态假设域名已绑定。
5. `npx wrangler d1 migrations apply nodequality-reports --remote` 应用远程迁移（会写入生产库）。
6. `npm run build` 然后 `npx wrangler deploy` 发布。此时没有上传秘密，业务接口安全返回503；仅静态 CSS/源码可读取。`npx wrangler secret put REPORT_UPLOAD_KEY` 通过交互输入安全生成的32字符以上密钥（这条命令可能立即产生/部署新版本）。不要用命令行参数、提交文件或聊天传输密钥。部署后再次确认配置和 Cron。
7. 用合成 fixture 做 `POST /api/v1/reports` → 手机打开返回 URL → `DELETE /api/v1/reports/{id}` → 确认404，再确认 `/healthz` 和 `/source.tar.gz`。**实际 Cloudflare 账号、DNS、TLS、远程 D1、Cron 和生产运行尚未验证。**

`npm run deploy` / `npm run deploy:ci` 是明确的线上发布命令，绝不用于测试。源码包必须每次修改后重新生成；它不包含 `.dev.vars`、运行数据库、node_modules 或任何部署秘密。保留 AGPL 与上游署名，修改版向网络使用者提供对应源码；页面底部 `/source.tar.gz` 提供本 Cloudflare 服务构建源码、锁文件、迁移及测试。不要关闭此链接而不提供等价源码途径。

## API（与容器版一致）

`POST /api/v1/reports`，`Content-Type: application/json`，上传 Bearer 密钥，内容示例见 `tests/fixture.json`：

```json
{"schema_version":1,"title":"我的节点报告","sections":[{"title":"硬件","content":"CPU: 合成测试"}],"generated_at":"2026-10-28T00:00:00Z","tool_version":"test","upstream_commit":"fixture"}
```

后三个字段可选，各字符串不超过100字符。未知字段、非字符串内容、空标题均拒绝。201 响应：`{id,url,delete_token,expires_at}`。请立即把删除令牌保存到私有文件，服务不会再次展示。

- `GET /r/{id}`：阅读报告；缺失/过期404。
- `DELETE /api/v1/reports/{id}`：`Authorization: Bearer <delete_token>`；成功204、令牌错误401、缺失/过期404。无需上传密钥，删除令牌只对应这一份报告。
- 400无效结构，401缺上传授权，413过大，415格式错误，429上传频率限制，503容量/配置/数据库问题。
- 没有列表端点，没有公共 JSON 下载端点，没有匿名上传 UI。分享就是复制报告地址；打印/另存PDF可用浏览器原生功能。

## 已验证与仍需验证

运行 `npm test` 检查本地 Workers/D1 真实运行、JSON约束、授权、XSS转义、创建阅读删除、过期及清理、35并发上传时30成功/5限流。`npm run check` 检查JS语法。源码只包含合成 fixture。详见仓库交付说明中的实际运行结果；生产部署、Cloudflare账号资源、域名和浏览器视觉效果需部署者最终验收。

## 官方部署资料

- [Wrangler 配置、D1/Assets/路由绑定](https://developers.cloudflare.com/workers/wrangler/configuration/)
- [D1 创建与绑定](https://developers.cloudflare.com/d1/get-started/)
- [D1 SQL 迁移](https://developers.cloudflare.com/d1/reference/migrations/)
- [Secrets 与本地 .dev.vars](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)

上游：[LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality)，AGPL-3.0-or-later。详见根目录 `NOTICE.md` / `LICENSE`。

### 本次沙箱验证记录（2026-10-28）

- `npm run check`、11组 `npm test`：通过（真实本地 workerd、D1及Assets模拟；包括源码下载）。
- `wrangler d1 migrations apply nodequality-reports --local`：成功执行迁移。
- `wrangler deploy --dry-run`：通过配置/绑定/静态资产及打包检查，**没有发布**。
- `wrangler dev --local` 的交互HTTP启动被沙箱系统接口限制阻止：`uv_interface_addresses ... error 1`；不是云部署失败。上述Miniflare测试独立通过，不能替代生产及手机浏览器视觉验收。
