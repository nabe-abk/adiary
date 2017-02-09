#!/usr/bin/speedy
use 5.8.1;
use strict;
BEGIN { unshift(@INC, './lib'); }
use Satsuki::Base ();
use Satsuki::AutoReload ();
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for speedycgi)
#						Copyright (C)2005-2017 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2017/02/10
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
	if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
	my $timer;
	if (defined $Satsuki::Timer::VERSION) {
		$timer = Satsuki::Timer->new();
		$timer->start();
	}

	#--------------------------------------------------
	# SpeedyCGI環境初期化
	#--------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;
	$ROBJ->{AutoReload} = $flag;

	$ROBJ->init_for_speedycgi();

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
X-Speedy-Br: <br>

$@
HTML
}

#--------------------------------------------------
# ライブラリのタイムスタンプ保存
#--------------------------------------------------
&Satsuki::AutoReload::save_lib();

