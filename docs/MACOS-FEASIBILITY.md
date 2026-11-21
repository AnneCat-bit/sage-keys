# macOS 桌面版可行性研究

**研究結論（2026 年 11 月 21 日）**　可在獨立的 macOS App 內重用網頁鍵盤、聲音和設定介面。要在 Word、其他網站或其他 macOS App 打字時同步顯示按鍵，則涉及系統級權限，須另外驗證。這一階段交付的是文件。現行 GitHub Pages 網頁的互動範圍是取得焦點的頁面。

## 視窗與離線資產

| 部件 | 建議方案與待驗證事項 |
| --- | --- |
| 主視窗 | 以 SwiftUI 管理偏好與狀態，內嵌系統的 WKWebView。將網頁、3D 程式、字型及 CC0 音效隨 App 打包，啟動後可離線使用。無須使用者安裝開發工具。[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) |
| 資產載入 | 先試從 App bundle 的專用資產目錄載入，讀取範圍限該目錄。逐項測試 JavaScript 模組、WebGL 紋理與供 Web Audio 使用的 WAV 請求。若檔案來源限制影響模組或取樣，可研究自訂網域協定，僅對應固定的內建資產清單。使用者的其他檔案與資料夾不在讀取範圍。[限制檔案讀取範圍](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29) · [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler) |
| 浮動鍵盤 | AppKit 的 NSPanel 可作小型顯示窗，nonactivatingPanel 可避免啟用所屬 App。預設面板在所屬 App 離開前景時會隱藏，因此須分別驗證跨 App 可見性、視窗層級與鍵盤焦點。浮窗只顯示鍵盤，編輯偏好由主視窗負責。全螢幕、Spaces、Stage Manager 及多螢幕的行為需實測。[NSPanel](https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel) · [不啟用 App 的面板](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) |

SwiftUI 可用 `NSViewRepresentable` 管理一個 WKWebView，顯示層在全尺寸與浮窗間共用。若之後提供原生偏好設定，應只傳遞列舉值和數字給本機頁面，避免拼接任意 JavaScript 字串。當 WebView 終止或重載時，清除按鍵狀態並重建單一顯示層。[Apple NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)

## 輸入範圍與使用者選擇

初次啟動採 App 內互動模式，在自己的視窗內處理鍵盤與輸入法。離線資源載入和顯示浮窗本身無須讀取其他 App 的鍵盤事件。單是把網頁裝入 WKWebView，所屬 App 並不會因此獲得讀取 Word 事件的權限。

