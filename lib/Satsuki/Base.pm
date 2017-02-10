use strict;
#------------------------------------------------------------------------------
# Base system functions for satsuki system
#						Copyright(C)2005-2017 nabe@abk
#------------------------------------------------------------------------------
package Satsuki::Base;
#------------------------------------------------------------------------------
our $VERSION = '2.20';
our $RELOAD;
#------------------------------------------------------------------------------
my $SYSTEM_CACHE_DIR = '__cache/';
my $_SALT = '8RfoZYxLBkqeQFMd0l.pEmVCuAyUDO9b/3wSi5Trn47IzcHKPvGgsXhjNt126JWa';
#------------------------------------------------------------------------------
# 文字コード等のデフォルト設定。
my $SYSTEM_CODING = 'UTF-8';
my $CODE_LIB = 'Jcode';
my $LOCALE = 'ja';
#------------------------------------------------------------------------------
use Satsuki::AutoLoader;
use Fcntl;		# for sysopen/flock
###############################################################################
# ■コンストラクタ
###############################################################################
# sub DESTROY { print "<br>ROBJ destroy!!!"; }
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = $self;

	# グローバル変数、特殊変数
	$self->{VERSION} = $VERSION;
	$self->{ENV}  = \%ENV;
	$self->{INC}  = \%INC;
	$self->{ARGV} = \@ARGV;
	$self->{UID}  = $<;
	$self->{GID}  = $(;
	$self->{PID}  = $$;
	$self->{Is_windows} = ($^O eq 'MSWin32' || $^O eq 'MSWin64');

	# 初期設定
	$self->{Status}  = 200;		# HTTP status (200 = OK)
	$self->{SALT64chars}  = $_SALT;	# SALT生成用文字列
	$self->{Form_options} = {};		# form用設定
	$self->{Loadpm_cache} = {};		# load済ライブラリ用Hash
	$self->{CGI_mode}     = 'CGI-Perl';
	$self->{Secret_word}  = '';
	$self->{Content_type} = 'text/html';
	$self->{Headers}      = [];		# ヘッダ出力バッファ

	# 内部文字コード
	$self->{System_coding} = $SYSTEM_CODING;
	$self->{Code_lib} = $CODE_LIB;
	$self->{Locale}  = $LOCALE;
	$self->{Locale2} = $LOCALE;

	# 時刻／日付関連の設定
	$self->{TM} = time;
	$self->{WDAY_name} = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
	$self->{AMPM_name} = ['AM','PM','AM'];	# 午前, 午後, 深夜
	$self->init_tm();

	# スケルトン関連、ネストcall/jumpによる無限ループ防止設定
	$self->{Skeleton_ext}    = '.html';
	$self->{Jump_count}      = 0;
	$self->{Nest_count}      = 0;
	$self->{Nest_count_base} = 0;
	$self->{Nest_max}        = 99;

	# error / debug
	$self->{Error}   = [];
	$self->{Debug}   = [];
	$self->{Warning} = [];
	$self->{Message} = [];

	# コンパイラの更新時間を保存
	$self->{Compiler_tm} = $self->get_libfile_modtime( 'Satsuki/Base/Compiler.pm' );

	# mod_perl初期化, get_filepath() 有効化
	if ($ENV{MOD_PERL}) { $self->init_for_mod_perl(); }

	#-------------------------------------------------------------
	# スケルトンキャッシュ関連
	#-------------------------------------------------------------
	my $cache_dir = $self->get_filepath( $ENV{SatsukiCacheDir} || $SYSTEM_CACHE_DIR );
	if (-d $cache_dir && -w $cache_dir) {
		$self->{__cache_dir} = $cache_dir;
	}
	return $self;
}

###############################################################################
# ■メイン
###############################################################################
my %CacheChecker;
#------------------------------------------------------------------------------
# ●スタートアップ (起動スクリプトから最初に呼ばれる)
#------------------------------------------------------------------------------
sub start_up {
	my $self = shift;

	my $cmd = $0;	# $ENV{SCRIPT_NAME} はレンタルサーバでは信用できない
	if (substr($^O,0,5) eq 'MSWin') { $cmd =~ tr|\\|/|; }
	my $cgi = substr($cmd, rindex($cmd, '/')+1) || $cmd;
	$self->{CMD_file} = $cmd;
	$self->{CGI_file} = $cgi;
	if ((my $x = rindex($cgi, '.'))>0) { $cgi=substr($cgi, 0, $x); }
	if ((my $x = rindex($cgi, '.'))>0) { $cgi=substr($cgi, 0, $x); }

	# .env があれば先に処理
	$self->{ENV_file} = $self->get_filepath( $cgi . '.env.cgi' );
	if (-r $self->{ENV_file}) {
		$self->_call($self->{ENV_file});
	}

	# cache checker
	my $checker = %CacheChecker{$cmd};
	if ($checker && &$checker($self)) {
		return;
	}

	# 初期化処理
	$self->init_tm();
	$self->init_path();

	# conf解析
	$self->{Conf_file}   = $cgi . '.conf.cgi';
	$self->{Conf_result} = $self->_call($self->{Conf_file});

	# 致命的エラーがあった場合、表示して終了
	if ($self->{Error_flag}) {
		my $err = $self->error_load_and_clear("\n");
		$self->set_status(500);
		$self->print_http_headers('text/plain');
		$self->output_array([$err]);
		$self->exit(-1);
	}

	# メインルーチンの実行
	my $main = $self->{Main};
	if (defined $main && $main->can('main')) {
		$main->main();
	} else {
		$self->main();	# すぐ下のルーチン
	}
}

#------------------------------------------------------------------------------
# ●conf.cgi の中身をそのまま出力するだけのメインルーチン
#------------------------------------------------------------------------------
sub main {
	my $self = shift;
	$self->print_http_headers();
	$self->output_array($self->{Conf_result});
}

#------------------------------------------------------------------------------
# ●時刻の初期化
#------------------------------------------------------------------------------
sub init_tm {
	my ($self, $tz) = @_;
	my $h = $self->time2timehash( $self->{TM} );
	$self->{Now} = $h;
	$self->{Timestamp} = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
			$h->{year}, $h->{mon}, $h->{day}, $h->{hour}, $h->{min}, $h->{sec});
}

