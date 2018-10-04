#!/usr/bin/perl
use 5.8.1;
use strict;
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for FastCGI)
#						Copyright (C)2005-2018 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2018/10/04
BEGIN {
	unshift(@INC, './lib');
	$0 =~ m|^(.*?)[^/]*$|;
	chdir($1);
}
use FCGI;
use Satsuki::Base ();
use Satsuki::AutoReload ();
BEGIN {
	if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
}
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
my $modtime = (stat($0))[9];
my $reload;
while($request->Accept() >= 0) {
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

		$ROBJ->init_for_fastcgi($request);

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
Content-Type: text/plain; charset=UTF8
X-FCGI-Br: <br>

$@
HTML
	}
	#--------------------------------------------------
	# ライブラリのタイムスタンプ保存
	#--------------------------------------------------
	&Satsuki::AutoReload::save_lib();

	#--------------------------------------------------
	# 自分自身の更新チェック
	#--------------------------------------------------
	if ($modtime != (stat($0))[9]) { $reload=1; last; }
}
# close
$request->Finish();
$socket && FCGI::CloseSocket($socket);

#--------------------------------------------------
# 自分自身を再起動
#--------------------------------------------------
if ($reload && $socket) {
	my $opt = $ARGV[0];
	my $max = $ARGV[1];
	$max =~ s/[^\d]//g;
	while(1) { exec($0, $opt, $max); }
}
