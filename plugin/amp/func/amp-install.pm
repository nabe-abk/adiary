#-----------------------------------------------------------------------------
# sitemap生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $table = "$self->{blogid}_art";
	my $r = $DB->add_column($table, {
		name => 'amp_txt',
		type => 'ltext'
	});
	if ($r) { return $r; }

	my $r = $DB->add_column($table, {
		name => 'amp_head',
		type => 'ltext'
	});
	if ($r) {
		$DB->drop_column($table, 'amp_txt');
		return $r;
	}

	my $r = $DB->add_column($table, {
		name => 'amp_tm',
		type => 'int'
	});
	if ($r) {
		$DB->drop_column($table, 'amp_txt');
		$DB->drop_column($table, 'amp_head');
		return $r;
	}
	return 0;
}

