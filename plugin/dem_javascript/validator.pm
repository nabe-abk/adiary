#-------------------------------------------------------------------------------
# JavaScriptモジュールの値チェック
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $script = $form->{script_txt};
	my $urls   = $form->{urls_txt};

	my @url;
	foreach(split(/\n/, $urls)) {
		$_ =~ s/\s//g; 
		if ($_ !~ m|^/| && $_ !~ m|^https?://|) { next; }
		push(@url, $_);
	}

	# 設定値
	my %h;
	$h{script} = $script;
	$h{urls}   = join("\n", @url);

	return \%h;
}