#------------------------------------------------------------------------------
# ●初期環境変数の設定（パス解析など）
#------------------------------------------------------------------------------
# 動作確認環境：Apache 1.3.x/2.x, Nginx
# Last update : 2016/11/18 --- この部分は無闇に書き換えないこと。
#
sub init_path {
	my $self = shift;
	if ($self->{Initialized_path}) { return; }
	my $cgi = $self->{CGI_file};

	# cgiファイル名、ディレクトリ設定
	my $req_uri = $ENV{REQUEST_URI};
	my $query   = '';
	if ((my $x = index($req_uri, '?')) >= 0) {
		$query   = substr($req_uri, $x+1);
		$req_uri = substr($req_uri, 0, $x);
	}
	if (index($req_uri, '%') >= 0) {
		$req_uri =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
	}

	# mod_rewrite時に %3f が"?"に復元されてしまうバグ対処（Apache）
	$ENV{QUERY_STRING_orig} = $ENV{QUERY_STRING};
	$ENV{QUERY_STRING} = $query;

	# ModRewrite flag
	my $rewrite = $self->{Mod_rewrite} ||= $ENV{Mod_rewrite};
	if (!defined $rewrite && exists $ENV{REDIRECT_URL} && $ENV{REDIRECT_STATUS}==200) {
		$self->{Mod_rewrite} = $rewrite = 1;
	}

	# REQUEST URI からベースパスを割り出す
	my $basepath = $self->{Basepath} ||= $ENV{Basepath};
	if (!defined $basepath) {
		my $script = $ENV{SCRIPT_NAME};
		if (index($req_uri, $script)==0) {
			$basepath = substr($script, 0, length($script) - length($cgi));
		} else {
			while( index($req_uri, $script)!=0 ) {
				chop($script);
				my $x = rindex($script, '/');
				$script = substr($script, 0, $x+1);
			}
			$basepath = $script;
		}
		$self->{Basepath} = $basepath;
	}

	my $req_base = $basepath . ($rewrite ? '' : $cgi);
	if ($rewrite) { chop($req_base); }
	$self->{Request_base} = $req_base;

	# 文字コード問題、// が / になる問題の対応のため REQUEST_URI から PATH_INFO を生成
	$ENV{PATH_INFO_orig} = $ENV{PATH_INFO};
	$ENV{PATH_INFO} = substr($req_uri, length($req_base));

	# 自分自身（スクリプト）にアクセスする URL/path
	if (!exists $self->{Myself}) {
		if ($rewrite) {
			$self->{Myself}  = $self->{Myself2} = $basepath;
		} elsif (substr($req_base, rindex($req_base, '/')+1) eq $cgi) {		# 通常のcgi
			$self->{Myself}  = $basepath . $cgi;
			$self->{Myself2} = $basepath . $cgi . '/';	# PATH_INFO用
		} else {	# cgi が DirectoryIndex
			$self->{Myself}  = $basepath;
			$self->{Myself2} = $basepath . $cgi . '/';	# PATH_INFO用
		}
	}

	# プロトコル判別
	if (!$self->{Server_url}) {
		my $port = int($ENV{SERVER_PORT});
		my $protocol = ($port == 443) ? 'https://' : 'http://';
		$self->{Server_url} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
	} else {
		substr($self->{Server_url},-1) eq '/' && chop($self->{Server_url});
	}

	# copyright
	$ENV{PATH_INFO} eq '/__getcpy' && print "X-Satsuki-System: Ver$VERSION (C)nabe\@abk\n";
	# パス初期化済フラグ
	$self->{Initialized_path} = 1;
}
###############################################################################
# ■終了処理
###############################################################################
#------------------------------------------------------------------------------
# ●終了前処理
#------------------------------------------------------------------------------
sub finish {
	my $self = shift;

	# メモリリーク対策 & 各デストラクタ呼び出し
	$Satsuki::DESTROY_debug = $self->{DESTROY_debug};
	if ($self->{DESTROY_debug}) {
		print '<pre id="destroy-debug"><strong>***DESTROY debug***</strong>'."\n";
	}
	$self->object_free_finish( $self );

	# エラー情報の表示
	my $error = $self->{Error};
	if ($self->{Develop} && @$error) {
		if ($ENV{SERVER_PROTOCOL} && $self->{Content_type} eq 'text/html') {
			print "<hr><strong>(ERROR)</strong><br>\n",join("<br>\n", @$error);
		} else { print "\n\n(ERROR) ",join("\n", @$error); }
	}
}

#------------------------------------------------------------------------------
# ●オブジェクト開放ルーチン
#------------------------------------------------------------------------------
# 循環参照を多用するため、それを含めて変数を開放する
# ※オブジェクト および HASH 循環参照のみ対応
sub object_free_finish {
	my $self = shift;
	my $h = shift;
	$h->{"_**objcheck"}=1;
	if ($h->can('Finish')) {
		$self->{DESTROY_debug} && print "CALL Finish() in $h\n";
		$h->Finish();
	}
	foreach(keys(%$h)) {
		my $r = ref($h->{$_}) || next;
		if (substr($r,0,7) ne 'Satsuki') { next; }
		if (!$h->{$_}->{"_**objcheck"}) {
			$self->object_free_finish($h->{$_});
		}
		$h->{$_} = undef;
	}
}

#------------------------------------------------------------------------------
# ●終了命令
#------------------------------------------------------------------------------
sub exit {
	my $self = shift;
	my $ext  = shift;
	$self->finish();	# 終了前処理
	$self->{Exit}  = $ext;
	$self->{Break} = -2;
	$ENV{SatsukiExit} = 1;
	die("exit($ext)");
}

