#-----------------------------------------------------------------------------
# コンテンツリストの生成モジュール
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

	# コンテンツキーの加工
	my $all = $root->{_all};
	foreach(@$all) {
		if ($_->{ctype} ne 'link') { next; }
		$_->{elink_key} =~ s/%25/%/g;
		$_->{elink_key} =~ s/%2[bB]/+/g;
		$_->{elink_key} =~ s/%3[fF]/?/;
	}

	my $node = int($self->load_plgset($name, 'node'));
	my $tree = {};
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
	$self->update_plgset($name, 'html', $ROBJ->call('_format/contents_list', $name, $tree));
	return 0;
}

