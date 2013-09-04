#!/usr/bin/speedy
use 5.8.1;
use strict;
BEGIN { unshift(@INC, './lib'); }
use Satsuki::Base ();
use Satsuki::AutoReload ();
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for speedycgi)
#						Copyright 2005-2012 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2013/07/09
{
	#--------------------------------------------------
	# ライブラリの更新確認
	#--------------------------------------------------
	my $flag;
	if (! $ENV{SatsukiReloadStop}) {
		$flag = &Satsuki::AutoReload::check_lib();
		if ($flag) { require Satsuki::Base; }
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

	#--------------------------------------------------
	# ライブラリのタイムスタンプ保存
	#--------------------------------------------------
	if (! $ENV{SatsukiReloadStop}) {
		&Satsuki::AutoReload::save_lib();
	}
}
