#-----------------------------------------------------------------------------
# 最近の記事、生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $num = $self->load_plgset($name, 'displays') || 5;
	my $blog_only  = $self->load_plgset($name, 'blog_only');

	my $h = {
		flag     => { enable => 1 },
		cols     => [ 'title', 'name', 'id', 'tm', 'yyyymmdd', 'link_key', 'ctype' ],
		sort     => [ 'yyyymmdd', 'tm'],
		sort_rev => [ 1, 1 ],
		limit    => $num
	};
	if ($self->{blog}->{separate_blog}) {
		$h->{match} = { priority => 0 };
	}
	my $ary = $DB->select("${blogid}_art", $h);

	foreach(@$ary) {
		$self->post_process_article($_);
	}

	$self->update_plgset($name, 'html', $ROBJ->call_and_chain('_format/recent_article', $name, $ary));
	return 0;
}

