#!/usr/bin/perl
use 5.8.1;
use strict;
BEGIN { unshift(@INC, './lib'); }
use Satsuki::Base ();
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for CGI)
#						Copyright 2005-2013 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2013/07/09
{
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
}
