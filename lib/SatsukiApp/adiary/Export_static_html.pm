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

	#-------------------------------------------------------------
	# セッション開始
	#-------------------------------------------------------------
	my $session = $aobj->open_session( $option->{snum} );

	#-------------------------------------------------------------
	# ディレクトリ確認
	#-------------------------------------------------------------
	my $dir = $aobj->{static_output_dir};
	if ($dir eq '') {
		$session->msg("'<\$v.static_output_dir>' not defined.");
		return ;
	}
	$dir = $ROBJ->get_filepath($dir);
	$ROBJ->mkdir($dir);
	if (!-w $dir) {
		$session->msg("'$dir' is not exists or not writeble!");
		return ;
	}

	# ディレクトリ内の初期化
	if ($option->{clear}) {
		$session->msg("'$dir' clear!");
		my $files = $ROBJ->search_files($dir, {dir=>1});
		foreach(@$files) {
			if ($_ =~ /^\./) { next; }
			my $f = "$dir$_";
			if (-d $f) {
				$session->msg("\tdelete dir: $_");
				$ROBJ->dir_delete( $f );
				next;
			}
			$session->msg("\tdelete file: $_");
			$ROBJ->file_delete( $f );
		}
	}
	$ROBJ->mkdir($dir);

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
	# URL書き換えルーチン
	#---------------------------------------------------------------------
	my $escape = $ROBJ->loadpm('TextParser::TagEscape');
	$escape->anytag(1);

	my $theme_dir = $aobj->{static_theme_dir};

	my $qr_basepath = $ROBJ->{Basepath};
	my $qr_myself2  = $aobj->{myself2};
	my $qr_pluginjs = $theme_dir . 'js/';
	
	my $qr_imgdir   = $ROBJ->{Basepath} . $aobj->blogimg_dir();
	$qr_basepath =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_myself2  =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_pluginjs =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_imgdir   =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$qr_basepath = qr/^$qr_basepath/;
	$qr_myself2  = qr/^$qr_myself2/;
	$qr_pluginjs = qr/^(\.\/)?$qr_pluginjs/;
	$qr_imgdir   = qr/^$qr_imgdir/;
	my $url_wrapper = sub {
		my $proto = shift;
		my $url = shift;
		if ($url =~ m|^\w+://|) {
			return $url;
		}

		$url =~ s|\?\d+$||;	# ?123456789 : リロード用Query除去
		$url =~ s|$qr_pluginjs|$1$aobj->{static_theme_dir}|g;
		$url =~ s|$qr_imgdir|$aobj->{static_files_dir}|g;
		if ($proto eq 'href') {
			if ($url eq $aobj->{myself2}) {
				return './index.html';
			}
			$url =~ s[$qr_myself2([^#]*)][
				my $key = $1;
				$key =~ s|/|-|g;
				"./$key.html"
			]eg;
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
	local($aobj->{script_dir})  = $theme_dir;
	local($aobj->{blogpub_dir}) = $theme_dir;

	my $set_orig = $aobj->{blog};
	my %s = %$set_orig;
	local($aobj->{blog}) = \%s;

	if (!$option->{custom_css}) { $s{theme_custom}=0; }
	if (!$option->{gaid}) { $s{gaid} = ''; }

	$s{'p:deh_login:erase_login'} = 1;	# ログインを消す
	$s{theme_custom}  = $s{theme_custom} ? "${theme_dir}custom.css" : '';
	$s{rss_files}     = '';
	$session->msg("blog_dir=$aobj->{blog_dir}");

	foreach (@$logs) {
		# １つの記事を前処理
		$aobj->post_process_article( $_, \%artopt );

		# URL系の書き換え
		my $file = $_->{link_key};
		if ($file =~ m|^[/\.]|) { next; }
		$file =~ s|/|-|g;
		$file .= '.html';

		# コメント非表示
		if ($option->{nocom}) {
			$_->{coms} = 0;
		}
		$_->{com_ok} = 0;

		#-------------------------------------------------------------
		# 出力データ生成
		#-------------------------------------------------------------
		# 記事本文の生成
		my $out = $ROBJ->call( $aobj->{article_skeleton}, $_ );
		$aobj->{extra_header} = [];	# clear OGP

		# フレームの前処理
		$ROBJ->{canonical_url} = '';

		# 外フレームの処理
		$out = $ROBJ->call( $aobj->{frame_skeleton}, $out, $option );
		$out = $ROBJ->chain_array($out);

		#-------------------------------------------------------------
		# URL書き換え
		#-------------------------------------------------------------
		$out = $escape->escape($out, { url => $url_wrapper });

		#-------------------------------------------------------------
		# ファイルに書き出し
		#-------------------------------------------------------------
		$session->msg("\t$file : $_->{title}");
		$ROBJ->fwrite_lines("$dir$file", $out);
	}

	$session->msg("Finish : $ROBJ->{Timestamp}");
	$session->close();

	$ROBJ->{export_return} = 0;
	return 0;
}
###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●link_key を file名 に加工
#------------------------------------------------------------------------------
sub key2file {
	my $art_obj = shift;
	foreach(@_) {
		$art_obj->link_key_encode( $_ );
		$_ =~ s[/][%2f]g;
		$_ .= ".html";
	}
	return $_[0];
}

1;
