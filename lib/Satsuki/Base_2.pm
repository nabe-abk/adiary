use strict;
#------------------------------------------------------------------------------
# Split from Base.pm for AutoLoader
#------------------------------------------------------------------------------
use Satsuki::Base ();
package Satsuki::Base;
###############################################################################
# ■スケルトンコンパイルとキャッシュ
###############################################################################
#------------------------------------------------------------------------------
# ●コンパイル
#------------------------------------------------------------------------------
sub compile {
	my ($self, $cache_file, $src_file, $src_filefull, $orig_tm) = @_;
	#------------------------------------------------------------
	# コンパイルログを残すか？
	#------------------------------------------------------------
	my $compile_log = $self->get_filepath( $self->{Compile_log_dir} );
	if ($compile_log ne '' && (-d $compile_log || $self->mkdir($compile_log)) ) {
		my $file = $src_file;
		$file =~ s|/|_-_|g;
		$file =~ s/[^\w\-\.]/_/g;
		$compile_log .= $file;	# log を残す
	} else {
		undef $compile_log;
	}
	#------------------------------------------------------------
	# コンパイル処理
	#------------------------------------------------------------
	if ($cache_file) { unlink($cache_file); }	# キャッシュ削除
	my $c     = $self->loadpm('Base::Compiler');
	my $lines = $self->fread_lines($src_filefull);
	my ($errors, $warns, $arybuf) = $c->compile($lines, $src_file, $compile_log);

	#------------------------------------------------------------
	# キャッシュの保存
	#------------------------------------------------------------
	if ($cache_file && $errors == 0 && (!$warns || !$self->{Develop})) {
		$self->save_cache($cache_file, $src_filefull, $orig_tm, $arybuf);
	}
	#------------------------------------------------------------
	# コンパイルエラー
	#------------------------------------------------------------
	my $err_msg = $c->{error_msg};
	if ($#$err_msg >= 0) {
		foreach(@$err_msg) {
			# 1 = warrning flag
			$self->error_from('', "[Compiler] $src_file : $_");
		}
		$self->set_status(500);
		# エラーがあっても処理継続（実行）する
		# $self->{Error_flag}=1;	# これを設定すると実行が止まる
	}

	return $arybuf;
}

