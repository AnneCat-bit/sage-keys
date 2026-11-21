# 離線資產與授權

| 隨附項目 | 輸入與包裝方式 | 來源與授權 |
| --- | --- | --- |
| Sage 75 模型、配列、鍵程、UI 配色、圖示 | 原有專案的程序化幾何、CSS 與圖示。App 圖示由原有 mark.svg 光柵化，Apple 原生視窗按鈕使用系統元件。 | [模型](../src/model.js) · [鍵位](../src/layout.js) · [圖示](../assets/mark.svg) |
| Three.js r160 | 已隨庫提供的模組在建置時連結入 pet.js。 | MIT，原授權全文隨 App 提供。[Three.js 授權](../assets/THREE-LICENSE.txt) |
| DM Sans、Instrument Serif | 四個 WOFF2 直接封裝，原生工具列使用 macOS 系統字型。 | SIL Open Font License 1.1。[DM Sans](../assets/fonts/DM-Sans-LICENSE.txt) · [Instrument Serif](../assets/fonts/Instrument-Serif-LICENSE.txt) |
| Rainy 75 | Techrul 的實錄，使用既有 rainy.wav。 | 作者頁標示 CC0 1.0。[Freesound 815614](https://freesound.org/people/Techrul/sounds/815614/) |
| HHKB Topre | grcekh 的實錄，使用既有 topre.wav。 | 作者頁標示 CC0 1.0。[Freesound 546033](https://freesound.org/people/grcekh/sounds/546033/) |
| Cherry MX Brown | majod 的實錄，使用既有 brown.wav。 | 作者頁標示 CC0 1.0。[Freesound 400167](https://freesound.org/people/majod/sounds/400167/) |

本次逐一重新核對三個 Freesound 作者頁的 CC0 連結。每個 WAV 的七段切片包含四個一般鍵取樣及 Space、Enter、Backspace 各一段。特殊鍵的對應是專案配置，原錄音未逐鍵標記。錄音剪輯方式及預覽檔雜湊見原始紀錄。[錄音來源與片段](../docs/AUDIO.md) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

在 Finder 對 App 選「顯示套件內容」，`Contents/Resources/Licenses/` 包含原始授權、錄音紀錄及輸入檔 SHA-256 清單。建置工作另對最終 Pet 檔案產生可核對的 SHA-256。esbuild 僅在雲端建置時使用，使用者下載的 App 內沒有 Node、npm 或 esbuild 執行檔。
