# uninstall
sub {
	my $self = shift;
	my $name = shift;
	$self->update_plgset($name, 'html', undef);
	return 0;
}

