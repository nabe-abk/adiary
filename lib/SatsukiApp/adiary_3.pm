use strict;
#-------------------------------------------------------------------------------
# adiary_3.pm (C)2014 nabe@abk
#-------------------------------------------------------------------------------
# ・画像管理
# ・ブログの設定
# ・記事、コメントなどの削除関連
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
package SatsukiApp::adiary;
###############################################################################
# ■画像管理
###############################################################################
#------------------------------------------------------------------------------
# ●画像dir関連の初期化
#------------------------------------------------------------------------------
sub init_image_dir {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir = $self->blogimg_dir();
	$ROBJ->mkdir($dir);
	$ROBJ->mkdir($dir . '.trashbox/');	# ごみ箱フォルダ

	# ブォルダリストの生成
	$self->genarete_imgae_dirtree();
}

#------------------------------------------------------------------------------
# ●画像ディレクトリツリーの生成
#------------------------------------------------------------------------------
sub genarete_imgae_dirtree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir   = $self->blogimg_dir();
	my $tree  = $self->get_dir_tree($dir);
	my $trash = $self->get_dir_tree($dir . '.trashbox/', '.trashbox/');	# ゴミ箱

	$tree->{name} = '/';
	$tree->{key}  = '/';
	$trash->{name} = '.trashbox/';
	$trash->{key}  = '.trashbox/';
	my $json = $self->generate_json([$tree, $trash], ['name', 'key', 'date', 'count']);
	$ROBJ->fwrite_lines( $self->{blogpub_dir} . 'images.json', $json);

	return $tree->{count};
}

#------------------------------------------------------------------------------
# ●ディレクトリ階層の全データ取得
#------------------------------------------------------------------------------
sub get_dir_tree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir  = $ROBJ->get_filepath(shift);
	my $path = shift;

	my @dirs;
	my @files;
	my $cnt=0;	# ファイル数カウント
	my $list = $ROBJ->search_files($dir, {dir=>1});
	@$list = sort {		# '@'(0x40)を最後に表示する仕組み
		my $x = (ord($a)==0x40) cmp (ord($b)==0x40);
		$x ? $x : $a cmp $b;
	} @$list;

	foreach(@$list) {
		if (substr($_,-1) ne '/') {
			# ただのファイル
			push(@files, $_);
			next;
		}
		# ディレクトリ
		my $tree = $self->get_dir_tree("$dir$_", "$path$_");
		$tree->{name} = $_;
		push(@dirs, $tree);
		$cnt += $tree->{count};
	}

	my $h = { key => $path, date => (stat($dir))[9], count => ($cnt + $#files+1) };
	if (@dirs) {
		$h->{children} = \@dirs;
	}
	return $h;
}

#------------------------------------------------------------------------------
# ●ディレクトリ内のファイル一覧取得
#------------------------------------------------------------------------------
sub load_image_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};

	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	my @ary;
	foreach(@$files) {
		my @st = stat("$dir$_");
		push(@ary,{
			name => $_,
			size => $st[7],
			date => $st[9],
			isImg=> $self->is_image($_)
		});
	}
	# サムネイル生成
	if (@ary) {
		$self->make_thumbnail($dir, $files);
	}

	my $json = $self->generate_json(\@ary, ['name', 'size', 'date', 'isImg']);
	return (0, $json);
}

#------------------------------------------------------------------------------
# ●ディレクトリ内のEXIFあり画像一覧
#------------------------------------------------------------------------------
sub load_exif_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};
	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	my $jpeg = $ROBJ->loadpm('Jpeg');
	my @ary;
	foreach(@$files) {
		if ($_ !~ /\.jpe?g$/i) { next; }
		if (! $jpeg->check_exif("$dir$_")) { next; }
		push(@ary, $_);
	}

	my $json = $self->generate_json(\@ary);
	return (0, $json);
}

