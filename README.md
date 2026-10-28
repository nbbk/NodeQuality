# NB NodeQuality（本地开发版）

## 只运行测试（无需部署网站）

在装有 **Git** 的 **Linux x86_64 / aarch64 VPS** 上，一条命令下载项目并进入交互测试选项：

```bash
git clone https://github.com/nbbk/NodeQuality.git && cd NodeQuality && sudo bash NodeQuality.sh
```

如果已经下载过，进入项目目录后直接运行：

```bash
sudo bash NodeQuality.sh
```

**不需要部署 Cloudflare 或 Docker，也不需要配置报告网站。默认只保存本地报告，不上传。** 脚本需要 root 权限和宿主基础命令（如 curl、tar、sha256sum、mount、chroot）；缺少依赖时会提示并退出。运行前请审阅源码；测试会产生 CPU、磁盘负载和网络流量。目前尚未完成真实 VPS 全流程验证，建议先在非重要机器上试。

下面的部署向导仅用于需要自建在线分享服务或配置向导的场景，与直接测试命令分开。

**双部署包入口：[Cloudflare / Docker 部署指南](DEPLOYMENT.md)**

基于 [LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality) 的用户维护版本；原作者 Lloyd@nodeseek.com。保留原始 `LICENSE`（GNU AGPL v3）和致谢，修改说明见 [NOTICE.md](NOTICE.md)。维护仓库：[nbbk/NodeQuality](https://github.com/nbbk/NodeQuality)。

## 一条命令开始（部署 / 测试向导）

```bash
git clone https://github.com/nbbk/NodeQuality.git && cd NodeQuality && bash setup.sh
```

这是克隆公开源码后启动向导，不是把网络响应直接交给 root 执行。运行前请审阅代码；后续只需在目录内 `bash setup.sh`。选择 Docker、Cloudflare 或运行测试；账号授权、域名、费用/部署确认不会被绕过，缺少 Docker/Node/Python 时不会擅自改宿主环境。

- `bash setup.sh docker`：生成私有配置并引导容器服务启动。
- `bash setup.sh cloudflare`：引导 Cloudflare 配置，提供 GitHub Workers Builds 自动部署设置。
- `sudo bash setup.sh run`：运行测试，默认本地报告；如发现 Docker 向导生成的 `service/client.env`，可交互选择分享，完成后仍需检查本地报告并输入 `SHARE`。
- 在另一台 VPS 使用配置：安全复制私有 `client.env`（`chmod 600`），再运行 `sudo bash setup.sh run --config /安全路径/client.env`。不要把配置/密钥发到公开仓库。

Cloudflare 首次 GitHub 连接需账号所有者授权；连接完成后可随主分支推送自动构建部署。详见 `cloudflare/README.md`。代码发布和 CI 不会自动创建云资源或部署到你的账号。

## 已实现

- 默认只保留本地日志/JSON，不调用原版在线上传接口。
- 每次使用独立的私有工作目录；报告保存到 `<工作目录>/reports/`，成功或失败均尽力保留。
- 仅支持 Linux x86_64 / aarch64；BenchOS v0.0.2 下载后验证固定 SHA-256。
- 下载失败、测试失败、上传失败返回非零；正常结束返回零；中断保留相应退出码。
- 卸载失败或发现残留挂载时拒绝删除 BenchOS，提示人工检查。
- 支持用户自建在线报告服务，必须显式提供 HTTPS 地址和上传同意。

## 运行

先检查完整源代码。测试需要 root，并会产生 CPU/磁盘负载及网络流量。

```bash
sudo bash NodeQuality.sh -E -D /root
```

`-D` 指定已存在且可写的工作目录；`-4` / `-6` 控制测试 IP 版本。报告路径会打印到终端。普通用户可以运行 `bash NodeQuality.sh --help`，不触发测试。

**chroot 不是安全沙箱。** 测试以 root 执行，绑定宿主 `/dev`、`/sys`、`/proc`，共享内核和网络；不能保证对宿主无影响或完全无痕。不要在不信任第三方脚本时运行，也不要直接用于重要生产机器。

## 自建在线报告

服务实现和部署说明位于 `service/`。先在自己的环境配置服务、HTTPS 和上传密钥；本开发任务没有实际部署。

```bash
# 在安全的 root shell 中设置密钥；避免把实际密钥写进命令历史。
read -rsp 'Upload key: ' NQ_UPLOAD_KEY; echo
export NQ_UPLOAD_KEY
bash NodeQuality.sh --upload-url https://your-domain.example/api/v1/reports --consent-upload
unset NQ_UPLOAD_KEY
```

上传功能额外需要宿主 Python3。没有这两个参数时，绝不上传。日志可能包含公网 IP、地理位置、硬件和网络信息，**没有自动脱敏保证**；执行此命令表示允许分享所选测试生成的完整日志。交互终端会列出本地文件并要求输入 `SHARE` 二次确认；请先在另一终端检查文件。非交互运行时 `--consent-upload` 直接授权传输原始内容，不提供自动脱敏。链接持有人可以阅读报告。默认保留期由服务配置。

接口发送 JSON `{schema_version:1,title,sections:[{title,content}],generated_at,tool_version,upstream_commit}`，不上传或解压 ZIP。认证头读取 `NQ_UPLOAD_KEY`；不跟随重定向。分享响应（包括删除凭据）保存为私有 `reports/share-response.json`，终端只打印分享 URL。上传失败不会删除本地报告。详细限制见服务 README。

## 供应链与验证边界

BenchOS 固定版本和摘要只能验证选定发布资产一致性，不能证明镜像安全；上游仓库未提供完整 rootfs 构建配方。原测试入口 Hardware.Check.Place、IP.Check.Place、Net.Check.Place 及其内部依赖仍是第三方动态下载内容，并未实现全依赖锁定。已移除本加载器错误的强制 amd64 下载。上游 NetQuality 在缺少 NextTrace 时会使用未显式要求 HTTPS 的安装路径，因此本版在网络/回程测试前检查 BenchOS 内的 NextTrace：缺失时拒绝该测试，不触发该安装路径。本版会在需要网络测试时下载固定 v1.7.5、按架构选择的 NextTrace 并验证 GitHub 发布资产 SHA-256 后放入临时 BenchOS；仍未完成真实架构和兼容性测试。运行前仍需审阅并信任这些内容，详见 [依赖验证记录](docs/DEPENDENCIES.md)。

本次仅完成无特权模拟测试和语法检查，**没有执行实际 VPS 测试、挂载、chroot、系统安装或真实上传**；x86_64/aarch64 实机回归和 ShellCheck 尚待完成。不能视作生产安全认证。

```bash
bash -n NodeQuality.sh
bash tests/cli-contract.sh
```

## 致谢与来源

原项目及作者：LloydAsp/NodeQuality，Lloyd@nodeseek.com；原始基础提交 `a92fca6c0067df29ddd03fdc2fee6f3000f64545`。感谢 [xykt](https://github.com/xykt)、[融合怪](https://github.com/spiritLHLS/ecs)、[16图床](https://111666.best/) 等上游项目贡献者。原版说明保存在 `README.upstream.md`，其中运行命令、上传行为和“沙箱/无痕”宣传不适用于本版本。
