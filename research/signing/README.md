# Sage Keys 簽署身分研究 · 原生版本暫停更新

本輪只研究簽署，**不修改 Sage Keys App、不重簽 v0.2.4、不建立 v0.2.5、不發佈新下載項目**。現有 GitHub Pages、Release、模型、聲音與使用者已安裝的副本保持原狀。研究日期：2026-11-22。

## 已確認的原因，與尚未確認的實機原因

`macos/build.sh` 的簽署步驟使用 `--sign -`，即 ad-hoc。這不是「重複使用同一個本機憑證」：它沒有持久的憑證與私鑰身分。已保存的成品證據如下。

| 成品 | 簽署／識別證據 |
| --- | --- |
| v0.1 | ad-hoc，CDHash `032ba9cdb70a410387ec9f17edb673b68ca5ddff`。[紀錄](../../macos/evidence/gatekeeper.txt) |
| v0.2.3 | ad-hoc，CDHash `8c93e04607247a2d08cb19db2cc28aea5db41975`。同一路徑上的新版曾實際不符合舊版 DR。[跨版本檢查](../../macos/evidence/v0.2.3/signing.log) |
| v0.2.4 | ad-hoc，CDHash `2efe300f287052b61c7bc455d02e6f7153e22a5f`。成品診斷讀到 DR 為 `cdhash H"2efe300f287052b61c7bc455d02e6f7153e22a5f"`。[實際程序紀錄](../../macos/evidence/v0.2.4/dmg-lifecycle.log) |

