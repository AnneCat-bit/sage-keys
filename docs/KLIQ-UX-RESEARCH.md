# Kliq UX／UI 參考研究：讓狀態與下一步清楚可見

整理日期：2026-11-22（香港時間）。本文件只作設計研究與未來交接，**Sage Keys 原生版維持 v0.2.4 凍結**。以下建議均未實作、未驗收，也不構成恢復開發或發行的授權。先前簽署研究、失敗證據及恢復條件仍以 [PROJECT-HANDOFF.md](PROJECT-HANDOFF.md) 為準。

核心參考是：使用者應直接知道「現在發生甚麼、為甚麼、下一步可以做甚麼」。音色試聽、設定分組與狀態文字可以改善理解，但不能代替真正有效的系統授權、事件監察或音訊播放。

## 1. 資料來源與證據界線

本次比對使用者提供的九張 Kliq 使用截圖、使用者的實機回報，以及 [Kliq 官方專案][repo] 的固定原始碼版本 `82409b253ab090d150d5d4bcb401ff300a36edba`。來源連結固定到該提交，避免日後 `main` 更新改變研究依據。

| 證據 | 可以確認 | 不能推論 |
| --- | --- | --- |
| 使用截圖 | General、Sound、Sleep、Stats、About 的版面；音色選擇、滑桿、開關、更多選項、選單列入口。About 顯示 0.0.3（22）。 | 截圖中的開關是當時設定，不是產品預設值；靜態畫面不能證明真正收到事件或播放聲音。 |
| 使用者回報 | 已實際使用 Kliq，批准一次 Accessibility 後可用；遇到麥克風觸發休眠時能看到原因及 Wake。 | 不代表每個 macOS 版本、每次更新或每種授權狀態均已測試成功。 |
| 原始碼閱讀 | 首次引導、權限與監聽欄位、休眠原因、Wake、試聽與設定的控制邏輯。 | 未證明此提交就是截圖中成品的精確建置來源，也不等於本輪做過真人授權／可聞音效／VoiceOver 實測。 |
| Sage Keys 建議 | 從觀察提出未來流程、狀態文案和驗收條件。 | 不是 v0.2.4 已有或已修復的功能，不能拿來宣稱 M2 TCC 問題已解決。 |

截圖未包含完整首次啟動或拒絕授權流程；這兩部分依原始碼分析。公開文件不保存截圖的桌面背景、私人使用數字或其他個人資訊，也不重新發布使用者截圖。

## 2. 設定分類：用少數穩定入口減少尋找成本

[SettingsRootView][settings-root] 將設定固定分成 General／Sound／Sleep／Stats／About；每頁有短標題及一句用途。截圖中的側欄透過文字、圖示、選取底色與側邊標記共同表達位置，無須記住設定藏在哪一層。

| Kliq 分類與觀察 | 值得參考的原則 | Sage Keys 未來取捨 |
| --- | --- | --- |
| General：目前狀態、主開關、快捷鍵、登入啟動；更多選項中有 Permissions。 | 把「能否運作」與常用啟停放在同一入口，開關旁有文字結果。 | 可稱「一般」，集中本次同步、已信任 App、系統權限與視窗偏好。阻擋同步的原因不能藏在更多選項。登入啟動及每次啟動的跨 App 同步仍預設關閉。 |
| Sound：音色卡片、音量百分比、輸出裝置；Typing／Effects／Tone 收在更多選項。 | 先選音色及調音量；低頻選項漸進展開，避免首次看到大量參數。 | 保留 Rainy 75、HHKB Topre、Cherry MX Brown，先提供試聽、選擇、音量與靜音。不因參考案例就增加七套音色、滑鼠聲、合成音或其他效果。 |
| Sleep：何時安靜、安靜時音量、可選通知。 | 將觸發條件與結果放在同一頁；休眠要有原因及恢復方式。 | 可整理既有暫停／省電行為，但「停止同步」「聲音靜音」「系統睡眠」必須分開。麥克風、相機、音樂偵測是另行評估的功能，未獲准實作或增加權限。 |
| Stats：總數、音色使用比例、重設入口。 | 把次要資訊與核心操作分開，數值層級簡單。 | **只參考資訊分類，不引入使用統計。** Sage Keys 現有隱私承諾優先，不新增按鍵歷史、時間序列、使用計數或分析追蹤。 |
| About：版本、來源與授權資訊。 | 使用者能辨認正在使用的版本及取得協助。 | 保留簡短版本／個人測試版標記；詳細安裝與簽署證據按需展開，不變成每次使用必經的教學。 |

