# IMGX 开发约定

- 按 `docs/PRD.md` 开发，历史“已实现”描述不等于本仓库已完成。
- 每个功能完成并验收通过后单独提交，提交信息使用中文。
- 用户已明确授权本项目所有 commit 直接提交，无需逐次询问。
- 仅做本地 Git 提交，不执行 push，除非用户再次明确要求。
- 验证结果记录在 `docs/IMPLEMENTATION.md`，区分自动化、实际窗口检查与未完成验收。
- 不覆盖或删除用户的源图片。图片仅在本机处理。
- macOS 26+、Apple Silicon、SwiftUI 与 AppKit；WebP 使用仓库内静态库。
