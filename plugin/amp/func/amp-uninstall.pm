# uninstall
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $table = "$self->{blogid}_art";
	$DB->drop_column($table, 'amp_txt');
	$DB->drop_column($table, 'amp_head');
	$DB->drop_column($table, 'amp_tm');

	$self->update_cur_blogset('amp:css_info');
	return 0;
}

