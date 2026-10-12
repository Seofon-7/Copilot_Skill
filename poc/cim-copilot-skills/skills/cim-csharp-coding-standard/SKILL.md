---
name: cim-csharp-coding-standard
description: CIM 課 C#/.NET 程式撰寫規範（命名、例外處理、非同步、日誌、設定）。在撰寫、修改或重構 C# 程式碼、新增類別或服務時使用。Keywords - C#, .NET, coding standard, naming, async, logging, exception handling, 程式規範, 命名規則.
metadata:
  owner: "CIM Skills Maintainers"
---

# CIM C# 程式撰寫規範

> 這是 POC 範例內容，正式發佈前請換成課內實際規範。

## 何時套用

- 撰寫或修改任何 C# 程式碼
- 新增類別、服務、Web API、Windows Service
- 使用者要求「依照課內規範」重構程式碼

## 命名

- 類別、方法、屬性、事件：PascalCase
- 區域變數、參數：camelCase
- 私有欄位：`_camelCase`
- 介面以 `I` 開頭，例如 `IEquipmentClient`
- 非同步方法以 `Async` 結尾，例如 `GetLotInfoAsync`
- 常數：PascalCase，不使用全大寫底線

## 例外處理

- 禁止空的 `catch { }`
- 只捕捉能處理的例外；其餘往上拋，並用 `throw;` 保留 stack trace（不要 `throw ex;`）
- 呼叫外部系統（設備、MES、資料庫）失敗時，日誌要帶上足以追查的上下文，例如設備 ID、批號、交易 ID

## 非同步

- I/O 作業一律 `async`/`await`，不使用 `.Result`、`.Wait()`
- 函式庫程式碼使用 `ConfigureAwait(false)`
- 可能長時間執行的作業要接受 `CancellationToken`

## 日誌

- 使用專案既有的 logger（例如 `ILogger<T>`），不要用 `Console.WriteLine`
- 使用結構化日誌：`logger.LogInformation("Lot {LotId} moved to {Step}", lotId, step);`
- 不可記錄密碼、token、個人資料

## 設定與機密

- 連線字串、IP、帳號密碼放設定檔或機密管理機制，不可寫死在程式碼裡

## 產生程式碼的步驟

1. 先確認專案的目標框架（.NET Framework 4.x 或 .NET 8 以上），只使用該版本支援的語法。
2. 依照上述規範產生程式碼。
3. 若既有程式碼不符規範，先指出問題；除非使用者要求，不要大幅改寫和本次需求無關的程式碼。
