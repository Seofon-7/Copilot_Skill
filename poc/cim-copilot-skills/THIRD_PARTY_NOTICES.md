# Third-Party Notices

本 repo 的部分 skill 取自以下公開專案，皆為 MIT 授權。每個 skill 資料夾內都附有原始 `LICENSE` 檔，`SKILL.md` 的 `metadata.source` 與 `metadata.source-ref` 記錄了來源路徑與 commit。

## 修改內容

所有取自外部的 skill 都做了以下修改：

- 資料夾與 `name` 加上 `cim-` 前綴
- `description` 最後加上中文關鍵字（`cim-csharp-async` 另外補了英文的使用時機）
- 若 skill 內文提到其他同樣被收錄的 skill，名稱改為對應的 `cim-` 名稱
- `cim-systematic-debugging` 移除了上游用來測試 skill 本身的開發檔案（`CREATION-LOG.md`、`test-academic.md`、`test-pressure-*.md`）

## 來源

| Skill | 上游 | 路徑 | Commit | 授權 / 版權 |
|---|---|---|---|---|
| `cim-run-tests` | [dotnet/skills](https://github.com/dotnet/skills) | `plugins/dotnet-test/skills/run-tests` | `9864ca7` | MIT, Copyright (c) .NET Foundation and Contributors |
| `cim-code-testing` | [dotnet/skills](https://github.com/dotnet/skills) | `plugins/dotnet-test/skills/code-testing` | `9864ca7` | MIT, Copyright (c) .NET Foundation and Contributors |
| `cim-test-anti-patterns` | [dotnet/skills](https://github.com/dotnet/skills) | `plugins/dotnet-test/skills/test-anti-patterns` | `9864ca7` | MIT, Copyright (c) .NET Foundation and Contributors |
| `cim-csharp-refactoring` | [dotnet/skills](https://github.com/dotnet/skills) | `plugins/dotnet/skills/csharp-refactoring` | `9864ca7` | MIT, Copyright (c) .NET Foundation and Contributors |
| `cim-dotnet-performance` | [dotnet/skills](https://github.com/dotnet/skills) | `plugins/dotnet-diag/skills/analyzing-dotnet-performance` | `9864ca7` | MIT, Copyright (c) .NET Foundation and Contributors |
| `cim-sql-code-review` | [github/awesome-copilot](https://github.com/github/awesome-copilot) | `skills/sql-code-review` | `70ddff7` | MIT, Copyright GitHub, Inc. |
| `cim-sql-impact-analysis` | [github/awesome-copilot](https://github.com/github/awesome-copilot) | `skills/sql-object-impact-analysis` | `70ddff7` | MIT, Copyright GitHub, Inc. |
| `cim-csharp-async` | [github/awesome-copilot](https://github.com/github/awesome-copilot) | `skills/csharp-async` | `70ddff7` | MIT, Copyright GitHub, Inc. |
| `cim-systematic-debugging` | [obra/superpowers](https://github.com/obra/superpowers) | `skills/systematic-debugging` | `bb92a77` | MIT, Copyright (c) 2025 Jesse Vincent |
| `cim-verification-before-completion` | [obra/superpowers](https://github.com/obra/superpowers) | `skills/verification-before-completion` | `bb92a77` | MIT, Copyright (c) 2025 Jesse Vincent |

## 更新上游

每季比對上游 commit，有重要更新時：

1. 重新複製上游資料夾。
2. 重做上面「修改內容」列出的修改。
3. 更新 `metadata.source-ref`。
4. 照一般流程發 MR。