#------------------------------------------------------------------------------
# ●サムネイル生成
#------------------------------------------------------------------------------
sub make_thumbnail {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir  = $ROBJ->get_filepath( shift );
	my $files= shift || [];
	my $opt  = shift || {};

	$ROBJ->mkdir("${dir}.thumbnail/");
	foreach(@$files) {
		my $thumb = "${dir}.thumbnail/$_.jpg";
		# すでに存在したら生成しない
		if (!$opt->{force} && -r $thumb) { next; }

		if ($self->is_image($_)) {
			if ($opt->{del_exif} && $_ =~ /\.jpe?g$/i) {
				my $jpeg = $ROBJ->loadpm('Jpeg');
				$jpeg->strip("$dir$_");
			}
			my $r = $self->make_thumbnail_for_image($dir, $_, $opt->{size});
			if (!$r) { next; }
		}
		my $r = $self->make_thumbnail_for_notimage($dir, $_);
		if (!$r) { next; }

		# サムネイル生成に失敗したとき
		my $icon = $self->{album_icons} . $self->{album_allow_ext}->{'..'};
		if ($_ =~ m/\.(\w+)$/) {
			my $ext = $1;
			$ext =~ tr/A-Z/a-z/;
			my $exts = $self->load_album_allow_ext();
			my $file = $self->{album_allow_ext}->{$ext};
			if ($file) {
				$icon = $self->{album_icons} . $file;
			}
		}
		$ROBJ->file_copy($icon, $thumb);	# アイコンをコピー
	}
}

#------------------------------------------------
# ○画像ファイル
#------------------------------------------------
sub make_thumbnail_for_image {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $size = int(shift) || 120;
	my $ROBJ = $self->{ROBJ};

	# リサイズ
	if ($size < 64)  { $size= 64; }
	if (800 < $size) { $size=800; }

	# print "0\n";
	my $img = $self->load_image_magick( 'jpeg:size'=>"$size x $size" );
	if (!$img) { return -99; }
	my ($w, $h);
	eval {
		$img->Read( "$dir$file" );
		$img = $img->[0];
		($w, $h) = $img->Get('width', 'height');
	};
	# print "4\n";
	if ($@) { return -1; }	# load 失敗

	if ($w<=$size && $h<=$size) {
		$size = 0;	# resize しない
	} elsif ($w>$h) {
		$h = int($h*($size/$w));
		$w = $size;
	} else {
		$w = int($w*($size/$h));
		$h = $size;
	}
	if ($size) {	# リサイズ
		eval { $img->Thumbnail(width => $w, height => $h); };
		if ($@) {
			# ImageMagick-5.x.x以前
			eval { $img->Resize(width => $w, height => $h, blur => 0.7); };
			if ($@) { return -2; }	# サムネイル作成失敗
			eval { $img->Strip(); }	# exif削除
 		}
	}
	# ファイルに書き出し
	$img->Set( quality => ($self->{jpeg_quality} || 80) );
	$img->Write("${dir}.thumbnail/$file.jpg");
	return 0;
}

#------------------------------------------------
# ○その他のファイル
#------------------------------------------------
sub make_thumbnail_for_notimage {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	# サイズ処理
	my $size  = 120;
	my $fsize = $self->{album_font_size};
	if($size <120){ $size = 120; }
	if($fsize<  6){ $fsize=   6; }
	my $fpixel = int($fsize*0.9 + 0.9999);
	my $f_height = $fpixel*3 +2;

	# キャンパス生成
	my $img = $self->load_image_magick();
	if (!$img) { return -99; }
	$img->Set(size => $size . 'x' . $size);
	$img->ReadImage('xc:white');

	# 拡張子アイコンの読み込み
	my $exts = $self->load_album_allow_ext();
	my $icon_dir  = $ROBJ->get_filepath( $self->{album_icons} );
	my $icon_file = $exts->{'.'};
	if ($file =~ m/\.(\w+)$/) {
		my $ext = $1;
		$ext =~ tr/A-Z/a-z/;
		if ($exts->{$1}) {
			$icon_file = $exts->{$1};
		}
	}
	if (!-r "$icon_dir$icon_file") {	# 読み込めない時はdefaultアイコン
		$icon_file = $exts->{'.'};
	}
	my $icon = $self->load_image_magick();
	eval {
		$icon->Read( $icon_dir . $icon_file );
	};

	if (!$@) {
		my ($x, $y) = $icon->Get('width', 'height');
		$x = ($size - $x) / 2;
		$y = ($size - $f_height - $y -4) / 2;
		if($x<0){ $x=0; }
		if($y<0){ $y=0; }
		$img->Composite(image=>$icon, compose=>'Over', x=>$x, y=>$y);
	}

	# 画像情報の書き込み
	my $album_file = $ROBJ->get_filepath( $self->{album_font} );
	if ($self->{album_font} && -r $album_file) {
		my @st = stat("$dir$file");
		my $tm = $ROBJ->tm_printf("%Y/%m/%d %H:%M", $st[9]);
		my $fs = $self->size_format($st[7]);
		my $name = $file;
		my $code = $ROBJ->{System_coding};
		if ($code ne 'UTF-8') {
			my $jcode = $ROBJ->load_codepm();
			$name = $jcode->from_to($name, $code, 'UTF-8');
		}
		my $text = "$name\r\n$tm\r\n$fs";
		$img->Annotate(
			text => $text,
			font => $album_file,
			x => 3,
			y => ($size - $f_height),
			pointsize => $fsize
		);
	}

	# ファイルに書き出し
	$img->Set( quality => 98 );
	$img->Write("${dir}.thumbnail/$file.jpg");
	return 0;
}

