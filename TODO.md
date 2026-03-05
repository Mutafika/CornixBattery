# Cornix LP 右側バッテリー表示の有効化

## 手順

1. https://github.com/hitsmaxft/zmk-keyboard-cornix をFork
2. `config/cornix.conf` に以下を追加：
   ```
   CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
   ```
3. GitHubにpush → GitHub Actionsが自動ビルド
4. Actions → 最新のワークフロー → Artifacts から `.uf2` をダウンロード
5. 左側をUSB接続 → リセットボタンをダブルクリック → `.uf2` をドラッグ＆ドロップ
6. 右側も同様に書き込み

## 完了後

CornixBattery.app を再起動すれば `L:xx% R:xx%` の両方が表示される
