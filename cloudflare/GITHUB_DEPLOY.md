# 连接 GitHub，自动部署到 Cloudflare

推荐 **Cloudflare Workers Builds 原生 Git 集成**，不是 Pages，也不需要在 GitHub Actions 中另放 Cloudflare API Token。代码已适配该流程；**尚未连接你的 GitHub/Cloudflare 账号、创建 D1、设置线上秘密、绑定域名或上线**。

## 最简单：一条命令引导初始化

在仓库根目录执行：

```sh
bash cloudflare/setup.sh
# 只看计划（完全不调用npm/Wrangler或修改文件）：
bash cloudflare/setup.sh --dry-run
```

需要本机预装 Node.js 22/24 LTS、npm、Python3。向导负责安装锁定依赖、收集Worker名称/账号ID/域名、备份配置、浏览器登录、创建或复用D1、迁移、生成私有上传密钥、测试并部署。每个外部修改阶段都必须输入指定确认词，不会默认替你操作账号；没有无人值守 `--yes` 模式。失败即停止，不自动重试可能已执行的云操作。

生成的上传密钥保存在 `cloudflare/.setup-private/secrets.json`（目录700/文件600，git忽略且不进入源码包）；不会打印到终端。通过自己的安全方式将其中的 `REPORT_UPLOAD_KEY` 交给CLI，不要发到聊天或提交仓库。重跑复用本地秘密，不会悄悄覆盖本地文件；发布前会明确提示它可能替换已有线上秘密。配置备份也在此私有目录。

**不能省去的最后一步**：在Cloudflare控制台连接GitHub并亲自批准GitHub App权限，按下表选择仓库/生产分支。向导不会伪称已经完成OAuth或自动扩大仓库权限。域名若尚未绑定，也需按控制台确认绑定。初始化之后，普通代码push可自动部署。

下面是等价的手动操作，便于审计和遇到问题时恢复。

## 一次性准备：账号所有者手动操作

1. 先在你自己的 Cloudflare 账号创建 D1 `nodequality-reports`，把真实 UUID 填入 `cloudflare/wrangler.jsonc` 的 `d1_databases[0].database_id`。全零值只是本地示例；部署预检会拒绝它。D1 ID不是密码，但它不能代替账号权限。
2. 将 `PUBLIC_BASE_URL` 改为你将使用的 HTTPS origin，不带路径；`name` 必须与 Cloudflare 项目名一致（默认 `nodequality-reports`）。自定义域名仍需单独确认、绑定，DNS 托管本身不会完成这一步。配置文件请保持有效 JSON，不添加注释。
3. 在本地安装依赖后，由有权限的账号所有者执行首次迁移：

   ```sh
   cd cloudflare
   npm ci
   npx wrangler login
   npx wrangler d1 migrations apply nodequality-reports --remote
   ```

   这一步会写入真实数据库。先核实账号和数据库。**自动部署脚本不创建数据库、不执行远程迁移**；未来涉及数据库结构的版本，应先备份、审阅迁移并在发布前手动执行。普通代码提交不需要重复初始化。
4. 将个性化非秘密配置提交到自己的 GitHub 仓库。不要提交上传秘密、`.dev.vars`、数据库文件、OAuth凭据或 API Token。

## 连接新项目或现有 Worker

- 新项目：Cloudflare Dashboard → **Workers & Pages → Create application → GitHub** → 选择本项目仓库。
- 已有项目：选择对应 Worker → **Settings → Builds → Connect** → 选择仓库。
- GitHub 登录、安装 Cloudflare GitHub App、授权仓库和确认 Cloudflare 构建令牌须由你完成；尽量只授权这个仓库。本文没有替你授予或扩大访问权限。Cloudflare 原生 Builds 自己管理部署授权，仍不是“完全无需权限”。
- 项目名称填写 `nodequality-reports`（如已改 Wrangler `name`，两处保持完全一致）。选择实际生产分支，通常为 `main`。

