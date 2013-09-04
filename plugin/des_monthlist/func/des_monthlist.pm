#-----------------------------------------------------------------------------
# 月別の記事一覧モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $num = $self->load_plgset($name, 'displays') || 5;
	my $ary = $DB->select("${blogid}_art",{
		flag     => { enable => 1 },
		cols     => [ 'yyyymmdd' ]
	});

	my %yyyymm;
	foreach(@$ary) {
		$yyyymm{ substr($_->{yyyymmdd},0,6) }++;
	}
	my @yyyymm = sort {$b <=> $a} keys(%yyyymm);
	@yyyymm = map {
		{yyyymm => $_,
		 year => substr($_,0,4),
		 mon  => substr($_,4,2),
		 count => $yyyymm{$_} }
	} @yyyymm;

	# スケルトンの実行
	$self->update_plgset($name, 'html', $ROBJ->call_and_chain('_format/month_list', $name, \@yyyymm));
	return 0;
}

