#-------------------------------------------------------------------------------
# sitemap pingモジュール
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $art  = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $plg  = $self->load_plgset($name);
	if (!$form->{ping} || !$plg->{ping}) { return; }

	my $urls = $plg->{urls_txt} || 'http://google.com/ping?sitemap=';
	my @url  = split(/\n/, $urls);
	my $sitemap  = $ROBJ->{ServerURL} . $self->{myself} . '?sitemap';
	$ROBJ->encode_uricom($sitemap);

	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout( $self->{sys}->{http_timeout} );
	$http->set_agent( $self->{http_agent} );

	foreach(@url) {
		$_ =~ s/^\s*(.*?)\s*$/$1/;
		if (!$_ || $_ =~ /^#/)    { next; }
		if ($_ !~ m|^https?://|i) { next; }

		# Ping送信
		$http->get("$_$sitemap");
	}
	$ROBJ->notice("Sitemap update notification sent");

	return 0;
}

