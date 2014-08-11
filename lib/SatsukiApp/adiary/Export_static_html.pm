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
	# 静的出力向けスケルトンと初期化処理
	#---------------------------------------------------------------------
	$ROBJ->regist_skeleton($aobj->{theme_dir} . '_static/_skel/', 999);
	$ROBJ->call('_static_init', $session, $option);

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
	$escape->allow_anytag();

	my $e_basepath = $ROBJ->{Basepath};
	my $e_myself2  = $aobj->{myself2};
	$e_basepath =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	$e_myself2  =~ s/([^0-9A-Za-z\x80-\xff])/"\\$1"/eg;
	my $url_wrapper = sub {
		my $proto = shift;
		my $url = shift;
		if ($url =~ m|^\w+://|) {
			return $url;
		}
		if ($proto eq 'href') {
			if ($url eq $aobj->{myself2}) {
				return './index.html';
			}
			$url =~ s|^$e_myself2([^#]*)|./$1.html|g;
		}
		if ($url =~ /^[^#]*\?/) {	# Queryは無視させる
			return '#';
		}
		$url =~ s|^$e_basepath|./|g;
		return $url;
	};

	#---------------------------------------------------------------------
	# ログの出力
	#---------------------------------------------------------------------
	$session->msg("\nCreate html files");

	local($ROBJ->{Basepath}) = './';
	local($aobj->{allow_edit}) = undef;
	local($aobj->{allow_com})  = undef;
	local($aobj->{blog_admin}) = undef;

	foreach (@$logs) {
		# １つの記事を前処理
		$aobj->post_process_article( $_, \%artopt );

		# URL系の書き換え
		my $file = $_->{link_key};
		if ($file =~ m|^/|) { next; }
		$file =~ s|/|-|g;
		$file .= '.html';

		# コメント非表示
		if ($option->{nocom}) {
			$_->{com_ok} = 0;
			$_->{coms}   = 0;
		}

		#-------------------------------------------------------------
		# 出力データ生成
		#-------------------------------------------------------------
		# 記事本文の生成
		my $out = $ROBJ->call( $aobj->{article_skeleton}, $_ );
		# 外フレームの処理
		$out = $ROBJ->call( $aobj->{frame_skeleton}, $out, $option );
		$out = $ROBJ->chain_array($out);

		#-------------------------------------------------------------
		# URL書き換え
		#-------------------------------------------------------------
		$out = $escape->escape($out, $url_wrapper);

		#-------------------------------------------------------------
		# ファイルに書き出し
		#-------------------------------------------------------------
		$session->msg("\t$file : $_->{year}/$_->{mon}/$_->{day} $_->{title}");
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