###############################################################################
# ■executor
###############################################################################
#------------------------------------------------------------------------------
# ●コンパイル済のデータを実行する
#------------------------------------------------------------------------------
sub execute {
	my ($self, $subroutine) = @_;
	if (ref $subroutine ne 'CODE') {
		my ($pack, $file, $line) = caller;
		$self->error_from("line $line at $file : $self->{__src_file}", "[executor] Can't execute string '%s'", $subroutine);
		return ;
	}

	#------------------------------------------------------------
	# ○ネストチェック（無限ループ防止）
	#------------------------------------------------------------
	$self->{Nest_count}++;	# パーサーのネストカウンタ
	if ($self->{Nest_count} > $self->{Nest_max}) {
		my $err = $self->error_from('', '[executor] Too depth nested call (max %d)', $self->{Nest_max});
		$self->{Nest_count}--;
		$self->{Break} = 2;
		return "<h1>$err</h1>";
	}

	#------------------------------------------------------------
	# ○executor（本体）
	#------------------------------------------------------------
	my @output;
	my $line;
	local($self->{Is_function});
	{
		## $self->{Timer}->start($self->{__src_file});
		my $v_ref;
		$self->{Return} = undef;
		eval{ $self->{Return} = &$subroutine(\@output, $self, $line, $v_ref); };
		$v_ref && ($self->{v} = $$v_ref);			# vを書き戻す
		if ($ENV{SatsukiExit}) { die($self->{Exit}); }		# exit代わりのdie検出
		## ($self->{"times"} ||= {})->{"$self->{__src_file}"} = $self->{Timer}->stop($self->{__src_file});
	}

	# break
	my $break = int($self->{Break});
	if (!$break && $@) {
		$self->set_status(500);
		my $err = $@;
		foreach(split(/\n/, $err)) {
			$self->error_from("line $line at $self->{__src_file}", "[executor] $_");
		}
		$RELOAD = 1;
	}

	#------------------------------------------------------------
	# ○後処理
	#------------------------------------------------------------
	$self->{Nest_count}--;		# ネストカウンタ

	while($break) {
		my $break_level = abs($break);
		# braek level 1 のとき、同一 callレベル 内で break
		if ($break_level==1 && $self->{Nest_count} > $self->{Nest_count_base}) { last; }
		# braek level 2 以上のとき、ネストレベル 0 まで break (super break)
		if ($break_level >1 && $self->{Nest_count} > 0) { last; }
		# 負数は現在までの処理結果を破棄
		if ($break < 0) { @output = (); }
		$self->{Break} = 0;
		# jump or call ?
		if ($self->{Jump_file}) {		# jump 処理
			$self->{Jump_count}++;
			if ($self->{Jump_count} < $self->{Nest_max}) {
				my ($jump_file, $jump_skel) = ($self->{Jump_file}, $self->{Jump_skeleton});
				undef $self->{Jump_file};
				undef $self->{Jump_skeleton};
				push(@output, $self->__call($jump_file, $jump_skel, @{ $self->{Jump_argv} }));
			} else {
				my $err = $self->error_from('', "[executor] Too many jump (max %d)", $self->{Nest_max});
				push(@output, "<h1>$err</h1>");
			}
		}
		last;
	}

	# functionとしてreturn値を取る？
	return $self->{Is_function} ? $self->{Return} : ($#output==0 ? $output[0] : \@output);
}

###############################################################################
# ■スケルトン呼び出し
###############################################################################
#------------------------------------------------------------------------------
# ●低レベル call
#------------------------------------------------------------------------------
my %SkelCache;
sub __call {
	my $self         = shift;
	my $src_file_org = shift;
	my $skel_name    = shift;

	my $src_file = $self->get_filepath($src_file_org);
	my $cache_file;
	if ($self->{__cache_dir}) {
		my $f = $src_file;
		$f =~ s/([^\w\.\#])/'%' . unpack('H2', $1)/eg;
		$cache_file = $self->{__cache_dir} . $f . '.cache';
	}

	# ソースファイルを読み込めない
	if (!-r $src_file) {
		if ($cache_file) { unlink($cache_file); }	# キャッシュ削除
		$self->error("[call] failed - Can't read file '%s'", $src_file || $skel_name . $self->{Skeleton_ext} );
		return undef;
	}

	#------------------------------------------------------------
	# メモリキャッシュロード
	#------------------------------------------------------------
	my $skel   = $SkelCache{$src_file};
	my $src_tm = (stat($src_file)) [9];

	# $self->debug("*** Call $src_file ***");
	#------------------------------------------------------------
	# 有効なキャッシュか確認
	#------------------------------------------------------------
	if ($cache_file && ($skel->{src_tm} != $src_tm || $skel->{compiler_tm} != $self->{Compiler_tm})) {
		# ファイルからキャッシュロード
		$skel = $self->load_cache($cache_file);

		# キャッシュが有効か確認する
		if (!$skel || $skel->{compiler_tm} != $self->{Compiler_tm} || $skel->{src_tm} != $src_tm) {
			# $self->debug("Unload cache file : $src_file");
			unlink($cache_file);
			$skel = undef
		}
	}

	#------------------------------------------------------------
	# キャッシュがない場合ソースファイルをコンパイル
	#------------------------------------------------------------
	if (! $skel) {
		$skel = {
			arybuf => $self->compile($cache_file, $src_file_org, $src_file, $src_tm),
			src_tm => $src_tm,
			compiler_tm => $self->{Compiler_tm}
		};
	}

	#------------------------------------------------------------
	# Perl構文コンパイル
	#------------------------------------------------------------
	my $arybuf = $skel->{arybuf};
	if (!$skel->{executable}) {
		my $error;
		foreach (@$arybuf) {
			my $x = $_;
			eval "\$_ = $_";
			if ($@) { $self->error_from("at $src_file", "[perl-compiler] $@"); $error=1; }
		}
		if ($error) { return undef; }
		$skel->{executable} = 1;

		# メモリキャッシュに保存
		if (-r $cache_file) {
			$SkelCache{$src_file} = $skel;
		}
	}

	#------------------------------------------------------------
	# 実行処理
	#------------------------------------------------------------
	my $c = $self->{__cont_level};
	local ($self->{argv}, $self->{__src_file}, $self->{__skeleton}, $self->{Nest_count_base});
	$self->{argv}            = \@_;
	$self->{__src_file}      = $src_file_org;
	$self->{__skeleton}      = $skel_name;
	$self->{Nest_count_base} = $self->{Nest_count};
	return $self->execute( $arybuf->[0] );
}

#------------------------------------------------------------------------------
# ●キャッシュのロード
#------------------------------------------------------------------------------
sub load_cache {
	my ($self, $file) = @_;
	my %cache;

	if (!-r $file) { return; }

	local($/) = "\0";	# デリミタ変更
	my $lines = $self->fread_lines($file);
	# 全データからデリミタ除去
	foreach(@$lines) { chop(); }

	shift(@$lines);	# 注意書き読み捨て
	my $version = shift(@$lines);
	$version = substr($version, index($version, '=')+1);
	if ($version < 1.01) { return; }	# 失敗

	# このキャッシュを生成したコンパイラのタイムスタンプ(UTC)
	$cache{compiler_tm} = shift(@$lines);
	# このキャッシュの生成に使用したソースファイルのタイムスタンプ(UTC)
	$cache{src_tm}      = shift(@$lines);

	# ルーチンバッファの読み込み
	my @arybuf;
	my $arys = shift(@$lines) + 0;
	for(my $i=0; $i<$arys; $i++) {
		push(@arybuf, shift(@$lines));
	}
	# 予備１
	my $rows = shift(@$lines) + 0;
	for(my $i=0; $i<$rows; $i++) {
		shift(@$lines);
	}
	# 予備２
	my $rows = shift(@$lines) + 0;
	for(my $i=0; $i<$rows; $i++) {
		shift(@$lines);
	}
	# 予備３
	$rows = shift(@$lines) + 0;
	for(my $i=0; $i<$rows; $i++) {
		shift(@$lines);
	}

	# @$lines が空であるかチェック
	if ($#$lines != -1) { return (2); }	# 失敗

	$cache{arybuf} = \@arybuf;
	return \%cache;
}

###############################################################################
# ■制御構文
###############################################################################
#------------------------------------------------------------------------------
# ●パーサーの中断処理
#------------------------------------------------------------------------------
sub break {
	my ($self, $break_level) = @_;
	$self->{Break} = int($break_level) || 1;
}
sub break_clear {	# 今までの内容破棄
	my $self = shift;
	$self->{Break} = -1;
}
sub superbreak {	# callネストをすべてbreak
	my $self = shift;
	$self->{Break} = 2;
}
sub superbreak_clear {	# callネストをすべてbreak/clear
	my $self = shift;
	$self->{Break} = -2;
}
#------------------------------------------------------------------------------
# ●beginブロックの実行
#------------------------------------------------------------------------------
sub exec {
	my $self = shift;
	my $ary  = shift;
	if (! @_) { return $self->execute($ary); }
	# 引数あり
	my $backup = $self->{argv};
	$self->{argv} = \@_;
	my $r = $self->execute($ary);
	$self->{argv} = $backup;
	return $r;
}

#------------------------------------------------------------------------------
# ●別ファイルへの処理移行
#------------------------------------------------------------------------------
sub jump_clear {
	my $self = shift;
	$self->{Break} = -1;
	return $self->jump(@_);
}
sub superjump {		# callネストをすべてbreak
	my $self = shift;
	$self->{Break} = 2;
	return $self->jump(@_);
}
sub superjump_clear {	# callネストをすべてbreak & clear
	my $self = shift;
	$self->{Break} = -2;
	return $self->jump(@_);
}

sub jump {
	my $self = shift;
	my $file = shift;
	$file =~ s/[^\w\/]//g;
	my ($jump_file, $dummy, $skel_level) = $self->check_skeleton($file);

	$self->{Break} ||= 1;
	if ($jump_file eq '') {	# not Found
		$self->error("[jump] failed - File not found '%s'", $file);
		return ;
	}
	$self->{Jump_file}     = $jump_file;
	$self->{Jump_skeleton} = $file;
	$self->{Jump_argv}     = \@_;
	$self->{__cont_level}  = $skel_level -1;
	return ;
}

# 低レベル（ファイル指定）
sub _jump {
	my $self              = shift;
	$self->{Jump_file}    = shift;
	$self->{Jump_skeleton} = undef;
	$self->{Break}        = 1;
	$self->{argv}         = \@_;
	return ;
}
#------------------------------------------------------------------------------
# ●ユーザーskeleton からよりレベルの低いスケルトンへの移行（継続処理）
#------------------------------------------------------------------------------
sub continue {
	my $self = shift;
	my $file = $self->{__skeleton};
	if ($self->{__cont_level}<0) { die "Can't continue($self->{__cont_level})."; }

	my ($jump_file, $dummy, $skel_level) = $self->check_skeleton($file, $self->{__cont_level});
	$self->{Jump_file}    = $jump_file;
	$self->{Jump_skeleton}= $file;
	$self->{Break}        = 1;
	$self->{Jump_argv}    = $self->{argv};
	$self->{__cont_level} = $skel_level -1;
}

#------------------------------------------------------------------------------
# ●別ファイルの呼び出し
#------------------------------------------------------------------------------
sub call {
	my $self = shift;
	my $skeleton_name = shift;
	$skeleton_name =~ s|[^\w/\-]||g;
	
	my ($call_file, $dummy, $skel_level) = $self->check_skeleton($skeleton_name);
	local ($self->{FILE}) = $skeleton_name;
	local ($self->{__cont_level});
	$self->{__cont_level} = $skel_level -1;
	return $self->__call($call_file, $skeleton_name, @_);
}
# 低レベルコール（ファイル指定）
sub _call {
	my $self = shift;
	my $file = shift;
	return $self->__call($file, undef, @_);
}


###############################################################################
# ■スケルトンシステム関連
###############################################################################
#------------------------------------------------------------------------------
# ●スケルトンディレクトリの登録
#------------------------------------------------------------------------------
sub regist_skeleton {
	my $self = shift;
	my $dir  = shift;
	my $level = shift || 0;
	if ($dir eq '') { 
		$self->message("Skeleton dir is '' in regist_skeleton.(level=%d)", $level);
		return;
	}

	my $dirs = $self->{Sekeleton_dir} ||= {};
	$dirs->{$level} = $dir;
	$self->{Sekeleton_dir_levels} = [ sort {$b <=> $a} keys(%$dirs) ];
}

#------------------------------------------------------------------------------
# ●スケルトンディレクトリの削除（引数：level）
#------------------------------------------------------------------------------
sub delete_skeleton {
	my $self = shift;
	my @r;
	foreach(@_) {
		push(@r, $self->{Sekeleton_dir}->{$_});
		delete $self->{Sekeleton_dir}->{$_};
	}
	return wantarray ? @r : $r[0];
}

#------------------------------------------------------------------------------
# ●スケルトンファイルの確認
#------------------------------------------------------------------------------
# 存在し、読み込み可能ならばファイル名（相対パス）を返す
#
sub check_skeleton {
	my $self  = shift;
	my $name  = $self->{Skeleton_subdir} . (shift) . $self->{Skeleton_ext};
	my $level = defined $_[0] ? shift : 0x7fffffff;

	my $dirs = $self->{Sekeleton_dir};
	if (!$dirs || !%$dirs) { return; }	# error

	foreach(@{ $self->{Sekeleton_dir_levels} }) {
		if ($_>$level) { next; }
		my $file = $dirs->{$_} . $name;
		if (-r (my $x = $self->get_filepath($file))) {
			return wantarray ? ($file, $x, $_): $file;
		}
	}
	return;		# error
}

###############################################################################
# ■出力処理
###############################################################################
#------------------------------------------------------------------------------
# ●ヘッダの設定
#------------------------------------------------------------------------------
sub set_header {
	my ($self, $name, $val) = @_;
	push(@{ $self->{Headers} }, "$name: $val\n");
	if ($name eq 'Status') { $self->{Status} = $val; }
}
sub set_status {
	my ($self, $status) = @_;
	$self->{Status} = $status;
}
sub set_content_type {
	my $self = shift;
	$self->{Content_type} = shift;
}
#------------------------------------------------------------------------------
# ●ヘッダを出力
#------------------------------------------------------------------------------
sub print_http_headers {
	my ($self, $ctype, $charset) = @_;
	if ($self->{No_httpheader}) { return; }
	my $x;
	my $rs = ($self->{Status}==200) && $self->{html_cache} || \$x;

	# Status
	$$rs .= "Status: $self->{Status}\n";
	$$rs .= join('', @{ $self->{Headers} });	# その他のヘッダ

	# Content-Type;
	$ctype   ||= $self->{Content_type};
	$charset ||= $self->{System_coding};
	$$rs .= <<HEADER;
Cache-Control: no-cache
Content-Type: $ctype; charset=$charset;
X-Content-Type-Options: nosniff

HEADER
	print $$rs;
}

#------------------------------------------------------------------------------
# ●配列出力
#------------------------------------------------------------------------------
sub output_array {
	my ($self, $ary) = @_;
	my $c = ($self->{Status}==200) && $self->{html_cache};
	if (!ref($ary)) { print $ary; $c && ($$c .= $ary); return; }
	return $self->_output_array( $ary, $c );
}
sub _output_array {
	# 2009/07/09 速度検証テストによる最適化
	my ($self, $ary, $c) = @_;
	foreach(@$ary) {
		if (ref($_) eq 'ARRAY') {
			$self->_output_array($_, $c);
			next;
		}
		print $_;
		$c && ($$c .= $_);
	}
}

#------------------------------------------------------------------------------
# ●出力キャッシュの登録
#------------------------------------------------------------------------------
sub regist_html_cache {
	my $self  = shift;
	$self->{html_cache} = shift;
}

#------------------------------------------------------------------------------
# ●キャッシュ判定ルーチン登録
#------------------------------------------------------------------------------
sub regist_cache_cheker {
	my $self  = shift;
	$CacheChecker{ $self->{CMD_file} } = shift;
}

###############################################################################
# ■文字列処理
###############################################################################
#------------------------------------------------------------------------------
# ●タグのエスケープ
#------------------------------------------------------------------------------
sub esc {	# 非破壊
	my $self = shift;
	return $self->tag_escape(join('',@_));
}
my %tesc = ('<'=>'&lt;', '>'=>'&gt;', '"'=>'&quot;', "'"=>'&#39;', '&'=>'&amp;');
sub tag_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(<|>|"|')/$tesc{$1}/g;
	}
	return $_[0];
}

sub tag_escape_amp {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(&|<|>|"|')/$tesc{$1}/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●タグの除去
#------------------------------------------------------------------------------
sub tag_delete {
	my $self = shift;
	foreach(@_) {
		$_ =~ s|</[\w\s]*>||sg;
		$_ =~ s/<\w(?:[^>"']|[=\s]".*?\"|[=\s]'.*?')*?>//sg;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●文頭、文末のスペース改行除去
#------------------------------------------------------------------------------
sub trim {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/^[\s\r\n]*(.*?)[\s\r\n]*$/$1/s;
	}
}

#------------------------------------------------------------------------------
# ●URIエンコード
#------------------------------------------------------------------------------
# 不正なURL（URL injection）などを防ぐ関数
#   http://xxxx/--/?a=1&b=2 を直接放り込める
sub encode_uri {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\w!\#\$\(\)\*\+,\-\.\/:;=\?\@\~&%])/'%' . unpack('H2',$1)/eg;
	}
	return $_[0];
}

# Queryを合成するための関数（encodeURIComponent()と「/, :」を除き同一）
sub encode_uricom {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\w!\(\)\*\-\.\~\/:])/'%' . unpack('H2',$1)/eg;
	}
	return $_[0];
}
#------------------------------------------------------------------------------
# ●ファイルサイズの調整
#------------------------------------------------------------------------------
sub size_format {
	my $self = shift;
	my $size = int(shift);
	my $unit = int(shift) || 1024;
	my $geta = int(shift) || 10;
	my @ary  = @_ || ('Byte', 'KB', 'MB', 'GB', 'TB');
	while(@ary) {
		my $x = shift(@ary);
		if ($size < $unit || !@ary) {
			return (int($size*$geta + 0.5)/$geta) . $x;
		}
		$size /= $unit;
	}
}

###############################################################################
# ■モジュール関連
###############################################################################
#------------------------------------------------------------------------------
# ●アプリケーションのロード
#------------------------------------------------------------------------------
sub loadapp {
	my $self = shift;
	return $self->_loadpm('SatsukiApp::' . shift, @_);
}
#------------------------------------------------------------------------------
# ●ライブラリのロード
#------------------------------------------------------------------------------
sub loadpm {
	my $self  = shift;
	my $pm    = shift;
	my $cache = $self->{Loadpm_cache};
	if ($cache->{$pm}) { return $cache->{$pm}; }
	my $obj = $self->_loadpm('Satsuki::' . $pm, @_);
	if (ref($obj) && $obj->{__CACHE_PM}) {
		$cache->{$pm} = $obj;
	}
	return $obj;
}
#------------------------------------------------------------------------------
# ○下位実装
#------------------------------------------------------------------------------
sub _loadpm {
	my $self = shift;
	my ($pm,@a) = @_;
	my $pm_file = $pm . '.pm';
	$pm_file =~ s|::|/|g;
	eval { require $pm_file; };
	if ($@) { delete $INC{$pm_file}; die($@); }
	{
		no strict 'refs'; 	# デバッグルーチン埋め込み
		my $dbg = $pm . '::debug';
		if (! *$dbg{CODE}) { *$dbg = \&export_debug; }
	}
	return $pm->new($self, @a);
}

sub export_debug {
	my $self = shift;
	$self->{ROBJ}->debug($_[0], 1);		# debug-safe
}

###############################################################################
# ■ファイル入力
###############################################################################
#------------------------------------------------------------------------------
# ●ファイル名の加工（mod_perl2との互換性用）
#------------------------------------------------------------------------------
sub get_filepath {
	my ($self, $file) = @_;
	if ($self->{WD} eq '' || $file eq '') { return $file; }
	if (substr($file, 0, 1) eq '/' ) { return $file; }
	if (substr($file, 0, 2) eq './') { $file = substr($file, 2); }
	return $self->{WD} . $file;
}

#------------------------------------------------------------------------------
# ●ファイル：すべての行を読み込む
#------------------------------------------------------------------------------
sub fread_lines_no_error {
	my ($self, $file) = @_;
	return $self->fread_lines($file, {NoError=>1});
}
sub fread_lines {
	my ($self, $file, $flags) = @_;
	my $_file = $self->get_filepath($file);

	my $fh;
	my @lines;
	if ( !sysopen($fh, $_file, O_RDONLY) ) {
		if ($flags->{NoError}) {
			$self->warning("File can't read '%s'", $file);
		} else {
			$self->error("File can't read '%s'", $file);
		}
		# return [];	# PostProcessorを通してからreturnする
	} else {
		$self->read_lock($fh);
		@lines = <$fh>;
		close($fh);
	}

	# delete CR
	if ($flags->{DelCR}) {
		map { $_ =~ s/\r\n?$/\n/ } @lines;
	}

	# 前処理関数
	my $lines = \@lines;
	if ($flags->{PostProcessor}) {
		$lines = &{$flags->{PostProcessor}}($flags->{self} || $self, $lines, $flags );
	}
	return $lines;
}
#------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式を読み込む
#------------------------------------------------------------------------------
#
# ※キュッシュ時のコピー生成の関係でハッシュの階層化（ネスト）実装はできない。
#
sub fread_hash_no_error {
	my ($self, $file) = @_;
	return $self->fread_hash($file, {NoError=>1});

}

sub fread_hash {
	my ($self, $file, $flags) = @_;
	my $lines;
	my %_flags = %{$flags || {}};
	$_flags{PostProcessor} = \&parse_hash;
	return $self->fread_lines($file, \%_flags);
}

sub parse_hash {
	my ($self, $lines, $flags) = @_;
	my ($blk, $key, $val);
	my %h;
	foreach (@$lines) {
		# ブロックモード
		if (defined $blk) {
			if ($_ eq $blk) {
				chomp($val);
				$h{$key} = $val;
				undef $blk;
			} else {
				$val .= $_;
			}
			next;
		}
		# 通常モード
		chomp($_);
		my $f = ord($_);
		if (!$f || $f == 0x23) { next; }	# 行頭'#'はコメント
		if ($f==0x2a && (my $x=index($_, '=<<')) >0) {	# *data=<<__BLOCK ブロックデータ
			$key = substr($_, 1, $x-1);
			$blk = substr($_, $x+3) . "\n";
			$val = '';
			next;
		}
		# 標準の key=val 表記
		my $x = index($_, '=');
		if ($x == -1) { next; }
		$key = substr($_, 0, $x);
		$h{$key} = substr($_, $x+1);
	}
	return \%h;
}

#------------------------------------------------------------------------------
# ●flock処理
#------------------------------------------------------------------------------
sub read_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, Fcntl::LOCK_SH() );
}
sub write_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, Fcntl::LOCK_EX() );
}
sub write_lock_nb {
	my ($self, $fh) = @_;
	$self->flock($fh, Fcntl::LOCK_EX() | Fcntl::LOCK_NB() );
}
sub unlock {
	my ($self, $fh) = @_;
	$self->flock($fh, Fcntl::LOCK_UN() );
}
sub flock {
	my ($self, $fh, $mode) = @_;
	if (defined $self->{Lock}) {
		return $self->{Lock}->lock($fh, $mode);
	}
	return flock($fh, $mode);
}
###############################################################################
# ■ファイルの最終更新日時取得
###############################################################################
#------------------------------------------------------------------------------
# ●ファイルが読み込み可能なとき、最終更新時刻を返す（cache付）
#------------------------------------------------------------------------------
sub get_lastmodified {
	my $self = shift;
	my $file = $self->get_filepath(shift);
	if ($self->{"STcache-$file"}) { return $self->{"STcache-$file"}->[9]; }
	if (!-r $file) { return ; }	# 読み込めない。存在しないファイル
	my $st = $self->{"STcache-$file"} = [ stat($file) ];
	return $st->[9];
}