**可確定的工程問題：現有簽署方式不能提供可靠的跨版本身分。** Apple TN3127 說明，macOS 可用 designated requirement（DR，判斷是否同一程式的條件）追蹤隱私授權；ad-hoc 的條件綁定具體版本。[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

**不能確定的部分：目前 M2 上 v0.2.4 為何在開關已開時仍被拒。** 我們沒有該次執行的系統授權歸屬及內部決策證據，也沒有讀取 TCC 資料庫。舊授權指向舊 DR 是合理假設，不能寫成已證實的唯一原因。v0.1 曾成功不代表新成品會滿足當時的識別條件。使用者已確認從 `/Applications/Sage Keys.app` 執行，這一輪不再把搬移 App 當作主要解法。

## 兩個問題必須分開驗收

| 問題 | 成功的判準 | 不能代表甚麼 |
| --- | --- | --- |
| 重新授權目前版本 | 固定同一份 v0.2.4 成品，真正執行的程序回報有效權限；使用者手動啟用後能建立 listenOnly tap 並正常同步。 | 不代表下一次更新仍有權限；本輪不要求使用者反覆授權或重裝。 |
| 長期更新保留權限 | 授權 A 後，內容不同的 B 仍滿足 A 的 DR；再於真實 macOS 更新後，權限 API 與唯讀監測均仍正常，且沒有自動開啟本次同步。 | 單看兩個 Bundle ID 相同、憑證名稱相同、DMG 或 `codesign --verify` 成功都不足。 |

新內容的 CDHash 改變是正常現象；要穩定的是對簽署者及程式識別的判斷，不能企圖固定每版程式的內容雜湊。由現有 ad-hoc 改到持久憑證是一次身分遷移，不能讓新簽章冒充已授權的舊 ad-hoc 成品。

## 免費本機持久簽署：值得驗證，但未成為完整解法

候選方案是在一部 Mac 的 keychain 保存同一份自簽 Code Signing 憑證及配對私鑰，後續版本沿用它與相同 signing identifier，由 `codesign` 產生預設 DR。不是每次建立一張同名憑證，也不是手寫只檢查 Bundle ID 的寬鬆規則。Apple 的舊版 Code Signing Guide 明確把自簽憑證定位為內部測試，能用來核對兩版是否來自同一來源；這不等於正式發行身分。[Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

限制包括：

- **簽署端信任需要驗證。** 匯入自簽憑證不等於系統工具願意用它簽署。本次實驗將未設定信任與僅為測試憑證設定 codeSign 用途信任分開記錄。憑證信任不是輸入監察權限，更不應擴大成所有用途或關閉安全保護。
- **私鑰所在位置決定在哪裏簽署。** 若私鑰只留在使用者 Mac，GitHub Runner 沒有它就不能簽署更新；公開憑證本身不能簽名。每次雲端產物都需要經過安全的本機重簽流程，否則仍是原來的 ad-hoc 身分。[TN3161](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)
- **免 Terminal 的更新流程尚未完成驗證。** 「鑰匙圈可以用 GUI 建立憑證」不等於 Finder 拖入 App 便會自動簽署。若將來研究 GUI 簽署工具，必須限定已核對來源的 Sage Keys 成品、保護私鑰存取、保存必要 entitlements、讓使用者確認更新，不能任意替未知程式背書。本輪沒有開發這個工具。
- **憑證生命週期需要管理。** 遺失私鑰、重新產生同名身分、換機、憑證更換及到期都要另驗，不能承諾永久有效。不得把私鑰塞進 App、DMG、Git、Artifact 或自動上傳。
- **分發限制仍在。** Apple TN3161 指出非 Apple 憑證並不能取得 Gatekeeper 的一般分發信任；自簽 App 也不符合 Developer ID 公證條件。DR 比對成功不能當作 Gatekeeper 或 Input Monitoring 驗收成功。[TN3161](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates) · [公證要求](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)

較早的 TN2206 說明，有些子系統重視穩定 DR，有些另要求特定信任來源；因此不能把「自簽可用於身分比較」推成「所有權限一定沿用」。TN2206 是歷史文件，這輪以目前系統實驗補充。[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)

## 選項判斷

| 方案 | 身分持續性的可能性 | 本次決定 |
| --- | --- | --- |
| 保持 ad-hoc，只重新授權／改 DMG／固定 Bundle ID | 未解決跨版本身分問題。 | 停止以新版本反覆試運氣。 |
| 重用本機自簽憑證＋私鑰 | 有建立穩定 DR 的機制基礎；需通過實測及本機更新流程驗證。 | 優先研究，未部署到使用者 Mac。 |
| 持久的雲端自簽身分 | 理論上可重用同一身分，但需要獨立的秘密保管、授權簽署與備份設計；仍未解決 Apple 分發信任。 | 不自行建立長期雲端私鑰或要求使用者交出私鑰。 |
| Apple Development 身分 | 適合開發測試，與 Developer ID 的預設 DR 並非同一種。 | 不當作免設定、免費公開發行的現成替代品；不要求安裝 Xcode。 |
| 同團隊 Developer ID＋相容 DR＋公證 | Apple 支援的對外分發路徑；TCC 最終仍由 macOS 與使用者批准。 | 目前付費、憑證與公證條件不符，不採購、不索取秘密。 |

## 驗證方法及停止條件

`probe.py` 只在一次性標準 ARM macOS Runner 執行，建立另一個研究 Bundle ID 的最小測試成品。既不編譯 Sage Keys，也不啟動全域按鍵監測、不請求 TCC、不讀取任何輸入。工作流程只有 repository 讀權限，只有 JSON 證據可以成為 Artifact。測試身分及成品不供下載使用。

1. **基本工具驗證。** 先驗證 A 滿足自己的 DR，防止把語法錯誤誤當作安全拒絕。
2. **負對照。** 相同 signing identifier、不同內容的 ad-hoc A／B，雙向比對原版 DR，預期不符合。
3. **候選身分。** 同一測試憑證簽兩版不同內容；中途鎖定並重開 keychain。CDHash 應改變，預設 DR 應穩定，且 B→A、A→B 都通過。
4. **防冒充。** 同名不同私鑰／憑證，以及同一憑證不同 signing identifier 均必須被原 DR 拒絕。新憑證簽章不能滿足舊 ad-hoc 的 DR。
5. **分發獨立評估。** 另記錄 Gatekeeper 結果；不將 DR 成功當成分發成功。沒有停用 Gatekeeper、SIP、TCC，也沒有修改授權資料庫。
6. **尚未執行的實機階段。** 只有前面結果及安全、免 Terminal 的重簽更新路徑清楚後，才安排一次受控的 A→B→C 權限保留驗收。應涵蓋重啟、正常系統批准、拒絕／撤銷、程序歸屬、Secure Event Input，以及每次 App 啟動同步仍關閉。這一階段需要真實使用者批准，不能以 Runner 替身或直接改 TCC 通過。

DR 雙向比對依照 TN3127 的方法，由雲端執行工具檢查；上面不是要求使用者執行指令。即使相同 keychain 在單次 Runner 的數次簽署可重用，仍不能稱為跨天、換機或憑證更新已驗證。

## 本輪實測結果：部分驗證完成，候選方案仍受阻

[最終研究執行 44981777951](https://github.com/AnneCat-bit/sage-keys/actions/runs/44981777951)，來源 `193b5f9`，兩個標準 ARM Runner：macOS 15.8.2（24H232）與 26.7.2（25G332）。**整體工作流程為 failure，不是成功的自簽方案驗收。** [macOS 15 原始 JSON](evidence/macos-15.json) · [macOS 26 原始 JSON](evidence/macos-26.json)

| 檢查 | 兩個系統的實際結果 |
| --- | --- |
| 自己符合自己的 DR | 通過，已排除 requirement 指令語法失敗造成的假陰性。 |
| 同 identifier 的不同 ad-hoc 成品 | CDHash 不同，雙向比對舊 DR 均真正回報 `code failed to satisfy specified code requirement(s)`，exit 3。 |
| 僅匯入自簽身分 | 可列出 matching identity，但標為 `CSSMERR_TP_NOT_TRUSTED`，有效身分數 0。 |
| 一次性 Runner 對測試憑證設定 codeSign 用途信任後 | `security find-identity` 列出 1 個 valid identity；`verify-cert` 亦成功，exit 0。沒有設定所有用途一律信任。 |
| codesign 實際使用該身分 | **失敗。** macOS 15 回報 `The specified item could not be found in the keychain`；macOS 26 回報 `no identity found`。不能因上一行成功而宣稱已完成簽署。 |
| 兩版重用憑證、不同憑證防冒充、遷移比對 | 因上一階段受阻，**未執行完成**。不可把腳本內的預定斷言當成已通過。 |
| 本機權限保留、Gatekeeper 新候選評估 | **未測得。** 本輪沒有請求或操作 TCC，也沒有重簽目前 Sage Keys。 |
| 清理 | 測試私鑰 keychain 刪除 exit 0、暫存資料夾已刪除；移除測試憑證信任的指令逾時，回報 `trustRemoved:false`。不能宣稱完整清理成功。餘下的測試公憑證／信任設定僅在一次性 Runner 內，隨工作結束銷毀；沒有接觸使用者 Mac。此腳本**不適合直接移植到日常電腦**。 |

實驗證明的是現有 ad-hoc 的身分問題；尚未證明免費持久身分已在目前 Runner 配置可用，也沒有證明自簽機制本身不可行。下一個工程驗證點應是 keychain 身分查找、私鑰存取與 `codesign` 實際簽署之間的差異；需先取得可重現的最小成功案例與可確認的清理流程，再進入兩版 DR 互認。本輪到此停止，不以擴大信任設定、修改授權資料庫或推出新 App 掩蓋阻礙。

較早嘗試曾有 requirement 參數格式錯誤及清理例外覆蓋原始錯誤，已在研究腳本修正；這些較早執行不作為成功證據。本報告只引用最後一輪具有正對照與完整失敗 JSON 的紀錄。


在找到可驗證的完整路徑之前，Sage Keys 原生版本維持 v0.2.4。使用者目前不需要進行任何重裝、重新授權或憑證操作。
