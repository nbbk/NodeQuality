# 验证记录（2026-10-28 UTC）

全部使用本地/合成数据；没有真实服务器报告、真实凭据或第三方上传。

## 已通过

- `python3 -m unittest discover -s tests -p 'test_*.py' -v`：私密客户端配置解析2项；不执行文件内 shell 指令，拒绝公开可读/未知配置。Docker 部署向导仅模拟 Docker 调用测试。

- `bash tests/cli-contract.sh`：默认零上传；私有报告保存；带空格路径；失败卸载保留目录；参数/HTTPS/同意校验；aarch64/不支持架构；下载/摘要失败不解压安装；固定 NextTrace 模拟原子安装；缺失 NextTrace 拒绝不安全安装路径；EOF 取消；退出码；私有删除令牌；上传失败保留报告。
- `bash tests/cli-service-contract.sh`：真实 CLI JSON 序列化 → 内存 WSGI 服务创建/读取 → CLI 分享响应处理；不发 HTTP、不跑测试负载。
- `python3 -m unittest discover -s service/tests -v`：17 个服务/部署向导测试（校验、鉴权、XSS、删除令牌、过期、容量、限速、源码提供等）。
- `python3 service/tests/smoke.py`：真实 localhost HTTP 合成数据创建、读取、删除、404。
- 主脚本、part、tests Bash 语法；`git diff --check`；原始 `LICENSE` 未改动。
- 工具箱独立工作树 `nodequality_contract`、`testsuite_contract`、`menu_contract`、`smoke`、`safety_contract`、`release_contract` 全部通过；菜单33和ID不变，待发布/不固定URL/缺少或错误哈希拒绝执行。
- Cloudflare：`npm run check`、`npm test`（11个运行时/配置向导测试（其中真实本地 workerd+D1/Assets））、`npm run build` 最终复跑通过；覆盖创建/读取/删除、XSS、到期清理、并发限额和源码下载。实现代理另验证本地 D1 migration 与 Wrangler deploy dry-run 通过，均不操作远程资源。
- Git ignore 对默认 `.nodequality-*` 报告目录、分享删除令牌/载荷文件、`.env`、Cloudflare `.dev.vars` 生效。

## 未执行 / 不应推断

- 没有运行 BenchOS、mount/chroot、root 跑分、第三方依赖安装或 NextTrace 二进制；没有实测 x86_64/aarch64 兼容性或实际中断时宿主挂载恢复。
- Docker 不可用：没有 build 或 Compose 启动。
- 没有真实 Cloudflare 账号资源、线上 D1、DNS、TLS、Worker 发布或公网分享验证。
- 交互 `wrangler dev --local` 因本环境 `uv_interface_addresses` 系统错误未启动；独立 Miniflare/workerd 自动测试已通过，不能混同为交互 dev 成功。
- ShellCheck 不可用。
- 浏览器视觉检查受环境限制未完成；不能声称截图/手机布局已人工验收。
- 不是渗透测试、第三方镜像安全审计、许可证法律意见或生产可靠性保证。

具体实现仍需在获授权的一次性 VPS 和自己的部署环境做上线验收；动态第三方脚本风险见 `docs/DEPENDENCIES.md`。
