The "adiary" is high performance HTML5 CMS.
This software licensed under AGPL version 3 or later.
Current Version is Japanese message only.

Require permission setting which '__cache' and 'data/' and 'pub/' is writable.
And, '__cache' and 'data/' directories not permit to access from web.
(by '.htaccess' or other way)

----------------------------------------------------------------------
[Japanese]

# 動作環境

  * Apache またはそれと互換性のあるWebサーバ
  * Perl 5.8.1以降（pure Perl可）

# インストール方法

  1. 解凍してでてきたファイルをサーバ上の任意の位置に置く
  2. adiary.cgi に実行属性を付ける
  3. __cache/, data/, pub/ を www 権限で書き込めるようにする。（suEXEC の場合は不要）
  4. adiary.conf.cgi.sample を adiary.conf.cgi としてコピーし適当にいじる
  5. adiary.cgi にアクセスし、ID、パスワードを適当に入力してログイン。
  6. その後、自分自身をユーザーとして追加する。

詳細は[オンラインマニュアル](http://adiary.org/v3man/)を参照してください。

# 著作権表示(Copyright)

 Copyright (C)2013-2016 nabe@abk.

本プログラム（システム）はフリーソフトウェアです。

AGPL(AFFERO GENERAL PUBLIC LICENSE) Vesrion 3 または
それ以降のバージョンの下で本プログラム（システム）を再配布
することが可能です。

もっと緩いライセンスをご希望の場合は、
理由を沿えてお知らせください。
考慮するかもしれません。

特にベースシステムに関しては、
より緩いライセンスへの移行も考えています。

# パッチを送られる方へ

パッチやPull Requestを送信される場合は、
必ずコードのライセンスを明記してください。
MITライセンスやWTFPLだと大変助かります。

ライセンスが不明記、
またはライセンスの内容によっては、
当方で記述し直すことがあります。
ご了承ください。

# 利用著作物

## JavaScript

以下の公開ライブラリをライセンスに基づき使用しています。

  * jQuery (MIT)
    * jQuery UI (MIT / GPLv2)
    * jquery-cookie (MIT)
    * dynatree  (MIT)
    * Color Picker (MIT / GPL)
  * Lightbox2 (Creative Commons Attribution 2.5)
  * highlight.js (BSD)

## Perl

  * ImageMagick (Apache 2.0)
  * Net::SSLeay (Perl)

## プラグインとテーマ

  * plugin/ 以下に存在するプラグインはそれぞれ個別の著作物です。
  * theme/ 以下に存在するテーマファイルはそれぞれ個別の著作物です。

ライセンスについては、各ディレクトリ内の README 等を参照してください。

## フォント

VLゴシックフォント（pub-dist/VL-PGothic-Regular.ttf）を
ライセンスに基づき同梱しています。
フォントのライセンスは pub-dist/VLGothic/ 以下を参照してください。

## 画像アイコン

  * pub-dist/album-icon  以下のアイコンの多くはせりか氏の著作物です。
  * pub-dist/album-icon/pdf.png は http://iconhoihoi.oops.jp/ の著作物です。
  * pub-dist/album-icon  以下の g-*.png と trashbox.png はGNOME Desktopアイコンです。
  * pub-dist/icon/ 以下にあるアイコンの一部はせりか氏の著作物です。
  * pub-dist/icon/tp*.gif に該当するファイルはSix Apartの著作物です。
  * pub-dist/mahjong/ 以下のファイルは「[麻雀豆腐](http://majandofu.com/mahjong-images)」の画像を利用しています。
  * theme/_img/social-buttons.png は「Simplicity (GPL)」に含まれるアイコンを元にしました。

せりか氏著作物のライセンスは、adiaryのライセンスに準じます。
