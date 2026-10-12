---
name: cim-code-review
description: 依 CIM 課檢查清單審查程式碼變更（正確性、例外處理、效能、資安、可維護性），並依嚴重度分級列出建議。在使用者要求 code review、檢查 MR/PR、審查 diff 或檢查某段程式碼時使用。Keywords - code review, review, merge request, pull request, diff, 程式審查, 檢查程式碼.
metadata:
  owner: "CIM Skills Maintainers"
---

# CIM Code Review

> 這是 POC 範例內容，檢查項目請依課內實際經驗調整。

## 步驟

1. 確認審查範圍：使用者指定的檔案、貼上的 diff，或目前分支相對於 main 的變更。範圍不清楚時先問。
2. 先讀懂變更的目的，再逐項對照 [檢查清單](references/checklist.md)。
3. 只評論這次變更相關的程式碼；既有問題可以另外列在「順帶一提」。
4. 依下面的格式輸出。

## 輸出格式

```
## 總結
<一到兩句：這次變更做了什麼，整體是否可以合併>

## 必須修改（Blocker）
- [檔案:行號] 問題說明 → 建議改法

## 建議修改（Major / Minor）
- [檔案:行號] 問題說明 → 建議改法

## 順帶一提（非本次變更）
- ...
```

## 原則

- 每個問題都要說明「為什麼是問題」和「建議怎麼改」，必要時附上修改後的程式碼片段。
- 不確定的地方標註「需要確認」，不要當成確定的錯誤。
- 沒有問題的類別不用硬寫。
