#!/usr/bin/perl
use 5.8.1;
use strict;
#------------------------------------------------------------------------------
# Satsuki system - Startup routine (for FastCGI)
#					Copyright (C)2005-2020 nabe@abk
#------------------------------------------------------------------------------
# Last Update : 2020/05/20
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

$SIG{CHLD} = 'IGNORE';	# for fork()

#------------------------------------------------------------------------------
# socket open?
#------------------------------------------------------------------------------
my $Socket;
my $Threads = int($ARGV[1]) || 10;
if ($Threads<1) { $Threads=1; }
{
	my $path = $ARGV[0];
	if ($path) {
		$Socket  = FCGI::OpenSocket($path, $ARGV[2] || 100);
		if ($path =~ /\.sock$/ && -S $path) {	# UNIX domain socket?
			chmod(0777, $path);
		}
	}
}

#------------------------------------------------------------------------------
# Normal mode
#------------------------------------------------------------------------------
if (!$Socket) {
	&fcgi_main_loop();
	exit(0);
}

#------------------------------------------------------------------------------
# Socket/thread mode
#------------------------------------------------------------------------------
{
	require threads;
	&create_threads( $Threads, $Socket );

	while(1) {
		sleep(3);
		my $exit_threads = $Threads - $#{[ threads->list() ]} - 1;
		if (!$exit_threads) { next; }

		&create_threads( $Threads, $Socket );
	}
}
exit(0);

sub create_threads {
	my $num  = shift;
	my $sock = shift;

	foreach(1..$num) {
		my $thr = threads->create(sub {
			my $sock = shift;
			my $req  = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock );

			&fcgi_main_loop($req, 1);
			threads->detach();
		}, $sock);
		if (!defined $thr) { die "threads->create fail!"; }
	}
}

################################################################################
# FastCGI main loop
################################################################################
sub fcgi_main_loop {
	my $req    = shift || FCGI::Request();
	my $deamon = shift;

	my $modtime = (stat($0))[9];
	my $shutdown;
	while($req->Accept() >= 0) {
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
			if ($ENV{SatsukiTimer} ne '0' && $Satsuki::Timer::VERSION) {
				$timer = Satsuki::Timer->new();
				$timer->start();
			}

			#--------------------------------------------------
			# FastCGI環境初期化
			#--------------------------------------------------
			my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
			$ROBJ->{Timer}        = $timer;
			$ROBJ->{AutoReload}   = $flag;
			$ROBJ->{mod_rewrite}  = $deamon;

			$ROBJ->init_for_fastcgi($req);

			#--------------------------------------------------
			# メイン
			#--------------------------------------------------
			$ROBJ->start_up();
			$ROBJ->finish();

			$shutdown = $ROBJ->{Shutdown};
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
		if ($shutdown) { last; }
		#--------------------------------------------------
		# ライブラリのタイムスタンプ保存
		#--------------------------------------------------
		&Satsuki::AutoReload::save_lib();

		#--------------------------------------------------
		# 自分自身の更新チェック
		#--------------------------------------------------
		if ($modtime != (stat($0))[9]) { last; }
	}
	$req->Finish();
}
