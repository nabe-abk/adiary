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
	my ($self, $cache_file, $src_file, $src_filefull, $src_tm) = @_;
	#------------------------------------------------------------
	# コンパイルログを残すか？
	#------------------------------------------------------------
	my $logfile = $self->{Compile_log_dir};
	if ($logfile ne '' && (-d $logfile || $self->mkdir($logfile)) ) {
		my $file = $src_file;
		$file =~ s|/|_-_|g;
		$file =~ s/[^\w\-\.]/_/g;
		$logfile .= $file;	# log を残す
	} else {
		undef $logfile;
	}
	#------------------------------------------------------------
	# コンパイル処理
	#------------------------------------------------------------
	if ($cache_file) { unlink($cache_file); }	# キャッシュ削除
	my $c     = $self->loadpm('Base::Compiler');
	my $lines = $self->fread_lines($src_filefull);
	my ($errors, $warns, $arybuf) = $c->compile($lines, $src_file, $logfile);
	if ($errors) {
		$self->set_status(500);
	}

	#------------------------------------------------------------
	# キャッシュの保存
	#------------------------------------------------------------
	if ($cache_file && $errors == 0 && (!$warns || !$self->{Develop})) {
		$self->save_cache($cache_file, $src_filefull, $src_tm, $arybuf);
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
# [WARNING] Don't edit this file. If you edit this, will be occoued error.
#------------------------------------------------------------------------------
\0
TEXT
	# バージョン／コンパイラ・スケルトンの更新時刻
	push(@lines, "Version=1.01\n\0");
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
# ■スケルトンのcall
###############################################################################
#------------------------------------------------------------------------------
# ●ディレクトリ内のスケルトンを呼び出し
#------------------------------------------------------------------------------
sub call_dir {
	my $self  = shift;
	my $dir   = shift;
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
	my $out = '';
	foreach(@files) {
		my $file = $dir . substr($_, 0, length($_) - $ext_len);
		$out .= $self->call( $file, @_ );
	}
	return $out;
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
#------------------------------------------------------------------------------
# ●すべての行をファイルに書き込む
#------------------------------------------------------------------------------
# Ret:	0	成功
# 	1	失敗
sub fwrite_lines {
	my ($self, $file, $lines, $flags) = @_;
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	my $fail_flag=0;
	my $fh;
	my $append = $flags->{append} ? O_APPEND : 0;
	if ( !sysopen($fh, $file, O_CREAT | O_WRONLY | $append) ) {
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
	$self->delete_file_cache($file);
	close($fh);

	# モード変更
	if (defined $flags->{FileMode}) { chmod($flags->{FileMode}, $file); }
	return 0;
}

#------------------------------------------------------------------------------
# ●ファイル：配列をファイルに追記する
#------------------------------------------------------------------------------
sub fappend_lines {
	my ($self, $file, $lines, $flags) = @_;
	$flags->{append} = 1;
	return $self->fwrite_lines($file, $lines, $flags);
}

#------------------------------------------------------------------------------
# ●ファイル：標準ハッシュ形式に書き込む
#------------------------------------------------------------------------------
sub fwrite_hash {
	my ($self, $file, $h, $flags) = @_;

	my @ary;
	my $append = $flags->{append};
	foreach(keys(%$h)) {
		my $val = $h->{$_};
		if (ref $val || (!$append && $val eq '')) { next; }
		if ($_ =~ /[\r\n=]/ || substr($_,0,1) eq '*') { next; } # 改行や「=」を含むか*で始まるkeyは無視
		if (0 <= index($val, "\n")) {	# 値に改行を含む
			$val =~ s/(^|\n)__END_BLK_DATA\n/$1__END_BLK_DATA \n/g;
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
	$flags->{append} = 1;
	return $self->fwrite_hash($file, $h, $flags);
}

#------------------------------------------------------------------------------
# ●ファイル：ファイルを編集
#------------------------------------------------------------------------------
# 編集用。ロック処理付き。ファイルがなければ作る。
sub fedit_readlines {
	my ($self, $file, $flags) = @_;

	my $fh;
	if ( !sysopen($fh, $file, O_CREAT | O_RDWR | ($flags->{append} ? O_APPEND : 0)) ) {
		if ($flags->{NoError}) {
			$self->warning("File can't open (for %s) '%s'", 'edit', $file);
		} else {
			$self->error("File can't open (for %s) '%s'", 'edit', $file);
		}
	}
	binmode($fh);
	if ($flags->{NB}) {
		my $r = $self->write_lock_nb($fh);
		if (!$r) { close($fh); return; }
	} else {
		my $method = $flags->{ReadLock} ? 'read_lock' : 'write_lock';
		$self->$method($fh);
	}

	my @lines;
	@lines = <$fh>;
	$self->delete_file_cache($file);

	# モード変更
	if (defined $flags->{FileMode}) {
		chmod($flags->{FileMode}, $file);
	}
	return ($fh, \@lines);
}

sub fedit_writelines {
	my ($self, $fh, $lines, $flags) = @_;
	if (ref $lines ne 'ARRAY') { $lines = [$lines]; }

	seek($fh, 0, 0);	# ファイルポインタを先頭へ
	foreach(@$lines) {
		print $fh $_;
	}
	truncate($fh, tell($fh));
	close($fh);
	return 0;
}

sub fedit_exit {
	my ($self, $fh) = @_;
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
	my ($self, $fh, $h, $flags) = @_;
	my $lines = $self->fwrite_hash('', $h);
	$self->fedit_writelines($fh, $lines, $flags);
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
	if (-e $dir) { return -1; }
	my $r = mkdir( $dir );	# 0:fail 1:Success
	if ($r) {
		if (substr($dir,-1) eq '/') { chop($dir); }
		if (defined $mode) { $r = chmod($mode, $dir); }
	} else { $self->error("Failed mkdir '%s'", $_[1]); }
	return $r;
}

#------------------------------------------------------------------------------
# ●ファイルの削除
#------------------------------------------------------------------------------
sub file_delete {
	my $self = shift;
	return unlink( $_[0] );
}

# rm -rf 
sub dir_delete {	# 再起関数
	my ($self, $dir) = @_;
	if ($dir eq '') { return; }
	if (substr($dir, -1) eq '/') { chop($dir); }
	if (-l $dir) {	# is symbolic link
		return unlink($dir);
	}
	$dir .= '/';
	my $files = $self->search_files( $dir, {dir=>1, all=>1});
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
	my ($self, $src, $des) = @_;
	my $d2  = $des;
	while((my $x = index($src,'/')+1) > 0) {
		if(substr($src, 0, $x) ne substr($d2, 0, $x)) { last; }
		$src = substr($src, $x);
		$d2  = substr($d2,  $x);
	}
	if (ord($src) != 0x2f && substr($src,0,2) ne '~/') {
		$d2 =~ s|/| $src = "../$src";'/' |eg;
	}
	my $r = symlink($src, $des);
	if (!$r) {
		$self->error("Create symlink error '%s' $src $des", $!);
		return 1;
	}
	return 0;
}

#------------------------------------------------------------------------------
# ●ファイルのmove
#------------------------------------------------------------------------------
sub file_move {
	my ($self, $src, $des) = @_;
	if (!-f $src) { return 1; }
	{
		my $r = rename($src, $des);
		if ($r) { return 0; }	# success
	}
	# copy and delete
	my $r = $self->file_copy($src, $des);
	if (!$r) {
		$self->file_delete($src);
	}
	return $r;
}


#------------------------------------------------------------------------------
# ●ファイルのコピー
#------------------------------------------------------------------------------
sub file_copy {
	my ($self, $src, $des) = @_;
	my $data;
	my $fh;

	# READ
	if ( !sysopen($fh, $src, O_RDONLY) ) { $self->error("File can't read '%s'", $src); return 1; }
	$self->read_lock($fh);
	my $size = (stat($fh))[7];
	sysread($fh, $data, $size);
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
	if (substr($src, -1) ne '/') { $src .= '/'; }
	if (substr($des, -1) ne '/') { $des .= '/'; }
	return $self->_dir_copy($src, $des)
}
# 再起関数
sub _dir_copy {
	my ($self, $src, $des) = @_;
	$self->mkdir("$des");
	my $files = $self->search_files( $src, {dir=>1, all=>1} );
	my $error = 0;
	foreach(@$files) {
		my $file = $src . $_;
		if (-d $file) {
			$error += $self->_dir_copy( "$file", "$des$_" );
		} else {
			$error += $self->file_copy($file, "$des$_") && 1;
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
	if (!-w $dir && !$self->mkdir($dir)) {
		$self->error("Can't write temporary dir '%s'", $dir);
		return ;
	}

	# テンポラリファイルのオープン
	my $fh;
	my $file;
	my $tmp_file_base = $dir . $$ . '_' . ($ENV{REMOTE_PORT} +0) . '_';
	my $i;
	for($i=1; $i<100; $i++) {
		$file = $tmp_file_base . int(rand(0x10000000)) . '.tmp';
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
	my $dir  = shift;
	my $sec  = shift || 3600;
	$dir = $dir ? $dir : $self->get_tmpdir();
	$dir =~ s|([^/])/*$|$1/|;
	if ($sec < 10) { $sec = 10; }

	# $check_tm より modtime が古ければ削除
	my $check_tm = $self->{TM} - $sec;

	# 削除ループ
	my $files = $self->search_files( $dir, {all=>1} );
	my $c = 0;
	foreach(@$files) {
		my $file = $dir . $_;
		if ((stat($file))[9] > $check_tm) { next; }
		$c += unlink( $file );
	}
	return $c;
}

#------------------------------------------------------------------------------
# ●ファイルに対するロック
#------------------------------------------------------------------------------
sub file_lock {
	my ($self, $file, $type) = @_;

	my $fh;	# READ
	if ( !sysopen($fh, $file, O_RDONLY) ) {
		$self->error("File can't open (for %s) '%s'", 'lock', $file);
		return undef;
	}
	$type ||= 'write_lock';
	my $r = $self->$type($fh);
	if (!$r) { close($fh); return; }
	return $fh;
}

#------------------------------------------------------------------------------
# ●ファイルシステムlocale
#------------------------------------------------------------------------------
sub set_fslocale {
	my $self = shift;
	$self->{FsLocale} = shift;
	$self->init_fslocale();
}
sub init_fslocale {
	my $self = shift;
	my $fs   = $self->{FsLocale};
	if (!$fs || $fs =~ /utf-?8/i && $self->{System_coding} =~ /utf-?8/i) {
		delete $self->{FsCoder};
		return;
	}
	$self->{FsCoder} ||= $self->load_codepm();
}
sub fs_decode {
	my $self = shift;
	my $file = shift;
	if (!$self->{FsCoder}) { return $file; }
	return $self->{FsCoder}->from_to( $file, $self->{FsLocale}, $self->{System_coding});
}
sub fs_encode {
	my $self = shift;
	my $file = shift;
	if (!$self->{FsCoder}) { return $file; }
	return $self->{FsCoder}->from_to( $file, $self->{System_coding}, $self->{FsLocale});
}

###############################################################################
# ■タグの除去、不正文字除去
###############################################################################
sub esc_xml {	# 非破壊
	my $self = shift;
	return $self->tag_escape_for_xml(join('',@_));
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
sub esc_js_string {	# 非破壊
	my $self = shift;
	my $str  = shift;
	$str =~ s/\\/\\\\/g;
	$str =~ s/\'/&apos;/g;
	return $str;
}

# 改行なし文字列の正規化
sub normalize_string {
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
	my $options = $self->{Form_options} || {};
	### マルチパート form か
	my $content_type = $ENV{CONTENT_TYPE};
	if (index($content_type, 'multipart/form-data') == 0) {
		if (exists $options->{allow_multipart} && !$options->{allow_multipart}) { return; }
		return $self->read_multipart_form( $content_type );
	}
	### データサイズの確認
	my $length = $ENV{CONTENT_LENGTH};
	my $total_max = $options->{total_max_size};	# 1MB
	if ($total_max && $length > $total_max) {
		$self->{POST_ERR} = 1;
		$self->message('Too large form data (max %dKB)', $total_max >> 10); return ;
	}
	### 通常のフォーム処理
	my $content;
	read($self->{STDIN}, $content, $ENV{CONTENT_LENGTH});
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
	my $options = $self->{Form_options} || {};

	### データサイズの確認
	my $length = $ENV{CONTENT_LENGTH};
	{
		my $max = $options->{multipart_total_max_size};
		if ($max && $length > $max) {
			$self->{POST_ERR} = 1;
			$self->message('Too large form data (max %dKB)', $max >> 10);
			return;
		}
	}

	my $file_max_size = $options->{multipart_file_max_size};
	my $use_temp_flag = $options->{multipart_temp_flag};
	my $header_max_size = 1024;

	# boundary の読み出し
	binmode($self->{STDIN});	# for Windows
	$content_type =~ /boundary=(.*)/;
	my $boundary = $1;
	my $form     = {};
	my $buffer   = $self->loadpm('Base::BufferedRead', $self->{STDIN}, $length, $options->{multipart_buffer_size});
	$buffer->{read_max} = $length;

	# 先頭の boundary 読み捨て
	{
		my $line;
		$buffer->read(\$line, "--$boundary\r\n", $header_max_size);
	}
	$boundary = "\r\n--$boundary";
	# 読み出しループ
	my $err = 1;
	while(! $buffer->{data_end}) {
		# ヘッダの読み出し
		my $name;
		my $filename;
		my $count = 32;
		while($count--) {
			my $line;
			$buffer->read(\$line, "\r\n", $header_max_size);
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
			# TAB以外の制御コードと " を除去
			$filename =~ s/[\x00-\x08\x0A-\x1F\x7F\"]//g;
			# ファイルデータを読み込み
			if ($use_temp_flag) {
				if ( my ($fh,$file) = $self->open_tmpfile() ) {
					# ファイルがオープンできたら、ファイルに出力
					my $size = $buffer->read($fh, $boundary, $file_max_size);
					close($fh);
					$value = {
						tmp	=> $file,		# tmp file name
						name	=> $filename,
						size	=> $size
					};
				} else {
					$buffer->read(\$value, $boundary, 0);	# データ読み捨て
				}
			} else {
				my $size = $buffer->read(\$value, $boundary, $file_max_size);
				$value = {
					data	=> $value,
					name	=> $filename,
					size	=> $size
				};
			}
		} else {
			$buffer->read(\$value, $boundary, 0);
		}
		$self->form_data_check_and_save($form, $options, $name, $value);

		# データの終わりか確認
		{
			my $line;
			$buffer->read(\$line, "\r\n", $header_max_size);
			if ($line eq '--') { $err=0; last; }
		}
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

	if ($name =~ /^(.+)(?:_ary|\[\])$/) {		# 配列処理
		my $a = $form->{"$1_ary"}  ||= [];
		push(@$a, $self->form_type_check($1, $val, $options));

	} elsif ($name =~ /^(.+)\[([^\]]+)\]$/) {	# hash（1階層のみ対応）
		my $h = $form->{"$1_hash"} ||= {};
		$h->{$2} = $self->form_type_check($1, $val, $options);

	} else {
		$form->{$name} = $self->form_type_check($name, $val, $options);
	}
}

sub form_type_check {
	my ($self, $name, $val, $options) = @_;

	my $type = substr($name,-4);

	if (!ref($val))	     { return $val; }		# ファイルupload
	if ($type eq '_bin') { return $val; }		# バイナリデータ
	if ($type eq '_int') { return int($val);    }	# 整数
	if ($type eq '_num') { return 0+$val;	    }	# 数値
	if ($type eq '_flg') { return $val ? 1 : 0; }	# フラグ

	# 文字コード変換（文字コードの完全性保証）
	my $jcode = $self->load_codepm_if_needs( $val );
	$jcode && $jcode->from_to( \$val, $self->{System_coding}, $self->{System_coding} );
	my $substr = $jcode ? sub { $jcode->jsubstr(@_) } : sub { substr($_[0],$_[1],$_[2]) };
	my $length = $jcode ? sub { $jcode->jlength(@_) } : sub { length($_[0]) };

	# TAB LF CR以外の制御コードを除去
	$val =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;

	my $bytes = &$length($val);
	if ($type eq '_txt') {	# テキストエリア系なら改行を統一
		$val =~ s/\r\n?/\n/g;
		my $txt_max_chars = $options->{txt_max_chars};
		if ($txt_max_chars && $bytes >$txt_max_chars) {
			$self->message("Too long form data '%s', limit %d chars", $name, $txt_max_chars);
			$val = &$substr($val, 0, $txt_max_chars);
		}
		return $val;
	}

	# その他文字列
	my $str_max_chars = $options->{str_max_chars};
	$val =~ s/[\r\n]//g;	# 改行を除去
	if ($str_max_chars && $bytes >$str_max_chars) {
		$self->message("Too long form data '%s', limit %d chars", $name, $str_max_chars);
		$val = &$substr($val, 0, $str_max_chars);
	}
	return $val;
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
#	reg_check:xxx	正規表現に一致しなければエラー
#	reg_ncheck:xxx	正規表現に一致すればエラー
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
		foreach my $o (qw(default min_chars max_chars min max type protocol enum enum_txt)) {
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
				$err=1;
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
				$self->normalize_string($v);
			} elsif ($f eq 'rgb') {
				$self->trim($v);
				if ($v !~ /^#[0-9A-Fa-f]{6}$/) { $v=''; }
			} elsif ($f eq 'notnull') {
				if ($v eq '') {
					$self->form_error($_, "'%s' is null or illegal value.", $title);
					$err=1;
				}
			} elsif ($f =~ /^file:(.*)$/) {
				my $x = $1;
				my $tag_esc = $self->loadpm('TextParser::TagEscape', $x);
				$tag_esc->anytag($f_opt);
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
				if (!$flag) {
					$self->form_error($_, "Illegal setting '%s'.", $v);
					$err=1;
				}
			} else {
				$self->error_from('validator()', "Unknown %s '%s'.", 'filter', $f);
				$err=-1;
			}
			if ($err) { last; }
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
	if (!$self->{POST} || $self->{CSRF_no_check}) { return; }
	my $check_key = $self->{CSRF_check_key};
	if ($post_key ne '' && $post_key eq $check_key) { return 0; }

	$self->form_clear();
	$self->message("This post may be CSRF attack");
	return 1;
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
	return $self->crypt_by_string($secret, $self->generate_rand_string());
}
sub crypt_by_rand_nosalt {
	my ($self, $secret) = @_;
	return $self->crypt_by_string_nosalt($secret, $self->generate_rand_string());
}

sub generate_rand_string {
	my $self = shift;
	my $len  = shift || 20;
	my $func = shift || sub { return chr($_[0]) };
	my $gen  = $ENV{REMOTE_ADDR};
	my $R    = $ENV{REMOTE_PORT} + rand(0xffffffff);
	my $str  ='';
	foreach(1..$len) {
		my $c = (ord(substr($gen, $_, 1)) + int(rand($R))) & 0xff;
		$str .= &$func($c);
	}
	return $str;
}
sub generate_nonce {
	my $self = shift;
	my $base = $self->{SALT64chars};
	$base =~ tr|+/.|-__|;
	$self->generate_rand_string(shift, sub {
		my $c = shift;
		return substr($base, $c & 63, 1);
	});
}

###############################################################################
# ■Cookie処理
###############################################################################
#==============================================================================
# ●cookie を消去
#==============================================================================
sub clear_cookie {
	my $self = shift;
	my $name = shift;
	$self->put_cookie("$name=; expires=Thu, 1-Jan-1970 00:00:00 GMT;", @_);
}

#==============================================================================
# ●cookie に文字列、配列、ハッシュを１つのcookieに保存
#==============================================================================
sub set_cookie {
	my $self = shift;
	my $name = shift;
	my $val  = shift;
	my $exp  = shift;
	if ($exp > 0) {
		$exp = ' expires='. $self->rfc_date($self->{TM} + $exp) . ';';
	} elsif ($exp) {	# 負数（無期限）
		$exp = ' expires=Tue, 19-Jan-2038 00:00:00 GMT;';
	} else {		# 0 or 未定義（今セッションのみ）
		$exp = '';
	}

	if (ref($val) eq 'ARRAY') {
		$val = "\0\1\0" . join("\0", @$val);	# 0x00 0x01
	} elsif (ref($val) eq 'HASH') {
		$val = "\0\2\0" . join("\0", %$val);	# 0x00 0x02
	}

	$val =~ s/([^\w\-\/\.\@\~\*])/ '%' . unpack('H2', $1)/eg;
	$self->put_cookie("$name=$val;$exp", @_);
}

#==============================================================================
# ●cookie を設定
#==============================================================================
sub put_cookie {
	my ($self, $str, $path, $dom) = @_;
	$path ||= $self->{CookiePath} || $self->{Basepath};
	$dom  ||= $self->{CookieDomain};
	if ($path) { $path = " path=$path;";      }
	if ($dom ) { $dom  = " domain=$dom;";  }
	my $opt = $self->{CookieOpt}      || 'HttpOnly;';
	my $ss  = $self->{CookieSameSite} || 'Lax';

	$self->set_header('Set-Cookie', "$str$path$dom${opt}SameSite=$ss");
}

###############################################################################
# ■HTTP, TCP/IP関連処理
###############################################################################
#------------------------------------------------------------------------------
# ●リダイレクト (RFC2616準拠)
#------------------------------------------------------------------------------
sub redirect {
	my ($self, $uri, $status_msg) = @_;
	$status_msg ||= "302 Moved Temporarily";	# GETへメソッド変更なし

	$uri =~ s/[\x00-\x1f]//g;		# 不正文字除去
	if ($self->{No_redirect}) { $status_msg='200 OK'; }

	my $status = ($status_msg =~ /^(\d+)/) ? $1 : 302 ;
	if ($status !~ /^200/) { $self->set_header('Location', $uri); }
	$self->set_status($status);

	my $refresh = 0;
	my $append  = '';
	if ($self->{No_redirect}) {
		$refresh = 1000;
		$append = '<p>' . join("<br>\n", @{$self->{Debug}}) . '</p>';
	}
	$self->tag_escape( $uri );
	$self->output(<<HTML);
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
	my $self = shift;
	my $ip   = $ENV{REMOTE_ADDR};
	my $host = $ENV{REMOTE_HOST};

	if ($self->{Resolve_host}) { return $host; }
	$self->{Resolve_host} = 1;
	$ENV{REMOTE_HOST} = '';

	# 逆引き
	my $ip_bin = pack('C4', split(/\./, $ip));
	if ($host eq '') {
		if ($ip eq '') { return ; }
		$host = gethostbyaddr($ip_bin, 2);
		if ($host eq '') { return ; }
	}

	# 2重引き
	my @addr = gethostbyname($host);
	splice(@addr, 0, 4);	# [0]-[3] を捨てて address リストのみ残す
	my $ok;
	foreach(@addr) {
		if ($_ eq $ip_bin) { $ok=1; last; }
	}
	if (!$ok) { return ; }
	return ($ENV{REMOTE_HOST} = $host);
}

#------------------------------------------------------------------------------
# ●IP/HOST名チェック
#------------------------------------------------------------------------------
# 1: OK, 0: NG
sub check_ip_host {
	my $self = shift;
	my $ip_ary   = shift || [];
	my $host_ary = shift || [];
	if (!@$ip_ary && !@$host_ary) { return 1; }	# ok

	my $ip = $ENV{REMOTE_ADDR} . '.';
	foreach(@$ip_ary) {		# 前方一致
		if ($_ eq '') { next; }
		my $x = $_ . (substr($_,-1) eq '.' ? '' : '.');
		if (0 == index($ip, $x)) { return 1; }
	}

	if (!@$host_ary) { return 0; }
	my $host = $self->resolve_host();
	foreach(@$host_ary) {
		if ($_ eq '') { next; }
		if ($_ eq $host) { return 1; }
		my $x = (substr($_,0,1) eq '.' ? '' : '.') . $_;
		if ($x eq substr($host,-length($x))) { return 1; }
	}
	return 0;
}

###############################################################################
# ■メッセージ関連
###############################################################################
#------------------------------------------------------------------------------
# ●メッセージのクラス分割
#------------------------------------------------------------------------------
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
	my $self = shift;
	$self->_debug(join(' ', @_));	# debug-safe
}
sub _debug {
	my $self = shift;
	my ($msg, $level) = @_;
	$self->tag_escape_amp($msg);
	$msg =~ s/\n/<br>/g;
	$msg =~ s/ /&ensp;/g;
	my ($pack, $file, $line) = caller(int($level)+1);
	push(@{$self->{Debug}}, $msg . "<!-- in $file line $line -->");
}
sub warning {
	my $self = shift;
	my $msg  = $self->translate(@_);
	my ($pack, $file, $line) = caller;
	push(@{$self->{Warning}}, '' . $msg . "<!-- in $file line $line -->");
}

###############################################################################
# ■JSON関連
###############################################################################
#------------------------------------------------------------------------------
# ●hash/arrayツリーからjsonを生成する
#------------------------------------------------------------------------------
sub generate_json {
	my $self = shift;
	my $data = shift;
	my $opt  = shift || {};
	my $tab  = shift || '';

	my $cols = $opt->{cols};	# データカラム
	my $ren  = $opt->{rename};	# カラムのリネーム情報
	my $t = $opt->{strip} ? '' : "\t";
	my $n = $opt->{strip} ? '' : "\n";
	my $s = $opt->{strip} ? '' : ' ';
	my @ary;

	my $is_ary = ref($data) eq 'ARRAY';
	my $dat = $is_ary ? $data : [$data];
	foreach(@$dat) {
		if (!ref($_)) {
			push(@ary, $self->json_encode($_));
			next;
		}
		if (ref($_) eq 'ARRAY') {
			push(@ary, $self->generate_json($_, $opt, "\t$tab"));
			next;
		}
		my @a;
		my @b;
		my $_cols = $cols ? $cols : [ keys(%$_) ];
		foreach my $x (@$_cols) {
			my $k = exists($ren->{$x}) ? $ren->{$x} : $x;
			my $v = $_->{$x};
			if (!ref($v)) {
				push(@a, "\"$k\":$s" . $self->json_encode( $v ));
				next;
			}
			# 入れ子
			my $ch = $self->generate_json( $v, $opt, "$t$tab" );
			push(@b, "\"$k\": $ch");
		}
		push(@ary, $is_ary
			? "$tab${t}{" . join(",$s"      , @a, @b) . "}"
			: "{$n$tab$t" . join(",$n$tab$t", @a, @b) . "$n$tab}"
		);
	}
	return $is_ary ? "[$n" . join(",$n", @ary) . "$n$tab]" : $ary[0];
}

sub json_encode {
	my $self = shift;
	my $v = shift;
	if ($v ne '-0' && $v =~ /^-?(?:[1-9]\d*|0)(?:\.\d+)?$/) { return $v; }
	if (ref($v) eq 'SCALAR') { return $$v; }	# true/false/null
	# 文字列
	$v =~ s/\\/&#92;/g;
	$v =~ s/\n/\\n/g;
	$v =~ s/\t/\\t/g;
	$v =~ s/\r/\\r/g;
	$v =~ s/\x08/\\b/g;	# Backspace
	$v =~ s/\x09/\\f/g;	# HT
	$v =~ s/"/\\"/g;
	return '"' . $v . '"';
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

sub unesc {	# 非破壊
	my $self = shift;
	return $self->tag_unescape(join('',@_));
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
	return join('',@ary);
}

1;
