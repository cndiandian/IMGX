# IMGX Apple HIG 检查与修复

日期：2026-11-03。检查对象为当前 macOS 原生应用，覆盖空状态、图片列表与对比预览、高级设置、菜单及批量导出。以本轮实际截图、无障碍树和代码检查作为证据。

结论：修复了输入说明、错误反馈、操作可发现性与导出进度方面的问题，并改善了原生控件和辅助技术支持。保留 PRD 的黑白灰、图片优先和底部单行设置布局。以下包含明确问题与 HIG 建议下的一致性改进，不将所有建议都视为硬性违规。

## 1. 空状态与主操作：已复测

- 原有空状态的信息层次、居中布局和导入指引可继续使用。
- 将主操作改为原生 `NSButton`，由 AppKit 管理按下、键盘焦点、禁用及非活动窗口状态；保留中性色，并明确设置深浅色文字对比。
- 空状态的“选择图片…”支持 Return；导出按钮增加省略号，明确下一步还需要选择位置。
- 实际验证：清空测试列表后恢复空状态，Return 打开与当前窗口关联的图片选择 Sheet。

![修复后的空状态](09-after-empty-state.png)

依据：[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) 对标准按钮、状态、主操作和省略号的建议。

## 2. 文件列表、预览与菜单：已复测

- 原有棋盘格、对比切换、尺寸和体积反馈在本轮浅色/深色最小窗口中保持可用。
- 明确放大移除、更多设置和关闭提示的图标点击范围；保留原生控件行为与工具提示。按 macOS 场景检查，不套用手机布局尺寸改造整个窗口。
- 文件名采用 13pt，状态从 10pt 调整到 caption；原 10pt 恰为 Apple 列出的 macOS 最小字号，并非本身违规，此处是可读性改善。
- 每项状态同时使用图标和文字；文件无障碍说明包含名称、原始体积与状态。
- 预览体积及像素尺寸作为可读静态文本暴露；质量滑块说明范围，并解释无损模式为什么不可调。
- 为画布补充放大、缩小、适应窗口和两种滑杆范围调整的无障碍自定操作。将手柄文字箭头改为 SF Symbol。
- 编辑菜单补充明确的列表管理入口，显示菜单补充对比模式和更多设置；实际从菜单切换到分屏，画布和分段控件同步。

![浅色最小窗口](04-after-preview-light.png)

![深色最小窗口](07-after-preview-dark.png)

依据：[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)、[Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders)。

## 3. 高级设置与尺寸校验：已修复并复测

原界面宽高只通过占位文字标识，填写后标识消失；尺寸错误主要通过远离字段的 toast 反馈。

修复后：

- 宽度、高度及像素单位始终可见。
- 错误出现在输入框下方，同时提供图标和文字；只给实际无效的字段标记错误，空白但合法的字段不会被误标。
- 原生文本框向辅助技术提供范围及错误说明。
- 弹层中已有就地错误时不再重复显示同一 toast；关闭弹层后仍可看到持续错误提示。
- 非 WebP 格式隐藏不适用的 WebP 无损开关。
- 实际验证：输入 0 显示就地错误；改为 320，Tab 进入高度并输入 100，宽度联动为 160，错误清除，焦点与原生编辑行为保持正常。

![修复前的尺寸输入](02-before-settings.png)

![无效尺寸就地反馈](05-after-inline-validation.png)

![有效输入与始终可见的字段标签](10-after-settings-valid.png)

依据：[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)、[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)。

## 4. 导出、进度与通知：已修复并复测

- 导入、导出位置选择改为与当前窗口关联的原生 Sheet，取消后返回原窗口。
- 将选择保存位置与实际导出区分开，避免尚未开始处理时显示“正在导出”。
- 实际导出使用确定性进度条，并保留处理数量；无障碍树包含原生 `progress indicator` 角色及已处理/总数。
- 通知通过 AppKit 的 announcement 通知辅助技术，不抢输入焦点。
- 实际批次：12 张 1600×1000 PNG 顺序导出，观察到 1/12 处理进度、各项状态与设置禁用；结束后控件恢复，磁盘上有 12 份有效 WebP 文件。

![原生导出 Sheet](06-after-export-sheet.png)

![真实批次处理进度与禁用状态](08-after-export-progress.png)

依据：[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)、[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)。

## 验证范围与限制

- 最终 Release 构建及临时签名检查通过，`git diff --check` 通过。
- 12 项自动化测试通过，新增画布无障碍操作测试验证无指针操作、倍率边界、复位及分屏保护。
- 本轮实际检查了浅色/深色最小内容窗口、菜单切换、原生 Sheet、Return、Tab、错误恢复及真实批次状态。
- 已查看捕获画面，并核验报告中本地截图与原始捕获字节完全一致。截图可能包含用户图片或目录，仅保留在本地，被 Git 忽略；报告中的图片在本地工作区可查看。
- 本次不等同于全面无障碍认证；VoiceOver 真人朗读顺序、系统放大文字及所有增强对比度/降低透明度设置组合仍需专项实操。
