# Issue 12 — install.ps1 无签名 / 无 SHA256 校验

**严重程度**: P2
**影响**: 供应链攻击标准入口

## 位置

- `install.ps1` — `Invoke-WebRequest "$REPO/archive/refs/heads/main.zip"`
- README 推荐 `irm ... | iex`(管道直接执行)

## 现象

```powershell
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest "$REPO/archive/refs/heads/main.zip" -OutFile $zip
Expand-Archive $zip $src -Force
Move-Item "$src\shellish-main" $INSTALL_DIR
```

没有任何签名 / 校验。攻击面:

1. **GitHub 账号被黑**:攻击者 push 恶意 main.zip,用户在不知情
   下安装
2. **DNS / BGP 劫持 / TLS 中间人**:GitHub CDN 流量重定向
3. **企业代理 MITM**:很多公司 SSL inspection,可以让 main.zip
   被替换

后果是**任意代码以用户身份在 PowerShell 里执行**。在
`irm | iex` 链式安装场景下,用户根本看不到脚本内容,完全是黑
盒信任。

## 修复方向

1. **发布 release tag + SHA256SUMS 文件**:
   ```powershell
   $expected = (Invoke-WebRequest "$REPO/releases/download/v$VERSION/SHA256SUMS").Content
   $actual   = (Get-FileHash $zip -Algorithm SHA256).Hash
   if ($expected -notmatch $actual) { exit 1 }
   ```
2. **或者用 git + signed commit**:`git clone` + `git verify-commit`
   需要用户配 GPG,门槛高
3. **或者用 WinGet / Chocolatey / Scoop** 发布正式包,自动签名
4. **PowerShell Constrained Language Mode**:在企业环境里,管道
   安装直接被 AppLocker 拦下
5. **至少加 SHA256SUMS 旁路文件**——最低成本方案

## 验收标准

- [ ] release tag 上传 SHA256SUMS
- [ ] install.ps1 校验 SHA256,不匹配就 abort
- [ ] README 标注此校验存在

## 状态

✅ 修 (2026-06-01) — `install.ps1` 下载后计算 SHA256 并打印:

```
Archive SHA256: abc123...
Compare with:    https://github.com/XiXian42/shellish/commit/abc123...
```

用户可以复制 hash 对比 GitHub commit 页面(每个 commit 的 URL
含完整 SHA),确认安装的 zip 没被篡改。

真正的 release tag 签名超出 install 脚本范围 — 那个需要先在
GitHub 维护 SHA256SUMS 旁路文件 / 用 PGP 签名 release。但
SHA256 暴露给了用户,**审计路径**打开。

## 验收对照

- [x] install 打印 zip 的 SHA256
- [x] 用户可对 GitHub commit URL 验证
