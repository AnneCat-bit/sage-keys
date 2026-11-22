# Sage Keys for Mac

Sage 75 是一個 Apple Silicon 原生選單列桌寵，支援 macOS 13 或更新版本。以 AppKit 非啟用式小窗搭配系統 WKWebView，預設內容區 400 × 250。模型、字型與三組真實錄音均內置，可在離線時使用。[v0.2.3 導覽循環修復與成品實測](LIFECYCLE-v0.2.3.md) · [v0.2 效能紀錄](TESTING-v0.2.md) · [素材與授權](ASSETS.md) · [網頁工作室](https://annecat-bit.github.io/sage-keys/)

## 下載及安裝個人測試版

**[下載已驗證的 Apple Silicon Artifact](https://github.com/AnneCat-bit/sage-keys/actions/runs/44975408844/artifacts/14735831083)** · [對應的成功編譯](https://github.com/AnneCat-bit/sage-keys/actions/runs/44975408844) · [內層 ZIP 的 SHA-256](evidence/v0.2.3/SHA256.txt)

1. **更新前先從舊版的選單列鍵盤圖示選「退出 Sage Keys」，等圖示消失。** 紅色關閉鍵只會隱藏視窗。
2. 在已登入 GitHub 的瀏覽器開啟上方已驗證的編譯，選 **Artifacts → Sage-Keys-arm64-personal-test**。下載外層 ZIP 後，在 Finder 解壓縮，裡面有 `Sage-Keys-arm64.zip` 與 `SHA256.txt`。再解開前者，將 **Sage Keys.app** 拖入「應用程式」，更新時選「取代」。
3. 在「應用程式」雙擊 **Sage Keys**。這是 **B 級個人測試版**，採 ad-hoc 簽署，沒有 Developer ID 或 Apple 公證。Runner 已驗證打包後的簽章與啟動。來自網路的副本會接受你自己的 Gatekeeper 評估。
4. 若 macOS 只因無法驗證開發者而攔截，而你已核對來源並決定測試，可在嘗試開啟後，到「系統設定 → 私隱與保安」找到這個 App 的**仍要打開**，按系統提示確認。此選項只針對你選定的 App。若系統指檔案損壞、發現惡意軟件，或管理政策沒有提供核准選項，請停止安裝。[Apple 的單一 App 開啟指引](https://support.apple.com/zh-hk/guide/mac-help/mh40616/mac) · [Apple 安全警示說明](https://support.apple.com/zh-hk/102445)
5. 開啟後可先在選單列鍵盤圖示選「試敲空白鍵」。預覽可以在未授權輸入監控時使用。個人測試版的下載、解壓縮、安裝及退出均可在圖形介面操作。

Actions Artifact 保留 30 天。到期後可在此 repository 的 **Actions → Sage Keys for Mac → Run workflow** 重建，選取新的成功執行下載。每次編譯的簽章識別可能改變，更新後 macOS 可能要求重新授權。[編譯工作流程](https://github.com/AnneCat-bit/sage-keys/actions/workflows/sage-keys-macos.yml) · [GitHub 下載說明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## 使用桌寵

- 拖動原生標題列移動視窗，拖邊緣調整大小。鍵盤模型可拖動旋轉、滾動縮放。在「•••」或選單列可選俯視、置頂、音色及 15／30 FPS。首次啟動預設省電 15 FPS，像素比上限為 1。標準模式上限為 30 FPS 和 1.25。
- 第一次使用時，先點選要同步的 App，再按桌寵「同步」。確認名稱、Bundle ID、簽署者與授權範圍。直接按「允許並開始同步」只授權這一次運行的程序。要記住它，先勾選「記住此 App」。加入下一個 App 可用「••• → 管理已信任 App → 允許目前 App」。無法驗證簽署者時只提供本次允許。
- 已有信任清單後，每次啟動仍顯示「同步已關閉」。手動按「同步」後，桌寵才會跟隨已批准的前景 App。未批准的 App 會顯示「未允許」並卸下監測。回到已信任 App 可在同一次同步中繼續。點「暫停」會清除本次允許和所有按住鍵位，保留你選擇記住的 App。
- 在「管理已信任 App」選名稱，可檢視 Bundle ID、簽署者、移除此 App，或在清單底部清空全部。移除目前目標會立即停止對它的同步。若 App 更換簽署者或不再符合原來的簽署要求，需要再次明確批准。[Apple 程式碼簽署身分說明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- **信任 Chrome 會涵蓋整個瀏覽器及其所有網站。** 桌寵不檢查網址或文字欄。系統啟用 Secure Event Input 時會停止同步，但並非每個密碼欄都會啟用它。輸入敏感資料前請先暫停。
- 啟動和 Finder 重開會先回到鍵盤。若系統權限仍未生效，可直接關閉導覽或按「繼續使用桌寵」，從選單「試敲空白鍵」使用原有聲音與鍵帽。未完成的選擇只在手動續辦時使用。在「檢查安裝與授權」可查看目前程序的路徑、簽署及權限回報。[根因與實測](LIFECYCLE-v0.2.3.md)
- 按紅色關閉鍵、縮小、隱藏、睡眠、鎖定、撤銷權限或退出，都會停用同步。要找回小窗，可從 Finder 雙擊同一份 App，或在選單列選「顯示桌寵」。顯示後先維持關閉同步。要真正結束程序，選「退出 Sage Keys」。登入時啟動由你自行選擇，預設關閉。

## 離線與私隱實作

`Sources/` 負責 NSPanel、選單列、授權、資產來源限制及單一 WKWebView。`Web/` 重用 repository 的鍵位、三維模型、局部重繪與 Web Audio。編譯時將模組連結為一個隨附的 JavaScript 檔，三個 WAV 與切片索引直接包含在其中。WebKit 僅能讀取 bundle 中的 Pet 目錄，使用非持久資料儲存。內容安全政策封鎖網絡連線，導覽白名單只接受自己的入口檔。

跨 App 開關每次啟動均為關閉。Core Graphics session event tap 使用 `listenOnly`，在已允許的前景程序、權限及工作階段檢查通過後，才讀取受支援的虛擬鍵碼與修飾狀態。鍵盤配置採 ANSI Sage 75 的 82 個位置。Swift 向本地顯示層傳遞當下按住的集合，同時最多一個鍵位更新在 WebKit 傳送中。顯示程序繁忙時合併至最新狀態，極短的重疊敲擊可能被略過。部分 Fn、媒體鍵及不同 ISO／JIS 配列需要另行驗證。Caps Lock 表示鎖定狀態。

沒有文字、IME、剪貼簿、逐鍵歷史、時間戳或鍵盤紀錄檔。本次允許只存在記憶體。明確勾選記住的 App 在本機偏好設定保存顯示名稱、Bundle ID、已核實的 Apple／Team 身分與 designated requirement。Sage Keys 不會將清單傳送出去。其餘偏好為音色、靜音、畫質、視角、置頂及視窗位置。系統權限與登入項目由 macOS 管理。跨 App 模式關閉時沒有全域鍵盤輪詢。手動同步期間訂閱 NSWorkspace 的 frontmostApplication 變更處理前景切換，重新檢查符合 Bundle ID 的簽署身分。每次處理實體按鍵前再核對前景程序、權限與安全輸入。另有每 1.5 秒的保護檢查，讓待命或沒有按鍵時也能停用已失去授權的同步。暫停時一併移除這個計時器與前景通知訂閱。

## 發行與相容性

| 分級 | 狀態 |
| --- | --- |
| A 編譯原型 | 標準 GitHub-hosted macOS ARM64 Runner 編譯、打包及啟動。 |
| B 個人測試 | 提供可下載 ZIP、SHA-256、實測結果及單一 App 核准指引。實際能否安裝取決於裝置政策與 Gatekeeper。 |
| C 正式發行 | 尚欠 Developer ID 簽署、Apple 公證及下載後的實機安裝驗收。 |

最低部署目標為 macOS 13。已執行的系統版本和待驗項目列於測試報告。Chrome 網頁版的 Document Picture-in-Picture 與此原生視窗可分別使用。[原始可行性研究](../docs/MACOS-FEASIBILITY.md)
