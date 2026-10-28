# NB NodeQuality 双部署包指南

本包是**代码和部署准备包**，源代码维护在 `nbbk/NodeQuality`；未修改 Cloudflare DNS，未创建 Worker/D1，未启动生产容器，也没有上传真实报告。维护品牌为 `NB NodeQuality`，原项目署名和 AGPL 保留。

## 简单开始

克隆仓库后运行 `bash setup.sh`，按提示选择 Docker / Cloudflare / 运行测试。Docker 和 Cloudflare 的专用向导在必要的外部操作前请求确认；不会默默安装系统软件、修改防火墙或 DNS。自动化不省略账号授权、域名和费用相关确认。

## 两种部署方式怎么选

| 方式 | 目录 | 需要准备 | 数据 |
|---|---|---|---|
| Cloudflare Workers + D1 | `cloudflare/` | Cloudflare 账号、Worker/D1 权限、自有域名/路由、上传密钥 | 自己账号的 D1 |
| Docker + HTTPS 反向代理 | `service/` | 运行 Docker 的服务器、TLS 反向代理、自有域名、上传密钥 | 持久化 SQLite volume |

**域名托管在 CF 不等于服务已经部署。** 两版实现相同 API，可二选一部署；如果同时部署，请使用不同子域名并分别管理数据、密钥和删除令牌。它们不会自动同步报告。

### A. Cloudflare

完整命令以 [`cloudflare/README.md`](cloudflare/README.md) 为准。流程：安装锁定依赖 → 创建自己的 D1 → 将真实数据库 ID 写入配置 → 应用 migrations → 设置 `REPORT_UPLOAD_KEY` secret → 设置 HTTPS `PUBLIC_BASE_URL` 和自有路由 → 构建源码包 → 发布 Worker → 用合成数据检查上传/读取/删除/到期。

配置中的 `reports.example.com` 和全零 D1 ID 都是占位值，不能原样当成完成部署。切勿把上传密钥写进 `wrangler.jsonc` 或提交仓库。

### B. Docker

完整命令见 [`service/README.md`](service/README.md)。流程：设置权限受限的 `.env` → 构建镜像 → `docker compose up -d` → TLS 反代到 `127.0.0.1:8080` → 合成数据验证。容器服务仅绑定主机 loopback，不能以为 Cloudflare DNS 代理自动提供源站安全/TLS 配置。

本交付环境没有 Docker，**镜像构建和 Compose 启动没有实际验证**。正式运行前应审阅基础镜像、依赖、磁盘配额、备份保留策略、访问日志和反代限速。

## CLI 与分享

`NodeQuality.sh` 是单文件入口，不依赖同目录辅助脚本，便于工具箱缓存运行。详见根 [`README.md`](README.md)。默认保留本地文件；只有指定自己的 HTTPS 地址和 `--consent-upload` 才会尝试分享。交互运行还要求输入 `SHARE`；非交互运行该参数明确授权原始日志上传。**不做自动脱敏。** 分享链接持有人可查看内容；删除令牌保存在本地私有 `share-response.json`，不可一起分享。

报告网页以可读纯文本呈现结果，可手动选择复制；不是上游商业/在线网站的源码复制，也不承诺其自动截图或图床功能。

## 工具箱接入

工具箱仓库：[nbbk/vps-toolkit](https://github.com/nbbk/vps-toolkit)。保留菜单 **33** 和 ID **test-nodequality**，使用维护版的真实固定提交 URL + SHA-256，而不是动态 main 或原版上传入口。更新方式见 [`integration/README.md`](integration/README.md)。

初始离线部署 ZIP 的待激活补丁是历史模板；以工具箱当前主分支实际配置为准，不要覆盖已启用的入口。入口可以独立缓存运行，不依赖旁边的向导文件。

## 验证范围与上线前检查

详见 `VERIFICATION.md`。源码/mock/API 合成测试通过不等于 VPS 实测或生产认证。

- Linux x86_64/aarch64 BenchOS、挂载/chroot、第三方跑分、NextTrace v1.7.5 兼容性未实机验证。
- BenchOS 和 NextTrace 采用发布资产摘要固定；其他测试脚本/内部依赖仍有动态供应链风险，详见 `docs/DEPENDENCIES.md`。
- chroot 不是安全隔离，不能声称无痕或绝无宿主影响。
- 使用一次性、获授权 VPS 做实际回归；先看成功/失败/中断清理、磁盘占用、网络流量，再考虑生产使用。
- 保护上传密钥；提供对应源码；确认报告到期、删除与备份保留策略。

保留 `LICENSE` 和 `NOTICE.md`，明确本版修改和原作者署名。
