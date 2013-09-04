#!/usr/bin/perl
use 5.8.1;
use strict;
BEGIN { unshift(@INC, './lib'); }
use Satsuki::Base ();
use Satsuki::AutoReload ();
#-------------------------------------------------------------------------------
# Satsuki system - Startup routine (for mod_perl)
#						Copyright 2005-2013 nabe@abk
#-------------------------------------------------------------------------------
# Last Update : 2013/07/09
our $RELOAD;
{
	#--------------------------------------------------
	# ライブラリの更新確認
	#--------------------------------------------------
	my $flag;
	if (! $ENV{SatsukiReloadStop}) {
		$flag = &Satsuki::AutoReload::check_lib( $RELOAD );
		if ($flag) {
			require Satsuki::Base;
			$RELOAD = 0;
		}
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
	# メイン
	#--------------------------------------------------
	my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
	$ROBJ->{Timer} = $timer;
	$ROBJ->{AutoReload} = $flag;

	eval {
		$ROBJ->start_up();
		$ROBJ->finish();
	};
	if (!$ROBJ->{DIE_alter_exit} && $@) {
		$RELOAD=1;
		print "Status: 500 Internal Server Error\n";
		print "Content-Type: text/plain;\n\n";
		print "<br>\n",$@;
	} else {
		#--------------------------------------------------
		# ライブラリのタイムスタンプ保存
		#--------------------------------------------------
		if (! $ENV{SatsukiReloadStop}) {
			&Satsuki::AutoReload::save_lib();
		}
	}
}
