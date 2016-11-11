#-----------------------------------------------------------------------------
# タグリストの生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $tree = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	if ($self->{event_name} ne 'TAG_STATE_CHANGE') {
		$tree = $self->load_tag_tree( $blogid );
	}

	# タグのない記事を探す
	my $ary = $DB->select_match("${blogid}_art", 'tags', '', '*cols', 'pkey', 'enable', 1);
	my $notag_arts = @$ary;

	# スケルトンの実行と保存
	$self->update_plgset($name, 'html', $ROBJ->call_and_chain('_format/taglist', $name, $tree, $notag_arts));

	# spmenu再生成
	$self->generate_spmenu( $name );

	return 0;
}

