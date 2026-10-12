# Changelog

格式參考 Keep a Changelog，版本號遵循 SemVer：
- MAJOR：刪除或改名 skill、行為有不相容的大改
- MINOR：新增 skill、既有 skill 新增能力
- PATCH：修正文字、修正錯誤

## [Unreleased]

## [1.1.0] - 2026-10-13
### Added
- 收錄 10 個公開 skill（皆為 MIT 授權，來源與修改內容見 THIRD_PARTY_NOTICES.md）：
  - 測試：cim-run-tests、cim-code-testing、cim-test-anti-patterns（dotnet/skills）
  - 重構與效能：cim-csharp-refactoring、cim-dotnet-performance（dotnet/skills）
  - SQL：cim-sql-code-review、cim-sql-impact-analysis（github/awesome-copilot）
  - C#：cim-csharp-async（github/awesome-copilot）
  - 工作方法：cim-systematic-debugging、cim-verification-before-completion（obra/superpowers）
- THIRD_PARTY_NOTICES.md

### Fixed
- cim-skills-sync.ps1 1.0.1：查詢 tag 時不再使用萬用字元參數。PowerShell 7 在 Linux/macOS 會把 `v*` 展開成目前資料夾的檔名（例如 `VERSION`），導致找不到 tag；Windows 不受影響。已安裝的電腦會透過自我更新取得修正版。

## [1.0.0] - 2026-10-12
### Added
- cim-csharp-coding-standard：C# 程式撰寫規範
- cim-commit-message：commit message 規範
- cim-code-review：code review 檢查清單
- tools/：同步、安裝、移除、儀表板、lint 工具
