# Sage Keys 專案交接：網頁版保留，原生版凍結

整理日期：2026-11-22（香港時間）。整理前的 repository 基準提交：`e397964fe46b5f3a6dd29d1f866bde0ffd3027b8`。

**這是一份文件交接，不是恢復開發或發行的指令。** 新的 Codex 工作階段先閱讀本文件，再按問題查閱所連結的原始來源。無需取得先前聊天內容即可理解目前成果、證據界線與下一步條件。若較早文件仍建議重新安裝、重建或開發桌面版，應按其歷史版本理解；目前原生版凍結要求優先。

本次「封存」指整理並保存進度，沒有把 GitHub repository 設為唯讀 Archived，也沒有刪除或停用既有內容、Release 或工作流程。本輪僅新增本文件。

## 1. 專案位置及目前成果

| 項目 | 目前狀態與來源 |
| --- | --- |
| Repository | [AnneCat-bit/sage-keys](https://github.com/AnneCat-bit/sage-keys)，主要分支 `main`。不得操作其他 repository。 |
| GitHub Pages 網頁版 | 已完成並保留：[正式網站](https://annecat-bit.github.io/sage-keys/)。使用原生 HTML、CSS、JavaScript、隨附的 Three.js；Pages 從 `main` 的根目錄發布，使用相對資產路徑。[總覽](../README.md) |
| Sage 75 模型 | 程序化真正 3D、82 鍵 Mac 風格配置、鼠尾草綠外觀、單鍵按壓與回彈、立體／俯視、旋轉縮放。不是鍵盤圖片。[模型](../src/model.js) · [繪製與相機](../src/view.js) |
| 聲音與站內輸入 | Rainy 75、HHKB Topre、Cherry MX Brown 三套真實錄音保留；原生 textarea 處理文字與 IME，實體 `code` 驅動模型。錄音來源、CC0 核對與切片時間見 [AUDIO.md](AUDIO.md)。作者沒有逐鍵標註，Space／Enter／Backspace 是本專案的片段分配，不能聲稱已辨認原錄音的真實鍵名。 |
| Chrome 懸浮模式 | Document Picture-in-Picture 已實作。請求內容區約 400 × 250，可調整大小；小窗與主頁共用原畫布和 WebGL context，不同時運行兩套 3D。[懸浮實作](../src/floating.js) · [互動驗收](INTERACTION-REPAIR.md) |
| macOS 原生 App | **凍結於 v0.2.4，build 6。** AppKit 非啟用式面板、WKWebView、內置離線模型與錄音。屬未經 Developer ID 簽署及 Apple 公證的 ad-hoc 個人測試版。[原生版說明](../macos/README.md) |
| DMG 安裝 | 已完成標準 DMG，包含 App 與 Applications 捷徑，保留鼠尾草綠手繪安裝版面。雲端 Mac 實際驗證掛載、Finder 拖放、卸載、安裝後啟動及全部 17 個檔案與簽章完整性。[安裝實測](../macos/INSTALL-v0.2.4.md) · [Finder 截圖](../macos/evidence/v0.2.4/dmg-finder.png) |
| M2 實際使用紀錄 | **使用者回報：v0.1 曾在同一部 M2 MacBook，取得系統授權後，成功跨 App 驅動鍵帽及機械鍵盤聲。** 這是使用者實機回報，並非雲端測試數據；不能推論後續版本亦可正常使用。 |
| 現在的主要未解問題 | 後續原生版本輸入監察失效，**尚未修復**。使用者已確認 v0.2.4 正確安裝到標準 Applications 位置，但系統設定顯示開啟時，程式仍可能判定未授權，跨 App 同步保持關閉。不要再把反覆搬移、重裝或新增導覽按鈕當作解法。 |

既有 [v0.2.4 Release](https://github.com/AnneCat-bit/sage-keys/releases/tag/v0.2.4) 與 [DMG](https://github.com/AnneCat-bit/sage-keys/releases/download/v0.2.4/Sage-Keys-Apple-Silicon.dmg) 僅作成品與歷史定位，不是本次要求使用者重新下載安裝。編譯來源為 `60f9410429e6fb182f1f1424a783d385f2ce07dc`；DMG SHA-256 及下載一致性見 [校驗檔](../macos/evidence/v0.2.4/DMG-SHA256.txt)、[公開下載核對](../macos/evidence/v0.2.4/download-verification.json)。

## 2. 網頁版的能力邊界與待驗案例

**Chrome 小窗即使保持置頂，也不能監聽其他網站、Word、ChatGPT 原生 App 或其他 macOS App 的實體鍵盤事件。** Document Picture-in-Picture 提供另一個顯示文件，不提供系統全域輸入監察。只有 Sage Keys 主頁或其小窗實際收到的鍵盤事件能驅動鍵帽及聲音；焦點在小窗時，按鍵也不是同時送給 Word。

這是網頁平台的限制，**不得列為可以透過普通 JavaScript 修復的 Bug**。不要以合成事件、持續動畫或自動試聽冒充外部輸入同步。原生版的系統事件監察是另一個實作及授權範圍。[Chrome API 說明](https://developer.chrome.com/docs/web-platform/document-picture-in-picture) · [站內事件處理](../src/app.js)

未來若獲准處理網頁互動，應依下列情境分開驗收；本輪文件整理沒有重新執行互動測試：

| 場景 | 正確預期 | 判定及後續 |
| --- | --- | --- |
| 主頁書寫區取得焦點，小窗開啟，輸入 A、S、Space、Enter | 文字正常出現，小窗對應鍵帽應下沉、按住、回彈；非靜音且音訊啟動後應播放錄音。 | 若失效，是站內互動待查：主頁事件傳遞、共享模型、焦點、可見性與繪製排程。 |
| 小窗本身取得鍵盤焦點，再按相同鍵位 | 小窗應有獨立鍵帽動畫及音效；不要求它提供完整網站書寫區。 | 若失效，才追查小窗按鈕焦點、事件監聽、AudioContext 啟動／恢復、解碼及 WebGL 狀態。 |
| 離開 Sage Keys，在其他網站或原生編輯器打字，小窗仍可見 | **不產生同步**，不因外部打字新增鍵帽敲擊或音源。 | 正常平台限制；保持可見不等於持有鍵盤焦點，不應嘗試「修復」成全域監聽。 |
| 小窗返回主頁或關閉後，再於主頁打字 | 原畫布／context 恢復，輸入與聲音仍可用，無卡住鍵帽。 | 作為前兩項問題的生命週期回歸。 |

歷史雲端 Chromium 驗收已覆蓋上述站內情境、其他分頁沒有同步、逐幀像素與音源／PCM 證據，見 [INTERACTION-REPAIR.md](INTERACTION-REPAIR.md)、[原始互動資料](interaction-evidence.json)。這不代替使用者目前 macOS Chrome 的重現；未來若再報站內問題，要記錄是哪一個文件持有焦點、實際收到哪些事件、畫面及音源是否改變，不能只以按鈕存在或頁面載入成功判定通過。

調查入口：`src/app.js` 的 `keydown`／`keyup`、`focus`／`blur`／`visibilitychange`；`src/floating.js` 的畫布移入移出與控制項焦點；`src/view.js` 的視窗排程與 WebGL；`src/sound.js` 的使用者手勢、AudioContext、錄音載入及靜音。保留原生 IME 組字、快捷鍵與單一 context，不加入全域監察。

網頁預設省電上限為 30 FPS，標準為 60 FPS；原生版則是 15／30 FPS，兩者不要混淆。兩版均採按需繪製，但不代表零 CPU／GPU 使用。雲端軟體繪圖數據不能推成 M2 耗電、溫度或電池續航。macOS 真實中文候選窗、音訊可聞延遲、Spaces／全螢幕／Stage Manager 行為仍有待實機確認，詳見原始報告。

## 3. 原生版簽署研究：結論與失敗證據

本節完整承接 [research/signing/README.md](../research/signing/README.md) 的主要結論、阻礙及驗收界線；研究腳本與完整失敗輸出仍以原始檔案為準。研究基準為提交 `193b5f9`，報告整理於 `e397964`。不要將腳本內尚未執行到的斷言視為測試通過。

### 3.1 已證實與未證實的原因

- **已確認：ad-hoc 跨版本身分問題。** [macos/build.sh](../macos/build.sh) 使用 `--sign -`，並未重用持久憑證與私鑰。現有成品的 designated requirement（DR，識別同一程式的條件）綁定具體 CDHash。舊新版的內容雜湊不同，曾在同一路徑實測新版不符合舊版 DR。[v0.1 簽署紀錄](../macos/evidence/gatekeeper.txt) · [跨版本比對](../macos/evidence/v0.2.3/signing.log) · [v0.2.4 診斷證據](../macos/evidence/v0.2.4/dmg-lifecycle.log)
- **尚未證實：目前 M2 的 TCC 失效根因。** TCC 是 macOS 管理隱私授權的系統。舊授權指向舊 DR 是合理假設，但沒有該實機系統決策的充分證據，不能寫成唯一確定原因。不能因為 DMG、安裝位置、Bundle ID 或畫面上的藍色開關正確，就宣稱有效授權已成立。
- **內容雜湊改變本身正常。** 長期更新要維持的是可信的簽署者與程式識別條件，不是讓每版二進位內容具有同一 CDHash。[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

| 必須分開的問題 | 成功條件 |
| --- | --- |
| 重新授權目前版本 | 固定同一份成品，真正執行的程序回報有效 Input Monitoring；使用者手動開始後，唯讀事件 tap 與物理鍵位回饋正常。這不代表下一次更新保留權限。 |
| 長期更新保留權限 | 內容不同的 B 滿足 A 的原 DR，並在真實 macOS 更新後仍通過權限 API 與監測驗收。DR 相容、Gatekeeper 接受、TCC 許可及本次同步開關須分別記錄。 |

### 3.2 免費持久自簽憑證候選

候選是把同一份自簽 Code Signing 憑證及配對私鑰保留在 Mac keychain，後續沿用相同 signing identifier，使用系統工具產生的預設 DR。它**尚不是已驗證解法**；每次新建同名憑證不算持久身分，也不能改成僅檢查 Bundle ID 的寬鬆 DR。

完整限制如下：

- 匯入憑證、憑證用途信任、成功取得私鑰簽署、DR 相容是不同步驟；任何一步成功都不等於 Input Monitoring 已授權。
- 私鑰若只留在使用者 Mac，GitHub Runner 就無法使用它簽署更新；公開憑證不能代替私鑰。安全、免 Terminal 的本機重簽更新路徑尚未實作或驗證，不可承諾 Finder 拖放會自動完成。
- 不索取私鑰，不把私鑰放入 App、DMG、Git、Artifact 或自動上傳。研究未建立長期雲端簽署秘密。
- 遺失私鑰、換機、憑證更換及到期均需獨立驗證。不能承諾永久保留權限。
- 自簽身分不是 Developer ID，也不等於 Apple 公證或 Gatekeeper 一般分發信任。Apple Development 亦不能當成免設定的公開發行替代品；付費 Developer ID 方案不在目前允許範圍。
- 從 ad-hoc 遷移到另一種簽章是身分遷移，不能假設新身分自動繼承舊授權。

原始依據：[Apple Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)、[TN3161](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)、[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)、[公證要求](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)。TN2206 是歷史文件；不同 macOS 子系統有各自政策，不能把一般身分比對機制當作目前 TCC 必然接受的承諾。

### 3.3 最後一輪雲端實驗的實際狀態

[研究執行 44981777951](https://github.com/AnneCat-bit/sage-keys/actions/runs/44981777951) 在標準 ARM macOS 15.8.2 與 26.7.2 Runner 完成，**整體結果 failure，候選方案 blocked**。研究只建立獨立 Bundle ID 的最小測試成品，沒有重編或重簽 Sage Keys、沒有請求 TCC、沒有監聽使用者輸入。

| 檢查 | 已觀察的結果 |
| --- | --- |
| 自身 DR 正對照 | 通過；先確認成品符合自己的 DR，避免把指令語法錯誤當安全拒絕。 |
| 同 identifier、不同 ad-hoc 成品 | CDHash 不同，雙向檢查均實際因不符合指定 requirement 失敗，exit 3。 |
| 僅匯入自簽憑證 | matching identity 存在，但回報 `CSSMERR_TP_NOT_TRUSTED`，有效身分數為 0。 |
| 一次性 Runner 對測試憑證設定 codeSign 用途信任後 | `security find-identity` 列出 1 個有效身分，`verify-cert` 成功，exit 0。 |
| `codesign` 實際簽署 | macOS 15：`The specified item could not be found in the keychain`；macOS 26：`no identity found`。有效憑證可見與實際簽署成功之間仍有阻礙。 |
| 相同持久身分的 A/B DR 相容 | **尚未完成。** 因簽署前置步驟失敗，無法聲稱兩版互認。 |
| 不同憑證防冒充、不同 identifier、身分遷移比對 | **尚未完成。** 它們是腳本的預定檢查，不是已通過項目。 |
| 候選方案的 Gatekeeper／真實 TCC | **未驗證。** 不存在已成功保留 M2 授權的證據。 |
| 清理 | 私鑰 keychain 刪除 exit 0，暫存資料夾已移除；移除測試憑證信任指令逾時，`trustRemoved:false`。完整清理未通過，餘下公憑證／設定只在一次性 Runner，隨環境銷毀處理。腳本不得直接移植到日常 Mac。 |

完整原始輸出：[macOS 15 JSON](../research/signing/evidence/macos-15.json)、[macOS 26 JSON](../research/signing/evidence/macos-26.json)。[研究程式](../research/signing/probe.py) 與 [研究工作流程](../.github/workflows/signing-identity-research.yml) 留作閱讀與後續獨立研究；本輪沒有重新執行。較早研究曾有參數格式及清理例外掩蓋原始錯誤，已修正；不能引用那些失敗嘗試作為方案成功證據。

目前研究只能確認 ad-hoc 的識別問題，不能宣稱自簽方案已可用，也不能由這些 Runner 阻礙斷言自簽機制本身不可能。

## 4. 未來恢復開發的條件

**原生版繼續凍結。先取得新的、可重現的獨立簽署證據，再評估是否需要新版 App。不得反覆編譯、換版本號或重簽成品測試運氣。** 本交接文件不授權新工作階段自動執行以下研究或發行。

未來若使用者重新啟動研究，依下列順序判斷：

1. 在一次性雲端環境，釐清 keychain 身分查找、私鑰存取與 `codesign` 之間的差異，取得可重現的最小成功簽署及完整清理。不得以擴大信任範圍或繞過系統安全掩蓋錯誤。
2. 用同一持久身分簽署內容不同的 A／B。確認 CDHash 改變、B 符合 A 的 DR、A 符合 B 的 DR；加入同名不同憑證、不同 identifier 的負對照。保留正反結果及工具鏈版本。
3. 獨立評估憑證持久保存、遺失／輪換／到期，以及免 Terminal、私鑰不外傳的更新路徑。單次 Runner 內重用 keychain 不代表跨天、換機或長期更新已通過。
4. 再評估一次受控的真實 macOS A→B→C 驗收：使用者正常批准系統權限，核對真正執行身分、權限 API、唯讀事件 tap，更新／重啟後是否保留權限，以及拒絕／撤銷／Secure Event Input 的安全行為。不能用模擬 API、改 TCC 或雲端環境預設權限替代真人授權證據。
5. 只有上述研究有實質新證據，才與使用者評估恢復原生 App 開發。仍須保留每次啟動同步預設關閉、明確手動啟用、信任清單核驗與一鍵暫停；不能把系統授權變成自動開始監測。

保留免費方案研究方向。不要求使用者提供私鑰、Apple ID 密碼、操作 Terminal、安裝 Xcode／開發工具、關閉 SIP／Gatekeeper 等系統保護或購買 Apple 開發者會員。不使用 `tccutil`、不修改 TCC 資料庫、不要求反覆重裝或授權。使用者目前不需要進行任何設定操作。

## 5. 原始來源索引與程式入口

| 問題 | 應讀來源 |
| --- | --- |
| 網頁功能、站內使用與相容性 | [README](../README.md)、[初版回歸](TESTING.md)、[互動修復實測](INTERACTION-REPAIR.md)、[效能原始數據](interaction-performance.json) |
| 音效及素材授權 | [錄音來源](AUDIO.md)、[原生離線資產](../macos/ASSETS.md)、[Three.js 授權](../assets/THREE-LICENSE.txt)、[字型目錄](../assets/fonts) |
| 網頁輸入／3D／PiP | [app.js](../src/app.js)、[model.js](../src/model.js)、[view.js](../src/view.js)、[floating.js](../src/floating.js)、[sound.js](../src/sound.js) |
| 網頁重現程式 | [站內回歸](../tests/studio.py)、[懸浮回歸](../tests/floating.py)、[事件與影格測試](../tests/interaction.py)、[效能量測](../tests/benchmark.py)；閱讀它們不代表本輪需要執行。 |
| 原生生命週期、事件及信任 | [PetApp.swift](../macos/Sources/PetApp.swift)、[KeyMonitor.swift](../macos/Sources/KeyMonitor.swift)、[TrustedApps.swift](../macos/Sources/TrustedApps.swift)、[PetWeb.swift](../macos/Sources/PetWeb.swift) |
| 安裝與權限診斷 | [InstallationCheck.swift](../macos/Sources/InstallationCheck.swift)、[PermissionGuide.swift](../macos/Sources/PermissionGuide.swift)、[InstallNotice.swift](../macos/Sources/InstallNotice.swift) |
| 原生歷史報告 | [v0.1](../macos/TESTING.md)、[v0.2](../macos/TESTING-v0.2.md)、[v0.2.1](../macos/PERMISSIONS-v0.2.1.md)、[v0.2.2](../macos/DIAGNOSTICS-v0.2.2.md)、[v0.2.3](../macos/LIFECYCLE-v0.2.3.md)、[v0.2.4](../macos/INSTALL-v0.2.4.md) |
| 原生回歸及效能證據 | [v0.2.4 結果](../macos/evidence/v0.2.4/mac-results.json)、[CPU／RSS 原始 CSV](../macos/evidence/v0.2.4/process.csv)、[Gatekeeper 評估](../macos/evidence/v0.2.4/gatekeeper.txt) |
| 簽署研究的完整結論 | [研究 README](../research/signing/README.md)、[macOS 15 失敗證據](../research/signing/evidence/macos-15.json)、[macOS 26 失敗證據](../research/signing/evidence/macos-26.json) |

歷史 macOS Runner 編譯、WebGL、三種錄音、重開、信任清單及退出測試，均須按各報告的真實系統／模擬／使用者回報分類理解。較早的 [原生版可行性研究](MACOS-FEASIBILITY.md) 是歷史設計資料；原生 App 已實作，但目前因授權問題凍結，不能再把它當成尚未開始的全新開發任務。

重要執行紀錄：

- [v0.2.4 編譯及 DMG 驗收：44979295414](https://github.com/AnneCat-bit/sage-keys/actions/runs/44979295414)，成功；不代表 M2 TCC 已恢復。
- [既有 DMG 發布：44979839026](https://github.com/AnneCat-bit/sage-keys/actions/runs/44979839026)，成功；使用已驗證成品，沒有再次編譯。
- [簽署研究：44981777951](https://github.com/AnneCat-bit/sage-keys/actions/runs/44981777951)，失敗；以已納入 Git 的 JSON 保留阻礙證據。

Actions Artifact 通常只有 30 天保存期。連結日後失效時，先讀 repository 內的歷史證據；**不得因此自動重跑編譯、簽署、研究或發行**。

## 6. 交接範圍與保護規則

- 只提交必要交接文件 `docs/PROJECT-HANDOFF.md`。保留全部歷史程式碼、報告、研究紀錄及 GitHub Releases，不建立 v0.2.5。
- 不修改正式網頁的 HTML、CSS、JavaScript、模型、音訊、字型或 Pages 設定；不重新編譯／簽署原生 App。
- 不執行 `macos/build.sh`、打包腳本、原生測試或研究腳本；不觸發 macOS 建置、發行或研究的手動 workflow。
- [macOS 建置流程](../.github/workflows/sage-keys-macos.yml) 會因特定程式與資產路徑的 push 自動執行；本交接文件路徑不在其觸發範圍。[發行流程](../.github/workflows/sage-keys-release.yml) 與 [研究流程](../.github/workflows/signing-identity-research.yml) 為手動入口。它們仍存在，不等於可以自動恢復執行；本次沒有修改工作流程。
- 不改其他 repository，不碰使用者 Mac、iCloud 或本機開發環境。本文件只含公開專案識別、通用系統概念與雲端證據引用，不新增私人電腦路徑、帳戶資料、私鑰或敏感診斷。
- 不記錄或上傳打字內容、Unicode、IME 組字、剪貼簿或按鍵歷史。保持網頁站內事件範圍；原生版保留唯讀、主動啟用與安全停止原則。
- 文件驗證限於內容、來源連結、變更範圍及 GitHub 提交確認。此輪沒有新增任何 App、瀏覽器互動或 TCC 測試結果。

新工作階段完成閱讀後，應能直接回答：哪一版可保留、哪些行為只是平台限制、哪些測試真的通過、簽署在哪一步失敗，以及為何目前不能製作新版。若沒有新證據或使用者的新任務，維持上述凍結狀態。
