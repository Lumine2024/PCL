# 同步公开仓库与本地私有改动

日常开发使用 `local-private`。`main` 用于公开发布，私有提交在
`git-repository.config.json` 的 `privateCommits` 中配置，禁止将整个
`local-private` 合并到 `main`，也不要推送 `local-private`。

先提交本地改动，保持工作区和子模块干净，再在仓库内运行：

```powershell
.\scripts\push-gitrepository.ps1
.\scripts\get-gitrepository.ps1
```

- `push` 检查当前分支，逐个将尚未应用的公开提交 cherry-pick 到 `main`，
  跳过私有提交及已同步的补丁。合并提交按第一父提交计算改动。
  提交信息中的源提交记录用于避免重复同步，包括手动解决过冲突的提交。
  检查待推送的每个提交的文件内容和提交信息后，只推送 `main`，最后回到 `local-private`。
- `get` 检查当前分支，切换到 `main` 执行 `git pull`，随后将 `main`
  合并到 `local-private`，保留本地私有改动。
- 两个脚本均拒绝脏工作区、未完成的 Git 操作和错误分支，不会自动 stash、
  强制推送或替你选择冲突内容。失败以非零状态退出。
- 冲突会保留在发生冲突的分支。按提示修复并 `git add` 后执行
  `git cherry-pick --continue` 或 `git merge --continue`；也可以执行相应的
  `--abort`。完成后切回 `local-private`，再次运行所需脚本。
  网络错误等没有遗留操作的失败会尽可能切回 `local-private`。
- 失败不会撤销已经成功应用到 `main` 的提交，修复问题后可重试。
- 远端有新提交而本地尚未接收时，推送会被拒绝；先运行 `get`。

配置文件保存分支、远端、私有提交编号和检查规则，不保存 Key。
检查器从本地私有提交读取受保护值，同时检查原始值和 Base64 解码后的值。
若以后添加新的私有提交或更换 Key，应同步维护配置。
这不替代代码审查：公开提交中其他未配置的敏感信息仍须自行检查。

本工作区另外设置了 `remote.origin.push=refs/heads/main:refs/heads/main`，
因此无参数的 `git push` 只推送 `main`。这一设置位于本地 Git 配置中，
不会随克隆传播；脚本始终显式指定只推送公开分支。