[StatsManager][stats] 確實將總計、各音色使用數量及起始日期保存到 UserDefaults；這和保存文字內容是兩回事，但不是 Sage Keys 因參考其 UI 就應新增的資料收集。[MoreOptions][controls] 的展開狀態有輔助功能文字，這個「簡單預設、需要時再看細節」的原則可參考；不要因此把關鍵錯誤藏起來。

浮窗仍應以約 400 × 250 的 3D 鍵盤為主，只保留短狀態、暫停、靜音及設定入口。分類設定放在使用者主動開啟的獨立輕量視窗，不把整個側欄或儀表板塞進桌寵。

## 3. 首次啟動與權限：參考順序，不照搬授權策略

[OnboardingView][onboarding] 在同一視窗依序呈現三件事：允許 Accessibility、尋找音色、選擇是否登入啟動。第一步簡述為何需要權限及不記錄輸入內容，顯示 Allowed／Waiting for permission，並有系統設定入口。音色選擇就在同一流程內，讓使用者理解授權後得到甚麼。

值得參考的是少數明確步驟、即時狀態、在操作位置提供說明，以及 [AppController][controller] 重用既有引導視窗，避免重複建立多個視窗。但以下行為不適合直接沿用：

- Kliq 的 Done 在沒有 Accessibility 時停用；Sage Keys 應始終允許關閉／稍後再說，繼續使用不需跨 App 監察的 3D 展示及主動試聽。
- Kliq 啟動時若已獲授權，或授權由無變有，會啟動事件監聽；Sage Keys 必須保留本次手動啟用與已信任 App 核驗，不能因系統權限變成有效就自動開始。
- Kliq 在第二次請求，或第一次請求後約六秒仍未授權時，顯示卡住提示與 Reset and Allow。[AccessibilityManager][access] 的重設操作會呼叫 `tccutil`。**本專案不採用、不執行這條路徑**；亦不能把六秒等待或兩次點擊當作舊簽章授權失效的充分證據。
- Kliq 使用 Accessibility／`AXIsProcessTrusted`；Sage Keys 目前使用 Input Monitoring。兩者不是可直接互換的權限流程。本輪不更換 API、不研究繞過授權，也不將 Kliq 使用成功推論為 Sage Keys 已有解法。

### 未來建議的最短正常路徑

1. **先能體驗。** 開啟後顯示原有 3D 鍵盤與「跨 App 同步已關閉」。使用者可主動試聽三套內置錄音，不必先完成系統授權。
2. **在需要時才請求。** 使用者主動選擇跨 App 同步，清楚確認目標 App 的識別及是否保存信任；同一輕量畫面顯示目前權限與一個主要操作。
3. **取得實際結果。** 回到 App 時重新檢查目前程序的權限。有效就顯示「系統授權有效；本次同步尚未啟用」，讓使用者確認並手動開始。失敗就原位顯示原因；不再串接第二、第三層導覽。
4. **成功或退回都清楚。** 只有事件監察實際建立成功且目標 App 合資格，才顯示同步中。取消則清除本次啟用意圖，保留已明確保存的信任及偏好，回到可使用的桌寵。

這是未來流程建議，不代表目前權限障礙已消失。若系統設定已開而 API 不允許，應說「系統設定的開關與目前程序的有效授權不一致，原因尚待確認」，不要斷言使用者沒開開關，也不要無證據要求再次搬移或重裝。當前免費簽署研究受阻時，應直接承認阻礙並允許繼續本機展示；更多按鈕無法修復簽署身分。

## 4. 狀態回饋：已啟用不等於正在監聽

[AppState][state] 分開記錄 `accessibilityGranted`、`inputMonitoringActive`、`isSleeping`、`sleepReasons`；[General][general] 的 Permissions 區也分開顯示 Allowed／Not allowed 與 Listening／Not listening。這比只有一個同步開關更容易理解。

仍需辨識參考案例的界線：Kliq General 主卡的「Kliq is on」和選單標頭的「On」沒有以 `inputMonitoringActive` 作為成立條件；事件 tap 啟動失敗會另設錯誤文字。因此 **On 不能當作成功監聽證據**。Sage Keys 應借鑑狀態分離，並讓阻擋原因直接出現在浮窗／選單，而非要求使用者自行展開權限詳情。