sub size_format() {
	my $self = shift;
	my $s = shift;
	if ($s > 104857600) {	# 100MB
		$s = int(($s+524288)/1048576);
		$s =~ s/(\d{1,3})(?=(?:\d\d\d)+(?!\d))/$1,/g;
		return $s . ' MB';
	}
	if ($s > 1023487) { return sprintf("%.3g", $s/1048576) . ' MB'; }
	if ($s >     999) { return sprintf("%.3g", $s/1024   ) . ' KB'; }
	return $s . ' Byte';
}

#------------------------------------------------------------------------------
# ●画像のアップロード
#------------------------------------------------------------------------------
sub image_upload_form {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $size = $form->{size};	# サムネイルサイズ
	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付

	# アップロード
	my $count_s = 0;
	my $count_f = 0;
	my @ary;
	push(@ary, @{ $form->{"file_ary"} || []});
	foreach(0..99) {
		push(@ary, @{ $form->{"file${_}_ary"} || [] });
	}
	my @files;
	foreach(@ary) {
		my $fname = $_->{file_name};
		if ($fname eq '') { next; }
		if ($self->do_upload( $dir, $_ )){
			# $ROBJ->message('Upload fail: %s', $fname);
			$count_f++;
			next;
		}
		$count_s++;
		$ROBJ->message('Upload: %s', $fname);
		push(@files, $fname);
	}

	# サムネイル生成
	$self->make_thumbnail( $dir, \@files, {
		size => $form->{size},
		del_exif => $form->{del_exif}
	});

	# ブォルダリストの再生成
	$self->genarete_imgae_dirtree();

	# メッセージ
	return wantarray ? ($count_s, $count_f) : $count_f;
}

#----------------------------------------------------------------------
# ●アップロードの実処理
#----------------------------------------------------------------------
sub do_upload {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir  = $ROBJ->get_filepath( shift );
	my $file_h = shift;

	# ハッシュデータ（フォームデータの確認）
	my $file_name = $file_h->{file_name};
	my $file_size = $file_h->{file_size};
	my $tmp_file  = $file_h->{tmp_file};		# 読み込んだファイルデータ(tmp file)
	if (!$self->check_file_name($file_name)) {
		$ROBJ->message("File name error : %s", $file_h->{file_name});
		return 2;
	}

	# 拡張子チェック
	if (! $self->album_check_ext($file_name)) { 
		$ROBJ->message("File extension error : %s", $file_name);
		return 3;
	}

	# ファイルの保存
	my $save_file = $dir . $file_name;
	if (-e $save_file && !$file_h->{overwrite}) {	# 同じファイルが存在する
		if ((-s $save_file) != $file_size) {	# ファイルサイズが同じならば、同一と見なす
			$ROBJ->message('Save failed ("%s" already exists)', $file_name);
			return 10;
		}
	} else {
		my $fail;
		if ($tmp_file) {
			if (! rename($tmp_file, $save_file)) { $fail=21; }
		} else {
			if ($ROBJ->fwrite_lines($save_file, $file_h->{data})) { $fail=22; }
		}
		if ($fail) {	# 保存失敗
			$ROBJ->message("File can't write '%s'", $file_name);
			return $fail;
		}
	}
	# サムネイル削除
	$ROBJ->file_delete( "${dir}.thumbnail/$file_name.jpg" );
	return 0;	# 成功
}

