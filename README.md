# ChatWorkKeeper

ChatWorkのメッセージとファイルをダウンロードするスクリプト。  
[Red言語](https://github.com/red/red)で実装されています。

## 免責事項

作成者はこのプログラムの実行に関して一切の責任を負いません。  
自己責任でご利用ください。

メッセージは1つのチャットルームにつき直近の100件のみ取得できます。  
これはChatWorkのWEB APIの制限仕様です。

## 対応OS

Windows 10で動作確認しています。  
MacやLinuxは言語上はコンパイルターゲットに指定可能ですが、動作未確認です。

## 使い方

* 起動後の画面で`ChatWork APIキー`と`保存先フォルダ`を指定して実行してください。

* ChatWork APIキーにはAPIキーを入力します
* 保存先フォルダにデータの保存を行うフォルダを入力します

かなりの数のファイルがダウンロードされる可能性があるため、保存先のディスク容量には注意してください

* 実行ボタンを押して、「処理が終了しました。」と表示されるまで待ちます

残念ながらRed言語がまだ非同期処理に対応していないため、実行中は画面が固まります。  
途中でやめたい場合はタスクマネージャーなどで直接プロセスを停止させてください。

## 再実行時の処理について

指定した出力フォルダに、以前ダウンロードしたファイルがある場合、そのデータはスキップして再ダウンロードは行いません。  
途中でエラーになったり停止させた場合、次の実行時に同じ出力先フォルダを指定すると処理時間の短縮になります。