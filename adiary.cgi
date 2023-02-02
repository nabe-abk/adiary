#!/usr/bin/perl
use strict;
unshift(@INC, './lib');
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for CGI)
#					Copyright (C)2005-2023 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2023/02/02
#
BEGIN {
	if ($] < 5.014) {
		my $v = int($]); my $sb = int(($]-$v)*1000);
		print "Content-Type: text/html;\n\n";
		print "Do not work with <u>Perl $v.$sb</u>.<br>Requires <strong>Perl 5.14 or newer</strong>.";
		exit(-1);
	}
};
#-------------------------------------------------------------------------------
eval {
	require Satsuki::Base;

	#---------------------------------------------------
	# 時間計測開始
	#---------------------------------------------------
	my $timer;
	if ($ENV{SatsukiTimer}) {
		require Satsuki::Timer;
		$timer = Satsuki::Timer->new();
		$timer->start();
	}

	#---------------------------------------------------
	# メイン
	#---------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;		# タイマーの保存

	$ROBJ->start_up();
	$ROBJ->finish();
};

#-------------------------------------------------
# エラー表示
#-------------------------------------------------
if (!$ENV{SatsukiExit} && $@) {
	print <<HTML;
Status: 500 Internal Server Error
Content-Type: text/plain; charset=UTF-8
X-Br: <br>

$@
HTML
}

