# SlideShowApp

iPhoneのフォトライブラリからアルバムを選択してスライドショーを再生するiOSアプリ。  
切り替え時間・トランジション・再生モードをカスタマイズ可能。

## 動作環境

| 項目 | 値 |
|---|---|
| プラットフォーム | iOS 16.0 以上 |
| 言語 | Swift 5.9 |
| UI フレームワーク | SwiftUI |
| Xcode | 15 以上推奨 |

---

## ソース構成

```
SlideShowApp/
├── SlideShowApp.swift                 // アプリエントリーポイント
├── Models/
│   ├── SlideShowSettings.swift        // 設定モデル・UserDefaults永続化
│   └── MediaItem.swift                // メディアモデル・オンデマンドローダー・キャッシュ
├── ViewModels/
│   └── SlideShowViewModel.swift       // 再生ロジック・タイマー・ランダム制御
└── Views/
    ├── ContentView.swift              // ルートビュー・sheet管理
    ├── SlideShowView.swift            // スライドショー本体・コントロールUI
    ├── MediaItemView.swift            // 写真/動画レンダリング・ケン・バーンズ
    ├── PhotoPickerView.swift          // 独自アルバム選択UI（全選択対応）
    └── SettingsView.swift             // 設定画面
```

---

## クラス・構造体 一覧

### Models

#### `SlideShowSettings` （class・ObservableObject）
アプリ全体の設定を管理する。全プロパティは `didSet` で即座に `UserDefaults` へ書き込まれ、次回起動時に復元される。

| プロパティ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `displayDuration` | Double | 15.0 | 写真の表示時間（秒） |
| `videoDuration` | Double | 15.0 | 動画の最大表示時間（秒） |
| `transitionType` | TransitionType | .crossFade | トランジション種類 |
| `transitionDuration` | Double | 1.0 | トランジションアニメーション時間（秒） |
| `playMode` | PlayMode | .loop | 再生モード |

#### `TransitionType` （enum）

| case | 表示名 | 動作 |
|---|---|---|
| `.crossFade` | クロスフェード | 2枚をZStackで重ねて opacity 0→1 でフェードイン |
| `.slide` | スライド | 右から左へスライドイン |
| `.kenBurns` | ケン・バーンズ | ゆっくりズーム＋パン（`withAnimation(.linear)`） |

#### `PlayMode` （enum）

| case | 表示名 | 動作 |
|---|---|---|
| `.sequential` | 順番 | 最後まで再生したら停止 |
| `.loop` | ループ | 最後まで来たら先頭に戻る |
| `.random` | ランダム | シャッフル再生。全件消費後に再シャッフル。⏮で履歴を遡れる |

#### `MediaItem` （struct）
表示中の1枚分のデータ。`AssetCache` が最大3件しかメモリに保持しない。

| プロパティ | 型 | 説明 |
|---|---|---|
| `type` | MediaType | `.photo` / `.video` |
| `image` | UIImage? | 写真本体 or 動画サムネイル |
| `videoURL` | URL? | 動画の一時コピーURL（写真はnil） |

#### `AssetLoader` （actor）
`PHAsset` を1枚ずつ非同期ロードする。Swiftの `actor` により並行アクセスを安全に管理。

- 写真：画面の物理解像度に合わせたサイズで `PHImageManager.requestImage` を呼ぶ。`PHImageResultIsDegradedKey` が true の中間結果は無視して高品質画像だけを返す。
- 動画：`PHImageManager.requestAVAsset` で取得後、`AVURLAsset` のURLを一時ディレクトリにコピーして保持。サムネイルは `AVAssetImageGenerator` で生成。

#### `AssetCache` （class・ObservableObject・@MainActor）
スライディングウィンドウ方式のキャッシュ。**常に最大3枚（前・現在・次）のみメモリに保持**し、範囲外の画像は即座に破棄する。

```
[PHAsset配列（何千枚でも軽量）]
         ↓ 表示直前に1枚ロード
┌─────────────────────────────┐
│ index-1 : 前の画像（プリフェッチ済み）│
│ index   : 現在の画像 ★             │
│ index+1 : 次の画像（プリフェッチ済み）│
└─────────────────────────────┘
         表示が終わった画像は破棄・動画一時ファイルも削除
```

| メソッド | 説明 |
|---|---|
| `setAssets(_:)` | アセット一覧をセット。既存キャッシュ・タスクをクリア |
| `prepare(index:)` | 指定インデックスの画像をロードし `currentItem` に反映。前後1枚をバックグラウンドでプリフェッチ |
| `evict(keepIndices:)` | 指定インデックス以外のキャッシュを破棄 |

---

### ViewModels

#### `SlideShowViewModel` （class・ObservableObject・@MainActor）
スライドショーの再生ロジック全体を管理する。

**タイマー管理**  
`Timer` を 0.25秒間隔で tick させて経過時間を積算する方式を採用。  
`displayDuration` / `videoDuration` に達したら `advance()` を呼ぶ。

