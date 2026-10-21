# Plain Craft Launcher

本分支恢复了 Minecraft 下载、整合包安装和已安装版本的 Minecraft 版本修改，并禁用启动器自身的更新，避免被官方版本覆盖。游戏、Mod 等资源的下载与更新不受影响。

修改以普通新提交叠加在 `e4b0489`、`6b9a50d` 之后，保留上游历史；这两次提交的源码、子模块版本和发布文件均恢复到 `5ef81e4` 的状态，再加入禁用启动器更新的改动。后续可正常合并上游提交；若上游修改同一处代码，需解决冲突并重新确认下载和更新策略。

请从源码构建本分支。仓库内的 `最新正式版.zip` 和 `patches/` 是还原后的上游发布文件，不包含本分支禁用启动器更新的改动。

微软正版登录默认使用仓库自带的官方 2.14.0.0 Release 中的公开 Client ID，保存在 `My Project/Resources.resx`。普通用户无需注册应用或填写 ID。开发者可通过环境变量 `PCL_MS_CLIENT_ID` 或 GitHub Actions 仓库 Secret `CLIENT_ID` 覆盖，优先级为运行时环境变量、构建时配置、内置默认值。空值或纯空白不会覆盖默认配置。

Client ID 是启动器应用的公开编号，不是账号、密码或 Client Secret；登录仍通过微软网页完成。一次设备授权的申请和后续轮询固定使用同一个 ID。若自行替换，应使用可访问 Xbox 和 Minecraft 服务的应用注册。协议说明见 [Microsoft 设备代码登录文档](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code)。

社区资源选择“全部”来源时，单个来源失败不会阻止其他来源的结果展示和分页。可用来源没有匹配项时显示空结果及来源失败提示；仅在所有选定来源请求失败且没有可保留结果时，显示整体错误。CurseForge API Key 仍需另行配置。

[![Stars](https://img.shields.io/github/stars/Meloong-Git/PCL?style=flat&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZlcnNpb249IjEiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiI+PHBhdGggZD0iTTggLjI1YS43NS43NSAwIDAgMSAuNjczLjQxOGwxLjg4MiAzLjgxNSA0LjIxLjYxMmEuNzUuNzUgMCAwIDEgLjQxNiAxLjI3OWwtMy4wNDYgMi45Ny43MTkgNC4xOTJhLjc1MS43NTEgMCAwIDEtMS4wODguNzkxTDggMTIuMzQ3bC0zLjc2NiAxLjk4YS43NS43NSAwIDAgMS0xLjA4OC0uNzlsLjcyLTQuMTk0TC44MTggNi4zNzRhLjc1Ljc1IDAgMCAxIC40MTYtMS4yOGw0LjIxLS42MTFMNy4zMjcuNjY4QS43NS43NSAwIDAgMSA4IC4yNVoiIGZpbGw9IiNlYWM1NGYiLz48L3N2Zz4=&logoSize=auto&label=Stars&labelColor=444444&color=eac54f)](https://github.com/Meloong-Git/PCL/)
[![Issues](https://img.shields.io/github/issues/Meloong-Git/PCL?style=flat&label=Issues&labelColor=444444&color=1F883D)](https://github.com/Meloong-Git/PCL/issues)
[![哔哩哔哩](https://img.shields.io/badge/动态-BiliBili-00A4DB?style=flat&labelColor=444444&logoSize=auto)](https://space.bilibili.com/11343203/dynamic)
[![爱发电](https://img.shields.io/badge/赞助-爱发电-946ce6?style=flat&labelColor=444444&logoSize=auto)](https://meloong.com/afd/a/LTCat)

包含 PCL 的大部分源代码，包括 UI 库、动画模块、下载模块、Minecraft 启动模块等！<br/>
代码并不是实时更新的，它会在每次 PCL 发布更新时同步一次。<br/>
非常感谢社区的大力支持！

<br/>

### 相关资源
- [PCL 下载](https://meloong.com/pcl)：下载可免费使用的正式版 PCL！
- [PCL 功能投票](https://github.com/Meloong-Git/PCL/discussions/2)：来参加投票吧，开发者会优先处理票数较高的项目！
- [帮助文档库](https://github.com/LTCatt/PCL2Help)：PCL 内置帮助文档的存储库