#------------------------------------------------------------------------------
# ●サムネイルの再生成
#------------------------------------------------------------------------------
sub remake_thumbnail {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary};
	my $size  = $form->{size};

	# filesの値チェック
	foreach(@$files) {
		if (!$self->check_file_name($_)) { return -1; }
	}

	# サムネイル生成
	$self->make_thumbnail( $dir, $files, {
		size     => $form->{size},
		del_exif => $form->{del_exif},
		force    => 1
	});

	return 0;
}

#------------------------------------------------------------------------------
# ●フォルダの作成
#------------------------------------------------------------------------------
sub create_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $name = $self->chop_slash( $form->{name} );
	if ( !$self->check_file_name($name) ) { return -1; }

	my $r = $ROBJ->mkdir("$dir$name");
	$ROBJ->mkdir("$dir$name/.thumbnail");

	return $r;
}

#------------------------------------------------------------------------------
# ●フォルダ名の変更
#------------------------------------------------------------------------------
sub rename_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $self->chop_slash( $form->{old}  );
	my $name = $self->chop_slash( $form->{name} );
	if ( !$self->check_file_name($old ) ) { return -2; }
	if ( !$self->check_file_name($name) ) { return -1; }

	return rename("$dir$old", "$dir$name") ? 0 : 1;
}

#------------------------------------------------------------------------------
# ●ゴミ箱を空にする
#------------------------------------------------------------------------------
sub clear_trashbox {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir  = $self->blogimg_dir() . '.trashbox/';

	my $ret = $ROBJ->dir_delete($dir) ? 0 : 1;

	$ROBJ->mkdir($dir);
	return $ret;
}

#------------------------------------------------------------------------------
# ●ファイルの移動
#------------------------------------------------------------------------------
sub move_files {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $from = $self->image_folder_to_dir( $form->{from} ); # 値check付
	my $to   = $self->image_folder_to_dir( $form->{to}   ); # 値check付

	my $src_trash = ($form->{from} =~ m|\.trashbox/|);	# 移動元がゴミ箱？
	my $des_trash = ($form->{to}   =~ m|\.trashbox/|);	# 移動先がゴミ箱？
	if ($src_trash && $des_trash) {
		# ゴミ箱内移動なら特になにもしない
		$src_trash = $des_trash = 0;
	}

	my $files = $form->{file_ary} || [];
	my @fail;
	my $tm = $ROBJ->tm_printf("%Y%m%d-%H%M%S");
	foreach(@$files) {
		if ( !$self->check_file_name($_) ) {
			push(@fail, $_);
			next;
		}
		my $src = $_;
		my $des = $_;
		#---------------------------------
		# ゴミ箱にファイルを移動
		#---------------------------------
		if ($des_trash && !-d "$from$_") {
			my $x = rindex($des, '.');
			if ($x > 0) {
				$des = substr($des, 0, $x) . ".#$tm" . substr($des, $x);
			} else {
				$des .= ".#$tm";
			}
		}
		#---------------------------------
		# ゴミ箱からファイルを移動
		#---------------------------------
		if ($src_trash && !-d "$from$_") {
			$des =~ s/\.#[\d\-]+//g;	# ここを修正したら album.js も修正すること
		}
		#---------------------------------
		# 同じファイル名が存在する
		#---------------------------------
		if (-e "$to$des") {
			push(@fail, $_);
			next;
		}
		#---------------------------------
		# リネーム（移動）
		#---------------------------------
		if (!rename("$from$src", "$to$des")) {
			push(@fail, $_);
			next;
		}

		# ファイルを移動した場合、サムネイルも移動
		if (-d "$to$des") { next; }
		# $ROBJ->mkdir("${to}.thumbnail/");
		if (!rename("${from}.thumbnail/$src.jpg", "${to}.thumbnail/$des.jpg")) {
			# 移動失敗時はサムネイル消去
			unlink("${from}.thumbnail/$src.jpg");
		}
	}
	my $f = $#fail+1;
	return wantarray ? ($f, \@fail) : $f;
}