#------------------------------------------------------------------------------
# ●ディレクトリとディレクトリ内ファイルの最終更新日時を取得
#------------------------------------------------------------------------------
sub get_lastmodified_in_dir {
	my ($self, $dir) = @_;
	$dir = $self->get_filepath($dir);

	opendir(my $fh, $dir) || return ;
	my $max = (stat("$dir")) [9];
	foreach(readdir($fh)) {
		if ($_ eq '.' || $_ eq '..' )  { next; }	# ./ ../ は無視
		my $t = (stat("$dir$_")) [9];
		if ($max<$t) { $max=$t; }
	}
	closedir($fh);
	return $max;
}

###############################################################################
# ■キャッシュ付きファイル入力
###############################################################################
my %FileCache;
#------------------------------------------------------------------------------
# ●キャッシュ付きファイルRead
#------------------------------------------------------------------------------
sub fread_lines_cached {
	my ($self, $_file, $flags) = @_;
	my $file = $self->get_filepath($_file);

	my $cache = $FileCache{$file} ||= {};
	my $key   = join('//',$flags->{PostProcessor},$flags->{DelCR});
	my $c     = $cache->{$key} || {};

	my $st = $self->{"STcache-$file"} ||= [ stat($file) ];
	my $size = $st->[7];
	my $mod  = $st->[9];

	my $lines;
	if (0<$mod && $mod == $c->{modified} && $size == $c->{size}) {
		$lines = $c->{lines};
	} else {
		# ファイルから読み込み
		$lines = $self->fread_lines( $file, $flags );
		$cache->{$key} = {lines => $lines, modified => $mod, size => $size };
	}
	if(ref($lines) eq 'ARRAY') { my @a = @$lines; return \@a; }
	if(ref($lines) eq 'HASH' ) { my %h = %$lines; return \%h; }
	return $lines;
}