**動画の終端処理**  
`AVPlayerItemDidPlayToEndTime` 通知を受けた時点での経過時間を確認し、`videoDuration` に満たない場合は残り時間を待機してから次へ進む（短い動画は最終フレームで静止）。

**ランダム再生**  
全インデックスをシャッフルしたキューを使い切ったら再シャッフル。直前と同じインデックスが先頭に来ないよう調整。⏮ボタンは `randomHistory` スタックを遡る。

**advance() のフロー**
```
advance()
  → stopTimer / stopVideo
  → PlayMode に応じて currentIndex を更新
  → cache.prepare(index:) で次の画像をロード（非同期）
  → ロード完了後 startCurrentItem()
```

---

### Views

#### `ContentView`
`SlideShowViewModel` と `SlideShowSettings` を `@StateObject` で生成・保持するルートビュー。`sheet` でピッカーと設定画面を管理。

#### `SlideShowView`
スライドショーの表示本体。

- `@ObservedObject` で `AssetCache` を監視し、`currentItem` の変化を即座に反映
- `ZStack` で現在画像と次画像を重ね、`crossFadeOpacity` を `withAnimation` で 0→1 に変化させてトランジションを実現
- コントロール（⏮⏯⏭・設定・アルバム）は4秒後に自動非表示。画面タップで再表示

**トランジション実装（クロスフェード）**
```
ZStack {
    現在の画像（下層）
    次の画像（上層）opacity: 0 → 1
}
アニメーション完了後に displayedIndex を更新してレイヤーを整理
```

#### `MediaItemView`
`MediaItem.type` に応じて写真または動画を表示。

- 写真：`Image(uiImage:).resizable().scaledToFit()`
- 動画：`VideoPlayer(player:)` + `AVPlayer`
- ケン・バーンズ：`.scaleEffect()` + `.offset()` を `withAnimation(.linear)` で駆動

#### `PhotoPickerView`（独自アルバム選択UI）

PHPickerViewController を使わず `PHAsset` + `PHFetchResult` ベースの独自UIで実装。これにより「現在開いているアルバムの中身だけを全選択」が正確に行える。

```
SmartPhotoPickerView           // 外部公開エントリーポイント
├── AlbumListView              // アルバム一覧（サムネイル付きList）
│   └── AlbumThumbnailView     // アルバムカバー画像（最新アセット）
└── AssetGridView              // アルバム内グリッド（LazyVGrid）
    ├── 個別タップ → チェック ON/OFF
    ├── 全選択ボタン（ナビバー右）→ 当該アルバム内だけ全選択
    ├── 全解除ボタン（全選択済み時）
    └── 「追加 (N)」ボタン → PHAsset配列を ViewModel へ渡す
```

アルバム種別：
- スマートアルバム（すべての写真・お気に入り・動画・スクリーンショット・セルフィー）
- ユーザー作成アルバム

#### `SettingsView`
`Form` + `Picker(.inline)` + `Slider` で構成。変更は即座に `SlideShowSettings` の `@Published` プロパティへ反映され `UserDefaults` に自動保存される。

---

## 設定の永続化

`SlideShowSettings` の各プロパティは `didSet` + `UserDefaults` で実装。

```swift
@Published var displayDuration: Double {
    didSet { UserDefaults.standard.set(displayDuration, forKey: "displayDuration") }
}
```

起動時に `init()` で `UserDefaults` から読み込み、未保存の場合はデフォルト値を使用。

---

## メモリ管理方針

多数の写真を選択しても OOM Kill されないよう、**オンデマンドロード方式**を採用。

| 方式 | メモリ使用量（100枚選択時の目安） |
|---|---|
| 一括展開（旧方式） | UIImage × 100枚 ≒ 数百MB〜1GB |
| オンデマンド（現方式） | UIImage × 最大3枚 ≒ 数十MB |

選択時は `PHAsset`（軽量なIDオブジェクト）の配列だけを保持し、表示直前に初めて `UIImage` へ展開する。表示が終わった画像は即座に破棄し、動画の一時コピーファイルも削除する。

---

## Info.plist 必須設定

| Key | Value |
|---|---|
| `NSPhotoLibraryUsageDescription` | `スライドショーのため写真へのアクセスが必要です` |

---

## デフォルト設定値

| 設定項目 | デフォルト値 |
|---|---|
| 写真表示時間 | 15秒 |
| 動画最大表示時間 | 15秒 |
| トランジション | クロスフェード |
| トランジション時間 | 1.0秒 |
| 再生モード | ループ |

---

## 操作方法

| 操作 | 動作 |
|---|---|
| 画面タップ | コントロール表示/非表示（4秒で自動非表示） |
| ⏮ ボタン | 前のメディアへ（ランダムモードは履歴を遡る） |
| ⏯ ボタン | 再生 / 一時停止 |
| ⏭ ボタン | 次のメディアへ |
| 📷 ボタン | アルバム選択画面を開く |
| ⚙️ ボタン | 設定画面を開く |
