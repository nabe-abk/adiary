use strict;
#-------------------------------------------------------------------------------
# Base system functions for satsuki system
#						Copyright(C)2005-2022 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::Base;
#-------------------------------------------------------------------------------
our $VERSION = '2.67';
our $RELOAD;
my %StatCache;
#-------------------------------------------------------------------------------
use Satsuki::AutoLoader;
use Fcntl;		# for sysopen/flock
use Scalar::Util();
################################################################################
# ■コンストラクタ
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = $self;
	Scalar::Util::weaken( $self->{ROBJ} );

	# グローバル変数、特殊変数
	$self->{VERSION} = $VERSION;
	$self->{ENV}  = \%ENV;
	$self->{INC}  = \%INC;
	$self->{ARGV} = \@ARGV;
	$self->{UID}  = $<;
	$self->{GID}  = $(;
	$self->{PID}  = $$;
	$self->{CMD}  = $0;
	$self->{STDIN}= *STDIN;
	$self->{IsWindows} = $^O eq 'MSWin32';

	# 初期設定
	$self->{Status}  = 200;		# HTTP status (200 = OK)
	$self->{LoadpmCache}  = {};
	$self->{FinishObjs}   = [];
	$self->{CGI_mode}     = 'CGI-Perl';
	$self->{Content_type} = 'text/html';
	$self->{Headers}      = [];		# ヘッダ出力バッファ

	# charset setting
	$self->{SystemCode} = 'UTF-8';
	$self->{CodeLIB};
	$self->{Locale};

	# 時刻／日付関連の設定
	$self->{TM} = time;
	$self->{WDAY_name} = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
	$self->{AMPM_name} = ['AM','PM','AM'];	# 午前, 午後, 深夜
	$self->init_tm();

	# ネストcall/jumpによる無限ループ防止設定
	$self->{SkeletonExt} = '.html';
	$self->{JumpCount}   = 0;
	$self->{NestCount}   = 0;
	$self->{CurrentNest} = 0;
	$self->{MaxNest}     = 99;
	$self->{SkelDirs}    = [];

	# error / debug
	$self->{Error}   = [];
	$self->{Debug}   = [];
	$self->{Warning} = [];
	$self->{Message} = [];

	# STAT cache init
	$self->init_stat_cache();

	#-------------------------------------------------------------
	# スケルトンキャッシュ関連
	#-------------------------------------------------------------
	$self->{CompilerTM} = $self->get_lastmodified( 'lib/Satsuki/Base/Compiler.pm' );

	my $cache_dir = $ENV{SatsukiCacheDir} || '__cache/';
	if (-d $cache_dir && -w $cache_dir) {
		$self->{__cache_dir} = $cache_dir;
	}
	return $self;
}