#------------------------------------------------------------------------------
# ●ファイル名の変更
#------------------------------------------------------------------------------
sub rename_file {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $form->{old};
	my $name = $form->{name};
	if ( !$self->check_file_name($old ) || !$self->album_check_ext($old ) ) { return -2; }
	if ( !$self->check_file_name($name) || !$self->album_check_ext($name) ) { return -1; }

	my $r = rename("$dir$old", "$dir$name") ? 0 : 1;
	if (!$r) {
		# 成功時、古いサムネイルの削除
		$ROBJ->file_delete( "${dir}.thumbnail/$old.jpg" );
		# 新しいサムネイル生成
		$self->make_thumbnail( $dir, [$name], {
			size  => $form->{size},
			force => 1
		});
	}

	return $r;
}

#------------------------------------------------------------------------------
# ■アルバム関連サブルーチン
#------------------------------------------------------------------------------
sub load_image_magick {
	eval { require Image::Magick; };
	if ($@) { return ; }
	return Image::Magick->new(@_);
}

#------------------------------------------------------------------------------
# ○画像フォルダ→実ディレクトリ
#------------------------------------------------------------------------------
sub image_folder_to_dir {
	my ($self, $folder) = @_;
	$folder =~ s#(^|/)\.+/#$1#g;
	return $self->{ROBJ}->get_filepath( $self->blogimg_dir() . $folder );
}