#------------------------------------------------------------------------------
# ●キャッシュ付きHASHファイルRead
#------------------------------------------------------------------------------
sub fread_hash_cached {
	my ($self, $file, $flags) = @_;
	my $lines;
	my %_flags = %{$flags || {}};
	$_flags{PostProcessor} = \&parse_hash;
	return $self->fread_lines_cached($file, \%_flags);
}

#------------------------------------------------------------------------------
# ●キャッシュの削除
#------------------------------------------------------------------------------
sub delete_file_cache {
	my ($self, $file) = @_;
	delete $self->{"STcache-$file"};
	$FileCache{$file} = {};
}

###############################################################################
# ■その他ファイル関連
###############################################################################
#------------------------------------------------------------------------------
# ●ファイルの更新日時を更新
#------------------------------------------------------------------------------
sub touch {
	my $self = shift;
	my $file = $self->get_filepath($_[0]);
	if (!-e $file) { $self->fwrite_lines($file, []); return; }
	my ($now) = $self->{TM};
	utime($now, $now, $file);
}

#------------------------------------------------------------------------------
# ●ファイルの更新日時を更新
#------------------------------------------------------------------------------
sub get_file_modtime {
	my ($self, $file) = @_;
	my $cache = $self->{__modtime_cache} ||= {};
	if ($cache->{$file}) { return $cache->{$file}; }
	my $filefull = $self->get_filepath($file);
	return ($cache->{$file} = (stat($filefull)) [9]);
}