### Sage Keys 未來狀態契約（建議，未實作）

狀態至少分開本次啟用意圖、有效系統權限、前景 App 信任、事件監察運作、安全暫停及音訊狀態。各入口讀取相同狀態來源；不以按鈕已點擊、開關呈綠色或固定延遲結束當成功。

| 情況 | 建議顯示 | 一個主要操作／行為 |
| --- | --- | --- |
| 啟動後或使用者已暫停 | 同步已關閉 | 「開始本次同步」；系統已有權限亦不自動啟動。 |
| 使用者剛開始操作，檢查尚未完成 | 正在檢查同步條件… | 即時顯示進度；重複點擊沿用同一流程，結束後給確定結果，不能無限轉圈。 |
| 沒有有效權限 | 尚未取得有效的輸入監察權限 | 依實際狀態提供一次正常授權或開啟設定的主操作；「稍後再說」始終可用。 |
| 使用者已開系統開關，但目前程序 API 仍拒絕／結果不一致 | 權限尚未對目前版本生效；原因未確認 | 主操作是查看當前檢查結果；同畫面按需展開具體證據，不再重複要求按同步。沒有新證據就停止循環。 |
| 權限有效，尚未手動確認本次同步 | 系統授權有效；同步尚未啟用 | 「確認並開始本次同步」。 |
| 本次已啟用，但前景 App 未信任 | 已啟用，待命：目前 App 未允許 | 可「選擇允許的 App」；必須明確核驗及同意，不自動加入信任清單。 |
| 所有安全條件有效，事件監察已建立 | 同步中：目前已信任 App 名稱 | 「暫停同步」；名稱僅作顯示，資格仍以已驗證身分判定。 |
| 系統安全輸入、鎖定或其他保護條件 | 同步已暫停：具體保護原因 | 停止監察並清空按鍵；不得用 Wake 或試聽繞過保護。 |
| 權限有效但事件監察啟動失敗 | 未能開始監聽；系統授權有效 | 停止假成功狀態；提供一次有結果的重試，仍失敗就保留原因與可選詳情。 |
| 使用者靜音、音量為零或音訊播放失敗 | 同步狀態照實顯示，另標「已靜音」／「音量 0%」／「音效未能播放」 | 分別提供取消靜音、調音量或重試音效；不誤導使用者重新授權鍵盤。 |

同時有多個條件時，先顯示目前真正阻擋操作的原因；若使用者已關閉同步，主狀態維持關閉，權限資訊只作補充，不強迫開啟導覽。隱藏、睡眠、鎖定、權限撤銷、暫停及退出仍須停止監察、清除即時鍵位；重新顯示或重新啟動不能自行恢復同步。未信任 App 間切換只可按既有本次啟用與信任規則處理。

「正在監聽」表示監察服務正常建立，不保證音效一定可聞；真實按鍵回饋仍須獨立驗收。瀏覽器受信任亦不代表能辨識其中網站或密碼欄，不能以狀態文案宣稱網站級敏感輸入保護。

## 5. 音色試聽：先聽見差異，再決定選擇

截圖可見「Hover to hear · click to choose」、音色名稱、選取框、勾號與頂部目前音色；音量同時顯示滑桿及百分比，Tone 有 Reset／Try It。[SoundBoard][soundboard] 進一步確認：

- 懸停約 160 毫秒才安排短試聽，避免游標快速經過所有卡片就連續發聲。
- 懸停試聽不改變正式選擇；點擊才選擇並試聽。離開卡片或頁面會取消尚未播放的試聽步驟，不應誤稱已播出的尾音必然立即截斷。
- [SoundEngine][engine] 有獨立預覽路徑，不需等下一個全域按鍵事件才聽到效果；它與正常按鍵播放的開關判斷不同，不能直接照搬成 Sage Keys 的靜音語意。
- [SoundSettingsView][sound] 在找不到原輸出裝置時顯示 Unavailable device，而不是空白選擇器；載入失敗亦有訊息位置。

未來 Sage Keys 應保留既有真實錄音，讓「試聽」與「選為音色」的效果一目了然。可參考短懸停預覽，但必須提供可由鍵盤與 VoiceOver 操作的明確試聽按鈕，不能把滑鼠懸停當唯一入口。選取以文字／勾號／描邊共同表達，不只靠顏色。

