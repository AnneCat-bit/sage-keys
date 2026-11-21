# Sage Keys for Mac v0.2.0 個人測試版

本版修復隱藏後重新開啟與退出，加入可選擇保存的已簽署 App 清單。首次保存要明確勾選。每次啟動及隱藏後恢復視窗，跨 App 同步均保持關閉。網頁版繼續使用原有 Pages 網址。[Finder 更新及操作](README.md) · [Apple Silicon ZIP 的 GitHub Artifact](https://github.com/AnneCat-bit/sage-keys/actions/runs/44916100751/artifacts/14711602046) · [編譯與驗收記錄](https://github.com/AnneCat-bit/sage-keys/actions/runs/44916100751) · [原始驗收 Artifact](https://github.com/AnneCat-bit/sage-keys/actions/runs/44916100751/artifacts/14711897277)

## 視窗與前景切換

舊版的紅色關閉鍵經 windowShouldClose 將 NSPanel 移出畫面，accessory 程序與選單列仍在。Finder 再開同一份 App 時會交給現有程序，而舊版缺少 reopen delegate。v0.2 在 applicationShouldHandleReopen 還原既有 NSPanel，選單列沿用同一路徑處理隱藏及縮小。選單的真正退出先停止同步、完成有時限的 WebKit 清理，再結束程序。

只有在使用者開啟本次同步後，才訂閱 NSWorkspace.frontmostApplication 的變更。以 Security.framework 驗證目前運行程序的簽署識別碼、Apple 或第三方 Team 身分，再比對使用者保存的 designated requirement。檢查失敗時保持待命。本次允許只認同一個還在運行的程序。權限或安全工作階段失效時結束本次同步，清除按住集合。確認框、清單管理入口均列出整個 App 的範圍，包括瀏覽器的所有網站。[Apple 的前景程序 API](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) · [簽署要求說明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) · [動態簽署檢查](https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:))

## 驗收證據