#------------------------------------------------------------------------------
# ●キャッシュのセーブ
#------------------------------------------------------------------------------
sub save_cache {
	my ($self, $cache_file, $src_file, $src_file_tm, $arybuf) = @_;
	my @lines;
	my $tms = $self->{Timestamp} || $self->init_tm();
	push(@lines, <<TEXT);
# $tms : Generate from '$src_file';
#------------------------------------------------------------------------------
# Caution) Don't edit this file . If you edit this, will be occoued error.
#------------------------------------------------------------------------------
\0
TEXT
	# バージョン／コンパイラ・元スケルトンの更新時刻
	push(@lines, "Version = 1.01\n\0");
	push(@lines, ($self->{Compiler_tm}) . "\0");
	push(@lines, $src_file_tm . "\0");

	# ルーチンの保存
	push(@lines, ($#$arybuf+1) . "\0");
	foreach (@$arybuf) {
		push(@lines, "$_\0");	# routines
	}
	# 予備領域
	push(@lines, "0\0");
	push(@lines, "0\0");
	push(@lines, "0\0");

	# ファイルに書き出し
	$self->fwrite_lines($cache_file, \@lines);
}

###############################################################################
# ■終了命令
###############################################################################
#------------------------------------------------------------------------------
# ●エラーによる終了
#------------------------------------------------------------------------------
sub error_exit {
	my ($self, $err) = @_;
	my ($pack, $file, $line) = caller(1);
	# HTTP mode
	if ($ENV{SERVER_PROTOCOL} && $self->{Content_type} eq 'text/html') {
		$err =~ s/\n/<br>\n/g;
		$self->set_status(500);	# Internal Server Error
		$self->print_http_headers();
		print <<HTML;
<html><body>
<h1>Perl interpreter error (exit)</h1>
<p><span style="font-family: monospace;">$err</p>
<!-- $file at $line -->
HTML
		foreach(sort keys(%ENV)) {
			print "$_=$ENV{$_}<br>\n";
		}
		print "</body></html>\n";
	} else {
		$self->tag_unescape($err);
		$err =~ s/<br>/\n/g;
		print "*** Perl interpreter error (exit) ***\n$err\n";
	}
	$self->exit(-1);	# 終了
}

###############################################################################
# ■スケルトンのcall
###############################################################################
#------------------------------------------------------------------------------
# ●ディレクトリ内のスケルトンを呼び出し
#------------------------------------------------------------------------------
sub call_dir {
	my $self  = shift;
	my $dir   = $self->{Skeleton_subdir} . shift;
	my $level = shift || 0x7fffffff;
	my $ext = $self->{Skeleton_ext};

	# パス安全性チェック
	$self->clean_path($dir);

	my %filehash;
	my $dirs = $self->{Sekeleton_dir};
	foreach(@{ $self->{Sekeleton_dir_levels} }) {
		if ($_>$level) { next; }
		my $files = $self->search_files( "$dirs->{$_}$dir", {ext => $ext});
		map { $filehash{$_}=1; } @$files;
	}
	# ソート
	my @files = sort(keys(%filehash));
	my $ext_len = length($ext);
	my @ary;
	foreach(@files) {
		my $file = $dir . substr($_, 0, length($_) - $ext_len);
		push(@ary, $self->call( $file, @_ ));
	}
	return \@ary;
}

###############################################################################
# ■文字列／入力チェック処理
###############################################################################
#------------------------------------------------------------------------------
# ●配列の重複削除
#------------------------------------------------------------------------------
# 配列の順序は保証されない
sub de_duplication {
	my ($self, $ary) = @_;
	my %h;
	foreach(@$ary) { $h{$_}=1; }
	return [ keys(%h) ];
}
#------------------------------------------------------------------------------
# ●入れ子配列の結合
#------------------------------------------------------------------------------
sub call_and_chain {
	my $self = shift;
	my $str;
	$self->_chain_array($self->call(@_), \$str);
	return $str;
}
sub chain_array {
	my ($self, $ary, $str) = @_;
	$self->_chain_array($ary, \$str);
	return $str;
}
sub _chain_array {
	my ($self, $ary, $r_str) = @_;
	foreach(@$ary) {
		if (ref($_) eq 'ARRAY') {
			$self->_chain_array($_, $r_str);
			next;
		}
		$$r_str .= $_;
	}
}

#------------------------------------------------------------------------------
# ●form埋込用サニタイズ / EBXSSのチェック
#------------------------------------------------------------------------------
# http://www.atmarkit.co.jp/fsecurity/rensai/hoshino10/hoshino02.html
# www.akiyan.com/blog/archives/2006/03/xsscssebcss.html
sub escape_into_quote {
	my $self = shift;
	my $form = shift || $self->{Form};
	my $jcode = $self->load_codepm();
	my $code  = $self->{System_coding};
	foreach(keys(%$form)) {
		$form->{$_} = $jcode->from_to($form->{$_}, $code, $code);
		$form->{$_} =~ s/&/&amp;/g;
		$form->{$_} =~ s/"/&quot;/g;
	}
	return;
}

#------------------------------------------------------------------------------
# ●URL XSSのチェック
#------------------------------------------------------------------------------
sub check_url_xss {
	my $self = shift;
	foreach(@_) {
		if ($_ =~ /^\s*$/) { $_=''; next; }
		if (ord($_) != 0x2f && substr($_, 0, 2) ne './'
		 && substr($_, 0, 7) ne 'http://' && substr($_, 0, 8) ne 'https://') {
			$_ =~ s/&#(?:0*58|x0*3a);/:/;
			$_ =~ s/:/%3a/g;
			$_ = './' . $_;
		}
	}
	return $_[0];
}

###############################################################################
# ■ファイル出力
###############################################################################
our %FileCache;
#------------------------------------------------------------------------------
# ●すべての行をファイルに書き込む
#------------------------------------------------------------------------------
# Ret:	0	成功
# 	1	失敗
sub fwrite_lines {
	my ($self, $_file, $lines, $flags) = @_;
	my $file = $self->get_filepath($_file);
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	my $fail_flag=0;
	my $fh;
	my $append = $flags->{Append} ? O_APPEND : 0;
	if ( !sysopen($fh, $file, O_CREAT | O_RDWR | $append) ) {
		$self->error("File can't write '%s'", $file);
		close($fh);
		return 1;
	}
	binmode($fh);
	$self->write_lock($fh);
	if (! $append) {		# 追記モードではない
		truncate($fh, 0);	# ファイルサイズを 0 に
		seek($fh, 0, 0);	# ファイルポインタを先頭へ
	}
	foreach(@$lines) {
		print $fh $_;
	}
	close($fh);

	$self->delete_file_cache($file);

	# モード変更
	if (defined $flags->{FileMode}) { chmod($flags->{FileMode}, $file); }
	return 0;
}

#------------------------------------------------------------------------------
# ●ファイル：配列をファイルに追記する
#------------------------------------------------------------------------------
sub fappend_lines {
	my ($self, $file, $lines, $flags) = @_;
	$flags->{Append} = 1;
	return $self->fwrite_lines($file, $lines, $flags);
}

#------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式に書き込む
#------------------------------------------------------------------------------
sub fwrite_hash {
	my ($self, $file, $h, $flags) = @_;

	my @ary;
	my $append = $flags->{Append};
	foreach(keys(%$h)) {
		my $val = $h->{$_};
		if (ref $val || (!$append && $val eq '')) { next; }
		if ($_ =~ /[\r\n=]/ || substr($_,0,1) eq '*') { next; } # 改行や「=」を含むか*で始まるkeyは無視
		if (0 <= index($val, "\n")) {	# 値に改行を含む
			$val =~ s/(?:^|\n)__END_BLK_DATA\n/__END_BLK_DATA \n/g;
			push(@ary, "*$_=<<__END_BLK_DATA\n$val\n__END_BLK_DATA\n");
		} else {
			push(@ary, "$_=$val\n");
		}
	}
	if ($file eq '') { return \@ary; }
	return $self->fwrite_lines($file, \@ary, $flags);
}

#------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式に追記する
#------------------------------------------------------------------------------
sub fappend_hash {
	my ($self, $file, $h, $flags) = @_;
	$flags->{Append} = 1;
	return $self->fwrite_hash($file, $h, $flags);
}

#------------------------------------------------------------------------------
# ●ファイル：ファイルを編集
#------------------------------------------------------------------------------
# 編集用。ロック処理付き。
sub fedit_readlines {
	my ($self, $_file, $flags) = @_;
	my $file = $self->get_filepath($_file);

	my $fh;
	if ( !sysopen($fh, $file, O_CREAT | O_RDWR | ($flags->{Append} ? O_APPEND : 0)) ) {
		if ($flags->{NoError}) {
			$self->warning("File can't open (for %s) '%s'", 'edit', $file);
		} else {
			$self->error("File can't open (for %s) '%s'", 'edit', $file);
		}
	}
	binmode($fh);
	if ($flags->{ReadLock}) {
		$self->read_lock($fh);
	} else {
		$self->write_lock($fh);
	}
	my @lines;
	@lines = <$fh>;
	$self->delete_file_cache($file);
	return ($fh, \@lines);
}

sub fedit_writelines {
	my ($self, $file, $fh, $lines, $flags) = @_;
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	seek($fh, 0, 0);	# ファイルポインタを先頭へ
	foreach(@$lines) {
		print $fh $_;
	}
	# ■Windows注意!
	# flock($fh, LOCK_SH) して truncate($fh, 0) すると必ずファイルサイズが 0 になる。
	# See more : http://adiary.blog.abk.nu/0352
	truncate($fh, tell($fh));
	close($fh);

	# モード変更
	if (defined $flags->{FileMode}) {
		chmod($flags->{FileMode}, $self->get_filepath($file));
	}
	return 0;
}

sub fedit_exit {
	my ($self, $file, $fh) = @_;
	close($fh);
}

#------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式のエデット
#------------------------------------------------------------------------------
sub fedit_readhash {
	my ($self, $file, $flags) = @_;
	my ($fh, $lines) = $self->fedit_readlines($file, $flags);
	my $hash = $self->fread_hash($lines);
	return ($fh, $hash);
}
sub fedit_writehash {
	my ($self, $file, $fh, $h, $flags) = @_;
	my $lines = $self->fwrite_hash('', $h);
	$self->fedit_writelines($file, $fh, $lines, $flags);
}

###############################################################################
# ■その他ファイル関連
###############################################################################
#------------------------------------------------------------------------------
# ●スケルトンファイルの読み出し
#------------------------------------------------------------------------------
sub fread_skeleton {
	my $self = shift;
	my $file = $self->check_skeleton( @_ );
	if (!$file) { return; }
	return $self->fread_lines( $file );
}

#------------------------------------------------------------------------------
# ●ディレクトリの作成
#------------------------------------------------------------------------------
sub mkdir {
	my ($self, $dir, $mode) = @_;
	$dir = $self->get_filepath($dir);
	if (-e $dir) { return -1; }
	my $r = mkdir( $dir );	# 0:fail 1:Success
	if ($r) {
		if (substr($dir,-1) eq '/') { chop($dir); }
		if (defined $mode) { $r = chmod($mode, $dir); }
	} else { $self->error("Failed mkdir '%s'", $_[1]); }
	return $r ? 0 : 1;
}

#------------------------------------------------------------------------------
# ●ファイルの削除
#------------------------------------------------------------------------------
sub file_delete {
	my $self = shift;
	return unlink( $self->get_filepath($_[0]) );
}

# rm -rf 
sub dir_delete {	# 再起関数
	my ($self, $dir) = @_;
	if ($dir eq '') { return; }
	$dir = $self->get_filepath($dir);
	if (substr($dir, -1) eq '/') { chop($dir); }
	if (-l $dir) {	# is symbolic link
		return unlink($dir);
	}
	$dir .= '/';
	my $files = $self->search_files( $dir, {dir=>1});
	foreach(@$files) {
		my $file = $dir . $_;
		if (-d $file) { $self->dir_delete( $file ); }
		  else { unlink( $file ); }
	}
	return rmdir($dir);
}

#------------------------------------------------------------------------------
# ●ファイルのシンボリックリンク作成
#------------------------------------------------------------------------------
sub file_symlink {
	my ($self, $src, $_des) = @_;
	my $des = $self->get_filepath($_des);
	if (ord($src) != 0x2f && substr($src,0,2) ne '~/') {
		$_des =~ s|/| $src = "../$src";'/' |eg;
	}
	my $r = symlink($src, $des);
	if (!$r) {
		$self->error("Create symlink error '%s' $src $des", $!);
		return 1;
	}
	return 0;
}

#------------------------------------------------------------------------------
# ●ファイルのコピー
#------------------------------------------------------------------------------
sub file_copy {
	my ($self, $src, $des) = @_;
	$src = $self->get_filepath($src);
	$des = $self->get_filepath($des);
	return $self->_file_copy($src, $des)
}
sub _file_copy {
	my ($self, $src, $des) = @_;
	my $data;
	my $fh;

	# READ
	if ( !sysopen($fh, $src, O_RDONLY) ) { $self->error("File can't read '%s'", $src); return 1; }
	$self->read_lock($fh);
	my $size = (stat($fh))[7];
	read($fh, $data, $size);
	close($fh);

	# Write
	if ( !sysopen($fh, $des, O_WRONLY | O_CREAT | O_TRUNC) ) { $self->error("File can't write '%s'", $des); return 2; }
	$self->write_lock($fh);
	syswrite($fh, $data, $size);
	close($fh);
	return 0;
}

#------------------------------------------------------------------------------
# ●ディレクトリの中身をコピー
#------------------------------------------------------------------------------
# cp -r src_dir/* new_dir
sub dir_copy {
	my ($self, $src, $des, $mode) = @_;
	$src = $self->get_filepath($src);
	$des = $self->get_filepath($des);
	if (substr($src, -1) ne '/') { $src .= '/'; }
	if (substr($des, -1) ne '/') { $des .= '/'; }
	return $self->_dir_copy($src, $des)
}
# 再起関数
sub _dir_copy {
	my ($self, $src, $des) = @_;
	$self->mkdir("$des");
	my $files = $self->search_files( $src, {dir=>1} );
	my $error = 0;
	foreach(@$files) {
		my $file = $src . $_;
		if (-d $file) {
			$error += $self->_dir_copy( "$file", "$des$_" );
		} else {
			$error += $self->_file_copy($file, "$des$_") && 1;
		}
	}
	return $error;
}

#------------------------------------------------------------------------------
# ●テンポラリファイルの作成
#------------------------------------------------------------------------------
sub get_tmpdir {
	my $self  = shift;
	my $dir = $self->{Temp};
	if ($dir eq '') {
		$dir = $ENV{TMPDIR} || $ENV{TEMP} || $ENV{TMP} || '/tmp';
		$dir =~ tr|\\|/|;		# for windows
		if ($dir eq '') { return ; }	# 失敗
		$dir .= '/satsuki-system/';
	} else {
		$dir = $self->get_filepath( $dir );
	}
	if (!-d $dir) {
		$self->mkdir($dir);
	}
	# 古いテンポラリの削除
	$self->tmpwatch( $dir );
	return $dir;
}

sub open_tmpfile {
	my $self = shift;
	my $dir  = $self->get_tmpdir();

	# ディレクトリ確認
	if (!-w  && !$self->mkdir($dir)) {
		$self->error("Can't write temporary dir '%s'", $dir);
		return ;
	}

	# テンポラリファイルのオープン
	my $fh;
	my $file;
	my $tmp_file_base = $dir . $$ . '_' . ($ENV{REMOTE_PORT} +0) . '_';
	my $i;
	for($i=1; $i<100; $i++) {
		$file = $tmp_file_base . $i . '.tmp';
		if (sysopen($fh, $file, O_CREAT | O_EXCL | O_RDWR)) {
			binmode($fh);
			$i=0; last;		# 作成成功
		}
	}
	if ($i) {	# 失敗
		$self->error("Can't open temporary file '%s'", $file);
		return ;
	}
	return wantarray ? ($fh, $file) : $fh;
}
#------------------------------------------------------------------------------
# ●テンポラリファイルの削除
#------------------------------------------------------------------------------
sub tmpwatch {
	my $self = shift;
	my ($dir, $type, $time) = @_;
	$dir = $dir ? $self->get_filepath( $dir ) : $self->get_tmpdir();
	if ($time < $self->{Temp_timeout}) { $time=$self->{Temp_timeout}; }
	if ($time < 10) { $time = 10; }

	# 削除条件の設定
	if    ($type eq 'atime') { $type= 8; }
	elsif ($type eq 'ctime') { $type=10; }
	else  { $type=9; }	# mtime (modified time)
	my $check_tm = $self->{TM} - $time;	# $check_tm より古ければ削除

	# 削除ループ
	my $files = $self->search_files( $dir );
	my $c = 0;
	foreach(@$files) {
		my $file = $dir . $_;
		if ((stat($file))[$type] > $check_tm) { next; }
		$c += unlink( $file );
	}
	return $c;
}

#------------------------------------------------------------------------------
# ●ファイルに対するロック
#------------------------------------------------------------------------------
sub file_lock {
	my ($self, $file, $type) = @_;
	my $file = $self->get_filepath($file);

	my $fh;	# READ
	if ( !sysopen($fh, $file, O_RDONLY) ) {
		$self->error("File can't open (for %s) '%s'", 'lock', $file);
		return undef;
	}
	$type ||= 'write_lock';
	my $r = $self->$type($fh);
	if (!$r) { return $r; }
	return $fh;
}

###############################################################################
# ■システムチェック
###############################################################################
#------------------------------------------------------------------------------
# ●特定のライブラリがあるかチェック
#------------------------------------------------------------------------------
#Ret:	空でない文字列	成功。ライブラリへのパス
#
sub check_pm {
	my $self = shift;
	my $pm   = 'Satsuki/' . shift;
	return $self->check_lib($pm, @_);
}
sub check_lib {
	my $self     = shift;
	my $lib_file = shift;
	if (index($lib_file, '.') < 0) { $lib_file .= ".pm"; }
	$lib_file =~ s|::|/|g;
	if ($INC{$lib_file}) { return $INC{$lib_file}; }
	foreach(@INC) {
		if (-r "$_/$lib_file") { return "$_/$lib_file"; }
	}
	return ;
}
###############################################################################
# ■タグの除去、不正文字除去
###############################################################################
sub esc_xml {	# 非破壊
	my $self = shift;
	return $self->{ROBJ}->tag_escape_for_xml(join('',@_));
}
sub tag_escape_for_xml {	# &nbsp; は使えない
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&(amp|lt|gt|quot|apos|#\d+;)/\x01$1/g;
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
		$_ =~ s/'/&apos;/g;
		$_ =~ tr/\x01/&/;
	}
	return $_[0];
}

# 改行なし文字列の正規化
sub string_normalize {
	my $self = shift;
	$self->trim(@_);	# 前後のスペース除去
	foreach(@_) {
		$_ =~ s/[ \t]+/ /g;
		$_ =~ s/[\x00-\x1f]//g;
	}
	return $_[0];
}

# emailのチェック
sub check_email {
	my $self = shift;
	$self->trim(@_);
	foreach(@_) {
		if ($_ !~ /[\w\.\-\+]+\@[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]+/) {
			$_=undef;
		}
	}
	return wantarray ? (grep {$_ ne ''} @_) : $_[0];
}

###############################################################################
# ■クエリー・フォーム処理
###############################################################################
#------------------------------------------------------------------------------
# ●フォームの読み込み（実体）
#------------------------------------------------------------------------------
sub _read_form {
	my ($self) = @_;
	if ($ENV{REQUEST_METHOD} ne 'POST') { return ; }
	if (ref $self->{Form} eq 'HASH') { return $self->{Form}; }

	### POST 事前スクリプトの exec 
	if ($self->{If_post_exec_pre}) { $self->execute( $self->{If_post_exec_pre} ); }
	### オプションロード
	my $options = $self->{Form_options};
	### マルチパート form か
	my $content_type = $ENV{CONTENT_TYPE};
	if (index($content_type, 'multipart/form-data') == 0) {
		if (!$options->{allow_multipart}) { return; }
		return $self->read_multipart_form( $content_type );
	}
	### データサイズの確認
	my $length = $ENV{CONTENT_LENGTH};
	if ($options->{total_max_size} && $length > $options->{total_max_size}) {
		$self->message('Too large form data'); return ;
	}
	### 通常のフォーム処理
	my $content;
	read(STDIN, $content, $ENV{CONTENT_LENGTH});
	my @form = split(/&/, $content);
	undef $content;

	### フォーム解析
	my $form = $self->{Form} = {};
	foreach (@form) {
		my ($name, $val) = split(/=/);
		$name=~ tr/+/ /;
		$name=~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$val =~ tr/+/ /;
		$val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$self->form_data_check_and_save($form, $options, $name, $val);
	}

	# save
	$self->{POST} = 1;		# POST であることを記録
	$self->{Form} = $form;

	# POST スクリプトの exec 
	if ($self->{If_post_exec}) { $self->execute( $self->{If_post_exec} ); }
	return $form;
}

#------------------------------------------------------------------------------
# ●multipart フォームの読み込み RFC1867, RFC2388
#------------------------------------------------------------------------------
sub read_multipart_form {
	my ($self, $content_type) = @_;
	my $options = $self->{Form_options};

	### データサイズの確認
	my $length    = $ENV{CONTENT_LENGTH};
	my $total_max = $options->{multipart_total_max_size};
	if ($total_max && $length > $total_max) {
		$self->message('Too large form data (max %dKB)', $total_max >> 10); return ;
	}

	my $file_max_size   = $options->{multipart_file_max_size} || $total_max || 0x100000;	#  1MB
	my $data_max_size   = $options->{multipart_data_max_size} || 0x10000;			# 64KB
	my $header_max_size = 1024;
	my $use_temp_dir    = $options->{multipart_use_temp_dir};

	# boundary の読み出し
	binmode(STDIN);		# for DOS/Windows
	$content_type =~ /boundary=(.*)/;
	my $boundary = $1;
	my $form     = {};
	my $buffer   = $self->loadpm('Base::BufferedRead', 'STDIN', $length, $total_max, $options->{multipart_buffer_size});
	$buffer->{read_max} = $length;

	# 先頭の boundary 読み捨て
	my $line;
	$buffer->read_line(\$line, "--$boundary\r\n", $header_max_size);
	$boundary = "\r\n--$boundary";
	# 読み出しループ
	my $err = 1;
	while(! $buffer->{data_end}) {
		# ヘッダの読み出し
		my $name;
		my $filename;
		my $count = 32;
		while($count--) {
			$buffer->read_line(\$line, "\r\n", $header_max_size);
			if ($line eq '') { last; }
			if ($line =~ /^Content-Disposition:(.*)$/i) {
				$line = $1;
				if ($line =~ /name="((?:\\"|.)*?)"/i)     { $name = $1; }
				if ($line =~ /filename="((?:\\"|.)*?)"/i) { $filename = $1; }
			}
			$name =~ s/\\"/"/g;
			$filename =~ s/\\"/"/g;
		}
		if (!$count) { $err=2; last; }		# 不正な形式？

		# データの読み出し
		my $value;
		if (defined $filename) {
			# ファイル名を加工（フルパスのとき、ファイル名のみ取り出す）
			$filename =~ tr|\\|/|;
			if ($filename =~ /\/([^\/]*)$/) { $filename = $1; }
			$filename =~ s/[\r\n\x00\"]//g;
			# ファイルデータを読み込み
			if ($use_temp_dir) {
				if ( my ($fh,$file) = $self->open_tmpfile() ) {
					# ファイルがオープンできたら、ファイルに出力
					my $size = $buffer->read_line($fh, $boundary, $file_max_size);
					close($fh);
					my %h;
					$form->{$name} = \%h;
					$h{tmp_file}   = $file;		# tmp file name
					$h{file_name}  = $filename;
					$h{file_size}  = $size;
				} else {
					$buffer->read_line(\$value, $boundary, 0);	# データ読み捨て
				}
			} else {
				# 変数に読み込む
				my $size = $buffer->read_line(\$value, $boundary, $file_max_size);
				my %h;
				$h{data}       = $value;	# tmp file name
				$h{file_name}  = $filename;
				$h{file_size}  = $size;
				$value = \%h;
			}
		} else {
			$buffer->read_line(\$value, $boundary, $data_max_size);
		}
		$self->form_data_check_and_save($form, $options, $name, $value);

		## print "$name=$form->{$name}\n";	## debug
		# データの終わりか確認
		$buffer->read_line(\$line, "\r\n", $header_max_size);
		if ($line eq '--') { $err=0; last; }
	}
	# データ読み終わり
	## print "error code : $err\n";	## debug
	if ($err) {		# エラーのときは全データを無視
		$self->message('Multipart form read error'); return ;
	}

	# save
	$self->{POST} = 1;		# POST であることを記録
	$self->{Form} = $form;

	# POST スクリプトの exec 
	if ($self->{If_post_exec}) { $self->execute( $self->{If_post_exec} ); }
	return 1;
}

#-----------------------------------------------------------
# ○フォームのデータ型チェック
#-----------------------------------------------------------
sub form_data_check_and_save {
	my ($self, $form, $options, $name, $val) = @_;
	if (!exists $options->{name_strict} || $options->{name_strict}) {
		$name =~ s/[^\w\.\-,:]//g;
	}
	if (substr($name,0,1) eq '*') { return; }	# *で始まる要素は受け取らない

	my $is_ary;
	my $type = substr($name,-4);
	if ($type eq '_ary') {	# _int_ary 等
		$is_ary=1;
		$type = substr($name, length($name)-8, 4);
	}

	if ($name eq 'checkbox.info') {
		$val =~ s/[\x00-\x1f]//g;
		if (!exists $form->{$val}) { $form->{$val}=0; }
	} elsif (substr($name,-8) eq '.default') {
		my $key = substr($name,0,length($name)-8);
		if (!exists $form->{$key}) {
			$form->{$key}=$val;
		}
	} elsif ($type ne '_bin' && !ref($val)) {	# バイナリデータではない
		# 文字コード変換（文字コードの完全性保証）
		my $jcode = $self->load_codepm_if_needs( $val );
		$jcode && $jcode->from_to( \$val, $self->{UA_code} || $self->{System_coding}, $self->{System_coding} );
		my $substr = $jcode ? sub { $jcode->jsubstr(@_) } : sub { substr($_[0],$_[1],$_[2]) };

		# TAB LF CR以外の制御コードを除去
		$val =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;

		my $bytes = length($val);
		if ($type eq '_txt') {	# テキストエリア系なら改行を統一
			$val =~ s/\r\n?/\n/g;
			my $txt_max_chars = $options->{txt_max_chars} || 65536;
			if ($txt_max_chars && $bytes >$txt_max_chars) { $val = &$substr($val, 0, $txt_max_chars); }
		} elsif ($type eq '_int') {	# 整数値
			if ($val ne '') { $val=int($val); }
		} elsif ($type eq '_num') {	# 数値
			if ($val ne '') { $val=0+$val; }
		} elsif ($type eq '_flg') {	# フラグ
			$val = $val ? 1 : 0;
		} else {
			my $str_max_chars = $options->{str_max_chars} || 256;
			$val =~ s/[\r\n]//g;	# 改行を除去
			if ($str_max_chars && $bytes >$str_max_chars) { $val = &$substr($val, 0, $str_max_chars); }
		}
	}

	# 配列処理
	if ($is_ary) {
		if (!defined $form->{$name}) { $form->{$name} = []; }
		push(@{ $form->{$name} }, $val);
	} else {
		$form->{$name} = $val;
	}
}

###############################################################################
# ■フォームの値チェッカー
###############################################################################
#  key = title	項目タイトル。タイトルに flag と書いた場合 :type=flag として処理
# :default	keyが存在しない時、値が空文字の時のデフォルト
# :min_chars	最小文字数。入力必須項目ではここに 1 を指定。
# :max_chars	最大文字数
# :min		最小値（数値）
# :max		最大値（数値）
# :type     = flag, int, num, html	データタイプ（その他は省略, html:改行を<br>に）
# :protocol = http, https, ftp, path	許可するプロトコル（path:ディレクトリパス）
# :enum	    = (data1), (data2)...	列挙したもののみ許可。空文字「,,」。
# :enum_txt				:enumでエラーになってときに代わりに表示する文字列
# :filter0-99		文字列除去等の方法を1つ指定。
#	tag		tag_escape()
#	tag_amp		tag_escape_amp() : &もエスケープ
#	file:xxxx	TagEscape.pm を指定ファイルで処理。_optは任意タグ許可フラグ
#	url, uri	trim後にencode_uri()
#	uricom		trim後にencode_uricom()
#	email		メールアドレス。正しくない時はundefされる。
#	emails		メールアドレス(複数可)。カンマ区切り。正しくないものは除去される。
#	reg_del:xxx	正規表現で指定した文字（列）を削除
#	reg_rep:xxx	正規表現置換。_optに置換文字列
#	reg_check:xxx	正規表現に一致すればそのまま。一致しなければ空文字に。
#	reg_ncheck:xxx	正規表現に一致すれば空文字に。一致しなければそのまま。
#	rgb		#7744ff 等のRGB色表現に一致すればそのまま。一致しなければ空文字に
#	trim		文字列の前後にあるスペース（改行含む）を除去
#	normalize	前後のスペースを除去し、複数のスペースやタブを' 'に置換します
#       notnull		空文字を許可しない
# :filter_opt :filter0_opt ...	該当filterに対するオプション。

sub validator {
	my $self = shift;
	my $check = shift || {};
	my $form = shift || $self->{Form};

	my %ret;
	my $jcode;
	my @keys = grep { index($_,':')<0 } keys(%$check);
	my %opts = %$check;		# オプションチェク用
	foreach(@keys) {
		#----------------------------------------------
		# 使用したオプションを削除
		#----------------------------------------------
		delete $opts{$_};
		foreach my $o qw(default min_chars max_chars min max type protocol enum enum_txt) {
			delete $opts{"$_:$o"};
		}
		# フィルタ前処理
		my @filter;
		my @filter_opt;
		foreach my $n (0..99) {
			if (exists $check->{"$_:filter$n"}) {
				push(@filter,     $check->{"$_:filter$n"});
				push(@filter_opt, $check->{"$_:filter${n}_opt"});
				delete $opts{"$_:filter$n"};
				delete $opts{"$_:filter${n}_opt"};
			}
		}
		#----------------------------------------------
		# 値チェック処理メイン
		#----------------------------------------------
		my $title = $check->{$_} || $_;
		my $type = $check->{"$_:type"} || $title;
		my $v = $form->{$_};
		my $err;

		# フラグ値（値が存在しなくても値を保存する）
		if ($type eq 'flag') {
			$v = $v ? 1 : 0;
		}
		# 値が存在しない
		if (!exists $form->{$_} && !exists $check->{"$_:default"}) {
			if ($type ne 'flag') { next; }
		}
		# デフォルト値のロード
		if ($v eq '') {
			$ret{$_} = $check->{"$_:default"};
			next;
		}

		if ($type ne '') {
			# $type eq 'flag' は先に処理
			if ($type eq 'int') {
				$v = int($v);
			} elsif ($type eq 'num') {
				$v = $v+0;
			} elsif ($type eq 'html') {
				$v =~ s/[\r\n]/<br>/g;
			} elsif (exists $check->{"$_:type"}) {
				$self->error_from('validator()', "Unknown %s '%s'.", 'type',$type);
				$err=-1;
			}
		}

		if (exists $check->{"$_:min_chars"} || exists $check->{"$_:max_chars"}) {
			my $jcode = $self->load_codepm_if_needs( $v );
			my $len = $jcode ? $jcode->jlength($v) : length($v);
			if ($len < $check->{"$_:min_chars"}) {
				if ($check->{"$_:min_chars"}>1) {
					$self->form_error($_, "'%s' is too short. (minimum %d chars)", $title, $check->{"$_:min_chars"});
					$err=1;
				} else {
					$self->form_error($_, "'%s' is empty", $title);
					$err=1;
				}
			}
			if ($len > $check->{"$_:max_chars"}) {
				$self->form_error($_, "'%s' is too long. (maximum %d chars)", $title, $check->{"$_:max_chars"});
				$err=1;
			}
		}

		if (exists $check->{"$_:min"} && $v<$check->{"$_:min"}) {
			$self->form_error($_, "'%s' is too small. (minimum %s)", $title, $check->{"$_:min"});
			$err=1;
		}
		if (exists $check->{"$_:max"} && $v>$check->{"$_:max"}) {
			$self->form_error($_, "'%s' is too large. (maximum %s)", $title, $check->{"$_:max"});
			$err=1;
		}

		if (exists $check->{"$_:protocol"} ne '' && $v ne '') {
			my $protocol = $check->{"$_:protocol"};
			my %h = map {$_ => 1} split(/\s*,\s*/, $protocol);
			$protocol =~ s[\s*,\s*][: ]g;
			$protocol =~ s[\s*$][:];
			$protocol =~ s[path:][(path)];
			if ($v =~ m|^([\w\-]+):(.*)|) {
				if (! $h{$1}) {
					$self->form_error($_, "In '%s', '%s' is not permitted. Permit protocols are '%s'.", $title, "$1:", $protocol);
					$err=1;
				}
			} else {
				if (! $h{path}) {
					$self->form_error($_, "'%s' need protocol. Permit protocols are '%s'.", $title, $protocol);
					$err=1;
				}
			}
		}

		if (exists $check->{"$_:enum"}) {
			my %h = map {$_ => 1} split(/\s*,\s*/, $check->{"$_:enum"});
			if (!exists $h{$v}) {
				$self->form_error($_, "'%s' is selected from '%s'.", $title, $check->{"$_:enum_txt"} || $check->{"$_:enum"});
			}
		}

		# 文字列のフィルタ処理
		foreach my $f (@filter) {
			my $f_opt = shift(@filter_opt);
			if ($f eq 'tag') {
				$self->tag_escape( $v );
			} elsif ($f eq 'tag_amp') {
				$self->tag_escape_amp( $v );
			} elsif ($f eq 'tag_del') {
				$self->tag_delete( $v );
			} elsif ($f eq 'url' || $_ eq 'uri') {
				$self->trim($v);
				$self->encode_uri( $v );
			} elsif ($f eq 'uricom') {
				$self->trim($v);
				$self->encode_uricom( $v );
			} elsif ($f eq 'email') {
				$v = $self->check_email( $v );
			} elsif ($f eq 'emails') {
				my @m = $self->check_email( split(',',$v) );
				$v = join(', ', @m);
			} elsif ($f eq 'trim') {
				$self->trim($v);
			} elsif ($f eq 'normalize') {
				$self->string_normalize($v);
			} elsif ($f eq 'rgb') {
				$self->trim($v);
				if ($v !~ /^#[0-9A-Fa-f]{6}$/) { $v=''; }
			} elsif ($f eq 'notnull') {
				if ($v eq '') {
					$self->form_error($_, "'%s' is null or illegal value.", $title);
				}
			} elsif ($f =~ /^file:(.*)$/) {
				my $x = $1;
				my $tag_esc = $self->loadpm('TextParser::TagEscape', $1);
				$tag_esc->{allow_anytag} = $f_opt;
				$x =~ s/([\x00-\x1f])/'#' . ord($_) . '#'/eg;
				$v = $tag_esc->escape( $v );
			} elsif ($f =~ /^reg_(del|rep):(.*)$/) {
				my $reg = $2;
				my $rep = $1 eq 'rep' ? $f_opt : '';
				eval { $v =~ s/$reg/$rep/g; };
				if ($@) {
					$self->error_from('validator()', "Regular expression error '%s'.", $reg);
					$err=-1;
				}
			} elsif ($f =~ /^reg_(n?)check:(.*)$/) {
				my $neg = $1;
				my $reg = $2;
				my $flag;
				eval { $flag = ($v =~ m/$reg/); };
				if ($@) {
					$self->error_from('validator()', "Regular expression error '%s'.", $reg);
					$err=-1;
				}
				$flag = $neg ? !$flag : $flag;
				if (!$flag) { $v=''; }
			} else {
				$self->error_from('validator()', "Unknown %s '%s'.", 'filter', $f);
				$err=-1;
			}
		}

		# 値保存
		if (!$err) {
			$ret{$_} = $v;
		}
	}

	# 未使用オプションのエラー表示
	foreach(sort keys(%opts)) {
		$self->error_from('validator()', "Unknown or unused option '%s'.", $_);
		if ($self->{Develop}) {
			$self->form_error('validator()', "validator() options error");
		}
	}
	return \%ret;
}

###############################################################################
# ■セキュリティ関連
###############################################################################
#------------------------------------------------------------------------------
# ●CSRF対策ルーチン
#------------------------------------------------------------------------------
sub csrf_check {
	my $self = shift;
	my $post_key = shift || $self->{Form}->{csrf_check_key};
	if ($self->{CSRF_no_check}) { return 0; }
	my $check_key = $self->{CSRF_check_key};
	if ($post_key ne '' && $post_key eq $check_key) { return 0; }

	$self->form_clear();
	$self->message("This post may be CSRF attack");
	return 1;
}

sub if_post_csrf_check {
	my $self = shift;
	if ($self->{POST}) { return $self->csrf_check(@_); }
	return $self->form_clear();
}

#------------------------------------------------------------------------------
# ●フォームの中身をすべて消去し、POST=0にする。
#------------------------------------------------------------------------------
sub form_clear {
	my $self=shift;
	my $form = $self->{Form} || {};
	$self->{POST} = 0;				# POST flag をクリア
	foreach(keys(%$form)) { delete $form->{$_}; }	# フォームデータを全て削除
}

#------------------------------------------------------------------------------
# ●ランダムなsaltでcryptする
#------------------------------------------------------------------------------
sub crypt_by_rand {
	my ($self, $secret) = @_;
	return $self->crypt_by_string_with_salt($secret, $self->get_rand_string());
}
sub crypt_by_rand_nosalt {
	my ($self, $secret) = @_;
	return $self->crypt_by_string($secret, $self->get_rand_string());
}

sub get_rand_string {
	my $self = shift;
	my $str = $ENV{REMOTE_ADDR} . ($ENV{REMOTE_PORT} + rand(0x3fffffff) + 0x4000000);
	my $len = int(shift) || 20;
	my $salt='';
	foreach(0..$len) {
		$salt .= chr((((ord(substr($str, $_, 1)) * int(rand(0x10000)))>>8) & 0xff)+1);
	}
	return $salt;
}

sub get_rand_string_salt {
	my $self = shift;
	my $len  = shift;
	my $base = $ENV{UNIQUE_ID} . $ENV{REMOTE_ADDR} . $ENV{REMOTE_PORT};
	my $salt = $self->{SALT64chars};
	my $str  = '';
	foreach(1..$len) {
		$str .= substr($salt, int(rand(256+ord(substr($base,$_,1))*256) % 64), 1);
	}
	return $str;
}

###############################################################################
# ■Cookie処理
###############################################################################
#==============================================================================
# ●cookie を消去
#==============================================================================
sub clear_cookie {
	my $self = shift;
	my ($name, $path, $domain) = @_;
	$self->put_cookie("$name=; expires=Thu, 1-Jan-1970 00:00:00 GMT;", $path, $domain);
}


#==============================================================================
# ●cookie に文字列、配列、ハッシュを１つのcookieに保存
#==============================================================================
sub set_cookie {
	my $self = shift;
	my ($name, $val, $expires, $path, $domain) = @_;
	if ($expires > 0) {
		$expires = ' expires='. $self->rfc_date($self->{TM} + $expires) . ';';
	} elsif ($expires) {	# 負数（無期限）
		$expires = ' expires=Tue, 19-Jan-2038 00:00:00 GMT;';7
	} else {		# 0 or 未定義（今セッションのみ）
		$expires = '';
	}

	if (ref $val eq 'ARRAY') {
		# 配列の保存
		my $ary = $val;
		$val = "\0\1";	# 0x00 0x01
		foreach (@$ary) { $val .= "\0" . $_; }
	} elsif (ref $val eq 'HASH') {
		# HASHの保存
		my $h = $val;
		$val = "\0\2";	# 0x00 0x02
		while(my ($k, $v) = each(%$h) ) {
			$val .= "\0" . $k . "\0" . $v;
		}
	}

	$val =~ s/([^\w\-\/\.\@\~\*])/ '%' . unpack('H2', $1)/eg;
	$self->put_cookie("$name=$val;$expires", $path, $domain);
}

#==============================================================================
# ●cookie を設定
#==============================================================================
sub put_cookie {
	my ($self, $str, $path, $domain) = @_;
	if ($path   eq '') { $path   = $self->{Cookie_path} || $self->{Basepath}; }
	if ($domain eq '') { $domain = $self->{Cookie_domain}; }
	if ($path   ne '') { $path   = ' path='   . $path . ';';    }
	if ($domain ne '') { $domain = ' domain=' . $domain . ';';  }

	$self->set_header('Set-Cookie', "$str$path$domain");
}

###############################################################################
# ■HTTP, TCP/IP関連処理
###############################################################################
#------------------------------------------------------------------------------
# ●リダイレクト (RFC2616準拠)
#------------------------------------------------------------------------------
sub redirect {
	my ($self, $uri) = @_;
	$uri =~ s/[\x00-\x1f]//g;	# 不正文字除去
	my $status;
	if ($ENV{SERVER_PROTOCOL} ne 'HTTP/1.0') {
		$status = "303 See Other";	# HTTP/1.1, GETメソッドに変更
	} elsif ($ENV{REQUEST_METHOD} eq 'POST') {
		$status = "200 OK"; 		# redirect不可
	} else {
		$status = "302 Found"; 		# HTTP/1.0, メソッド変更なし
	}
	if ($self->{Is_phone}) { $status="302 Found"; }
	# 相対パスの場合絶対URIに書き換え
	if (! $self->{Redirect_use_relative_url} && index($uri, '://') < 0) {
		if (substr($uri,0,1) ne '/') { $uri = $self->{Basepath} . $uri; }
		$uri = $self->{Server_url} . $uri;
	}
	if ($self->{No_redirect}) { $status='200 OK'; }
	if ($status ne '200 OK') { $self->set_header('Location', $uri); }
	$self->set_status($status);
	$self->print_http_headers('text/html');

	my $refresh = 0;
	my $append  = '';
	if ($self->{No_redirect}) {
		$refresh = 1000;
		$append = '<p>' . join("<br>\n", @{$self->{Debug}}) . '</p>';
	}
	$self->tag_escape( $uri );
	print <<HTML;
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<HTML><HEAD>
<TITLE>$status</TITLE>
<META HTTP-EQUIV="Refresh" CONTENT="$refresh; url=$uri">
</HEAD><BODY>
<P><A HREF="$uri">Please move here</A>(redirect).<P>
$append</BODY></HTML>
HTML

	$self->superbreak_clear();	# 本来不要だが、念のため
	$self->exit(0);
}

#------------------------------------------------------------------------------
# ●ホスト名の逆引き
#------------------------------------------------------------------------------
sub resolve_host {
	my $self  = shift;
	my $force = shift;
	if (!$force && $ENV{REMOTE_HOST} ne '') { return ; }

	# 逆引き
	my $ip = $ENV{REMOTE_ADDR};
	if ($ip eq '') { return ; }
	my $ip_bin = pack('C4', split(/\./, $ip));
	my $host   = gethostbyaddr($ip_bin, 2);
	if ($host eq '') { return ; }

	# 2重引き
	my @addr = gethostbyname($host);
	splice(@addr, 0, 4);	# [0]-[3] を捨てて address リストのみ残す
	my $flag = 1;
	foreach(@addr) {
		if ($_ eq $ip_bin) { $flag=0; last; }
	}
	if ($flag) { return ; }
	# 2重引き成功
	$ENV{REMOTE_HOST} = $host;
}

###############################################################################
# ■その他
###############################################################################
#------------------------------------------------------------------------------
# ●ディレクトリ・ファイル名中の「../」「./」を取り除き、先頭「/」を除去
#------------------------------------------------------------------------------
sub clean_path {
	my $self = shift;
	foreach(@_) {
		$_ =~ s|/+|/|g;		# //→/
		while ($_ =~ s[(^|/)\.?\./][$1]g) {};
		$_ =~ s[^/|^~][];	# /,~始まりを禁止
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●ハッシュの中へハッシュの値をコピー
#------------------------------------------------------------------------------
sub into {
	my ($self,$out,$in) = @_;
	if (! ref($in )) { return {}; }
	if (! ref($out)) { $out = {}; }
	foreach(keys(%$in)) {
		$out->{$_} = $in->{$_};
	}
	return $out;
}

sub tag_unescape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&#39;|&apos;/'/g;
		$_ =~ s/&quot;/"/g;
		$_ =~ s/&lt;/</g;
		$_ =~ s/&gt;/>/g;
		$_ =~ s/&amp;/&/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●ハッシュのダンプ
#------------------------------------------------------------------------------
sub dump_hash {
	my $self = shift;
	my ($format, $h) = @_;
	if (ref $format eq 'HASH') { $h=$format; $format="%k = %v<br>\n"; }

	my @ary;
	my $keys = $h->{_order};
	if (ref $keys ne 'ARRAY') {
		my @keys = sort {$a cmp $b} keys(%$h);
		$keys = \@keys;
	}
	foreach(@$keys) {
		my $x = $format;
		$x =~ s/%[Kk]/$_/g;
		$x =~ s/%[Vv]/$h->{$_}/g;
		push(@ary, $x);
	}
	return \@ary;
}

1;
