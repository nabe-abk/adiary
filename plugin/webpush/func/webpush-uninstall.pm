# uninstall
sub {
	my $self = shift;
	my $name = shift;
	$self->update_plgset($name, 'mpub', undef);
	$self->update_plgset($name, 'mprv', undef);
	return 0;
}

