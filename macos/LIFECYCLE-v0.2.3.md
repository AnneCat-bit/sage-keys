# v0.2.3 · 修復授權導覽循環

**啟動桌寵、關閉導覽及試敲錄音均可在沒有輸入監察權限時使用。** 舊版留下的目標選擇和已信任 App 會保留。新版只有在使用者主動要求同步或診斷時才開啟導覽。[Apple Silicon 測試版 ZIP](https://github.com/AnneCat-bit/sage-keys/actions/runs/44975408844/artifacts/14735831083) · [完整編譯與測試](https://github.com/AnneCat-bit/sage-keys/actions/runs/44975408844) · [修復前後的程式碼](https://github.com/AnneCat-bit/sage-keys/compare/fa418331b29cd23fe7a9026fcd273fd91a8f7b69...b40225b0a9fe822446131db80c6d94c9cc6c648b)

## 根因與修改

| 雲端可核實的行為 | 修復 |
| --- | --- |
| v0.2.2 把「待處理的目標」和「下次顯示導覽」一起保存。模型載入完便自動顯示導覽，打開導覽又將恢復旗標寫成 true。用已發布的 v0.2.2 和舊偏好設定，連續兩次冷啟動都出現導覽。 | 移除自動顯示入口，升級時捨棄舊旗標；未完成的目標保留到主動續辦。冷啟動及 Finder 重開均以鍵盤小窗為先。[PetApp.swift](Sources/PetApp.swift) |
| v0.2.2 的導覽回到前景時會重查權限，卻繼續使用原先的安裝資料。實際加入另一份 App，切回舊導覽時未顯示它，手動重查才出現。舊判斷亦把路徑中任何名為 AppTranslocation 的資料夾視作隔離執行。 | 移除 InstallationCheck 快取，打開、切回和重查診斷時重新讀取。執行檔優先取自核心的 proc_pidpath。只有符合系統暫存目錄、AppTranslocation、UUID、d/ 和 bundle 執行檔結構時才提示該路徑特徵；可取得時亦列出實際掛載點及唯讀狀態。位於「應用程式」時顯示目前執行路徑。[安裝檢查](Sources/InstallationCheck.swift) |
| 藍色開關、同名副本、現有程序與未通過的權限檢查，舊畫面給出相近的搬移與重啟建議。 | 分列 PID、是否收到重開事件、其他運行中的同識別碼程序、已知副本、啟動時與目前的簽署資訊、磁碟雜湊、過去曾有效的 build 和即時權限。拒絕或開關已開時，主操作是「繼續使用桌寵」，旁邊只保留「檢查安裝與授權」。首次狀態未定可直接打開系統設定。關閉或按紅色關閉鍵即回到可試聽的鍵盤。[權限視窗](Sources/PermissionGuide.swift) |

開啟 App 或單純查閱診斷均不會開始監測。系統回報有效後仍須手動開始本次同步，獲准的目標照常驗證簽署身分。診斷只在本機將必要資料顯示給使用者。未讀取 TCC 資料庫，未記錄輸入。[拒絕時的實際畫面](evidence/v0.2.3/guide-repair.png) · [原生診斷畫面，截自 QA bundle](evidence/v0.2.3/guide-installation.png)

## 同機安裝生命週期

標準 GitHub-hosted ARM macOS Runner 下載 v0.2.2 及本次兩個 Artifact，以 ditto 解壓。測試在真正的 **/Applications/Sage Keys.app** 操作兩個原始簽署成品；Finder 開啟行為透過相同的 Launch Services API 執行。下表中的程序編號來自這一次執行。[逐步記錄](evidence/v0.2.3/release-lifecycle.json) · [可重跑的測試程式](Tests/ReleaseLifecycle/main.swift)

| 驗證 | 實際觀察 |
| --- | --- |
| 舊版與現有程序 | 舊版兩次冷啟動的 PID 是 2034、2067。再送開啟事件仍是 PID 2067。把新版移到同一路徑時，舊程序仍然存在。 |
| 副本與已運行程序 | 在測試桌面額外啟動一個新版程序 2079，診斷在「其他執行程序」實際列出舊 PID 2067，然後退出兩個程序。 |
| 確實退出及重新開啟 | 舊 PID 已結束，再打開新版得到 PID 2095，畫面只顯示桌寵。由這個程序自己的 AppKit 診斷讀到 **/Applications/Sage Keys.app/Contents/MacOS/SageKeys**、0.2.3 (5) 和目前 PID；沒有搬移提示。 |
| 取消與重啟 | 在成品按「繼續使用桌寵」後，導覽關閉。再次退出、啟動所得 PID 2105，仍只顯示桌寵。 |
| 實際 OS 與受控權限狀態 | 原生 QA 直接讀取 CGPreflightListenEventAccess 為 **false**、IOHIDCheckAccess 為 **unknown**。舊開關回報、過去有效 build／雜湊是 Runner 的 Sage Keys 測試偏好。拒絕、撤銷、IOHID 與 CG 不一致及後來授權成功採用替身；沒有替使用者操作系統授權。 |
| 資料更新、取消與手動續辦 | 在診斷可見期間新增副本，切回視窗會出現；移除後再檢查會消失。驗證五個路徑樣本。拒絕時關閉導覽、手動試敲，觀察到新的 WebGL 繪圖及 Web Audio 音源播放；重開後手動續辦保留原目標，只在手動確認後開始。[診斷與試敲](evidence/v0.2.3/guide-draft.json) · [跨程序續辦](evidence/v0.2.3/guide-restored.json) |
| 回歸 | 16 組原生檢查通過，涵蓋鍵帽、三組錄音、前景 App、信任清單、暫停、離線及退出。內置網頁、模型、字型及錄音相關檔案的雜湊與 v0.2.2 一致。[原始數據](evidence/v0.2.3/mac-results.json) |

重現方法是在此 repository 的「Actions → Sage Keys for Mac → Run workflow」選包含此測試的 main 分支，在 previous_run 填入 v0.2.2 的成功執行 44922576387（需舊 Artifact 仍可下載）。若已保存兩個原始 ZIP，工作流程中的 Tests/update-identity.sh 亦可在一次性 macOS Runner 以這兩個 ZIP 重跑。測試會在一次性 Runner 進行，若安裝路徑已被佔用會停止。完整原始檔案、QA 截圖及打包紀錄見[測試 Artifact](https://github.com/AnneCat-bit/sage-keys/actions/runs/44975408844/artifacts/14735103874)。

正式 GitHub Pages 網址在此輪重新通過工作室八項檢查及懸浮小窗測試。[工作室結果](evidence/v0.2.3/pages-studio.log) · [懸浮小窗結果](evidence/v0.2.3/pages-pip.log)

## 系統授權的界線

這兩個免費版本各自通過簽章完整性驗證，但新版不符合舊版以 CDHash 表示的指定簽署要求。相同 Bundle ID 和安裝路徑無法證明是同一個授權主體。免費測試版可以修復導覽循環、辨識現有程序與副本、如實顯示有效權限，以及提供完整離線預覽。跨版本建立可驗證的穩定發行身分，正式對外分發通常採用同一團隊的 Developer ID Application 簽署與相容的 designated requirement，並辦理 Apple 公證。公證與輸入監察是不同決定；最後仍由 macOS 和使用者批准。[兩版簽署比較](evidence/v0.2.3/signing.log) · [Apple 的簽署身分說明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

本成品為未經 Apple 公證的 ad-hoc 個人測試版。[ZIP SHA-256](evidence/v0.2.3/SHA256.txt) · [Gatekeeper 評估](evidence/v0.2.3/gatekeeper.txt)

此輪未在你的 M2 重現藍色開關對應的 TCC 記錄，亦未重現由 Finder 下載隔離觸發的真正 AppTranslocation 掛載。需要實機確認的是你的程序是否得到有效權限，以及手動啟用後外部 App 的鍵帽與聲音能否恢復。當系統仍未允許時，可以直接繼續使用本機鍵盤和試聽。
