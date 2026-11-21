# Sage Keys for Mac

Sage 75 是一個 Apple Silicon 原生選單列桌寵，支援 macOS 13 或更新版本。以 AppKit 非啟用式小窗搭配系統 WKWebView，預設內容區 400 × 250。模型、字型與三組真實錄音均內置，可在離線時使用。[測試與效能](TESTING.md) · [素材與授權](ASSETS.md) · [網頁工作室](https://annecat-bit.github.io/sage-keys/)

## 下載及安裝個人測試版

**[下載已驗證的 Apple Silicon Artifact](https://github.com/AnneCat-bit/sage-keys/actions/runs/44912535484/artifacts/14710202421)** · [對應的成功編譯](https://github.com/AnneCat-bit/sage-keys/actions/runs/44912535484) · [內層 ZIP 的 SHA-256](evidence/SHA256.txt)

1. 在已登入 GitHub 的瀏覽器開啟下方已驗證的編譯，選 **Artifacts → Sage-Keys-arm64-personal-test**。下載外層 ZIP 後，在 Finder 解壓縮，裡面有 `Sage-Keys-arm64.zip` 與 `SHA256.txt`。再解開前者，將 **Sage Keys.app** 拖入「應用程式」。
2. 在「應用程式」雙擊 **Sage Keys**。這是 **B 級個人測試版**，採 ad-hoc 簽署，沒有 Developer ID 或 Apple 公證。Runner 已驗證打包後的簽章與啟動。來自網路的副本會接受你自己的 Gatekeeper 評估。
3. 若 macOS 只因無法驗證開發者而攔截，而你已核對來源並決定測試，可在嘗試開啟後，到「系統設定 → 私隱與保安」找到這個 App 的**仍要打開**，按系統提示確認。此選項只針對你選定的 App。若系統指檔案損壞、發現惡意軟件，或管理政策沒有提供核准選項，請停止安裝。[Apple 的單一 App 開啟指引](https://support.apple.com/zh-hk/guide/mac-help/mh40616/mac) · [Apple 安全警示說明](https://support.apple.com/zh-hk/102445)
4. 開啟後可先在選單列鍵盤圖示選「試敲空白鍵」。預覽可以在未授權輸入監控時使用。個人測試版的下載、解壓縮、安裝及退出均可在圖形介面操作。

Actions Artifact 保留 30 天。到期後可在此 repository 的 **Actions → Sage Keys for Mac → Run workflow** 重建，選取新的成功執行下載。每次編譯的簽章識別可能改變，更新後 macOS 可能要求重新授權。[編譯工作流程](https://github.com/AnneCat-bit/sage-keys/actions/workflows/sage-keys-macos.yml) · [GitHub 下載說明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## 使用桌寵

- 拖動原生標題列移動視窗，拖邊緣調整大小。鍵盤模型可拖動旋轉、滾動縮放。在「•••」或選單列可選俯視、置頂、音色及 15／30 FPS。首次啟動預設省電 15 FPS，像素比上限為 1。標準模式上限為 30 FPS 和 1.25。
- 要與 Word、Chrome、ChatGPT、Ulysses、TextEdit 或另一款一般 App 同步，**先點選該 App 讓它成為前景，再按桌寵的「同步」**，核對對話框內的 App 名稱並確認。選單列會顯示「同步」或「待命」。若切換至另一個 App，需要時選「允許另一個目前 App」。
- 首次由 macOS 詢問「輸入監控」。若拒絕，桌寵會暫停。你也可以到「系統設定 → 私隱與保安 → 輸入監控」為 Sage Keys 選擇授權。如系統要求，退出並重開，再手動開啟同步。[Apple 輸入監控說明](https://support.apple.com/zh-hk/guide/mac-help/mchl4cedafb6/mac)
- 點小窗「暫停」、選單列「立即暫停同步」或「隱藏並暫停」會移除監測並清除鍵位及本次允許清單。關閉小窗後可從選單列再顯示。**完全退出**請選「退出 Sage Keys」。登入時啟動預設關閉，可自行在選單切換，系統可能另要求核准登入項目。
- 系統標示安全鍵盤輸入、鎖定、切換使用者、睡眠或監測失效時，桌寵會停用同步。**在未確認有安全輸入保護的網站或 App 輸入密碼前，先按暫停**。本版不檢查畫面、網頁網址或文字欄內容，無法自動識別每一個敏感欄位。切換網站不會改變瀏覽器的程序身分。

## 離線與私隱實作

`Sources/` 負責 NSPanel、選單列、授權、資產來源限制及單一 WKWebView。`Web/` 重用 repository 的鍵位、三維模型、局部重繪與 Web Audio。編譯時將模組連結為一個隨附的 JavaScript 檔，三個 WAV 與切片索引直接包含在其中。WebKit 僅能讀取 bundle 中的 Pet 目錄，使用非持久資料儲存。內容安全政策封鎖網絡連線，導覽白名單只接受自己的入口檔。

跨 App 開關每次啟動均為關閉。Core Graphics session event tap 使用 `listenOnly`，在已允許的前景程序、權限及工作階段檢查通過後，才讀取受支援的虛擬鍵碼與修飾狀態。鍵盤配置採 ANSI Sage 75 的 82 個位置。Swift 向本地顯示層傳遞當下按住的集合，同時最多一個鍵位更新在 WebKit 傳送中。顯示程序繁忙時合併至最新狀態，極短的重疊敲擊可能被略過。部分 Fn、媒體鍵及不同 ISO／JIS 配列需要另行驗證。Caps Lock 表示鎖定狀態。

沒有文字、IME、剪貼簿、逐鍵歷史、時間戳或鍵盤紀錄檔。允許清單只存在本次同步的記憶體中。持久資料為音色、靜音、畫質、視角、置頂及視窗位置。系統權限與登入項目由 macOS 管理。跨 App 模式關閉時沒有全域鍵盤輪詢。監測運作期間另有低頻授權及工作階段檢查，可在沒有新鍵盤事件時停用監測。

## 發行與相容性

| 分級 | 狀態 |
| --- | --- |
| A 編譯原型 | 標準 GitHub-hosted macOS ARM64 Runner 編譯、打包及啟動。 |
| B 個人測試 | 提供可下載 ZIP、SHA-256、實測結果及單一 App 核准指引。實際能否安裝取決於裝置政策與 Gatekeeper。 |
| C 正式發行 | 尚欠 Developer ID 簽署、Apple 公證及下載後的實機安裝驗收。 |

最低部署目標為 macOS 13。已執行的系統版本和待驗項目列於測試報告。Chrome 網頁版的 Document Picture-in-Picture 與此原生視窗可分別使用。[原始可行性研究](../docs/MACOS-FEASIBILITY.md)