sub get_libfile_modtime {
	my ($self, $file) = @_;
	foreach(@INC) {
		if (-e "$_/$file") { return (stat("$_/$file")) [9]; }
        }
}

#------------------------------------------------------------------------------
# ●ファイルを検索する
#------------------------------------------------------------------------------
# search_files("directory name", $opt);
#	拡張子は "txt" のように指定する。配列ref, ハッシュref可。
#	拡張子を省略した場合、すべてのリストが返る。
#	ディレクトリには最後に / を付けて返す。
#
#	$opt->{ext}	 	検索する拡張子（".txt"のように指定）
#	$opt->{all}	 = 1	'.'で始まるファイルを含める（"."と".."は無視）
#	$opt->{dir}	 = 1	ディレクトリを含める
#	$opt->{dir_only} = 1	ディレクトリのみ返す

sub search_files {
	my $self = shift;
	my ($dir, $opt) = @_;
	$dir = $self->get_filepath($dir);
	
	opendir(my $fh, $dir) || return [];
	my $ext = $opt->{ext};
	if (ref($ext) eq  'ARRAY') {
		$ext = { map {$_ => 1} @$ext };
	} elsif ($ext ne '' && ref($ext) ne 'HASH') {
		$ext = { $ext => 1 };
	}
	$opt->{dir} ||= $opt->{dir_only};
	my @filelist;
	foreach(readdir($fh)) {
		if ($_ eq '.' || $_ eq '..' )  { next; }		# ./ ../ は無視
		if (!$opt->{all} && substr($_,0,1) eq '.') { next; }	# 隠しファイルを無視
		my $isDir = -d "$dir$_";
		if ((!$opt->{dir} && $isDir) || ($opt->{dir_only} && !$isDir)) { next; }
		if ($ext && ($_ !~ /(\.\w+)$/ || !$ext->{$1})) { next; }
		push(@filelist, $_ . ($isDir ? '/':''));
	}
	closedir($fh);

	## @filelist = sort @filelist;
	return \@filelist;
}

#------------------------------------------------------------------------------
# ●指定ディレクトリからの相対パスを得る
#------------------------------------------------------------------------------
sub get_relative_path {
	my ($self, $base, $file) = @_;
	if (ord($file) == 0x2f) { return $file; }	# / で始まる
	my $x = rindex($base, '/');
	if ($x<0) { return $file; }
	return substr($base, 0, $x+1) . $file;
}

###############################################################################
# ■クエリー・フォーム・環境変数処理
###############################################################################
#------------------------------------------------------------------------------
# ●フォームの読み込み
#------------------------------------------------------------------------------
sub read_form {
	if ($ENV{REQUEST_METHOD} ne 'POST') { return ; }
	return &_read_form(@_);		# 実体呼び出し (use AutoLoader)
}
#------------------------------------------------------------------------------
# ●クエリー解析
#------------------------------------------------------------------------------
sub read_query {
	my $self = shift;
	my $array = shift || {};
	if ($self->{Query}) { return $self->{Query}; }
	if ($ENV{QUERY_STRING} eq '') { return {}; }

	# 文字コード関連, UA_code=表示（Form）文字コードが内部コードと違う場合
	my $from = $self->{UA_code} || $self->{System_coding};
	my $to   = $self->{System_coding};

	my @query = split(/&/, $ENV{QUERY_STRING});
	my %query;
	foreach (@query) {
		my ($name, $val) = split(/=/,$_,2);
		$name =~ s|[^\w\-/]||g;
		$val =~ tr/+/ /;
		$val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;

		# 文字コード変換（文字コードの完全性保証）
		my $jcode = $self->load_codepm_if_needs( $val );
		$jcode && $jcode->from_to( \$val, $from, $to );

		$val =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;	# TAB LF CR以外の制御コードを除去
		$val =~ s/\r\n?/\n/g;	# 改行を統一
		if ($array->{$name}) {
			$query{$name} ||= [];
			push(@{$query{$name}}, $val);
			next;
		}
		$query{$name} = $val;
	}
	return ($self->{Query} = \%query);
}

#------------------------------------------------------------------------------
# ●クエリー構築	※フォームデータ構築にも使える
#------------------------------------------------------------------------------
sub make_query {
	my $self = shift;
	my $h = shift || $self->{Query};
	my $amp = shift;
	my $q;
	foreach(keys(%$h)) {
		my $k = $_;
		my $v = $h->{$k};
		$self->encode_uricom($k);
		foreach(@{ ref($v) ? $v : [$v] }) {
			my $x = $_;
			$self->encode_uricom($x);
			$q .= "$k=$x&";
		}
	}
	chop($q);
	return $q;
}
sub make_query_amp {
	my $q = &make_query(@_);
	$q =~ s/&/&amp;/g;
	return $q;
}

