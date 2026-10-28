# VPS 工具箱集成

维护仓库：https://github.com/nbbk/vps-toolkit

工具箱保留菜单 **33** 和 ID **test-nodequality**。发布维护版后，工具箱来源应为：

- `https://raw.githubusercontent.com/nbbk/NodeQuality/<真实40位commit>/NodeQuality.sh`
- 对该提交实际文件计算的 SHA-256；下载后必须一致，否则不执行。

入口是独立单文件，不依赖仓库旁的配置/辅助脚本。默认本地报告；在线分享须显式同意并配置用户自己的 HTTPS 服务。固定入口并不表示已固定所有第三方测试依赖。

以工具箱当前主分支中的来源配置为准。初始离线部署 ZIP 曾提供待激活补丁，它是历史模板；不要用旧模板覆盖已经启用的来源。

更新入口时：在一次性环境做静态/模拟测试，审查新提交，计算摘要，然后通过工具箱 PR 更新两个字段。不得用动态 main URL、空摘要或未审阅 fallback 绕过验证。