入口和名称匹配要求见 [Cloudflare Workers Builds 官方指南](https://developers.cloudflare.com/workers/ci-cd/builds/)。

## 可以直接填写的构建设置

| 设置 | 值 |
|---|---|
| Root directory / 根目录 | `cloudflare`（即仓库的 `cloudflare/`，不是仓库根） |
| Build command / 构建命令 | `npm ci && npm run build:ci` |
| Deploy command / 部署命令 | `npm run deploy:ci` |
| Production branch | 你的生产分支，如 `main` |
| Build variable | `SKIP_DEPENDENCY_INSTALL=1` |
| 非生产分支/PR预览自动构建 | **初始关闭**，参见下节 |

`SKIP_DEPENDENCY_INSTALL=1` 跳过平台自动安装，安装完全由显式的 `npm ci` 按锁文件执行；**它不是一个单独的Install command栏位**。`.node-version` 固定本次已测试的 Node 24.22.1，`packageManager` 固定 npm 11.9.0。平台构建镜像提供 Python；Python3仅用于打包源码，不作为 Worker 运行时。

`build:ci` 执行语法检查和合成测试；`npm test` 首先生成 `public/source.tar.gz`，因此每次推送都有对应的新源码下载包。`deploy:ci` 本地预检真实D1 ID/域名后才执行锁定版本的 Wrangler。**不要把 Deploy command 换成只有 `npm run build`，也不要遗漏构建命令；只构建不等于部署。**

设置依据：[Build配置](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)；安装跳过和版本覆盖依据：[Build镜像](https://developers.cloudflare.com/workers/ci-cd/builds/build-image/)。

## 上传秘密必须是运行时 Secret

在 Worker **Settings → Variables & Secrets** 中添加类型为 **Secret** 的 `REPORT_UPLOAD_KEY`（自己生成并私下保管，至少32字符）。**不是 Settings → Builds 中的构建秘密**；只有构建时变量不会自动成为运行时 `env.REPORT_UPLOAD_KEY`。配置和代码均不读取构建机上的上传密钥。

首次新 Worker 创建可能先完成一次部署才可设置运行时秘密；此期间业务接口安全返回503，不会开放匿名上传。保存秘密后按界面要求部署/激活，再验收。之后代码自动部署沿用已有运行时秘密；每次仍应验证 `/healthz` 和上传。通过 Secrets 官方支持的运行时流程轮换，不把值复制进构建日志。详见 [Cloudflare Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)。

## 生产分支、预览与自动发布范围

初始只启用生产分支的自动部署，关闭其他分支/PR预览，避免未知分支代码接触生产D1和令牌。本包**没有配置独立预览D1/上传密钥/域名**。以后启用预览前，由账号所有者建立隔离资源与独立秘密，并验证预览确实不访问生产报告；不要盲目复用生产绑定，也不要把 `versions upload` 当成资源隔离。分支配置见 [Build branches](https://developers.cloudflare.com/workers/ci-cd/builds/build-branches/)。

启用后，向生产分支推送会执行检查并自动上线；因此只有经过审阅的代码才应进入该分支。账号的构建分钟数、Worker请求、D1读写存储可能产生费用，先核对预算。可暂时断开构建或调整生产部署策略；不要同时添加另一条GitHub Actions发布流水线，避免重复部署。

可选变更监听路径需覆盖 `cloudflare/**` 和根目录 `NOTICE.md`（源码包会读取它）；不设路径过滤也可以。不要只监听 `src/**` 而漏掉配置、迁移或锁文件。

## 首次上线验收与后续操作

1. 在构建历史确认成功的 commit SHA 就是刚提交的版本，Worker部署已激活，而不只是构建成功。
2. `/healthz` 返回200；上传一个 `tests/fixture.json` 合成报告，打开报告，删除后确认404。
3. 打开 `/source.tar.gz` 确认源码可下载；手机确认排版；确认Cron已配置，过期后不可读取。
4. 配好自定义域名和TLS，并确保返回分享URL使用该域名；若不用 `workers.dev`，按README关闭入口。
5. 更新代码后 push 到生产分支即可自动部署；迁移仍是显式维护步骤。回滚代码不会自动回滚数据库，先确认兼容性。

### 本地预检（不会部署）

```sh
cd cloudflare
npm ci
npm run build:ci
npm run deploy:dry-run
```

示例占位配置允许 dry-run 以验证打包；真实 `npm run deploy:ci` 会拒绝全零D1/示例域名。这里的“预检通过”不代表账号授权、远程数据库、域名、运行时秘密已设置。**真实GitHub→Cloudflare连接及自动发布尚未执行或验证。**
