
リリースツール郡です。
親ディレクトリから __tool/checker.pl という風に使用してください。


checker.pl
	リリース用チェッカーです。
	文字コード、改行コード、デバッグコード（"debug"文字列のサーチ）をします。

release.sh
	リリーサーです。adiary-3.00/ 等のディレクトリを自動的に生成し、
	その中にリリース向けのファイルをコピーします。

package.sh
	リリーサーで生成したディレクトリを tar でパッケージングします。

norelease.list
	リリースしないファイル一覧


pp.bat
	Windows用adiary.exeを生成するためのバッチファイルです
pp.opt
	pp用実行オプション
pp.ico
	adiary.exe用iconファイル。置き換えると実行時エラーが起こるので置き換えせず。

