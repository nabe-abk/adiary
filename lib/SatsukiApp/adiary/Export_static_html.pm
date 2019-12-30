use strict;
#------------------------------------------------------------------------------
# データエクスポート for 静的HTML
#                                                   (C)2014 nabe / nabe@abk
#------------------------------------------------------------------------------
package SatsukiApp::adiary::Export_static_html;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	return $self;
}

###############################################################################
# ■出力メイン
###############################################################################
#------------------------------------------------------------------------------
# ●HTML形式でファイルを書き出し
#------------------------------------------------------------------------------
sub export {
	my ($self, $logs, $option) = @_;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $option->{aobj};
	$option->{sphinx} = 1;

	#-------------------------------------------------------------
	# セッション開始
	#-------------------------------------------------------------
	my $session = $aobj->open_session( $option->{snum} );

	# 権限確認
	if (!$aobj->{static_export}) {
		$session->msg("Static export disabled");
		return;
	}

	#-------------------------------------------------------------
	# ディレクトリ作成
	#-------------------------------------------------------------
	my $dir  = $option->{export_dir};
	my $dir_ = $ROBJ->get_filepath($dir);

	$ROBJ->mkdir($dir);
	if (!-w $dir_) {
		$session->msg("Can not create '$dir' or not writeble!");
		return;
	}

	# ディレクトリ内の初期化
	if ($option->{format} || $option->{type} eq 'format') {
		$session->msg("'$dir' clear!");
		my $files = $ROBJ->search_files($dir, {dir=>1, all=>1});
		foreach(@$files) {
			my $f_   = "$dir_$_";
			my $file = $ROBJ->fs_decode( $_ );
			if (-d $f_) {
				$session->msg("\tdelete dir: $file");
				$ROBJ->dir_delete( $f_ );
				next;
			}
			$session->msg("\tdelete file: $file");
			$ROBJ->file_delete( $f_ );
		}
	}

	#-------------------------------------------------------------
	# フォーマットのみで終了
	#-------------------------------------------------------------
	if ($option->{type} eq 'format') {
		$session->msg("\tdelete dir: $dir");
		$ROBJ->dir_delete( $dir );

		$session->close();
		$ROBJ->{export_return} = 0;
		return 0;
	}

	#---------------------------------------------------------------------
	# 初期化処理
	#---------------------------------------------------------------------
	$ROBJ->exec($option->{init}, $session, $option);

	# 記事データ加工のオプション
	my %artopt;
	$artopt{see_all} = 1;
	$artopt{myself2} = '';		# 相対リンクで
	$artopt{static_mode} = 1;	# 静的リンクモード
	$artopt{static_html_mode} = 1;	# HTML生成モード
	$artopt{static_image_dir} = 1;

	#---------------------------------------------------------------------
	# HTMLフィルター
	#---------------------------------------------------------------------
	my $escape = $ROBJ->loadpm('TextParser::TagEscape');
	$escape->anytag(1);

	my $base_url = './';
	my $filter = sub {
		my $html = shift;
		foreach my $p ($html->getAll) {
			my $type = $p->type();
			if ($type ne 'tag') { next; }

			my $at = $p->attr();
			my $flag;
			foreach(keys(%$at)) {
				if ($_ eq 'id' && $at->{id} eq 'adiary-vars') { $flag=1; last; }
			}
			if (!$flag) { next; }
			my $c = $p->next;
			if ($c->type ne 'comment') { next; }

			my $com = $c->val();
			$com =~ s/("myself\d?":\s+)".*?"/$1"$base_url"/g;
			$com =~ s/(\s+)}/,$1	"Static":	1\n}/g;

			$c->val($com);
		}
	};

	#---------------------------------------------------------------------
	# URL書き換えルーチン
	#---------------------------------------------------------------------

	my $static_theme_dir = $aobj->{static_theme_dir} || 'theme/';
	my $static_files_dir = $aobj->{static_files_dir} || 'files/';

	my $qr_basepath = $ROBJ->{Basepath};
	my $qr_myself2  = $aobj->{myself2};
	my $qr_blogpub  = $aobj->{blogpub_dir};
	my $qr_imgdir   = $ROBJ->{Basepath} . $aobj->blogimg_dir();
	my $qr_query    = $aobj->{myself} . '?';

	$qr_basepath =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_myself2  =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_blogpub  =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_imgdir   =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_query    =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_basepath = qr|^$qr_basepath|;
	$qr_myself2  = qr|^$qr_myself2|;
	$qr_blogpub  = qr|^(?:\./)?$qr_blogpub(?:[\w\.]+/)?|;
	$qr_imgdir   = qr|^$qr_imgdir|;
	$qr_query    = qr|^$qr_query|;

	my $url_wrapper = sub {
		my $proto = shift;
		my $url = shift;
		if ($url =~ m|^\w+://| || $url =~ m|^//|) {
			return $url;
		}

		$url =~ s|\?\d+$||;	# ?123456789 : リロード用Query除去
		$url =~ s|$qr_blogpub|$static_theme_dir|g;
		$url =~ s|$qr_imgdir|$static_files_dir|g;
		if ($proto eq 'href') {
			if ($url eq $aobj->{myself2}) {
				return './index.html';
			}
			# query
			$url =~ s[$qr_query(artlist)][q/artlist.html];
			$url =~ s[${qr_query}d=(\d+)][q/$1.html];
			$url =~ s[$qr_query.*][#-link-not-found];

			# other
			$url =~ s[$qr_myself2([^#]*)][
				my $key = $1;
				if ($key =~ m|^\w+://|) {
					$key;
				} else {
					$aobj->export_escape_filename($key);
					$key =~ s|%3f|-|g;	# %3f = ?
					"./$key.html"
				}
			]e;
		}
		if ($url =~ /^([^#]*)\?\d*$/) {	# 更新検出 ?time は除去
			return $1;
		}
		if ($url =~ /^[^#]*\?/) {	# Queryは無視させる
			return '#';
		}
		$url =~ s|$qr_basepath|./|g;
		return $url;
	};

	#---------------------------------------------------------------------
	# ログの出力
	#---------------------------------------------------------------------
	$session->msg("\nCreate html files");

	my $auth = $ROBJ->{Auth};
	local($ROBJ->{Basepath}) = './';
	local($auth->{ok})         = undef;
	local($auth->{id})         = undef;
	local($aobj->{allow_edit}) = undef;
	local($aobj->{allow_com})  = undef;
	local($aobj->{blog_admin}) = undef;
	local($aobj->{theme_dir})   = $static_theme_dir;
	local($aobj->{script_dir})  = $static_theme_dir;

	my $set_orig = $aobj->{blog};
	my %s = %$set_orig;
	local($aobj->{blog}) = \%s;

	if (!$option->{custom_css}) { $s{theme_custom}=0; }
	if (!$option->{gaid}) { $s{gaid} = ''; }

	$s{'p:deh_login:erase_login'} = 1;	# ログインを消す
	$s{theme_custom}  = $s{theme_custom} ? "${static_theme_dir}custom.css" : '';
	$s{rss_files}     = '';
	$session->msg("blog_dir=$aobj->{blog_dir}");

	my $index;
	my @files;
	my %ymd;
	foreach (@$logs) {
		if ($_->{ctype} eq 'link') { next; }

		# URL系の書き換え
		my $file = $_->{link_key};
		if ($file =~ m|^[/\.]|) { next; }
		if ($file =~ m!^\w+://!) { next; }
		$aobj->export_escape_filename($file);
		$file .= '.html';

		# 記事の前処理
		$aobj->post_process_article( $_, \%artopt );

		# コメント非表示
		if ($option->{nocom}) {
			$_->{coms} = 0;
		}
		$_->{com_ok} = 0;

		#-------------------------------------------------------------
		# 出力データ生成
		#-------------------------------------------------------------
		# 記事本文の生成
		$aobj->{stop_ogp} = 1;	# do not output OGP
		my $out = $ROBJ->call( $aobj->{article_skeleton}, $_ );

		# フレームの前処理
		$ROBJ->{canonical_url} = '';

		# 外フレームの処理
		$out = $ROBJ->call( $aobj->{frame_skeleton}, $out );

		#-------------------------------------------------------------
		# URL書き換え
		#-------------------------------------------------------------
		$out = $escape->escape($out, { filter => $filter, url => $url_wrapper });

		#-------------------------------------------------------------
		# ファイルに書き出し
		#-------------------------------------------------------------
		$session->msg("\t$file: $_->{title}");
		$ROBJ->fwrite_lines($ROBJ->fs_encode("$dir$file"), $out);

		#-------------------------------------------------------------
		# 一覧用に記録
		#-------------------------------------------------------------
		$_->{file} = $file;
		unshift(@files, $_);
		my $yy = $_->{year};
		my $ym = $_->{year} . $_->{mon};
		unshift(@{$ymd{$yy} ||= []}, $_);
		unshift(@{$ymd{$ym} ||= []}, $_);

		if ($file eq 'index.html') { $index=1; }
	}

	#---------------------------------------------------------------------
	# 記事一覧の生成
	#---------------------------------------------------------------------
	my $gen_skel = sub {
		# html生成
		my $out = $ROBJ->exec( @_ );
		$ROBJ->{canonical_url} = '';
		$out = $ROBJ->call( $aobj->{frame_skeleton}, $out );
		$out = $escape->escape($out, { filter => $filter, url => $url_wrapper });
	};
	if ($option->{artlist}) {
		my $qdir = $dir . 'q/';
		$ROBJ->mkdir($qdir);
		$ymd{''} = \@files;
		$base_url = '../';

		$session->msg("Generate artlist to '$qdir'");
		foreach(sort keys(%ymd)) {
			my $h = {
				year => substr($_, 0, 4),
				mon  => substr($_, 4, 2)
			};

			# html生成
			my $html = &$gen_skel( $option->{artlist_skel}, $ymd{$_}, $h );

			# 親ディレクトリ参照
			$html =~ s!\s(href|src)="\./! $1="../!g;

			my $file = ($_ ? $_ : 'artlist') . '.html';

			$session->msg("\t$file");
			$ROBJ->fwrite_lines($qdir . $file, $html);
		}
	}

	#---------------------------------------------------------------------
	# index.htmlの生成
	#---------------------------------------------------------------------
	if (!$index && @files) {
		$base_url = './';

		my $html = &$gen_skel( $option->{artlist_skel}, \@files, {} );
		$session->msg("Create: index.html");
		$ROBJ->fwrite_lines($dir . 'index.html', $html);
	}

	#---------------------------------------------------------------------
	# 終了処理
	#---------------------------------------------------------------------
	$session->msg("\nFinish: $ROBJ->{Timestamp}");
	$session->close();

	$ROBJ->{export_return} = 0;
	return 0;
}

1;
