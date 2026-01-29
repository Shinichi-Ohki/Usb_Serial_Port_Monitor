# Mac USBシリアルポート表示メニューバーアプリ

## 概要
Macのメニューバーに常駐し、接続されているUSBシリアルポートを表示・コピーできるアプリケーション。
ポートの接続・切断時にポップアップ通知を表示します。

## プロジェクト構成

```
SerialPortMenuApp/
├── SerialPortMenuApp/
│   ├── main.swift               # エントリーポイント
│   ├── SerialPortMenuApp.swift  # AppDelegate
│   ├── SerialPortMonitor.swift  # シリアルポート監視
│   ├── MenuBarView.swift        # メニューバーUI & ポップアップ通知
│   └── Info.plist               # バンドル設定
├── SerialPortMenuApp.xcodeproj/
├── Package.swift                 # Swift Package Manager設定
├── app.png                       # カスタムアプリアイコン
├── app.icns                      # macOS用アイコン
└── SerialPortMenuApp.app/        # 完成したアプリバンドル
```

## 実装された機能

### 1. SerialPortMonitor.swift
- `/dev/cu.*` (USB通信デバイス) の検出
- 1秒ごとのポーリングでデバイス変化を監視
- `@Published` プロパティで変更を通知
- **ポートの追加・削除を検出して NotificationCenter で通知**
  - `.serialPortAdded`: ポート接続時
  - `.serialPortRemoved`: ポート切断時
- **接続順ソート機能**
  - 既存ポート: アルファベット順
  - 新規ポート: 接続順（リストの後ろに追加）
  - `connectionOrder: [String: Int]` で接続順序を管理

### 2. MenuBarView.swift
- `NSStatusItem` を使用してメニューバーに常駐
- SF Symbolの `cable.connector` アイコンを表示
- ポート数をバッジとして表示
- ポートリストをメニューとして表示
- クリックでポート名をクリップボードにコピー
- Refresh / Quit メニューアイテム
- **カスタムポップアップ通知ウィンドウ**
  - 接続時: 緑色の `plus.circle.fill` アイコン
  - 切断時: 赤色の `minus.circle.fill` アイコン
  - 3秒で自動消滅
  - 画面右上に表示

### 3. SerialPortMenuApp.swift (AppDelegate)
- `LSUIElement` でDockに表示せずメニューバーのみ
- `NSApp.setActivationPolicy(.accessory)` でバックグラウンド実行
- **`ProcessInfo.processInfo.disableSuddenTermination()` で通知表示時のアプリ終了を防止**
- **`applicationShouldTerminateAfterLastWindowClosed` でウィンドウ閉じても終了しないように設定**

### 4. main.swift
- AppKitのみを使用（SwiftUI非依存）
- `NSApplication.shared.run()` でイベントループを開始

## 技術的詳細

### フレームワーク
- **AppKit**: NSStatusItem, NSMenu, NSPasteboard, NSWindow, NSVisualEffectView
- **Foundation**: FileManager, Timer, Combine, ProcessInfo
- **Combine**: @Published, sinkでポート変化を監視

### ポップアップ通知の実装

```swift
// NotificationCenter でポート変化を受け取る
NotificationCenter.default.addObserver(
    self,
    selector: #selector(portAdded(_:)),
    name: .serialPortAdded,
    object: nil
)

// カスタムウィンドウでポップアップ表示
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), ...)
window.level = .floating
window.isReleasedWhenClosed = false  // 重要: アプリ終了防止
```

### 通知デザイン
- ぼかし効果付きの背景（`NSVisualEffectView`）
- 角丸デザイン（`cornerRadius = 12`）
- SF Symbol アイコン
- 自動レイアウトなしで固定位置配置

### Swift Package Manager設定
```swift
import PackageDescription

let package = Package(
    name: "SerialPortMenuApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SerialPortMenuApp", targets: ["SerialPortMenuApp"])
    ],
    targets: [
        .executableTarget(
            name: "SerialPortMenuApp",
            path: "SerialPortMenuApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        )
    ]
)
```

### Info.plist設定
- `LSUIElement = true`: Dockアイコンを非表示
- `CFBundleIconFile = app.icns`: カスタムアイコン

