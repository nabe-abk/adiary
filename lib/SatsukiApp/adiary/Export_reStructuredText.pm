use strict;
#------------------------------------------------------------------------------
# データエクスポート for Sphinx/reStructuredText
#                                                   (C)2019 nabe / nabe@abk
#------------------------------------------------------------------------------
package SatsukiApp::adiary::Export_reStructuredText;
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
	# ディレクトリ作成
	#-------------------------------------------------------------
	my $dir = $option->{export_dir} = $aobj->{blogpub_dir} . 'sphinx/';

	$ROBJ->mkdir($dir);
	if (!-w $ROBJ->get_filepath($dir)) {
		$session->msg("Can not create '$dir' or not writeble!");
		return;
	}

	# ディレクトリ内の初期化
	if ($option->{format} || $option->{type} eq 'format') {
		my @keep;
		$session->msg("'$dir' clear!");
		my $files = $ROBJ->search_files($dir, {dir=>1});
		foreach(@$files) {
			if ($_ =~ /^\./) { next; }
			if ($_ =~ m!^(?:_\w+/|conf.py|Makefile|make.bat)$!i) {
				push(@keep, $_);
				next;
			}

			my $f = "$dir$_";
			if (-d $f) {
				$session->msg("\tdelete dir: $_");
				$ROBJ->dir_delete( $f );
				next;
			}
			$session->msg("\tdelete file: $_");
			$ROBJ->file_delete( $f );
		}
		foreach(@keep) {
			$session->msg("\tkeep: $_");
		}
		$session->msg("");
	}

	#-------------------------------------------------------------
	# フォーマットのみで終了
	#-------------------------------------------------------------
	if ($option->{type} eq 'format') {
		$session->close();
		$ROBJ->{export_return} = 0;
		return 0;
	}

	#-------------------------------------------------------------
	# rstのログのみ抽出
	#-------------------------------------------------------------
	$logs = [ grep { $_->{parser} =~ /^re?st/i } @$logs ];

	#-------------------------------------------------------------
	# ログのソート
	#-------------------------------------------------------------
	my $order = $option->{order};
	if ($order eq 'date') {
		$logs = [ sort { $a->{yyyymmdd} <=> $b->{yyyymmdd} || $a->{tm} <=> $b->{tm} } @$logs ];
	}
	if ($order eq 'date_r') {
		$logs = [ sort { $b->{yyyymmdd} <=> $a->{yyyymmdd} || $b->{tm} <=> $a->{tm} } @$logs ];
	}
	if ($order eq 'tree') {
		$logs = [ grep { $_->{enable} && $_->{ctype} ne '' } @$logs ];
		my $h = $aobj->load_contents_cache();
		foreach(@$logs) {
			my $pkey = $_->{pkey};
			if (! $h->{$pkey}) { next; }	# ツリーに含まれない記事は無視（通常起きない）
			$_->{prev}  = $h->{$pkey}->{prev};
			$_->{next}  = $h->{$pkey}->{next};
			$_->{_log}  = 1;
			$h->{$pkey} = $_;
		}
		my @first = grep { !$h->{$_}->{prev} } keys(%$h);

		$logs = [];
		my %safety;	# 本来は不要
		my $x = $first[0];
		while($x) {
			if ($safety{$x}) { last; }	# 万が一の無限ループ対策
			$safety{$x}=1;

			my $art = $h->{$x};
			if ($art->{_log}) {
				push(@$logs, $h->{$x});
			}
			$x = $art->{next};
		}
	}

	#-------------------------------------------------------------
	# ログ確認
	#-------------------------------------------------------------
	if (!@$logs) {
		$session->msg("reStructuredText article not found");
		return 0;
	}

	#---------------------------------------------------------------------
	# 初期化処理
	#---------------------------------------------------------------------
	$ROBJ->exec($option->{init}, $session, $option);

	my $sphinx  = $ROBJ->{Auth}->{isadmin} && $aobj->{special_export} && $option->{sphinx};
	my $conf_py = $ROBJ->get_filepath($dir . $option->{init_check});
	if ($sphinx) {
		if (!-r $conf_py) {
			$session->msg("Not Found: conf.py");
			my $cmd = $option->{sphinx_init};
			$cmd =~ s/%a/$ROBJ->{Auth}->{id}/g;

			$self->call_command($session, $dir, $cmd);
		}
		if (!-r $conf_py) {
			$session->msg("Sphinx mode: disable");
			$sphinx = 0;
		}
	}

	#---------------------------------------------------------------------
	# ログの出力
	#---------------------------------------------------------------------
	$session->msg("Create .rst files");

	my @files;
	my $index_rst='';
	foreach (@$logs) {
		if ($_->{ctype} eq 'link') { next; }

		#-------------------------------------------------------------
		# ファイル名の加工
		#-------------------------------------------------------------
		my $file = $_->{link_key};
		if ($file =~ m|^[/\.]|) { next; }
		if ($file =~ m!^\w+://!) { next; }
		$aobj->export_escape_filename($file);
		$file .= '.rst';

		#-------------------------------------------------------------
		# 記事の前処理 for index.html
		#-------------------------------------------------------------
		$aobj->post_process_article( $_ );

		#-------------------------------------------------------------
		# テキスト処理
		#-------------------------------------------------------------
		my $text  = $_->{_text};
		my $title = $_->{title};
		$ROBJ->tag_unescape($title);

		if ($option->{title} && $file ne 'index.rst') {
			my $t = $option->{title_line} || '@' x 60;
			$text = "$t\n$title\n$t\n\n" . $text;
		}
		if ($option->{make_index} && $file eq 'index.rst') {
			$index_rst = $text . "\n\n";
		}

		#-------------------------------------------------------------
		# ファイルに書き出し
		#-------------------------------------------------------------
		my $mod = $ROBJ->get_lastmodified("$dir$file");
		if ($mod && $mod > $_->{update_tm}) {
			$session->msg("\t$file: $_->{title}\t\t-> No change");
		} else {
			$session->msg("\t$file: $_->{title}");
			$ROBJ->fwrite_lines("$dir$file", $text);
		}
		$_->{file} = $file;
		push(@files, $_);
	}

	#---------------------------------------------------------------------
	# index.rstの生成
	#---------------------------------------------------------------------
	my @files2 = grep { $_->{file} ne 'index.rst' } @files;
	if ($option->{make_index} && @files2) {
		my $rst = $ROBJ->exec($option->{index_rst_skel}, \@files2);
		$session->msg("Create: index.rst");
		$ROBJ->fwrite_lines($dir . 'index.rst', $index_rst . $rst);
	}

	#---------------------------------------------------------------------
	# make
	#---------------------------------------------------------------------
	if ($sphinx) {
		$session->msg('');
		$option->{builder} =~ s/\W//g;
		my $cmd = "make $option->{builder}";

		$self->call_command($session, $dir, $cmd);
	}

	#---------------------------------------------------------------------
	# index.htmlの生成
	#---------------------------------------------------------------------
	if (@files) {
		my $html = $ROBJ->exec($option->{index_skel}, \@files);
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

#------------------------------------------------------------------------------
# ●call shell command
#------------------------------------------------------------------------------
sub call_command {
	my ($self, $session, $dir, $command) = @_;

	$session->msg("\$ $command");
	my $fh;
	open($fh, "export LC_ALL=C.UTF-8; cd \"$dir\"; $command 2>&1 |");
	while (my $x = <$fh>) {
		$x =~ s/\n//g;
		$session->msg("\t$x");
	}
	close($fh);
}

1;