跨 App 模式應由使用者每次明確開啟。開啟前說明，即使只取得物理鍵位，觀察按鍵順序也可能推斷輸入內容。Apple 將跨 App 的唯讀鍵盤監察歸於「輸入監控」，修改或發送事件則涉及另一種授權。Apple 的 AppKit 全域事件監察文件另載有輔助使用權限條件，不能推定所有 API 有相同的要求。候選方案只評估唯讀途徑，在每個目標系統版本實測權限對話框。若所選途徑索求更廣的權限，應停留在 App 內互動模式。[Apple 對唯讀與修改事件的說明](https://developer.apple.com/videos/play/wwdc2019/701/) · [Apple 輸入監控設定](https://support.apple.com/en-bn/guide/mac-help/mchl4cedafb6/mac) · [AppKit 文件](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)

權限流程會依下列步驟運作。

1. 使用者選取「跨 App 同步」才解釋用途並提出系統請求。授權前、拒絕或撤銷後均可繼續使用 App 內鍵盤。
2. 同步期間，浮窗與選單列均清楚顯示狀態，提供單次操作即可暫停的控制。隱藏浮窗、鎖定、睡眠或退出時結束觀察並清空即時按鍵。恢復顯示後由使用者再次選擇是否啟用。
3. 碰到系統安全輸入或失去可用性時，停止跨 App 回饋並重設鍵帽。Apple 的「終端機」安全輸入會保護其鍵盤輸入。各 App 的密碼欄保護程度及可偵測狀態須分開測試，不能向使用者保證自動識別所有私人欄位。可隨時手動暫停，遇到不確定的狀態應保守停用。[Apple 安全鍵盤輸入說明](https://support.apple.com/zh-hk/guide/terminal/trml109/mac)

## 按鍵狀態與隱私

App 內可評估 `NSEvent.keyCode`。跨 App 的候選技術為 Core Graphics 唯讀 event tap（`listenOnly`），提取按下、放開與修飾鍵變化及其鍵位欄位，立即映射到允許的模型按鍵。這些是作業系統提供的虛擬鍵碼，ANSI、ISO、JIS 及被重新映射的鍵盤需分別驗證。每次狀態變動只向本地 WebView 傳遞當前按住集合的差異，規格不需存取 `characters`、Unicode 或輸入法結果。[Apple NSEvent.keyCode](https://developer.apple.com/documentation/appkit/nsevent/keycode) · [唯讀 tap](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly) · [鍵位欄位](https://developer.apple.com/documentation/coregraphics/cgeventfield/keyboardeventkeycode)

只在記憶體保留目前按下的受支援鍵位及瞬時動畫狀態，放開即移除。向離線繪圖層提供有界的鍵位狀態，不把原始作業系統事件交給網頁。快速連打、左右修飾鍵與同時按鍵要一起驗證。系統快捷鍵、繁體中文候選字處理及文件編輯都交由正在輸入的 App 負責。

此路徑不需要文字、Unicode 字元、輸入法組字、剪貼簿、視窗內容或文件存取。禁止保留按鍵次序、次數明細或逐鍵時間戳，也不應將資料放入除錯日誌、分析、崩潰附件、網絡或儲存空間。偏好僅限音量、音色、畫質及浮窗位置。應封鎖 WebView 對外導覽及外部資源請求，並在離線和可連網兩種環境核對實際行為。

## 能耗與發布

採用按需繪圖和按鍵回彈結束即停止更新。浮窗需要在 Word 取得焦點時顯示，因此要以「浮窗是否可見、同步是否啟用」決定工作量，不能單憑主視窗失焦判斷。隱藏、休眠或暫停後應停止繪圖及音效。WebKit 內容與 GPU 程序可能有獨立記憶體開銷，現有網頁的 Linux 數據無法估算它們在 MacBook 上的耗電。

若日後公開提供下載，Developer ID 簽署、Hardened Runtime 與 Apple 公證是應評估的直接發行路徑。Apple Developer Program 公布的標準年費為 99 美元，按地區以當地貨幣結算。實際費用、現有會員資格、簽章持有人、發布方式及支援版本仍待確認。收費資格或成本未確認前，可停留在本研究與免費網頁階段。[Developer ID](https://developer.apple.com/developer-id/) · [公證要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [會員年費](https://developer.apple.com/help/account/membership/program-enrollment)

## 下一階段的實機驗證

在另行同意的 macOS 測試機及專用測試帳戶執行，由開發端準備環境。以下均為待驗證項目。

| 驗證項目 | 通過條件 |
| --- | --- |
| 離線啟動 | 中斷網絡後，冷啟動可見鍵盤、三種錄音可播放、視角可操作。重新連線後檢查封包，產品內容沒有外部資源請求。 |
| 權限生命週期 | 全新安裝、拒絕、允許、執行中撤銷、重新啟動五種情況均有清楚狀態。本身輸入功能可獨立使用，撤銷後立即清除即時狀態。 |
| 浮窗與輸入法 | 在 Word、瀏覽器及 TextEdit 輸入預設的非私人測試字串。檢驗左右 Shift、Command 組合、多鍵、倉頡／速成／拼音選字及快捷鍵。測試浮窗開啟時仍由文件接收文字。 |
| 安全輸入與異常 | 用專用測試帳戶開啟安全輸入、切換 App、睡眠喚醒、終止 WebKit 內容程序。保護生效時無跨 App 回饋，恢復時不重播或殘留鍵帽。 |
| 效能 | 在同一部電池供電的 MacBook，固定亮度，記錄機型、OS 版本及畫質。比較只開 Word 的基線，以及浮窗靜止、固定節奏打字、隱藏浮窗各 5 分鐘，重複三次。量測 App 與相關 WebKit 程序的 CPU、記憶體、Energy Impact 及動畫幀數，回報中位數與尖峰。Energy Impact 是相對指標，不能換算成電池續航。[活動監視器](https://support.apple.com/guide/activity-monitor/welcome/mac) · [耗電指標說明](https://support.apple.com/en-is/guide/activity-monitor/actmntr43697/mac) |
| 發行 | 在全新測試環境從下載到啟動檢查 Gatekeeper、公證、更新後權限，以及完全離線的日常操作，另外確認下載者毋須安裝 Xcode 或執行終端機指令。 |