**試聽不應啟動跨 App 監察或改變信任。** 也不應在靜音、睡眠或保護狀態下悄悄發聲；若目前不播放，直接標明原因，讓使用者明確恢復聲音後再試。切換及試聽需取消過期排程，避免快速點擊堆疊大量音源；載入失敗不能仍顯示「播放中」。不新增連續預覽、背景動畫或無限重試。

## 6. 休眠：原因與恢復放在發生問題的位置

使用者特別指出「因麥克風使用而休眠」時，Kliq 能說明原因並提供 Wake。這也得到原始碼支持：[StatusMenuController][menu] 在休眠列顯示 `Sleeping · microphone in use` 等原因及 Wake；[SleepSettingsView][sleep-view] 顯示原因卡及 Wake Now；[QuietStatus][controls] 把原因寫成自然句子。這個模式避免使用者以為音效故障或沒有權限。

[SleepManager][sleep-manager] 的 Wake 會暫時忽略已啟用的休眠觸發條件，直到這些條件全部清除，之後才恢復正常觸發。它不是永久關閉所有 Sleep 設定，也不是取得系統授權。[AppController][controller] 的休眠處理主要調整播放音量／靜音，**不能把 Kliq 的 Sleep 理解為事件 tap 已停止**。其主開關也主要控制聲音播放，不等同 Sage Keys 的「停止跨 App 監察」。

Sage Keys 可先借鑑「一行具體原因＋一個有明確作用的操作」，而不引入新偵測功能。例如既有安全暫停必須說明原因；真正的使用者暫停則顯示手動恢復入口。若將來另獲准研究麥克風等自動安靜功能，須先定義是只停聲音，還是停止動畫／監察，以及 Wake 的有效範圍，並驗證隱私、系統 API 與耗能。不能為了模仿這個 UI 就開始存取麥克風／攝影機，或讓 Wake 跳過權限、信任與 Secure Event Input。

## 7. 保持 Sage Keys 的視覺與操作語言

- 保留鼠尾草綠、奶油白、霧銀色及原有精緻 3D Sage 75；手繪小鍵盤、箭嘴、線框只作少量說明，與狀態文字相伴。
- 借鑑留白、分組、選取回饋與漸進展開，不複製 Kliq 的紅色品牌、K 字標誌、圖示、文案口號、卡片畫面或音效資產。
- 主狀態與主要操作直接可見，非必要診斷收在同一畫面的詳情。正常路徑不需穿過多個教學視窗；手繪插畫不能取代具體錯誤原因。
- 選單列提供短狀態、暫停／恢復、靜音、顯示桌寵及退出，與浮窗同步。切換後立即更新文字與開關，不能只有顏色變化。
- 狀態改變時才更新畫面；不使用持續閃爍、呼吸動畫或高成本玻璃效果來證明 App 還在運作。保留預設 15 FPS、可選 30 FPS、按需渲染及單一 WebGL context。
- 不照搬 Kliq 未授權時持續每秒檢查的做法。未來權限檢查應以使用者操作、返回 App 等事件為主；如需短期檢查，必須有終點並可取消，不因增加導覽造成長期背景輪詢。

## 8. 未來恢復開發後的驗收清單

**本輪沒有執行下列測試。** 這是未來獲准恢復後的驗收要求；先完成交接文件所述獨立簽署驗證，再評估實作。不可用截圖、按鈕存在或模擬權限替代真人 TCC 證據。

