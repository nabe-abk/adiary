#!/usr/bin/perl
use 5.8.1;
use strict;
unshift(@INC, './lib');
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for CGI)
#						Copyright (C)2005-2017 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2017/02/10
eval {
	require Satsuki::Base;

	#--------------------------------------------------
	# 時間計測開始
	#--------------------------------------------------
	my $timer;
	if ($ENV{SatsukiTimer}) {
		require Satsuki::Timer;
		$timer = Satsuki::Timer->new();
		$timer->start();
	}

	#--------------------------------------------------
	# メイン
	#--------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;		# タイマーの保存

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
X-Br: <br>

$@
HTML
}

