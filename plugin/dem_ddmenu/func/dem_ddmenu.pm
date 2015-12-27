#-----------------------------------------------------------------------------
# プルダウンメニュー用リストの生成
#-----------------------------------------------------------------------------
sub {
	my ($self, $name) = @_;
	my $evt = $self->{event_name};

	# 記事のロード？
	my $pkey = $self->load_plgset($name, 'art_pkey');
	if ($pkey) {
		if ($evt eq 'CONTENT_STATE_CHANGE') { return 0; }
		return &make_from_article(@_);
	}
	if ($evt eq 'ARTICLE_AFTER') { return 0; }
	return &make_contents_tree(@_);
#-----------------------------------------------------------------------------
# コンテンツツリーのロード
#-----------------------------------------------------------------------------
sub make_contents_tree {
	my $self = shift;
	my $name = shift;
	my $root = shift;
	my $ROBJ = $self->{ROBJ};

	if ($self->{event_name} ne 'CONTENT_STATE_CHANGE') {
		$root = $self->load_contents_tree( $self->{blogid} );
	}

	# コンテンツキーの加工
	my $all = $root->{_all};
	foreach(@$all) {
		if ($_->{ctype} ne 'link') { next; }
		$_->{elink_key} =~ s/%25/%/g;
		$_->{elink_key} =~ s/%2[bB]/+/g;
		$_->{elink_key} =~ s/%3[fF]/?/;
	}

	my $node = int($self->load_plgset($name, 'node'));
	my $tree = [];
	if ($node) {
		my $all = $root->{_all};
		foreach(@$all) {
			if ($_->{pkey} != $node) { next; }
			$tree = $_;
			last;
		}
	} else {
		$tree = $root;
	}

	# スケルトンの実行
	$self->update_plgset($name, 'html', $ROBJ->call_and_chain('_format/ddmenu', $name, $tree));
	return 0;
}
#-----------------------------------------------------------------------------
# 記事からメニューリストの作成
#-----------------------------------------------------------------------------
sub make_from_article {
	my $self = shift;
	my $name = shift;
	my $art  = shift;
	my $ROBJ = $self->{ROBJ};
	my $evt  = $self->{event_name};
	my $pkey = $self->load_plgset($name, 'art_pkey');

	if ($evt eq 'ARTICLE_AFTER' && $pkey != $art->{pkey}) {
		# 該当記事以外が編集されたときのイベント
		return 0;
	}
	if ($evt ne 'ARTICLE_AFTER') {
		$art = $self->load_article_current_blog("0$pkey") || {};
	}

	# 本文の処理
	my $text = $art->{text};
	if (!$art->{pkey}) {
		$text = "<li><a>Not found!</a></li>";
	} else {
		my $escaper = $self->_load_tag_escaper( $self->plugin_name_dir($name) . 'allow_tags.txt' );
		$text = $escaper->escape( $text );
		$ROBJ->trim( $text );
		if ($text =~ m|^<ul>(.*)</ul>$|s) {
			$text = $1;
		} else {
			$text = "<li><a>Format error!</a></li>";
		}
	}
	my $class = $self->load_plgset($name, 'no_centering') ? '' : ' class="js-auto-width"';
	my $text = "<ul$class>$text</ul>";

	# スケルトンの実行
	$self->update_plgset($name, 'html', $text);
	return 0;
}
#-----------------------------------------------------------------------------
}