### アイコン作成手順
```bash
# PNGから各サイズのアイコンを作成
sips -z 16 16 app.png --out app.iconset/icon_16x16.png
sips -z 32 32 app.png --out app.iconset/icon_16x16@2x.png
# ... (他のサイズも作成)

# iconsetからicnsに変換
iconutil -c icns app.iconset -o app.icns
```

## ビルドと実行

### ビルド
```bash
cd "/Volumes/SN7100_4TB/Project/MacでUSBシリアルポートを表示するメニューバーアプリ"
swift build
```

### 実行
```bash
open SerialPortMenuApp.app
```

### アプリバンドルの手動作成
```bash
mkdir -p SerialPortMenu.app/Contents/MacOS
mkdir -p SerialPortMenu.app/Contents/Resources
cp .build/arm64-apple-macosx/debug/SerialPortMenuApp SerialPortMenu.app/Contents/MacOS/
cp app.icns SerialPortMenu.app/Contents/Resources/
```

**注意**: 現在のリリースバイナリは ARM64 (Apple Silicon) 専用です。Intel Mac では動作しません。

## 検証された機能

1. ✅ メニューバーにアイコンが表示される
2. ✅ シリアルポートが検出される（4ポート検出済み）
   - cu.ACEFASTT1
   - cu.Bluetooth-Incoming-Port
   - cu.debug-console
   - cu.soundcoreLiberty4
3. ✅ メニューを展開してポート名が表示される
4. ✅ ポート名をクリックしてクリップボードにコピーされる
5. ✅ デバイス抜き挿しでメニューが更新される（1秒ポーリング）
6. ✅ ポート接続時にポップアップ通知が表示される
7. ✅ ポート切断時にポップアップ通知が表示される
8. ✅ 通知が消えてもアプリは終了しない
9. ✅ 接続順ソートが正しく動作する
10. ✅ **M4 Macで動作確認済み**

## トラブルシューティング

### セグメンテーションフォールトの解決
- `UNUserNotificationCenter` を削除（バンドル構造の問題）
- SwiftUIの `@main` を削除し、純粋なAppKitに変更
- `main.swift` を分離してエントリーポイントを明確化

### 通知表示時のアプリ終了問題の解決
- `window.isReleasedWhenClosed = false` を設定
- `ProcessInfo.processInfo.disableSuddenTermination()` を呼び出し
- `applicationShouldTerminateAfterLastWindowClosed` で false を返す

### バンドルリソースの読み込み
- Swift Package Managerのビルドでは `Bundle.main.path` が期待通り動作しない場合がある
- 実行ファイルからの相対パスでのリソース読み込みを実装

## 今後の改善案

1. ~~**通知機能**: コピー完了時の通知を再実装（バンドル対応版）~~ ✅ 完了
2. **IOKitによるリアルタイム監視**: ポーリングの代わりにIOKitの通知を使用
3. **設定画面**: ポーリング間隔や表示設定の変更
4. **ポート名のカスタマイズ**: エイリアス設定など
5. **配布用の署名**: 公開用のコード署名と公证
6. **通知の音**: 接続・切断時に音を鳴らす

## GitHub公開情報

- **リポジトリ名**: `Usb_Serial_Port_Monitor`
- **ユーザー名**: `Shinichi-Ohki`
- **URL**: https://github.com/Shinichi-Ohki/Usb_Serial_Port_Monitor
- **ライセンス**: MIT License
- **動作環境**: macOS 14.0 以降、Apple Silicon (M1/M2/M3/M4) のみ
- **リリース**: v1.0.0 (2026-01-29)

## 更新履歴

### 2026-01-29 (v1.0.0 リリース)
- ポート接続・切断時のポップアップ通知機能を追加
- 通知表示時のアプリ終了問題を修正
- NotificationCenterを使用したポート変化検出を実装
- **接続順ソート機能を追加**: 既存ポートはアルファベット順、新規ポートは接続順
- GitHubで公開: README.md, LICENSE (MIT) 作成
- v1.0.0 リリース作成 (Usb_Serial_Port_Monitor-v1.0.0.zip)
- Intel Mac対応を削除 (Apple Silicon専用)