#------------------------------------------------------------------------------
# ○画像フォルダ名/ファイル名チェック
#------------------------------------------------------------------------------
sub check_file_name {
	my ($self, $file) = @_;
	if ($file eq '' || $file =~ /^\./) { return 0; }	# ng
	# 制御コードや / 等の使用不可文字
	if ($file =~ m![\x00-\x1f\\/\:*\?\"\'<>|&]!) { return 0; }
	return 1;	# ok
}
# 最後のスラッシュを取り除く
sub chop_slash {
	my ($self, $folder) = @_;
	if (substr($folder,-1) eq '/') { chop($folder); }
	return $folder;
}

#------------------------------------------------------------------------------
# ○画像ファイルか拡張子判定
#------------------------------------------------------------------------------
sub is_image {
	my ($self, $f) = @_;
	$f =~ tr/A-Z/a-z/;
	return ($f =~ m/\.(\w+)$/ && $self->{album_image_ext}->{$1});
}

#------------------------------------------------------------------------------
# ○許可拡張子か判定
#------------------------------------------------------------------------------
sub album_check_ext {
	my ($self, $f) = @_;
	# if ($self->{trust_mode}) { return 1; }	## 危険すぎるので無効に
	$self->load_album_allow_ext();

	while($f =~ /^(.*)\.([^\.]+)$/) {
		$f = $1;
		if (!$self->album_check_ext_one($2)) { return 0; }
	}
	return 1;
}

sub album_check_ext_one {
	my ($self, $ext) = @_;
	$ext =~ tr/A-Z/a-z/;
	if ($self->{album_image_ext}->{$ext} || $self->{album_allow_ext}->{$ext}) { return 1; }
	if (!$self->{album_allow_ver_ext}) { return 0; }

	# adiary-3.00-beta1.3.tbz のようなファイルを許可
	# '#' は内部使用（ゴミ箱）
	return ($ext =~ /[-#]/ || $ext =~ /^\d/);
}

#------------------------------------------------------------------------------
# ○その他拡張子のロード
#------------------------------------------------------------------------------
sub load_album_allow_ext {
	my $self = shift;
	if (!$self->{album_allow_ext}->{'.'}) {
		$self->{ROBJ}->call('album/_load_extensions');
	}
	return $self->{album_allow_ext};
}

###############################################################################
# ■設定関連
###############################################################################
#------------------------------------------------------------------------------
# ●ブログの設定変更（保存）
#------------------------------------------------------------------------------
sub save_blogset {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my ($new_set, $blogid) = @_;

	# 権限確認
	my $blog;
	if ($blogid eq '') {
		if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 10; }
		$blogid = $self->{blogid};
		$blog   = $self->{blog};
	} else {
		# 他のブログ or デフォルト設定
		if (! $auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 11; }
		$blog = $self->load_blogset( $blogid );
		if (! $blog) { $ROBJ->message("Blog '%s' not found", $blogid); return 12; }
	}

	if ($blogid ne '*') {
		# 通常のブログ設定保存
		$self->update_blogset($blogid, $new_set);

		# プライベートモードチェック
		$self->save_private_mode( $blogid );

		# ブログ一覧情報に保存
		$self->update_bloginfo($blogid, {
			private   => $blog->{private},
			blog_name => $blog->{blog_name}
		});
	} else {
		# デフォルトのブログ設定値保存
		# 新規設定値をマージ
		$ROBJ->into($blog, $new_set);	# %$blog <- %$new_set

		# 固定値
		$blog->{arts} = 0;
		$blog->{coms} = 0;

		# ファイルに保存
		$ROBJ->fwrite_hash($self->{my_default_setting_file}, $blog);
	}

	return 0;
}

#------------------------------------------------------------------------------
# ●プライベートモードの現在の状態保存
#------------------------------------------------------------------------------
sub save_private_mode {
	my $self = shift;
	my $blogid = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->load_blogset($blogid);

	my $postfix = $blog->{blogpub_dir_postfix};
	my $evt_name;
	if ($blog->{private} && $postfix eq '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid, $self->{sys}->{dir_postfix_len} || $self->{dir_postfix_len} );
		$evt_name = "PRIVATE_MODE_ON";
	} elsif (!$blog->{private} && $postfix ne '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid, 0 );
		$evt_name = "PRIVATE_MODE_OFF";
	} else {
		return ;	# 特に変更がなければ何もしない
	}
	if (!defined $postfix) {
		$ROBJ->error('Rename failed blog public directory (%s)', $blogid);
		return 1;
	}
	$blog->{blogpub_dir_postfix} = $postfix;
	$self->{blogpub_dir} = $self->blogpub_dir();

	$self->call_event($evt_name);
	$self->rebuild_blog();
}

#------------------------------------------------------------------------------
# ●ブログ公開ディレクトリ名の変更
#------------------------------------------------------------------------------
sub change_blogpub_dir_postfix {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($blogid, $len) = @_;
	$len = int($len) || 6;

	my $postfix = '';
	if ($len > 0) {
		if (32<$len) { $len=32; }
		$postfix = $ROBJ->get_rand_string_salt($len);
		$postfix =~ s/\W/-/g;
		$postfix = '.' . $postfix;
	}

	# ディレクトリ名変更
	my $cur_dir = $ROBJ->get_filepath( $self->blogpub_dir($blogid) );
	chop($cur_dir);
	my $new_dir = $cur_dir;
	$new_dir =~ s|\.[^./]+$||;
	$new_dir .= $postfix;

	# リネーム
	my $r = rename( $cur_dir, $new_dir );
	if (!$r) { return undef; }

	return $postfix;
}

###############################################################################
# ■タグの編集処理
###############################################################################
#------------------------------------------------------------------------------
# ●タグの編集
#------------------------------------------------------------------------------
sub tag_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $joins = $form->{join_ary} || [];
	my $dels  = $form->{del_ary}  || [];
	my $edits = $form->{tag_ary};

	# タグリスト
	my @tags;
	{
		my $ary = $DB->select_match("${blogid}_tag");
		foreach(@$ary) {
			$tags[ $_->{pkey} ] = $_;
		}
	}

	my %e_art;	# 編集したarticleのpkey
	# 中で e_art を参照しているので順番を逆にしてはいけない。
	foreach(@$joins) {
		my ($master, @slaves) = split(',',$_);
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', \@slaves, '*cols', ['a_pkey', 'a_enable'] );
		$DB->delete_match("${blogid}_tagart", 't_pkey', [$master, @slaves]);
		$DB->delete_match("${blogid}_tag", 'pkey', \@slaves);
		foreach(@$ta) {
			if ($e_art{ $_->{a_pkey} }) { next; }
			$DB->insert("${blogid}_tagart", {
				a_pkey => $_->{a_pkey},
				t_pkey => $master,
				a_enable => $_->{a_enable}
			});
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの削除
	if(@$dels) {
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $dels, '*cols', 'a_pkey' );
		$DB->delete_match("${blogid}_tagart", 't_pkey', $dels);
		$DB->delete_match("${blogid}_tag"   ,   'pkey', $dels);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの編集
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$name) = split(',',$_,4);
		$ROBJ->string_normalize($name);
		$ROBJ->tag_escape($name);
		if($upnode) {
			$name = $tags[ $upnode ]->{name} . '::' . $name;
		}
		my $org = $tags[ $pkey ];
		if ($upnode != $org->{upnode} || $name ne $org->{name}) {
			my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $pkey);
			foreach(@$ta) {
				$e_art{ $_->{a_pkey} } = 1;
			}
		} elsif ($priority == $org->{priority}) {
			next;	# 変更なし
		}
		my %h = (
			upnode   => ($upnode==0 ? undef : $upnode),
			priority => $priority,
			name     => $name
		);
		$DB->update_match("${blogid}_tag", \%h, 'pkey', $pkey);
		$h{pkey} = $pkey;
		$tags[ $pkey ] = \%h;
	}

	# 変更があったarticleのタグ情報を書き換える
	foreach my $a_pkey (keys(%e_art)) {
		my $ta = $DB->select_match("${blogid}_tagart", 'a_pkey', $a_pkey, '*cols', 't_pkey');
		my @t_pkeys = map { $_->{t_pkey} } @$ta;

		# upnodeのいずれかのタグを含まないかチェック
		my %h;
		foreach(@t_pkeys) {
			my $up = $tags[$_]->{upnode};
			while($up) {
				$h{$up} = 1;
				$up = $tags[$up]->{upnode};
			}
		}
		my @tag;
		my @dels;
		foreach(@t_pkeys) {
			if ($h{$_}) {
				push(@dels, $_);
				next;
			}
			push(@tag, $tags[ $_ ]->{name});
		}
		# ツリー組み換えにより重複したタグを削除
		$DB->delete_match("${blogid}_tagart", 'a_pkey', $a_pkey, 't_pkey', \@dels);

		# 新しいタグ情報に書き換え
		my $tag = join(',', @tag);
		$DB->update_match("${blogid}_art", {tags => $tag}, 'pkey', $a_pkey);
	}
	$self->update_taglist();

	return 0;
}

###############################################################################
# ■コンテンツの編集処理
###############################################################################
#------------------------------------------------------------------------------
# ●コンテンツの編集
#------------------------------------------------------------------------------
sub contents_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	# タグリスト
	my %cons;
	{
		my $ary = $DB->select_match("${blogid}_art",
			'enable', 1,
			'-ctype', '',
			'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'coms_all']
		);
		%cons = map { $_->{pkey} => $_ } @$ary;
	}

	# タグの編集
	my $edits = $form->{contents_ary};
	my $com_edit;
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$link_key) = split(',',$_,4);
		$ROBJ->string_normalize($link_key);
		if ($link_key =~ /^[\"\',]/ || $link_key =~ /^\s*$/ || $link_key =~ m|^[\d&]|) {
			$link_key = '';
		}
		my $org = $cons{ $pkey };
		my %h;
		if ($upnode != $org->{upnode} && ($cons{$upnode} || $upnode==0)) {
			$h{upnode} = $upnode;
		}
		if ($link_key ne '' && $link_key ne $org->{link_key}) {
			$h{link_key} = $link_key;
		}
		if ($priority != $org->{priority}) {
			$h{priority} = $priority;
		}
		if (!%h) { next; }

		$DB->update_match("${blogid}_art", \%h, 'pkey', $pkey);
		if (exists($h{link_key}) && $cons{$pkey}->{coms_all}) {
			my $elkey = $h{link_key};
			$self->link_key_encode($elkey);
			my $r = $DB->update_match("${blogid}_com", { a_elink_key=>$elkey }, 'a_pkey', $pkey);
			if ($r) { $com_edit=1; }
		}
	}

	# イベント処理
	my $a_pkeys = keys(%cons);
	$self->call_event('ARTICLE_STATE_CHANGE', $a_pkeys);
	if ($com_edit) {
		$self->call_event('COMMENT_STATE_CHANGE', $a_pkeys);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', $a_pkeys);

	return 0;
}


1;
