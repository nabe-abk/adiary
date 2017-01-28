*********************************************************************
AMP対応プラグイン
						(c) nabe@abk
*********************************************************************
[UTF-8]

サイトをGoogle AMP(Accelerated Mobile Pages)に対応させます。
単一記事を表示してる状態で「?amp」を追加して表示確認することもできます。

・Google Analytics IDが設定されていれば、AMPページも解析できます。

・画像サイズは自動設定されますが、これは最初に記事がAMP表示された時に行われます。
　更新するためには記事を再保存するか、再構築してください。

・使用テーマがスマホに対応していれば、AMP表示はスマホ画面に準拠します。
　JavaScript等で要素順を入れ替えてるテーマは一部表示が崩れることがあります。

https://www.ampproject.org/docs/reference/components

●使用ライブラリ

Image::Magick
Net::SSLeay

●対応している自動変換

-<img>
-<audio>
-<video>  : width / height を指定するようにしてください。
-<iframe> : width / height を指定するようにしてください。
-YouTube
-Twitter
