#-----------------------------------------------------------------------------
# タグリストの生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $root = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	if ($self->{event_name} ne 'CONTENT_STATE_CHANGE') {
		$root = $self->load_contents_tree( $self->{blogid} );
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
	$self->update_plgset($name, 'html', $ROBJ->call_and_chain('_format/contents_list', $name, $tree));
	return 0;
}

