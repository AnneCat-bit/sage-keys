# 鍵盤錄音與授權

2026 年 11 月 21 日逐一檢查以下 Freesound 作者頁。三頁均標示 Creative Commons 0，授權連結指向 CC0 1.0 Universal。每位作者都將素材描述為實際敲擊鍵盤的錄音。Sage Keys 收錄從各頁公開播放器的高品質 MP3 預覽剪出的片段。播放時由網站自身提供檔案，無須連線到 Freesound。[CC0 1.0 授權聲明](https://creativecommons.org/publicdomain/zero/1.0/)

| 音色 | Freesound 原始作品 | 錄製資料 | 公開預覽 |
| --- | --- | --- | --- |
| Rainy 75 | Techrul，2025-07-10，[Typing on a rainy 75](https://freesound.org/people/Techrul/sounds/815614/) | 作者敲打自己的 Rainy 75。原檔為雙聲道 MP3。 | [815614 HQ](https://cdn.freesound.org/previews/815/815614_15899953-hq.mp3) |
| HHKB Topre | grcekh，2020-11-24，[Keyboard Typing 2 (HHKB, Topre)](https://freesound.org/people/grcekh/sounds/546033/) | 原裝 HHKB Professional Hybrid，45 g Topre 鍵軸，Yeti Nano 麥克風。原檔為雙聲道 MP3。 | [546033 HQ](https://cdn.freesound.org/previews/546/546033_12206738-hq.mp3) |
| Cherry MX Brown | majod，2017-08-21，[Mechanical Keyboard Cherry MX Brown](https://freesound.org/people/majod/sounds/400167/) | 採用 Cherry MX Brown 鍵軸的機械鍵盤。原檔為雙聲道 FLAC。 | [400167 HQ](https://cdn.freesound.org/previews/400/400167_7690632-hq.mp3) |

## 片段來源

下表為各片段在解碼後原始預覽中的時間範圍，以毫秒計。每個音色使用七段互不重疊的錄音，其中四段供一般鍵交替播放。Space、Enter、Backspace 各配置獨立片段。三位錄音者均未標註逐鍵時間，因此這三種按鍵的對應為本作品的音色配置，原錄音中的實際鍵名無從辨識。

| 播放鍵 | Rainy 75 | HHKB Topre | Cherry MX Brown |
| --- | --- | --- | --- |
| 一般鍵 1 | 9312–9394 | 125217–125294 | 479–565 |
| 一般鍵 2 | 15606–15702 | 91510–91584 | 33288–33358 |
| 一般鍵 3 | 39248–39318 | 147273–147344 | 7994–8065 |
| 一般鍵 4 | 14453–14530 | 112366–112448 | 15843–15967 |
| Space | 16262–16348 | 45075–45216 | 5855–5998 |
| Enter | 35203–35342 | 136161–136319 | 22946–23056 |
| Backspace | 55971–56050 | 112251–112328 | 40139–40212 |

## 音檔處理與核對

剪輯程序先將預覽解碼為 32 kHz 單聲道，使用 65 Hz 二階高通減輕低頻雜音，再調整片段音量、套用 1 ms 淡入及 12 ms 淡出。輸出為 16-bit PCM WAV，每個音色一個檔案。保留 10 ms 的樣本間距。三個 WAV 合計 140,676 bytes，另有 842 bytes 的索引。[播放索引](../assets/audio/sprites.json)

| 已核對的預覽 | SHA-256 |
| --- | --- |
| Rainy 75 | `c426ec057d1d2e52dd6cb97cf12269c9c5c76bc32eab003fe9fd3741737f13b0` |
| HHKB Topre | `a4cffe3b457f69b645b32da45e21dc6e83d8c520f4a27fd85618981e734297f3` |
| Cherry MX Brown | `a175c98b1d4561d5b8ac8439269bf79443c9b48770ad9ded371f0d23234b8521` |

第一版收錄上述三種鍵盤音色。Rainy 75 是鍵盤型號，錄音內容是敲鍵聲。
