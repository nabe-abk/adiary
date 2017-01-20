#-----------------------------------------------------------------------------
# sitemap pingモジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $art  = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $plg  = $self->load_plgset($name);
	if (!$form->{ping} || !$plg->{ping}) { return; }

	my $urls = $plg->{urls_txt} || 'http://www.google.com/webmasters/tools/ping';
	my @url  = split(/\n/, $urls);
	my $sitemap  = $ROBJ->{Server_url} . $self->{myself} . '?sitemap';
	$ROBJ->encode_uricom($sitemap);

	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout( $self->{sys}->{http_timeout} );
	$http->set_agent( $self->{http_agent} );

	foreach(@url) {
		$_ =~ s/^\s*(.*?)\s*$/$1/;
		if (!$_ || $_ =~ /^#/) { continue; }
		if ($_ !~ m|^https?://|i) { continue; }

		# Ping送信
		$http->get("$_?$sitemap");
		$self->debug("$_?$sitemap");
	}
	$ROBJ->notice("sitemap.xml update ping sended");

	return 0;
}

