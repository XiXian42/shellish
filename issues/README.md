# shellish Windows 兼容性问题清单

针对 README 中标注为"🧪 beta"的 Windows 平台,目前共发现 23 个需要
修复的问题。按优先级和依赖关系排序:

## 优先级图谱

```
P0(必须修)             P1(应当修)         P2(建议修)         P3(可选)
01 shell hook         03 codex 路径      05 Read-Host        11 history key
02 config UTF-16      08 taskkill         06 CN API           13 旧 shim
04 safe-rm COM       10 rm 拦截 PS       07 readline         14 长路径
                       17 cmd 参数转义    09 ANSI VT         15 CJK 对齐
                       18 Windows prompt  12 供应链签名      16 退出码语义
                                            19 hook marker
                                            20 profile 目标
                                            21 agent cwd
                                            22 agent auth stdin
                                            23 codepage/Unicode
```

## 依赖关系

- 01 (shell hook 拿不到完整命令行) 阻塞 06
- 02 (config 一致性) 是新模块的地基,优先做
- 04 (safe-rm COM) 和 10 (rm 拦截 PS) 互相依赖,先做 04
- 17 (`shellish.cmd` 参数转义) 会影响 01 的最终入口方案,应与 01 同步设计
- 18 (prompt 平台规则) 已改为 shell-agnostic:只提供 Host OS 事实和 safe-delete 边界,不再硬编码 PowerShell 命令替换
- 19 (hook marker) 和 20 (profile 目标) 应在重写 hook/install-hook 时一起做
- 21 (agent cwd) 是低风险修复,可随 run.js 相关改动一起做
- 22 (agent auth stdin) 影响首次使用体验,与 status/health check 相关
- 23 (codepage/Unicode) 与 17 强相关,优先通过 PowerShell/Node 入口绕开 `.cmd`
- 16 (退出码语义) 在 04 之后做,作为加固

## 修复路线图

### 第一阶段:核心跑通(2-3 天)
- 01 修复 PowerShell hook
- 02 统一配置读取
- 04 safe-rm 改用 .NET BCL
- 08 进程树终止
- 10 PowerShell rm 拦截
- 17 避免 `.cmd` 破坏 prompt 参数
- 18 移除 Windows PowerShell 命令硬编码,改为 shell-agnostic + shellish-trash safe-delete 规则

### 第二阶段:稳定(2 天)
- 03 codex.js 路径解析
- 05 Read-Host 修复
- 07 readline 健壮性
- 09 ANSI VT fallback
- 19 hook marker 精准安装/卸载
- 20 统一 PowerShell profile 写入目标
- 21 显式设置 agent cwd
- 23 Unicode/codepage 测试与提示

### 第三阶段:加固(2-3 天)
- 06 / 11 / 12 / 13 / 14 / 15 / 16 / 22

## 状态总览

- [x] 已识别 23 个 issue
- [ ] 全部修复

详见各 `NN-*.md` 文件。
