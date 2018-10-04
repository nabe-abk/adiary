#!/usr/bin/perl
use 5.8.1;
use strict;
BEGIN { unshift(@INC, './lib'); }
use Satsuki::Base ();
use Satsuki::AutoReload ();
BEGIN {
	if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
}
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for mod_perl)
#						Copyright (C)2005-2018 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2018/10/04
eval {
	#--------------------------------------------------
	# ライブラリの更新確認
	#--------------------------------------------------
	my $flag = &Satsuki::AutoReload::check_lib();
	if ($flag) {
		$Satsuki::Base::RELOAD = 1;	# Base.pmコンパイルエラー時
		require Satsuki::Base;		# 次回、強制RELOADさせる。
		$Satsuki::Base::RELOAD = 0;
	}

	#--------------------------------------------------
	# 時間計測開始
	#--------------------------------------------------
	my $timer;
	if ($Satsuki::Timer::VERSION) {
		$timer = Satsuki::Timer->new();
		$timer->start();
	}

	#--------------------------------------------------
	# FastCGI環境初期化
	#--------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;
	$ROBJ->{AutoReload} = $flag;

	#--------------------------------------------------
	# メイン
	#--------------------------------------------------
	$ROBJ->start_up();
	$ROBJ->finish();

};
#--------------------------------------------------
# エラー表示
#--------------------------------------------------
if (!$ENV{SatsukiExit} && $@) {
	print <<HTML;
Status: 500 Internal Server Error
Content-Type: text/plain; charset=UTF-8
X-modperl-Br: <br>

$@
HTML
}

#--------------------------------------------------
# ライブラリのタイムスタンプ保存
#--------------------------------------------------
&Satsuki::AutoReload::save_lib();

