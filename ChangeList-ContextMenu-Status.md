# 更改列表右键菜单功能状态报告

> 审查日期: 2026-04-24
> 审查范围: `WorkbenchRootView.swift` 右键菜单 + `WorkbenchModel.swift` 操作实现

---

## 一、当前右键菜单项一览

| # | 菜单项 | 图标 | 禁用条件 | 后端实现 | 状态 |
|---|--------|------|----------|----------|------|
| 1 | Show Diff (查看差异) | `doc.text.magnifyingglass` | unversioned | `selectAndShowDiff()` | **已完成** |
| 2 | Revert (还原) | `arrow.uturn.backward` | `!canRevert` | `revertPath()` → `SubversionWorkspaceOperator.revert()` | **已完成** |
| 3 | Rollback to Revision (回滚到历史版本) | `arrow.uturn.backward.2.circle` | unversioned | `rollbackPath()` → `SubversionWorkspaceOperator.rollback()` | **已完成** |
| 4 | Add to SVN (添加到 SVN) | `plus.circle` | `!canAdd` | `addPath()` → `RustCommandBridgeSVNClient.add()` | **已完成** |
| 5 | Resolve (解决冲突) | `checkmark.circle` | `!canResolve` | `resolvePath()` → `SubversionWorkspaceOperator.resolve()` | **已完成** |
| 6 | Ignore - 文件 (忽略) | `eye.slash` | unversioned | `ignorePath()` → `svn propset svn:ignore` | **已完成** |
| 6 | Ignore - 目录 (忽略) | `folder.badge.questionmark` | unversioned | `ignoreDirectory()` → `ignorePath()` | **已完成** |
| 7 | Delete (删除) | `trash` | 无 (destructive) | `deletePath()` → `svn delete --force` / `FileManager.removeItem` | **已完成** |
| 8 | Reveal in Finder | `folder` | 无 | `revealInFinder()` → `NSWorkspace` | **已完成** |
| 9 | Copy Path (复制路径) | `doc.on.doc` | 无 | `copyPathToClipboard()` → `NSPasteboard` | **已完成** |

---

## 二、各功能实现细节与质量评估

### 2.1 Show Diff — 已完成
- **代码位置**: `WorkbenchRootView.swift:791-796`, `WorkbenchModel.swift:869-876`
- **实现**: 选中路径后切换到 workingCopy diff 预览模式，触发 `refreshDiffPreview`
- **质量**: 完整，支持外部 diff 工具启动 (IntegrationKit)

### 2.2 Revert — 已完成
- **代码位置**: `WorkbenchModel.swift:616-636`, `SubversionWorkspaceOperator.swift:106-139`
- **实现**: 弹出 NSAlert 确认 → 调用 `svn revert --depth infinity`
- **质量**: 有确认弹窗保护，支持批量和单文件两种入口

### 2.3 Rollback — 已完成
- **代码位置**: `WorkbenchModel.swift:774-836`, `SubversionWorkspaceOperator.swift:321-351`
- **实现**: 查询 `recentHistory` 获取前一版本 → `svn revert -r <revision>`
- **存在问题**:
  - 没有 UI 让用户选择具体回滚到哪个版本（目前自动回滚到上一版本）
  - 缺少确认弹窗（Revert 有确认，Rollback 却没有）
  - `svn revert -r` 不是标准 svn 命令，实际回滚应该用 `svn merge -c -REV` 方式

### 2.4 Add — 已完成
- **代码位置**: `WorkbenchModel.swift:638-663`, `RustCommandBridgeSVNClient.swift:318-334`
- **实现**: 通过 Rust bridge 调用 `bridge-add --depth infinity`
- **质量**: 完整，有错误处理和状态刷新

### 2.5 Resolve — 已完成
- **代码位置**: `WorkbenchModel.swift:665-684`, `SubversionWorkspaceOperator.swift:154-185`
- **实现**: NSAlert 确认 → `svn resolve --accept working`
- **存在问题**: 只支持 `--accept working` 一种策略，缺少 mine-full/theirs-full/base 等选择

### 2.6 Ignore — 已完成
- **代码位置**: `WorkbenchModel.swift:728-772` (文件), `WorkbenchModel.swift:838-856` (目录)
- **实现**: `svn propget svn:ignore` → 追加文件名 → `svn propset svn:ignore`
- **质量**: 实现正确，有去重检查，目录忽略有确认弹窗
- **可改进**: 不支持 `svn:global-ignores` (SVN 1.8+)，不支持通配符模式忽略

### 2.7 Delete — 已完成
- **代码位置**: `WorkbenchModel.swift:686-726`
- **实现**: 确认弹窗 → 版本控制文件用 `svn delete --force`，未版本控制文件用 `FileManager.removeItem`
- **质量**: destructive 样式 + 确认弹窗，区分版本控制/非版本控制处理

### 2.8 Reveal in Finder — 已完成
- **代码位置**: `WorkbenchModel.swift:858-861`
- **质量**: 简单完整

### 2.9 Copy Path — 已完成
- **代码位置**: `WorkbenchModel.swift:863-867`
- **质量**: 简单完整

---

## 三、缺失功能 — 与 TortoiseSVN 右键菜单对比

以下是 TortoiseSVN 提供但当前 MacTortoiseSVN 右键菜单**尚未实现**的功能:

### 高优先级（核心工作流缺失）

