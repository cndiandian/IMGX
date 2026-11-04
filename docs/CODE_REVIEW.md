# 全仓库代码审查与整理

日期：2026-11-04。审查基线：`e7163eb`。覆盖 Swift 应用、测试、构建/发布脚本、Actions 和相关文档。

## 已处理的发现

| 发现 | 原有影响 | 本次处理 | 验证 |
| --- | --- | --- | --- |
| 尺寸解析及边界判断散落在界面、模型和编码层 | 修改规则时容易不一致；无效或极大源尺寸可能在浮点转整数时触发运行时错误 | 独立转换参数类型，共用 ImageSizing；在转整数前验证边界，维持 PRD 的等比边界框规则 | 增补零、负值、极大值用例；实际输入错误与恢复 |
| 导出复用了完整预览创建流程 | 每张导出图片都多做输出解码；WebP 还复制整张 RGBA 缓冲区 | 纯编码返回 Data，预览另行解码；WebP 在独占 CGContext 缓冲区还原 alpha | 三种格式导出与预览字节一致、透明度、尺寸及源文件不变测试 |
| 主视图含高级设置、菜单和共享图标；更新服务混有界面模型 | 阅读和修改职责边界不清，跨页面共享组件依附主视图文件 | 提取 AdvancedSettingsView、ImageCommands、BrandIcon、ThumbnailWorker 和 AppUpdateModel；主视图由 482 行降为 343 行 | 构建、回归测试、实际最小窗口及关于窗口检查 |
| 缓存和任务句柄参与 Observation，可由外部改写部分内部阶段 | 状态接口过宽，非界面数据无需观察 | 标注 ObservationIgnored，将预览结果、列表、更新阶段等设为外部只读；EncodedImage 使用编译器验证的 Sendable | Swift 6 编译及异步预览、更新取消回归测试 |
| Release 创建和上传不是一个原子操作 | 创建成功后上传失败或网络响应丢失，重跑可能遇到 Release 已存在；用户也可能读到附件不完整的公开版本 | 先上传并核验草稿，再公开；继续未完成草稿；已发布且摘要一致则幂等成功，不一致则停止 | 模拟上传中断、发布响应丢失、权限失败、附件不全和摘要不一致 |
| Homebrew 所有版本共用默认单 pending 并发组 | 多版本排队时可能取消尚未同步的某个版本 | 去掉跨版本并发组，使用已有版本单调检查及 GitHub 内容 SHA 冲突重试 | 并发更新、旧版本跳过及新 SHA 重试测试 |

## 代码边界

- `ContentView` 组合主页面；高级设置和菜单有独立入口。
- `AppModel` 协调导入、选择、预览、导出和提示；`ImageProcessor` / `ThumbnailWorker` 承担后台图片工作。
- `ConversionSettings` 和 `ImageSizing` 提供共享规则；`ImageCodec.encode` 生成文件数据，`convert` 创建真实预览，`ExportWriter` 负责排他写入。
- `AppUpdateModel` 负责界面阶段及取消；`GitHubUpdateService` 负责版本元数据、下载和摘要验证。
- `build-app.sh` / `release.sh` 负责签名公证；`publish-release.py` 负责 GitHub 发布恢复；`update-homebrew-tap.py` 负责 Cask 同步；GitHub CLI 基础调用共用一个模块。

继续使用系统框架和 Python 标准库，没有新增第三方运行依赖。没有为了文件数量或模式名称增加通用仓储、服务定位器等额外层次。

## 验证与边界

- 19 项 Swift 测试；7 项构建流程、8 项 tap 同步、10 项发布恢复及 CLI 测试。
- Actions 使用 actionlint 校验；内嵌 Shell 通过语法检查，变更通过 git diff --check。
- 实际检查最小窗口图片页面；640×400 原图输入宽度 320 后高度联动为 200，Tab 切换正常；无效高度出现错误，恢复后生成 320×200 预览；关于窗口保持精简布局，链接无焦点蓝框。
- 先前已完成真实 GitHub Release 和 Homebrew Cask 下载验收。本次新增的发布恢复流程仅做离线故障模拟，需下一个正式 tag 完成云端端到端验收；没有为审查创建额外 tag 或 Release。
- 当前没有做超大图长期内存压力或 Instruments 性能采样；本次确认消除了具体副本和多余解码，没有给出未经测量的性能提升比例。棋盘格绘制仍按现有方式逐格绘制，后续应先测量再决定是否缓存纹理。

发布行为依据：[GitHub CLI Release](https://cli.github.com/manual/gh_release_create)、[附件上传](https://cli.github.com/manual/gh_release_upload)、[GitHub 并发组规则](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)。
