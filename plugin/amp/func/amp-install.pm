#-----------------------------------------------------------------------------
# sitemap生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my @cols;
	my $table = "$self->{blogid}_art";
	my $r;
	while(1) {
		my $r = $DB->add_column($table, {
			name => 'amp_txt',
			type => 'ltext'
		});
		if ($r) { last; }
		push(@cols, 'amp_txt');

		my $r = $DB->add_column($table, {
			name => 'amp_head',
			type => 'text'
		});
		if ($r) { last; }
		push(@cols, 'amp_head');

		my $r = $DB->add_column($table, {
			name => 'amp_tm',
			type => 'int'
		});
		if ($r) { last; }
		push(@cols, 'amp_tm');
		last;
	}

	if ($r) {	# error exit
		while(@cols) {
			my $col = pop(@cols);
			$DB->drop_column($table, $col);
		}
		return $r;
	}

	return 0;
}