| 情境 | 需要驗證的結果 |
| --- | --- |
| 首次啟動，未授權 | 桌寵仍可展示及主動試聽；明確顯示同步關閉；不自動開始監察或登入啟動。 |
| 請求授權、拒絕、取消、返回 App | 同一引導視窗給結果與一個主要操作；可關閉，不循環重開；取消不遺失已保存信任。 |
| 設定顯示開啟但程序 API 拒絕 | 顯示不一致及尚未確認的原因；不誤稱已同步、不反覆要求搬移；診斷使用當前程序資料。 |
| 權限有效、tap 失敗／恢復 | 成功與失敗狀態來自實際啟動結果；重試有結束，失敗不仍顯示正在監聽。 |
| 切換已信任／未知 App，安全輸入與暫停 | 原因在浮窗及選單一致可見；未知 App 不自動授權；暫停或安全阻擋停止監察並清空鍵帽。 |
| 隱藏、退出、重開 | 隱藏停止同步；顯示／重開不擅自恢復；保留偏好及已同意的信任，無卡住鍵帽。 |
| 三套錄音選擇、短試聽、快速切換 | 預覽與正式選擇可區分；有真實音源播放證據；不依賴全域事件，不堆疊失效預覽。 |
| 靜音、音量零、解碼／輸出失敗 | UI 明確解釋無聲原因；取消靜音與播放恢復分開驗證，不跳到鍵盤權限導覽。 |
| 若日後另行實作自動安靜 | 以實際觸發測試原因、Wake 範圍及條件清除；不能只改狀態變數就稱偵測成功。 |
| 鍵盤導航、VoiceOver、文字放大 | 不需懸停即可試聽；能讀出開關、選取、原因及不可操作原因；小窗與設定不裁切關鍵操作。 |
| 低功耗 | 以相同環境對比閒置、試聽、同步、暫停的 CPU／RSS／繪製次數；沒有狀態動畫或長期輪詢增加負載，M2 結果須另外實測。 |

本輪完成的是截圖與固定來源核對、文件連結及變更範圍檢查；沒有啟動 Kliq 或 Sage Keys、編譯 App、呼叫 TCC、量測效能或觸發研究／發行流程。沒有新增使用者實機測試結果。

## 9. MIT License 與實際重用界線

Kliq 的 [LICENSE][license] 為 MIT，版權聲明是 `Copyright (c) 2026 Crafter Station`。本輪只閱讀原始碼、整理設計原則並連結出處；**沒有將 Kliq 程式碼、圖示、音效或畫面複製進 Sage Keys**。

一般設計參考是重新設計分類、回饋及操作次序；若未來實際複製或改寫其程式碼的重要部分，則屬程式碼重用，須記錄來源提交及修改範圍，按 MIT 條款保留版權與授權聲明，隨分發保留完整授權文本及免責內容。素材如有各別來源／授權需另行核對；MIT 不能當作品牌背書或複製 Kliq 品牌識別的理由。本次沒有新第三方程式碼依賴。

Kliq 的正式簽署／公證與 Sage Keys 免費持久身分研究仍是另一個議題，見 [交接文件第 3.4 節](PROJECT-HANDOFF.md#34-參考案例kliq)。Developer ID／公證不豁免系統授權；UX 改善不證明跨版本權限穩定。原生版凍結及網站保留要求不變。

## 10. 固定原始來源索引

下列皆為上述固定提交的唯讀參考；外部文件中的編譯、重設權限或發行命令不是本任務的操作指令。

- [官方 README][readme]、[MIT License][license]。
- [OnboardingView][onboarding]：三步引導及權限未完成時的限制。
- [AppState][state]、[AppController][controller]：狀態分離、生命週期、試聽、事件監察與錯誤處理。
- [AccessibilityManager][access]：真正權限 API、檢查與重設路徑；只作分析，不採用重設操作。
- [SettingsRootView][settings-root]、[GeneralSettingsView][general]、[SettingsControls][controls]：分類、權限欄、狀態文字與更多選項。
- [SoundBoard][soundboard]、[SoundSettingsView][sound]、[SoundEngine][engine]：預覽／選取、音訊設定及試聽排程。
- [SleepSettingsView][sleep-view]、[SleepManager][sleep-manager]、[StatusMenuController][menu]：休眠原因、Wake 與選單回饋。
- [StatsManager][stats]：本地累計資料的實際保存範圍。

[repo]: https://github.com/crafter-station/kliq
[readme]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/README.md
[license]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/LICENSE
[onboarding]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/OnboardingView.swift
[state]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/App/AppState.swift
[controller]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/App/AppController.swift
[access]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/Input/AccessibilityManager.swift
[settings-root]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Settings/SettingsRootView.swift
[general]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Settings/GeneralSettingsView.swift
[controls]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Settings/SettingsControls.swift
[soundboard]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Components/SoundBoard.swift
[sound]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Settings/SoundSettingsView.swift
[engine]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/Audio/SoundEngine.swift
[sleep-view]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/Settings/SleepSettingsView.swift
[sleep-manager]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/Sleep/SleepManager.swift
[menu]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/UI/StatusMenuController.swift
[stats]: https://github.com/crafter-station/kliq/blob/82409b253ab090d150d5d4bcb401ff300a36edba/Sources/Kliq/Stats/StatsManager.swift
