# CornixBattery

Cornix LP 分割キーボードのバッテリー残量を macOS メニューバーに表示するアプリです。

![menubar](https://img.shields.io/badge/menubar-L:85%25_R:92%25-blue)

## 機能

- BLE Battery Service (0x180F) からバッテリー残量を取得
- メニューバーに `L:xx% R:xx%` 形式で表示
- 5分ごとに自動更新
- 切断時の自動再接続
- 手動リフレッシュ / 再接続メニュー

## ビルド & 実行

```bash
git clone https://github.com/Mutafika/CornixBattery.git
cd CornixBattery
bash build.sh
open CornixBattery.app
```

**必要環境:** macOS 13+, Swift 5.9+

## 右側バッテリーの表示について

Cornix LP はデフォルトでは左側（セントラル）のバッテリーのみ BLE で公開しています。

右側も表示するには、ZMK ファームウェアの設定で以下を有効にする必要があります：

```
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

詳しくは [TODO.md](TODO.md) を参照してください。

## 注意事項

- 初回起動時に Bluetooth アクセスの許可が必要です
- Cornix LP が macOS に接続済みの状態で使用してください

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照