#------------------------------------------------------------------------------
# ●PATH INFO 解析
#------------------------------------------------------------------------------
#  PATH_INFO = /xxx/yyy/zzz
sub read_path_info {
	my $self = shift;
	my ($dummy, @pinfo) = split('/', $ENV{PATH_INFO} . "\0");
	if (@pinfo) { chop($pinfo[$#pinfo]); }

	return ($self->{Pinfo} = \@pinfo);
}

###############################################################################
# ■フォーム処理／セキュリティ関連
###############################################################################
#------------------------------------------------------------------------------
# ●CSRF対策ルーチン
#------------------------------------------------------------------------------
sub make_csrf_check_key {
	my ($self, $base_string) = @_;
	my $check_key = $self->crypt_by_string( $base_string );
	return ($self->{CSRF_check_key} = $check_key);
}

#------------------------------------------------------------------------------
# ●特殊IDルーチン
#------------------------------------------------------------------------------
sub make_secure_id {
	my ($self, $base_string, $old, $len) = @_;
	my $secure_time = $self->{Secure_time} || 3600;
	my $code = ($old<0) ? 0 : int($self->{TM} / $secure_time);
	my $id = $self->crypt_by_string($base_string . ($code - int($old)));
	$id =~ tr|/|-|;
	return substr($id, 0, $len || $self->{Secure_id_len} || 12);
}

#------------------------------------------------------------------------------
# ●任意文字列を generator として crypt
#------------------------------------------------------------------------------
# generator に同じものを与えれば、同じ SALT 文字列が生成される。
# 但し、仕様変更の可能性があるため generator を SALT 代わりにしてはならない。
#
my $s_cache_base64;
my %s_cache;
my $s_cache_tm;
# 乱数の配列
my @s_ary0 = (0xb5d8f3c,0x96a4072,0x492c3e6,0x6053399,0xae5f1a8,0x5bf1227,0x02a7e6f,0x4b0bd91);
my @s_ary1 = (0xd31289f,0x76a6d1e,0xd912fac,0xe119b5b,0xe2823fd,0x67f561d,0xa753dc1,0x5b8062b);
sub crypt_by_string_with_salt {
	my ($self, $secret, $generator) = @_;
	if (!defined $generator) { $generator = $self->{Secret_word}; }
	my $base64 = $self->{SALT64chars};

	# SALTキャッシュシステム（１日おきに初期化）
	if ($s_cache_base64 ne $base64 || $s_cache_tm < $self->{TM}) {
		%s_cache=(); $s_cache_tm = $self->{TM} + 86400;
		$s_cache_base64=$base64;
	}
	my $cache_id = "$secret\x01$generator";
	if (exists $s_cache{ $cache_id }) { return $s_cache{ $cache_id }; }

	# SALT文字列を生成
	my $salt;
	{
		# 文字列用の数値生成
		my ($x,$y);
		my $len = length($generator);
		for(my $i=0; $i<$len; $i++) {
			my $c = ord(substr($generator, $i, 1));
			$x += $c * $s_ary0[$i & 7];
			$y += $c * $s_ary1[$i & 7];
		}
		# SALT文字列生成
		$salt
		= substr($base64, ($x    ) & 63,1) . substr($base64, ($y    ) & 63,1)
		. substr($base64, ($x>> 6) & 63,1) . substr($base64, ($y>> 6) & 63,1)
		. substr($base64, ($x>>12) & 63,1) . substr($base64, ($y>>12) & 63,1)
		. substr($base64, ($x>>18) & 63,1) . substr($base64, ($y>>18) & 63,1);
	}
	# crypt実行
	my $key = $self->crypt($secret, $salt);
	# キャッシュ
	$s_cache{ $cache_id } = $key;
	return $key;
}

# salt文字列を除去したハッシュを得る
sub crypt_by_string {
	my $self = shift;
	my $key = $self->crypt_by_string_with_salt(@_);
	if ($key =~ /^\$1\$.*?\$(.*)/) { return $1; }
	return substr($key, 2);
}

#------------------------------------------------------------------------------
# ●crypt
#------------------------------------------------------------------------------
# md5が利用可能ならばmd5を利用するcrypt
my $MD5_flag;
sub crypt {
	my $self = shift;
	my ($x, $salt) = @_;
	if (substr($salt, 0, 3) eq '$1$') { return crypt($x, $salt); }

	if (!defined $MD5_flag) {	# md5が利用可能かチェック
		$MD5_flag = crypt('', '$1$') eq '$1$$qRPK7m23GJusamGpoGLby/' ? 1 : 0;
	}
	return $MD5_flag ? crypt($x, '$1$'.$salt) : crypt($x, $salt);
}

###############################################################################
# ■Cookie処理
###############################################################################
#==============================================================================
# ●Cookieの解析
#==============================================================================
sub get_cookie {
	my $self = shift;
	my %cookie;
	foreach (split(/; */, $ENV{HTTP_COOKIE})) {
		my ($name, $val) = split('=', $_);
		$val =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
		if (ord($val)) {	# start char isn't 0x00
			$cookie{$name} = $val;
		} else {
			$cookie{$name} = $self->split_cookie($val);
		}
	}
	return ($self->{Cookie} = \%cookie);
}

#==============================================================================
# ○cookie を分解（array cookie, hash cookie の復元）
#==============================================================================
sub split_cookie {
	my $self = shift;
	my @array = split(/\0/, $_[0]);
	shift(@array);	# 読み捨て

	my $flag = ord(shift(@array));
	if ($flag == 1) {		# array
		return \@array;
	} elsif ($flag == 2) {		# hash
		my ($k, %h);
		while($#array >= 0) {
			$k     = shift(@array);
			$h{$k} = shift(@array);
		}
		return \%h;
	}
}


###############################################################################
# ■日付・時刻処理
###############################################################################
#------------------------------------------------------------------------------
#●RFC日付処理
#------------------------------------------------------------------------------
# Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 2822
sub rfc_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d GMT"
		, $mday, $year+1900, $hour, $min, $sec);
}

#------------------------------------------------------------------------------
#●W3C Date
#------------------------------------------------------------------------------
sub w3c_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);
	return sprintf("%04d-%02d-%02dT%02d:%02d:%02d+00:00"
		,$year+1900, $mon+1, $mday, $hour, $min, $sec);
}

#------------------------------------------------------------------------------
# ●時刻ハッシュの設定
#------------------------------------------------------------------------------
# time2timehash($time_utc, $change_hour);
#	$change_hour	日付変更時間の指定
#
sub time2timehash {
	my $self = shift;
	my $tm   = $self->change_hour(@_);

	my %h;
	$h{tm} = $tm;
	( $h{sec},  $h{min},  $h{hour},
	  $h{_day}, $h{_mon}, $h{year},
	  $h{wday}, $h{yday}, $h{isdst}) = localtime($tm);
	$h{year} +=1900;
	$h{_mon} ++;
	$h{mon} = sprintf("%02d", $h{_mon});
	$h{day} = sprintf("%02d", $h{_day});

	return \%h;
}

