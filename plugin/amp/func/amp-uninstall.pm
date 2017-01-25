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

	$self->update_plgset('amp', 'css_info');
	$self->update_plgset('amp', 'logo_tm');
	$self->update_plgset('amp', 'logo_width');
	$self->update_plgset('amp', 'logo_height');
	return 0;
}

