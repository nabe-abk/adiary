*********************************************************************
WebPushプラグイン
						(c) nabe@abk
*********************************************************************
[UTF-8]

WebPush により更新を配信できるようになります。
また手動で通知を配信することもできます。

※WebPushには「https接続が必須」です。
※ライブラリの関係から自前サーバ向けのプラグインです。

●必要なPerlライブラリ
CryptX ()
Net::SSLeay

Net::SSLeayはレンタルサーバでも大抵入っていると思いますが、
CryptX ( http://search.cpan.org/~mik/CryptX/lib/CryptX.pm )は、
手動インストールが必要になります。

RPM系ならば perl-CryptX パッケージががありますが、
Debian系ではCPANからインストールする必要があります。

●動作確認ブラウザ（2018/08）

-Chrome
-Firefox
-Edge

●WebPush登録

サイドバーなどに登録のためのボタンを配置することもできます。

	<button type="button" class="regist-webpush">登録</button>

もしくは、サイドバーの「ブログの基本情報」（des_information-ja）を使うと、
このボタンをすぐに配置できます。

●履歴

-Ver1.10  RFC準拠。Edge対応。aes128gcm encoding
-Ver1.00  First Version

