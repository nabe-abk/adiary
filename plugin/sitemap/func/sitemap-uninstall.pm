# uninstall
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->{blogpub_dir} . 'sitemap.xml';
	$ROBJ->file_delete($file);

	return 0;
}