編譯提交 `15e3042`，標準 GitHub macos-15 arm64 Runner，實際系統 Version 15.8.2 (Build 24H232)。簽章驗證後解壓啟動個人測試版，再使用同一套正式源碼另編 QA App 觀察 AppKit 和 WebKit。共 16 組檢查，以及兩次獨立程序的退出／重啟。此 Launch Services 測試程序的真實 TCC preflight 為 false，正式 KeyMonitor 啟動被拒，沒有系統鍵盤事件進入程式。正向切換案例注入只有開關狀態的 QA 測試替身，無法接收按鍵。 此替身、取樣探針與測試腳本均未打進下載用 App。較早的 v0.2 編譯在取得 Runner 系統授權的環境中，實際建立並移除了 listenOnly tap。[此版結果 JSON](evidence/v0.2/mac-results.json) · [早期 v0.2 原生 API 執行](https://github.com/AnneCat-bit/sage-keys/actions/runs/44914592042)

| 測試 | 操作及結果 |
| --- | --- |
| 首次啟動、紅色關閉鍵、選單列 | 解包後啟動 arm64 程序。QA 在非啟用式 400 × 250 NSPanel 上按原生關閉鍵，再從「顯示桌寵」恢復。隱藏時監測、前景觀察及保護計時器已停。 |
| Finder 對應的重新開啟路徑 | 再次隱藏後，透過 Launch Services 打開同一份 bundle。觀察到 1 次 reopen callback，原 PID 和原面板均被重用，縮小後也能從選單恢復。模擬按住 A 關窗前有 396 個顯著變化像素，恢復後為 0，WebGL context 共 1 個。 |
| 真正退出及重新啟動 | 按選單「退出 Sage Keys」結束 PID 4046，外部測試程序確認舊 PID 已消失才重新啟動。新 PID 4060 的面板可見，已儲存的 TextEdit 仍在，切回 TextEdit 後也沒有自行開啟同步。[退出前](evidence/v0.2/quit-active.json) · [新程序](evidence/v0.2/restart-off.json) |
| 授權與清單 | 操作真實 NSAlert 的取消、預設不勾選及勾選保存。從 UserDefaults 重載兩個識別、刪除當前目標及清空，均符合預期。同名同 Bundle ID 但簽署要求不合的測試資料，以及 ad-hoc QA 程序，都未取得持久信任。 |
| 前景自動跟隨 | 讓真正的 TextEdit → Calculator → Finder → TextEdit 依次取得前景。兩個已保存的 Apple App 可跟隨，未允許的 Finder 進入待命，再次回到 TextEdit 才恢復。暫停後切換不會重啟。 |
| 第三方簽署 | 在 Runner 的 Google Chrome 程序上驗證 `com.google.Chrome`、`Team EQHXZ8M8AV` 和簽署要求，測試清單儲存、重讀、驗證及移除。一次識別與重讀驗證共 0.201 秒。 |
| 系統保護 | 實際開啟 Carbon Secure Event Input，確認停用，解開保護後仍未自動監測。以測試開關分別在運作和待命時模擬撤銷授權，均清除即時狀態、取消訂閱和計時器。另驗證模擬睡眠通知與實際關窗。 |
| 3D、聲音、離線 | WKWebView 自 bundle 載入，離線模型兩鍵按壓改變 2768 個像素、單鍵 326、放開 0。三種錄音在 running 的 AudioContext 有非零混音峰值。Rainy 75、HHKB Topre、MX Brown 分別為 0.4570、0.3930、0.0545。實際清理後 AudioContext 關閉、WebGL 釋放、畫布數量 0。 |
| 網頁版 | 正式 Pages 子路徑及 18 個公開資源逐一核對。雲端 Chromium 工作室八組回歸和 Document PiP 回歸通過，涵蓋輸入組字、錄音與原畫布往返。[工作室 log](evidence/v0.2/pages-studio.log) · [小窗 log](evidence/v0.2/pages-floating.log) |

## 靜置與耗用量

已信任 App 靜置及未允許 App 待命各觀察 4.2 秒，兩段新增的 draw call、requestAnimationFrame 及音源啟動均為 0。另在關閉同步時觀察 2.3 秒，新增 draw call 與動畫請求均為 0。以下是同一次 Runner 讀取 ps 累積 CPU 時間與 RSS 的短時取樣。100% 代表一個核心。CPU 為按區間長度加權平均，RSS 為各區間中位數，以 MiB 計。WebKit 欄合計啟動測試後出現的 WebKit 服務，其記憶體可包含共享頁。[原始 CSV](evidence/v0.2/process.csv) · [取樣方法](Tests/processes.py)

| 情境 | 取樣區間 | 原生 CPU | WebKit CPU | 原生 RSS | WebKit RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 關閉同步，顯示桌寵 | 6 | 0.31% | 1.25% | 87.0 | 167.5 |
| 已信任 App，靜止 | 7 | 0.25% | 0.00% | 86.2 | 170.4 |
| 未信任 App，待命 | 7 | 0.00% | 0.26% | 86.2 | 170.2 |
| 15 FPS，24 次模擬敲擊 | 5 | 1.37% | 10.24% | 87.0 | 170.2 |
| 30 FPS，24 次模擬敲擊 | 5 | 1.49% | 11.92% | 87.0 | 168.9 |

打字測試經本機 Swift → WebKit 橋接，每組 24 次固定模擬敲擊。15／30 FPS 設定下分別繪製 45／92 幀。Runner 數據不代表 M2 的 GPU 功率、電池續航或長時間溫度。[v0.1 歷史結果](TESTING.md)

## 更新與實機驗收

Apple Silicon、最低 macOS 13，Bundle ID 沿用 `io.github.annecat-bit.sagekeys`，版本 0.2.0（build 2）。從 GitHub 重新下載並核對內層 ZIP 與 bundle 的封裝資源。ZIP 大小 675,714 bytes。[SHA-256](evidence/v0.2/SHA256.txt)

v0.1 與 v0.2 的 ad-hoc CDHash 分別為 `032ba9cdb70a410387ec9f17edb673b68ca5ddff`、`5b09e5c23be1da875aaf1317122d6313d76143af`。新版 Gatekeeper assessment 回報 rejected。這是未經 Developer ID 簽署或 Apple 公證的個人測試版。舊版輸入監察授權是否可沿用，須在更新的 Mac 上確認。更新前先退出舊程序，再從 Finder 取代「應用程式」內的副本。[新版簽署及 Gatekeeper 記錄](evidence/v0.2/gatekeeper.txt) · [安裝與授權](README.md)

仍需以目標 MacBook 驗收 Finder 實際雙擊、下載隔離與單一 App 核准、TCC 授權與撤回、Word／ChatGPT／Ulysses 及中文輸入法的跨程序實體按鍵、真實鎖屏睡眠、全螢幕與 Spaces，以及長時間耗電。Runner 驗證了 Launch Services 對同一 bundle 的重新開啟，未以滑鼠操作 Finder 或替使用者核准系統權限。瀏覽器的網站和密碼欄無法逐一辨識，輸入敏感資料前應先暫停。