sub change_hour {
	my $self = shift;
	my $tm = shift || $self->{TM};
	my $change_hour = (defined $_[0]) ? shift : $self->{Change_hour};

	my ($sec, $min, $hour, $day, $mon, $year) = localtime($tm);
	my $ch_func = $self->{Change_hour_func};
	if ($change_hour && $ch_func) {
		$change_hour = &$ch_func($sec, $min, $hour, $day, $mon+1, $year+1900) ? $change_hour : 0;
	}

	my $ch_flag=0;
	if ($hour < $change_hour) {	# 日付変更時間 処理
		$ch_flag =1;
		$tm -= 86400;
	}
	return wantarray ? ($tm, $ch_flag) : $tm;
}
#------------------------------------------------------------------------------
# ●時刻フォーマットの整形
#------------------------------------------------------------------------------
# tm_printf($format, $UTC, $change_hour);
#	$format		書式
#	$UTC		UTCタイム
#
sub tm_printf {
	my $self = shift;
	my $str  = shift;
	my ($tm, $ch_flag) = $self->change_hour(@_);

	# This macro like 'strftime(3)' function.
	# 完全互換　：%Y %y %m %d %I %H %M %S %w %s %e
	# ほぼ互換  ：%j %k %l （桁可変が非互換）
	# 表記変更可：%a %p
	# 独自拡張　：%n, %i %L, %J %K
	my %h;
	$h{s} = $tm;
	($h{S}, $h{M}, $h{k}, $h{e}, $h{n}, $h{Y}, $h{w}, $h{j}, $h{isdst}) = localtime($tm);
	$h{y}  = sprintf("%02d", $h{Y} % 100);
	$h{Y} +=1900;
	$h{n} +=1;		# month
	$h{m}  = sprintf("%02d", $h{n});
	$h{d}  = sprintf("%02d", $h{e});
	$h{H}  = sprintf("%02d", $h{k});	# 24時間表記
	$h{M}  = sprintf("%02d", $h{M});
	$h{S}  = sprintf("%02d", $h{S});
	$h{a}  = $self->{WDAY_name}->[$h{w}];	# 曜日名
	$h{i}  = $h{k} % 12;			# 12時間表記( 0-11)
	$h{L}  = sprintf("%02d", $h{L});	# 12時間表記(00-11)（2桁）
	$h{l}  = $h{i} || 12;			# 12時間表記( 1-12)
	$h{I}  = sprintf("%02d", $h{l});	# 12時間表記(01-12)（2桁）
	$h{J}  = $h{H} + 24*$ch_flag;		# 24+$change_hour 時間処理
	$h{K}  = sprintf("%02d", $h{J});	# 24+$change_hour 時間処理（2桁）
	$h{p}  = $self->{AMPM_name}->[ int($h{J}/12) ];	# 午前、午後、深夜

	$str =~ s/%(\w)/$h{$1}/g;
	return $str;
}

###############################################################################
# ■メッセージ処理、ディバグ関連
###############################################################################
#------------------------------------------------------------------------------
# ●フォームエラーシステム
#------------------------------------------------------------------------------
sub clear_form_error {
	my $self = shift;
	$self->{FormError}=undef;
}
sub form_error {
	my $self = shift;
	my $name = shift;
	if ($name eq '') { return $self->{FormError}; }
	$self->{FormError} ||= {};
	$self->{FormError}->{$name}=$_[0] || 1;
	$self->{FormError}->{"c_$name"}=' class="error"';
	$self->{FormError}->{"e_$name"}=' error';
	return defined $_[0] ? $self->message(@_) : undef;
}
sub form_info {
	my $self = shift;
	my $name = shift;
	$self->{FormInfo} ||= {};
	$self->{FormInfo}->{$name}=shift || 1;;
}

#------------------------------------------------------------------------------
# ●言語ファイルのロード
#------------------------------------------------------------------------------
sub load_language_file {
	my ($self, $file) = @_;
	# 言語ファイルロード
	my $mt = $self->{Msg_translate} = $self->fread_hash_cached($file);
	# システムの言語設定
	$self->{System_coding} = $mt->{System_coding};
	$self->{Code_lib} = $mt->{Code_lib};
	$self->{Locale}   = $mt->{Locale};
	$self->{Locale2}  = $mt->{Locale2} || $mt->{Locale};
}

#------------------------------------------------------------------------------
# ●文字ライブラリのロード
#------------------------------------------------------------------------------
sub load_codepm {
	my $self = shift;
	return $self->loadpm('Code::' . $self->{Code_lib}, @_);
}
sub load_codepm_if_needs {
	my $self = shift;
	foreach (@_) {
		if ($_ =~ /[^\x00-\x0D\x10-\x1A\x1C-\x7E]/) {
			return $self->loadpm('Code::' . $self->{Code_lib}, @_);
		}
	}
	return ;
}

#------------------------------------------------------------------------------
# ●メッセージの翻訳
#------------------------------------------------------------------------------
sub message_translate {
	my $self = shift;
	my $msg  = shift;
	my $msg_translate = $self->{Msg_translate};
	if ($msg_translate->{$msg} ne '') { $msg = $msg_translate->{$msg}; }
	if (@_) { return sprintf($msg, @_); }	# 整形
	return $msg;
}

#------------------------------------------------------------------------------
# ●メッセージ処理ルーチン
#------------------------------------------------------------------------------
sub message {
	my $self = shift;
	$self->_message('message', @_);
}
sub notice {
	my $self = shift;
	$self->_message('notice', @_);
}
sub warn {
	my $self = shift;
	$self->_message('warn', @_);
}
sub _message {
	my $self = shift;
	my $class= shift;
	if ($self->{Message_stop}) { return []; }

	my $msg = $self->message_translate(@_);
	my $ary = $self->{Message};
	$self->tag_escape($class,$msg);
	push(@$ary, "<div class=\"$class\">$msg</div>");
}
sub message_split {
	my $self = shift;
	my $class= shift;
	my @ary;
	my @msg;
	foreach(@{ $self->{Message} }) {
		if ($_ =~ /<div [^>]*class="([\w-]+)"/ && $1 eq $class) {
			push(@ary, $_);
		} else {
			push(@msg, $_);
		}
	}
	$self->{Message} = \@msg;
	return \@ary;
}

#------------------------------------------------------------------------------
# ●ディバグルーチン
#------------------------------------------------------------------------------
sub debug {
	my ($self, $msg, $level) = @_;
	$self->tag_escape_amp($msg);
	$msg =~ s/\n/<br>/g;
	$msg =~ s/ /&ensp;/g;
	my ($pack, $file, $line) = caller(int($level));
	push(@{$self->{Debug}}, $msg . "<!-- in $file line $line -->");
}
sub warning {
	my $self = shift;
	my $msg  = $self->message_translate(@_);
	my ($pack, $file, $line) = caller;
	push(@{$self->{Warning}}, '' . $msg . "<!-- in $file line $line -->");
}

#------------------------------------------------------------------------------
# ●エラー処理ルーチン
#------------------------------------------------------------------------------
# &error_from('error from', "表示するエラー");
# &error("表示するエラー");
sub error {
	my $self = shift;
	return $self->error_from('', @_);
}
sub error_from {
	my $self = shift;
	my $from = shift;
	my $msg  = $self->message_translate(@_);

	# エラー元参照
	if ($from eq '') {
		my @froms;
		my $prev_file='';
		my $i=1;
		while(1) {
			my ($pack, $file, $line) = caller($i++);
			$file = substr($file, rindex($file, '/') +1);
			if ($file eq $prev_file) {
				push(@froms, $line);
			} else {
				push(@froms, "in $file $line");
				$prev_file = $file;
			}
			if (!($pack eq __PACKAGE__ || $pack =~ /::DB_/) || $i>9) { last; }
		}
		$from = pop(@froms);
		while(@froms) {
			$from = pop(@froms) . " ($from)";
		}
	} else {
		$from = "From $from";
	}
	if ($from ne '') { $msg = "$msg ($from)"; }
	$self->tag_escape($msg);

	chomp($msg);
	push(@{$self->{Error}}, $msg);
	$self->{Error_flag} = 1;
	return $msg;
}

sub error_load_and_clear {
	my $self  = shift;
	my $chain = shift || "<br>\n";
	my $error = $self->{Error};
	$self->{Error} = [];
	if (! @$error) { return ''; }
	return join($chain, @$error);
}

###############################################################################
# ■その他
###############################################################################
#------------------------------------------------------------------------------
# ●スリープ
#------------------------------------------------------------------------------
sub usleep {
	my ($self, $usec) = @_;
	select(undef, undef, undef, ($usec/1000000));
}
sub msleep {
	my ($self, $msec) = @_;
	select(undef, undef, undef, ($msec/1000));
}


1;