################################################################################
# ■メイン
################################################################################
my %CacheChecker;
#-------------------------------------------------------------------------------
# ●スタートアップ (起動スクリプトから最初に呼ばれる)
#-------------------------------------------------------------------------------
sub start_up {
	my $self = shift;

	# cache checker
	my $checker = $CacheChecker{$0};
	if ($checker && &$checker($self)) {
		return;
	}

	my $cgi = $0;
	if ($self->{IsWindows}) { $cgi =~ tr|\\|/|; }

	my $env;
	my $conf;
	if ($cgi =~ m!(?:^|/)([^/\.]*)[^/]*$!) {
		$env  = $1 .  '.env.cgi';
		$conf = $1 . '.conf.cgi';
	} else {
		$env = $conf = '__(internal_error)__';
	}

	# .env があれば先に処理
	if (-r $env) {
		$self->_call($env);
	}

	# 初期化処理
	$self->init_tm();
	$self->init_path();

	# conf解析
	$self->{Conf_result} = $self->_call($conf);

	# 致命的エラーがあった場合、表示して終了
	if ($self->{Error_flag}) {
		$self->set_status(500);
		$self->output_error('text/html');
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

#-------------------------------------------------------------------------------
# ●conf.cgi の中身をそのまま出力するだけのメインルーチン
#-------------------------------------------------------------------------------
sub main {
	my $self = shift;
	$self->output($self->{Conf_result});
}

#-------------------------------------------------------------------------------
# ●時刻の初期化
#-------------------------------------------------------------------------------
sub init_tm {
	my ($self, $tz) = @_;
	my $h = $self->time2timehash( $self->{TM} );
	$self->{Now} = $h;
	$self->{Timestamp} = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
			$h->{year}, $h->{mon}, $h->{day}, $h->{hour}, $h->{min}, $h->{sec});
}

#-------------------------------------------------------------------------------
# ●初期環境変数の設定（パス解析など）
#-------------------------------------------------------------------------------
sub init_path {
	my $self = shift;
	if ($self->{Initialized_path} || !$ENV{REQUEST_URI}) { return; }

	# ModRewrite flag
	my $rewrite = $self->{ModRewrite} ||= $ENV{ModRewrite};
	if (!defined $rewrite && exists $ENV{REDIRECT_URL} && $ENV{REDIRECT_STATUS}==200) {
		$self->{ModRewrite} = $rewrite = 1;
	}

	# cgiファイル名、ディレクトリ設定
	$ENV{QUERY_STRING}='';
	my $request = $ENV{REQUEST_URI};
	if ((my $x = index($request, '?')) >= 0) {
		$ENV{QUERY_STRING} = substr($request, $x+1);	# Apache's bug, treat "%3f" as "?"
		$request = substr($request, 0, $x);
	}
	if (index($request, '%') >= 0) {
		$request =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
	}

	# SCRIPT_NAME からベースパスを割り出す
	my $script   = $ENV{SCRIPT_NAME};
	my $basepath = $self->{Basepath} ||= $ENV{Basepath};
	if (!defined $basepath) {
		my $path = $script;
		while(1) {
			$path = substr($path, 0, rindex($path,'/')+1);
			if (index($request, $path) == 0) { last; }
		}
		$self->{Basepath} = $basepath = $path;
	}

	# 文字コード問題と // が / になる問題の対応
	$ENV{PATH_INFO_orig} = $ENV{PATH_INFO};
	$ENV{PATH_INFO} = substr($request, ($rewrite ? length($basepath)-1 : length($script)) );

	# 自分自身（スクリプト）にアクセスする URL/path
	if (!exists $self->{myself}) {
		if ($rewrite) {
			$self->{myself}  = $self->{myself2} = $basepath;
		} elsif (index($request, $script) == 0) {	# 通常のcgi
			$self->{myself}  = $script;
			$self->{myself2} = $script . '/';	# PATH_INFO用
		} else {	# cgi が DirectoryIndex
			$self->{myself}  = $basepath;
			$self->{myself2} = $script . '/';	# PATH_INFO用
		}
	}

	# プロトコル判別
	if (!$self->{ServerURL}) {
		my $port = int($ENV{SERVER_PORT});
		my $protocol = ($port == 443) ? 'https://' : 'http://';
		$self->{ServerURL} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
	} else {
		substr($self->{ServerURL},-1) eq '/' && chop($self->{ServerURL});
	}

	# copyright
	$ENV{PATH_INFO} eq '/__getcpy' && print "X-Satsuki-System: Ver$VERSION (C)nabe\@abk\n";
	# パス初期化済フラグ
	$self->{Initialized_path} = 1;
}

#-------------------------------------------------------------------------------
# ●statキャッシュの初期化
#-------------------------------------------------------------------------------
my $StatTM;
sub init_stat_cache {
	my $self = shift;
	if ($StatTM == $self->{TM}) { return; }
	undef %StatCache;
	$StatTM = $self->{TM};
}

################################################################################
# ■終了処理
################################################################################
#-------------------------------------------------------------------------------
# ●終了前処理
#-------------------------------------------------------------------------------
sub finish {
	my $self = shift;

	# Finish
	foreach my $obj (reverse(@{ $self->{FinishObjs} })) {
		$obj->FINISH();
	}

	# エラー情報の表示
	if ($self->{Develop} && @{$self->{Error}}) {
		$self->output_error();
	}

	if (!$self->{CGI_cache}) { return; }

	#-------------------------------------------------------------
	# memory limiter
	#-------------------------------------------------------------
	my $limit = $self->{MemoryLimit};
	if (!$limit) { return; }

	local($/);
	sysopen(my $fh, "/proc/$$/status", O_RDONLY) or return;
	<$fh> =~ /VmHWM:\s*(\d+)/;
	close($fh);

	my $size = $1<<10;
	if ($limit<$size) { $self->{Shutdown} = 1; }
}

#-------------------------------------------------------------------------------
# ●終了命令
#-------------------------------------------------------------------------------
sub exit {
	my $self = shift;
	my $ext  = shift;
	$self->{Exit}  = $ext;
	$self->{Break} = -2;
	$ENV{SatsukiExit} = 1;
	die("exit($ext)");
}

################################################################################
# ■executor
################################################################################
#-------------------------------------------------------------------------------
# ●コンパイル済のデータを実行する
#-------------------------------------------------------------------------------
sub execute {
	my ($self, $subroutine) = @_;
	if (ref $subroutine ne 'CODE') {
		my ($pack, $file, $line) = caller;
		$self->error_from("$file line $line: $self->{CurrentSrc}", "[executor] Can't execute string '%s'", $subroutine);
		return ;
	}

	#-------------------------------------------------------------
	# ○ネストチェック（無限ループ防止）
	#-------------------------------------------------------------
	$self->{NestCount}++;
	if ($self->{NestCount} > $self->{MaxNest}) {
		my $err = $self->error_from('', '[executor] Too depth nested call (max %d)', $self->{MaxNest});
		$self->{NestCount}--;
		$self->{Break} = 2;
		return "<h1>$err</h1>";
	}

	#-------------------------------------------------------------
	# ○executor（本体）
	#-------------------------------------------------------------
	my $output='';
	my $line;
	local($self->{IsFunction});
	{
		my $v_ref;
		$self->{Return} = undef;
		eval{ $self->{Return} = &$subroutine($self, \$output, \$line, $v_ref); };
		$v_ref && ($self->{v} = $$v_ref);			# vを書き戻す
		if ($ENV{SatsukiExit}) { die("exit($self->{Exit})"); }	# exit代わりのdie
	}

	# break
	my $break = int($self->{Break});
	if (!$break && $@) {
		$self->set_status(500);
		my $err = $@;
		foreach(split(/\n/, $err)) {
			$self->error_from("$self->{CurrentSrc} line $line", "[executor] $_");
		}
		$RELOAD = 1;
	}

	#-------------------------------------------------------------
	# ○後処理
	#-------------------------------------------------------------
	$self->{NestCount}--;		# ネストカウンタ

	while($break) {
		my $break_level = abs($break);
		if ($break_level==1 && $self->{NestCount} > $self->{CurrentNest}) { last; }	# 同一 level内
		if ($break_level >1 && $self->{NestCount} > 0) { last; }			# superbreak
		if ($break < 0) { $output = ''; }						# clear option
		$self->{Break} = 0;

		if ($self->{JumpFile}) {
			my $file = $self->{JumpFile};
			my $skel = $self->{JumpSkel};
			$self->{JumpFile} = undef;
			$self->{JumpSkel} = undef;
			$self->{JumpCount}++;
			if ($self->{JumpCount} < $self->{MaxNest}) {
				$output .= $self->__call($file, $skel, @{ $self->{JumpArgv} });
			} else {
				my $err = $self->error_from('', "[executor] Too many jump (max %d)", $self->{MaxNest});
				$output .= "<h1>$err</h1>";
			}
		}
		last;
	}
	if ($self->{Break}) { die "Break"; }

	# functionとしてreturn値を取る？
	return $self->{IsFunction} ? $self->{Return} : $output;
}

################################################################################
# ■スケルトン呼び出し
################################################################################
#-------------------------------------------------------------------------------
# ●低レベル call
#-------------------------------------------------------------------------------
my %SkelCache;
sub __call {
	my $self      = shift;
	my $src_file  = shift;
	my $skel_name = shift;

	my $cache_file;
	if ($self->{__cache_dir}) {
		my $f = $src_file;
		$f =~ s/([^\w\.\#])/'%' . unpack('H2', $1)/eg;
		$cache_file = $self->{__cache_dir} . $f . '.cache';
	}

	# ソースファイルを読み込めない
	if (!-r $src_file) {
		if ($cache_file) { unlink($cache_file); }	# キャッシュ削除
		$self->error("[call] failed - Can't read file '%s'", $src_file || $skel_name . $self->{SkeletonExt} );
		return undef;
	}

	#-------------------------------------------------------------
	# メモリキャッシュロード
	#-------------------------------------------------------------
	my $skel   = $SkelCache{$src_file};
	my $src_tm = ($StatCache{$src_file} ||= [ stat($src_file) ])->[9];

	# $self->debug("*** Call $src_file ***");
	#-------------------------------------------------------------
	# 有効なキャッシュか確認
	#-------------------------------------------------------------
	if ($cache_file && ($skel->{src_tm} != $src_tm || $skel->{compiler_tm} != $self->{CompilerTM})) {
		# ファイルからキャッシュロード
		$skel = $self->load_cache($cache_file);

		# キャッシュが有効か確認する
		if (!$skel || $skel->{compiler_tm} != $self->{CompilerTM} || $skel->{src_tm} != $src_tm) {
			# $self->debug("Unload cache file : $src_file");
			unlink($cache_file);
			$skel = undef
		}
	}

	#-------------------------------------------------------------
	# キャッシュがない場合ソースファイルをコンパイル
	#-------------------------------------------------------------
	if (! $skel) {
		$skel = {
			arybuf => $self->compile($cache_file, $src_file, $src_file, $src_tm),
			src_tm => $src_tm,
			compiler_tm => $self->{CompilerTM}
		};
	}

	#-------------------------------------------------------------
	# Perl構文コンパイル
	#-------------------------------------------------------------
	my $arybuf = $skel->{arybuf};
	if (!$skel->{executable}) {
		my $error;
		foreach (@$arybuf) {
			my $X = $_;
			eval "\$_ = $X";
			if ($@) { $self->error_from($src_file, "[perl-compiler] $@"); $error=1; }
		}
		if ($error) { return undef; }
		$skel->{executable} = 1;

		# メモリキャッシュに保存
		if (-r $cache_file) {
			$SkelCache{$src_file} = $skel;
		}
	}

	#-------------------------------------------------------------
	# 実行処理
	#-------------------------------------------------------------
	my $c = $self->{__cont_level};
	local ($self->{argv}, $self->{CurrentSrc}, $self->{CurrentSkel}, $self->{CurrentNest});
	$self->{argv}        = \@_;
	$self->{CurrentSrc}  = $src_file;
	$self->{CurrentSkel} = $skel_name;
	$self->{CurrentNest} = $self->{NestCount};

	return $self->execute( $arybuf->[0] );
}

#-------------------------------------------------------------------------------
# ●キャッシュのロード
#-------------------------------------------------------------------------------
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
	if ($version<2) { return; }	# 失敗

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

	# @$lines が空であるかチェック
	if ($#$lines != -1) { return (2); }	# 失敗

	$cache{arybuf} = \@arybuf;
	return \%cache;
}

################################################################################
# ■制御構文
################################################################################
#-------------------------------------------------------------------------------
# ●パーサーの中断処理
#-------------------------------------------------------------------------------
sub break {
	my ($self, $break_level) = @_;
	$self->{Break} = int($break_level) || 1;
	die("Break");
}
sub break_clear {	# 今までの内容破棄
	my $self = shift;
	$self->{Break} = -1;
	die("Break");
}
sub superbreak {	# callネストをすべてbreak
	my $self = shift;
	$self->{Break} = 2;
	die("Break");
}
sub superbreak_clear {	# callネストをすべてbreak/clear
	my $self = shift;
	$self->{Break} = -2;
	die("Break");
}
#-------------------------------------------------------------------------------
# ●beginブロックの実行
#-------------------------------------------------------------------------------
sub exec {
	my $self = shift;
	my $code = shift;
	local ($self->{argv});
	$self->{argv} = \@_;
	return $self->execute($code);
}

#-------------------------------------------------------------------------------
# ●別ファイルへの処理移行
#-------------------------------------------------------------------------------
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
	my $skel = shift;
	$self->{Break} ||= 1;

	my ($file, $level) = $self->check_skeleton($skel);
	if ($file eq '') {
		return $self->error("[%s] failed - File not found '%s'", 'jump', $skel);
	}
	$self->{JumpFile}  = $file;
	$self->{JumpSkel}  = $skel;
	$self->{JumpArgv}  = \@_;
	$self->{SkelLevel} = $level -1;
	die("Break");
}
sub _jump {
	my $self = shift;
	$self->{Break}     = 1;
	$self->{JumpFile}  = shift;
	$self->{JumpSkel}  = undef;
	$self->{JumpArgv}  = \@_;
	die("Break");
}

#-------------------------------------------------------------------------------
# ●ユーザーskeleton からよりレベルの低いスケルトンへの移行（継続処理）
#-------------------------------------------------------------------------------
sub continue {
	my $self = shift;
	my $skel = $self->{CurrentSkel};
	if ($self->{SkelLevel}<0) { die "Can't continue($self->{SkelLevel})."; }

	my ($file, $level) = $self->check_skeleton($skel, $self->{SkelLevel});
	$self->{Break}     = 1;
	$self->{JumpFile}  = $file;
	$self->{JumpSkel}  = $skel;
	$self->{JumpArgv}  = $self->{argv};
	$self->{SkelLevel} = $level -1;
	die("Break");
}

#-------------------------------------------------------------------------------
# ●別ファイルの呼び出し
#-------------------------------------------------------------------------------
sub call {
	my $self = shift;
	my $skel = shift;
	my ($file, $level) = $self->check_skeleton($skel);
	if ($file eq '') {
		$self->error("[%s] failed - File not found '%s'", 'call', $skel);
		return;
	}
	local ($self->{SkelLevel}) = $level -1;
	return $self->__call($file, $skel, @_);
}
sub _call {
	my $self = shift;
	my $file = shift;
	return $self->__call($file, undef, @_);
}

################################################################################
# ■スケルトンシステム関連
################################################################################
#-------------------------------------------------------------------------------
# ●スケルトンディレクトリの登録
#-------------------------------------------------------------------------------
sub regist_skeleton {
	my $self = shift;
	my $dir  = shift;
	my $level = shift || 0;
	if ($dir eq '') { 
		$self->error("Skeleton dir is '' in regist_skeleton (level=%d)", $level);
		return;
	}

	my $dirs = $self->{SkelDirs};
	push(@$dirs, { level=>$level, dir=>$dir });
	$self->{SkelDirs} = [ sort {$b->{level} <=> $a->{level}} @$dirs ];
}

#-------------------------------------------------------------------------------
# ●スケルトンディレクトリの削除（引数：level）
#-------------------------------------------------------------------------------
sub delete_skeleton {
	my $self = shift;
	my $lv   = shift;
	my $dirs = $self->{SkelDirs};
	$self->{SkelDirs} = [ grep { $_->{level} != $lv } @$dirs ];
	return grep { $_->{level}==$lv } @$dirs;
}

#-------------------------------------------------------------------------------
# ●スケルトンファイルの確認
#-------------------------------------------------------------------------------
# 存在し、読み込み可能ならばファイル名（相対パス）を返す
#
sub check_skeleton {
	my $self  = shift;
	my $name  = shift;
	my $level = defined $_[0] ? shift : 0x7fffffff;
	$name =~ s|//+|/|g;

	if ($name =~ m|^\.\.?/| && $self->{CurrentSkel} =~ m|^(.*/)|) {
		my $dir = $1;
		$dir =~ s|//+|/|g;
		while($name =~ m|^(\.\.?)/(.*)|) {
			$name = $2;
			if ($1 eq '.') { next; }
			if ($1 eq '..') {
				$dir =~ s|[^/]+/+$||;
			}
		}
		$name = $dir . $name;
	}
	if ($name =~ m|[^\w/\.\-]| || $name =~ m|\.\./|) {
		$self->error("Not allow characters are used in skeleton name '%s'", $name);
		return;
	}

	$name .= $self->{SkeletonExt};
	foreach(@{ $self->{SkelDirs} }) {
		my $lv = $_->{level};
		if ($lv > $level) { next; }
		my $file = $_->{dir} . $name;
		if (-r $file) {
			return wantarray ? ($file, $lv): $file;
		}
	}
	return;		# error
}

################################################################################
# ■出力処理
################################################################################
#-------------------------------------------------------------------------------
# ●ヘッダの設定
#-------------------------------------------------------------------------------
sub set_header {
	my ($self, $name, $val) = @_;
	if ($name eq 'Status') { $self->{Status} = $val; return; }
	push(@{ $self->{Headers} }, "$name: $val\r\n");
}
sub set_status {
	my $self = shift;
	$self->{Status} = shift;
}
sub set_lastmodified {
	my $self = shift;
	my $date = $self->rfc_date(shift);
	$self->{LastModified} = $date;
	$self->set_header('Last-modified', $date);
}
sub set_content_type {
	my $self = shift;
	$self->{Content_type} = shift;
}
sub set_charset {
	my $self = shift;
	$self->{Charset} = shift;
}

#-------------------------------------------------------------------------------
# ●HTML出力
#-------------------------------------------------------------------------------
sub output {
	my $self  = shift;
	my $body  = shift;
	my $ctype   = shift || $self->{Content_type};
	my $charset = shift || $self->{Charset};

	# Last-modified
	if ($self->{Status}==200 && $self->{LastModified} && $ENV{HTTP_IF_MODIFIED_SINCE} eq $self->{LastModified}) {
		$self->{Status}=304;
	}

	my $html = $self->http_headers($ctype, $charset, length($body));
	my $head = $ENV{REQUEST_METHOD} eq 'HEAD';
	if (!$head && $self->{Status} != 304) {
		$html .= $body;
	}

	my $c = !$head && ($self->{Status}==200) && $self->{HTML_cache};
	if ($c) { $$c = $html; }

	print $html;
	$self->{Send} = length($html);
}

#-------------------------------------------------------------------------------
# ●ヘッダを出力
#-------------------------------------------------------------------------------
sub output_http_headers {
	my $self = shift;
	print $self->http_headers(@_);
}
sub http_headers {
	my ($self, $ctype, $charset, $clen) = @_;
	if ($self->{No_httpheader}) { return''; }

	# Status
	my $header;
	my $status = $self->{Status};
	if ($self->{HTTPD}) {
		$header  = "HTTP/1.0 $status\r\n";
		my $st = $self->{HTTPD_state};
		$header .= "Connection: " . ($st->{keep_alive} ? 'keep-alive' : 'close') . "\r\n";
	} else {
		$header  = "Status: $status\r\n";
	}
	$header .= join('', @{ $self->{Headers} });	# その他のヘッダ

	# Content-Type;
	$ctype   ||= $self->{Content_type};
	$charset ||= $self->{SystemCode};
	if ($clen ne '') {
		$header .= "Content-Length: $clen\r\n";
	}
	$header .= <<HEADER;
Content-Type: $ctype; charset=$charset;\r
X-Content-Type-Options: nosniff\r
Cache-Control: no-cache\r
\r
HEADER
	return $header;
}

#-------------------------------------------------------------------------------
# ●互換性のためのコード / call結果の連結
#-------------------------------------------------------------------------------
sub chain_array {
	my ($self, $ary) = @_;
	return $ary;
}
sub call_and_chain {
	my $self = shift;
	return $self->call(@_);
}

#-------------------------------------------------------------------------------
# ●出力キャッシュの登録
#-------------------------------------------------------------------------------
sub regist_html_cache {
	my $self  = shift;
	$self->{HTML_cache} = shift;
}

#-------------------------------------------------------------------------------
# ●キャッシュ判定ルーチン登録
#-------------------------------------------------------------------------------
sub regist_cache_cheker {
	my $self  = shift;
	$CacheChecker{$0} = shift;
}

################################################################################
# ■文字列処理
################################################################################
#-------------------------------------------------------------------------------
# ●タグのエスケープ
#-------------------------------------------------------------------------------
sub esc {
	my $self = shift;
	return $self->tag_escape(join('',@_));
}
sub esc_amp {
	my $self = shift;
	return $self->tag_escape_amp(join('',@_));
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

#-------------------------------------------------------------------------------
# ●タグの除去
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# ●文頭、文末のスペース改行除去
#-------------------------------------------------------------------------------
sub trim {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/^[\s\r\n]*(.*?)[\s\r\n]*$/$1/s;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●URIエンコード
#-------------------------------------------------------------------------------
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
#-------------------------------------------------------------------------------
# ●ファイルサイズの調整
#-------------------------------------------------------------------------------
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

################################################################################
# ■モジュール関連
################################################################################
#-------------------------------------------------------------------------------
# ●アプリケーションのロード
#-------------------------------------------------------------------------------
sub loadapp {
	my $self = shift;
	return $self->_loadpm('SatsukiApp::' . shift, @_);
}
#-------------------------------------------------------------------------------
# ●ライブラリのロード
#-------------------------------------------------------------------------------
sub loadpm {
	my $self  = shift;
	my $pm    = shift;
	my $cache = $self->{LoadpmCache};
	if ($cache->{$pm}) { return $cache->{$pm}; }
	my $obj = $self->_loadpm('Satsuki::' . $pm, @_);
	if (ref($obj) && $obj->{__CACHE_PM}) {
		$cache->{$pm} = $obj;
	}
	return $obj;
}
#-------------------------------------------------------------------------------
# ○下位実装
#-------------------------------------------------------------------------------
sub _loadpm {
	my $self = shift;
	my $pm   = shift;
	my $pm_file = $pm . '.pm';
	$pm_file =~ s|::|/|g;

	if (! $INC{$pm_file}) {
		eval { require $pm_file; };
		if ($@) { delete $INC{$pm_file}; die($@); }

		no strict 'refs';

		if (! *{"${pm}::debug"}{CODE}) { *{"${pm}::debug"}   = \&export_debug; }
		if ($self->{DestroyDebug}) {
			*{"${pm}::DESTROY"} = sub {
				my $self = shift;
				print STDERR "[$$] DESTROY $self\n";    # debug-safe
			};
			print STDERR "[$$] loadpm $pm\n";               # debug-safe
		}
	}

	my $obj = $pm->new($self, @_);
	if (ref($obj) && $obj->{ROBJ}) {				# 循環参照対策
		Scalar::Util::weaken( $obj->{ROBJ} );
	}
	if ($obj->{__FINISH}) {
		push(@{$self->{FinishObjs}}, $obj);
	}
	return $obj;
}
sub export_debug {
	my $self = shift;
	$self->{ROBJ}->_debug(join(' ', @_));			# debug-safe
}

################################################################################
# ■ファイル入力
################################################################################
#-------------------------------------------------------------------------------
# ●ファイルパスの取得（互換性のため）
#-------------------------------------------------------------------------------
sub get_filepath {
	return $_[1];
}

#-------------------------------------------------------------------------------
# ●ファイル：すべての行を読み込む
#-------------------------------------------------------------------------------
sub fread_lines {
	my ($self, $file, $flags) = @_;

	my $fh;
	my @lines;
	if ( !sysopen($fh, $file, O_RDONLY) ) {
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

	# 後処理関数
	my $lines = \@lines;
	if ($flags->{PostProcessor}) {
		$lines = &{$flags->{PostProcessor}}($flags->{self} || $self, $lines, $flags );
	}
	return $lines;
}
#-------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式を読み込む
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# ●flock処理
#-------------------------------------------------------------------------------
sub read_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, $self->{IsWindows} ? &Fcntl::LOCK_EX : &Fcntl::LOCK_SH );
}
sub write_lock {
	my ($self, $fh) = @_;
	$self->flock($fh, &Fcntl::LOCK_EX );
}
sub write_lock_nb {
	my ($self, $fh) = @_;
	$self->flock($fh, &Fcntl::LOCK_EX | &Fcntl::LOCK_NB );
}
sub flock {
	my ($self, $fh, $mode) = @_;
	if ($self->{IsWindows}) {
		# Windowsでは、同一 $fh に2回以上 lock できない
		if ($self->{WinLock}->{$fh}) { return 100; }
		$self->{WinLock}->{$fh} = 1;
	}
	return flock($fh, $mode);
}
################################################################################
# ■ファイルの最終更新日時取得
################################################################################
#-------------------------------------------------------------------------------
# ●ファイルが読み込み可能なとき、最終更新時刻を返す（cache付）
#-------------------------------------------------------------------------------
sub get_lastmodified {
	my $self = shift;
	my $file = shift;

	if (!-r $file) { return ; }	# 読み込めない。存在しないファイル
	my $st = $StatCache{$file} ||= [ stat($file) ];
	return $st->[9];
}

#-------------------------------------------------------------------------------
# ●ディレクトリとディレクトリ内ファイルの最終更新日時を取得
#-------------------------------------------------------------------------------
sub get_lastmodified_in_dir {
	my ($self, $dir) = @_;

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

################################################################################
# ■キャッシュ付きファイル入力
################################################################################
my %FileCache;
#-------------------------------------------------------------------------------
# ●キャッシュ付きファイルRead
#-------------------------------------------------------------------------------
sub fread_lines_cached {
	my ($self, $file, $flags) = @_;

	my $cache = $FileCache{$file} ||= {};
	my $key   = join('//',$flags->{PostProcessor},$flags->{DelCR});
	my $c     = $cache->{$key} || {};

	my $st   = $StatCache{$file} ||= [ stat($file) ];
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

#-------------------------------------------------------------------------------
# ●キャッシュ付きHASHファイルRead
#-------------------------------------------------------------------------------
sub fread_hash_cached {
	my ($self, $file, $flags) = @_;
	my $lines;
	my %_flags = %{$flags || {}};
	$_flags{PostProcessor} = \&parse_hash;
	return $self->fread_lines_cached($file, \%_flags);
}

#-------------------------------------------------------------------------------
# ●キャッシュの削除
#-------------------------------------------------------------------------------
sub delete_file_cache {
	my $self = shift;
	my $file = shift;

	delete $StatCache{$file};
	$FileCache{$file} = {};
}

################################################################################
# ■その他ファイル関連
################################################################################
#-------------------------------------------------------------------------------
# ●ファイルの更新日時を更新
#-------------------------------------------------------------------------------
sub touch {
	my $self = shift;
	my $file = shift;
	if (!-e $file) { $self->fwrite_lines($file, []); return; }
	my ($now) = $self->{TM};
	utime($now, $now, $file);
}

#-------------------------------------------------------------------------------
# ●ファイルを検索する
#-------------------------------------------------------------------------------
# search_files("directory name", $opt);
#	拡張子は "txt" のように指定する。配列ref, ハッシュref可。
#	拡張子を省略した場合、すべてのリストが返る。
#	ディレクトリには最後に / を付けて返す。
#
#	$opt->{ext}	 	検索する拡張子（".txt"のように指定）
#	$opt->{all}	 = 1	'.'で始まるファイルを含める（"."と".."は常に無視）
#	$opt->{dir}	 = 1	ディレクトリを含める
#	$opt->{dir_only} = 1	ディレクトリのみ返す

sub search_files {
	my $self = shift;
	my $dir  = shift;
	my $opt  = shift;

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
		if ($_ eq '.' || $_ eq '..')  { next; }			# ./ ../ は無視
		if (!$opt->{all} && substr($_,0,1) eq '.') { next; }	# 隠しファイルを無視
		my $isDir = -d "$dir$_";
		if ((!$opt->{dir} && $isDir) || ($opt->{dir_only} && !$isDir)) { next; }
		if ($ext && ($_ !~ /(\.\w+)$/ || !$ext->{$1})) { next; }
		push(@filelist, $_ . ($isDir ? '/' : ''));
	}
	closedir($fh);

	## @filelist = sort @filelist;
	return \@filelist;
}

#-------------------------------------------------------------------------------
# ●ファイルパスから相対パスを得る
#-------------------------------------------------------------------------------
sub get_relative_path {
	my ($self, $base, $file) = @_;
	if (ord($file) == 0x2f) { return $file; }	# / で始まる
	my $x = rindex($base, '/');
	if ($x<0) { return $file; }
	return substr($base, 0, $x+1) . $file;
}

################################################################################
# ■クエリー・フォーム・環境変数処理
################################################################################
#-------------------------------------------------------------------------------
# ●フォームの読み込み
#-------------------------------------------------------------------------------
sub read_form {
	if ($ENV{REQUEST_METHOD} ne 'POST') { return ; }
	return &_read_form(@_);		# 実体呼び出し (use AutoLoader)
}
#-------------------------------------------------------------------------------
# ●クエリー解析
#-------------------------------------------------------------------------------
sub read_query {
	my $self = shift;
	if ($self->{Query}) { return $self->{Query}; }
	return ($self->{Query} = $self->parse_query($ENV{QUERY_STRING}, @_));
}
sub parse_query {
	my $self   = shift;
	my $q      = shift;
	my $arykey = shift || {};
	my $code   = $self->{SystemCode};

	my %h;
	foreach(split(/&/, $q)) {
		my ($key, $val) = split(/=/,$_,2);
		$key =~ s|[^\w\-/]||g;
		$val =~ tr/+/ /;
		$val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;

		# 文字コード変換（文字コードの完全性保証）
		my $jcode = $self->load_codepm_if_needs( $val );
		$jcode && $jcode->from_to( \$val, $code, $code );

		$val =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;	# TAB LF CR以外の制御コードを除去
		$val =~ s/\r\n?/\n/g;	# 改行を統一
		if ($arykey->{$key} || substr($key,-4) eq '_ary') {
			my $a = $h{$key} ||= [];
			push(@$a, $val);
			next;
		}
		$h{$key} = $val;
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# ●クエリー構築	※フォームデータ構築にも使える
#-------------------------------------------------------------------------------
sub make_query {
	return &_make_query(shift, '&', @_);
}
sub make_query_amp {
	return &_make_query(shift, '&amp;', @_);
}
sub _make_query {
	my $self = shift;
	my $amp  = shift;
	my $h    = ref($_[0]) ? shift : $self->{Query};
	my $add  = shift;
	my $q;
	foreach(keys(%$h)) {
		my $k = $_;
		my $v = $h->{$k};
		$self->encode_uricom($k);
		foreach(@{ ref($v) ? $v : [$v] }) {
			my $x = $_;
			$self->encode_uricom($x);
			$q .= ($q eq '' ? '' : $amp ) . "$k=$x";
		}
	}
	if ($add ne '') { $q .= "$amp$add"; }
	return $q;
}

#-------------------------------------------------------------------------------
# ●PATH INFO 解析
#-------------------------------------------------------------------------------
#  PATH_INFO = /xxx/yyy/zzz
sub read_path_info {
	my $self = shift;
	my ($dummy, @pinfo) = split('/', $ENV{PATH_INFO} . "\0");
	if (@pinfo) { chop($pinfo[$#pinfo]); }

	return ($self->{Pinfo} = \@pinfo);
}

################################################################################
# ■Cookie処理
################################################################################
#===============================================================================
# ●Cookieの解析
#===============================================================================
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

#===============================================================================
# ○cookie を分解（array cookie, hash cookie の復元）
#===============================================================================
sub split_cookie {
	my $self  = shift;
	my @array = split(/\0/, shift);
	shift(@array);	# 読み捨て

	my $flag = ord(shift(@array));
	if ($flag == 1) {		# array
		return \@array;
	} elsif ($flag == 2) {		# hash
		my %h = @array;
		return \%h;
	}
}

################################################################################
# ■日付・時刻処理
################################################################################
#-------------------------------------------------------------------------------
# RFC date
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# W3C date
#-------------------------------------------------------------------------------
sub w3c_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);
	return sprintf("%04d-%02d-%02dT%02d:%02d:%02d+00:00"
		,$year+1900, $mon+1, $mday, $hour, $min, $sec);
}

#-------------------------------------------------------------------------------
# make time hash
#-------------------------------------------------------------------------------
sub time2timehash {
	my $self = shift;
	my $tm   = shift || $self->{TM};

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

#-------------------------------------------------------------------------------
# print formatted time
#-------------------------------------------------------------------------------
# print_tm($UTC);
# print_tmf($format, $UTC);
#
sub print_tm {
	my $self = shift;
	return $self->print_tmf('%Y-%m-%d %H:%M:%S', @_);
}
sub print_tmf {
	my $self = shift;
	my $fm   = shift;
	my $tm   = shift || $self->{TM};

	# This macro like 'strftime(3)' function.
	# compatible : %Y %y %m %d %I %H %M %S %w %s %e and %a %p
	my ($s, $m, $h, $D, $M, $Y, $wd, $yd, $isdst) = localtime($tm);
	my %h;
	$h{s} = $tm;
	$h{j} = $yd;
	$h{y} = sprintf("%02d", $Y % 100);
	$h{Y} = $Y + 1900;
	$h{m} = sprintf("%02d", $M+1);
	$h{d} = sprintf("%02d", $D);
	$h{H} = sprintf("%02d", $h);		# 00-23
	$h{M} = sprintf("%02d", $m);
	$h{S} = sprintf("%02d", $s);
	$h{I} = sprintf("%02d", $h % 12);	# 00-11

	$h{a}  = $self->{WDAY_name}->[$wd];
	$h{p}  = $self->{AMPM_name}->[ int($h/12) ];
	$fm =~ s/%(\w)/$h{$1}/g;
	return $fm;
}

################################################################################
# ■メッセージ処理、ディバグ関連
################################################################################
#-------------------------------------------------------------------------------
# ●フォームエラーシステム
#-------------------------------------------------------------------------------
sub clear_form_error {
	my $self = shift;
	$self->{FormError}=undef;
}
sub form_error {	# for compatible
	my $self = shift;
	if (!@_) { return $self->{FormError}; }
	my $name = shift;
	$self->{FormError} ||= {};
	$self->{FormError}->{$name}=$_[0] || 1;
	$self->{FormError}->{"c_$name"}=' class="error"';
	$self->{FormError}->{"e_$name"}=' error';
	return defined $_[0] ? $self->message(@_) : undef;
}

sub clear_form_err {
	my $self = shift;
	$self->{FormErr}  =undef;
}
sub form_err {
	my $self = shift;
	if (!@_) { return $self->{FormErr}; }
	my $name = shift;
	my $msg  = $self->translate(@_);
	my $h = $self->{FormErr} ||= { _order => [] };
	$h->{$name}= $msg;
	push(@{$h->{_order}}, $name);
}

#-------------------------------------------------------------------------------
# ●言語ファイルのロード
#-------------------------------------------------------------------------------
sub load_language_file {
	my ($self, $file) = @_;
	# 言語ファイルロード
	my $h = $self->{Msg_translate} = $self->fread_hash_cached($file);

	$self->{CodeLib} = $h->{CodeLib};
	$self->{Locale}  = $h->{Locale};
}

#-------------------------------------------------------------------------------
# ●文字ライブラリのロード
#-------------------------------------------------------------------------------
sub load_codepm {
	my $self = shift;
	return $self->{CodeLib} ? $self->loadpm('Code::' . $self->{CodeLib}, @_) : undef;
}
sub load_codepm_if_needs {
	my $self = shift;
	foreach (@_) {
		if ($_ =~ /[^\x00-\x0D\x10-\x1A\x1C-\x7E]/) {
			return $self->load_codepm(@_);
		}
	}
	return;
}

#-------------------------------------------------------------------------------
# ●メッセージの翻訳
#-------------------------------------------------------------------------------
sub translate {
	my $self = shift;
	my $msg  = shift;
	$msg = $self->{Msg_translate}->{$msg} || $msg;
	if (@_) { return sprintf($msg, @_); }
	return $msg;
}

#-------------------------------------------------------------------------------
# ●メッセージ処理ルーチン
#-------------------------------------------------------------------------------
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

	my $msg = $self->translate(@_);
	my $ary = $self->{Message};
	$self->tag_escape($class,$msg);
	push(@$ary, "<div class=\"$class\">$msg</div>");

	return $msg;
}

#-------------------------------------------------------------------------------
# ●エラー処理ルーチン
#-------------------------------------------------------------------------------
# &error_from('error from', "表示するエラー");
# &error("表示するエラー");
sub error {
	my $self = shift;
	return $self->error_from('', @_);
}
sub error_from {
	my $self = shift;
	my $from = shift;
	my $msg  = $self->translate(@_);

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
				push(@froms, "$file line $line");
				$prev_file = $file;
			}
			if (!($pack eq __PACKAGE__ || $pack =~ /::DB_/) || $i>9) { last; }
		}
		$from = pop(@froms);
		while(@froms) {
			$from = pop(@froms) . " ($from)";
		}
	}
	if ($from ne '') { $msg = "$msg ($from)"; }
	$self->tag_escape($msg);

	chomp($msg);
	push(@{$self->{Error}}, $msg);
	$self->{Error_flag} = 1;
	return $msg;
}

sub clear_error {
	my $self  = shift;
	my $chain = shift || "<br>\n";
	my $error = $self->{Error};
	$self->{Error} = [];
	if (! @$error) { return ''; }
	return join($chain, @$error);
}

#-------------------------------------------------------------------------------
# ●エラー出力
#-------------------------------------------------------------------------------
sub output_error {
	my $self  = shift;
	my $ctype = shift;
	my $errs  = $self->{Error};

	if ($ENV{SERVER_PROTOCOL} && $ctype) {
		$self->output_http_headers($ctype, @_);
	}
	if ($ENV{SERVER_PROTOCOL} && $self->{Content_type} eq 'text/html') {
		print "<hr><strong>(ERROR)</strong><br>\n",join("<br>\n", @$errs);
	} else {
		print "\n(ERROR) ",$self->unesc(join("\n", @$errs)),"\n";
	}
}

1;
