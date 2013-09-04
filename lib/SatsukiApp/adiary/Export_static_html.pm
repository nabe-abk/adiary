use strict;
#------------------------------------------------------------------------------
# データエクスポート for 静的HTML
#                                                   (C)2006 nabe / nabe@abk.nu
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
sub output {
	my ($self, $dir, $logs, $option) = @_;
	my $ROBJ  = $self->{ROBJ};
	my $Diary = $ROBJ->{Diary};

	# 文字コード変換
	my $system_coding = $ROBJ->{System_coding};
	my $output_coding = $system_coding;
	my $jcode;
	if ($system_coding ne $output_coding) {
		$jcode = $ROBJ->load_codepm();
	}

	# 静的出力向けスケルトン
	$ROBJ->{User_skeleton_dir2} = $Diary->{theme_dir} . '_static/_skeleton/';
	$ROBJ->call('_static_init', $option);	# initailze

	# ディレクトリ内のクリアとディレトリ作成
	if ($option->{static_clear}) {
		my $files = $ROBJ->search_files($dir, {ext => '.html'});
		foreach(@$files) {
			print "Delete file: $_\n";
			$ROBJ->file_delete("$dir$_");
		}
	}
	$ROBJ->mkdir($dir);

	# 記事データ加工のオプション
	my %logopt;
	$logopt{see_all} = 1;
	$logopt{myself2} = '';		# 相対リンクで
	$logopt{static_mode} = 1;	# 静的リンクモード
	$logopt{static_html_mode} = 1;	# HTML生成モード
	$logopt{static_image_dir} = $Diary->{static_image_dir};

	#---------------------------------------------------------------------
	# 埋め込みテキストを表示しない
	#---------------------------------------------------------------------
	if ($option->{static_nodisp_emtxt}) {
		my $s = $Diary->{blog_setting};
		foreach(qw(text_info text_main0 text_main1 bodyend_1st bodyend title_after text_footer text_side0 text_side1 text_side_a0 text_side_a1 text_side_b0 text_side_b1)) {
			delete $s->{$_};
		}
	}

	#---------------------------------------------------------------------
	# ログの出力準備
	#---------------------------------------------------------------------
	my $blogid = $Diary->{blogid};
	$Diary->generate_contents_list($blogid, 1);	# コンテンツリスト
	# テンプレート名抽出
	if ($Diary->{template_dir} =~ m|/([^/]+)/$|m) {
		$option->{template_name} = $Diary->{template_name} = $1;
	}

	#---------------------------------------------------------------------
	# ログの出力
	#---------------------------------------------------------------------
	foreach (@$logs) {
		# 非公開記事は出力しない
		if (! $_->{enable}) { next; }

		# １つの記事を前処理
		$Diary->process_daylog( $_, \%logopt );

		# URL系の書き換え
		my $file = $_->{link_key};
		&key2file( $Diary, $file, $_->{this_art_url}, $_->{this_day_url}, $_->{this_art_pkeyurl} );
		# 子記事リスト
		$_->{children_cache} =~ s|href=".*?/([\w\-]+)"|href=$1.html|g;

		#-------------------------------------------------------------
		# 出力ファイル
		#-------------------------------------------------------------
		print "$file : $_->{year}/$_->{mon}/$_->{day} $_->{title}\n";

		# 記事本文の生成
		$Diary->{inframe} = $ROBJ->call('_main_onelog', $option, $_);
		# 外フレームの処理
		my $out = $ROBJ->call( '_frame', $option );

		# ファイルに書き出し
		my @ary;
		$ary[0] = $ROBJ->chain_array($out);
		$ROBJ->fwrite_lines("$dir$file", \@ary, {FileMode => $Diary->{File_mode}} );

		# 致命的エラーがあれば終了
		if (ref $ROBJ->{Error}) { last; }
	}
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
