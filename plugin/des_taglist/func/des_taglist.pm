#-----------------------------------------------------------------------------
# タグリストの生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $root = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	if ($self->{event_name} ne 'TAG_STATE_CHANGE') {
		$root = $self->load_tag_tree( $blogid );
	}

	my $node = $self->load_plgset($name, 'node');
	my $id   = $self->load_plgset($name, 'id');
	my $tree = {};
	if ($node) {
		my $all = $root->{_all};
		foreach(@$all) {
			if ($_->{name} ne $node) { next; }
			$tree = $_;
			last;
		}
	} else {
		$tree = $root;
	}

	# タグのない記事を探す
	my $ary = $DB->select_match("${blogid}_art", 'tags', '', '*cols', 'pkey', 'enable', 1);
	my $notag_arts = @$ary;

	# スケルトンの実行と保存
	$self->update_plgset($name, 'html', $ROBJ->call('_format/taglist', $name, $tree, $notag_arts));

	return 0;
}

