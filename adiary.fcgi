#!/usr/bin/perl
use 5.8.1;
use strict;
BEGIN {
	unshift(@INC, './lib');
	$0 =~ m|^(.*?)[^/]*$|;
	chdir($1);
}
use Satsuki::Base ();
use Satsuki::AutoReload ();
use FCGI;
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for FastCGI)
#						Copyright 2005-2016 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2016/11/18
#--------------------------------------------------
# socket open?
#--------------------------------------------------
my $socket;
my $request;
if ($ARGV[0]) {
	$socket  = FCGI::OpenSocket($ARGV[0], $ARGV[1] || 100);
	$request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%ENV, $socket );
} else {
	$request = FCGI::Request();
}
#--------------------------------------------------
# FastCGI メインループ
#--------------------------------------------------
while($request->Accept() >= 0) {
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
	# FastCGI環境初期化
	#--------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;
	$ROBJ->{AutoReload} = $flag;

	$ROBJ->init_for_fastcgi($request);

	#--------------------------------------------------
	# メイン
	#--------------------------------------------------
	eval {
		$ROBJ->start_up();
		$ROBJ->finish();
	};
	if (!$ROBJ->{DIE_alter_exit} && $@) {
		print <<TEXT;
Status: 500 Internal Server Error
Content-Type: text/plain

$@
TEXT
		last;
	}

	#--------------------------------------------------
	# ライブラリのタイムスタンプ保存
	#--------------------------------------------------
	if (! $ENV{SatsukiReloadStop}) {
		&Satsuki::AutoReload::save_lib();
	}
}
# close
$socket && FCGI::CloseSocket($socket);