| 功能 | 说明 | 后端支持 | 工作量评估 |
|------|------|----------|------------|
| **Show Log / 查看日志** | 查看选中文件的提交历史 | `SubversionRepositoryInspector.recentHistory()` 已有 | **小** — 后端已有，只需右键菜单入口 + 导航到历史面板 |
| **Blame / Annotate (追溯)** | 逐行显示每行最后修改者和版本 | **完全没有** | **大** — 需要新增 `svn blame --xml` 解析 + 全新 Blame 视图 |
| **Properties (属性)** | 查看/编辑 SVN 属性 (svn:ignore, svn:externals, svn:keywords 等) | 部分 (只有 svn:ignore 的 propget/propset) | **中** — 需要通用属性编辑面板 |
| **Lock / Unlock (锁定/解锁)** | 文件锁定防止他人修改 | 状态识别已有 (`VersionControlStatus.locked`)，操作**未实现** | **中** — `svn lock` / `svn unlock` + UI |
| **Rename / Move (重命名/移动)** | SVN 感知的重命名 | **完全没有** | **中** — `svn move` + 文件名输入框 |

### 中优先级（增强体验）

| 功能 | 说明 | 后端支持 | 工作量评估 |
|------|------|----------|------------|
| **Create Patch (创建补丁)** | 导出当前修改为 .patch/.diff 文件 | **完全没有** | **小** — `svn diff > file.patch` |
| **Apply Patch (应用补丁)** | 导入补丁文件 | **完全没有** | **中** — 需要文件选择器 + `svn patch` |
| **Shelve / Unshelve (搁置)** | 临时保存修改 | 接口已定义，抛出 `unsupportedOperation` | **中** — 需接入 Rust bridge 或 CLI |
| **Export (导出)** | 导出干净的文件副本（无 .svn） | **完全没有** | **小** — `svn export` |
| **Switch (切换)** | 切换到不同分支/标签 | **完全没有** | **中** — `svn switch` + URL 输入 |
| **Relocate (重定位)** | 更改仓库 URL | **完全没有** | **小** — `svn relocate` |
| **Check for Modifications (检查修改)** | 对比远程变更 | 部分 (status 只查本地) | **中** — 需要 `svn status -u` |

### 低优先级（高级功能）

| 功能 | 说明 |
|------|------|
| Merge (合并) | 分支合并向导 |
| Branch/Tag (创建分支/标签) | `svn copy` 到 branches/tags |
| Update to Revision (更新到指定版本) | `svn update -r REV` |
| Diff with Previous Version (与前一版本对比) | `svn diff -r PREV:WORKING` |
| Repository Browser (仓库浏览器右键) | 仓库浏览器中的右键菜单 |

---

## 四、Finder 右键菜单（FinderSyncBridge）

当前 Finder 右键菜单只暴露了 4 个命令:

```swift
enum FinderMenuCommand {
    case commitSelected     // 提交
    case diffSelected       // 差异
    case refreshNow         // 刷新
    case openInWorkbench    // 打开工作台
}
```

**与 TortoiseSVN 的 Explorer 右键菜单差距很大**，TortoiseSVN 在资源管理器中提供了几乎全部操作。建议后续按需扩展。

---

## 五、已知问题与改进建议

### 5.1 Rollback 实现有误
`SubversionWorkspaceOperator.rollback()` 使用 `svn revert -r <revision>`，但 `svn revert` 不接受 `-r` 参数。正确的回滚方式应为:
```bash
svn merge -c -<revision> <path>   # 反向合并指定版本的修改
```
或:
```bash
svn merge -r HEAD:<old_revision> <path>   # 合并到旧版本状态
```

### 5.2 Rollback 缺少版本选择 UI
当前自动取上一版本回滚，应提供版本选择器（类似 TortoiseSVN 的 "Revert to this revision"）。

### 5.3 Rollback 缺少确认弹窗
Revert/Resolve/Delete 都有确认弹窗，Rollback 没有，属于漏洞。

### 5.4 Resolve 策略单一
只有 `--accept working`，建议至少支持:
- `working` — 使用当前工作副本
- `mine-full` — 使用我的版本
- `theirs-full` — 使用对方版本
- `base` — 使用基础版本

### 5.5 Ignore 不支持通配符
只能按文件名精确匹配，不支持 `*.log`、`build/` 等通配符模式。

### 5.6 右键菜单缺少"查看日志"入口
`HistoryViews.swift` 已有完整的历史展示 UI，`SubversionRepositoryInspector.recentHistory()` 已有后端，但右键菜单没有 "Show Log" 入口将两者串联。这是最容易补上的功能。

---

## 六、总结

| 维度 | 评估 |
|------|------|
| **已实现菜单项** | 10 项 (Diff / Revert / Rollback / Add / Resolve / Ignore 文件 / Ignore 目录 / Delete / Reveal / Copy Path) |
| **实现质量** | 大部分良好，Rollback 有实现缺陷 |
| **对比 TortoiseSVN 覆盖率** | 约 **45-50%**（核心日常操作基本覆盖，高级功能缺失） |
| **最容易补齐的功能** | Show Log（后端+UI 都已有，只差串联）、Create Patch（一行 svn diff）、Export |
| **工作量最大的功能** | Blame/Annotate（需全新视图）、Merge（需完整向导）、Branch/Tag |
| **建议下一步优先级** | Show Log > Lock/Unlock > Blame > Rename > Properties > Create Patch |
