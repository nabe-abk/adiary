#-------------------------------------------------------------------------------
# Informationモジュールの設定フォーム値チェック
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	# jQueryなので並び順で送られることが期待できる
	my @links;
	my %map;
	my $url_ary  = $form->{url_ary}  || [];
	my $text_ary = $form->{text_ary} || [];
	foreach(@$text_ary) {
		my ($n,$text) = split(',', $_, 2);
		my $h = $map{$n} = { text => $text };
		push(@links, $h);
	}
	foreach(@$url_ary) {
		my ($n,$url) = split(',', $_, 2);
		my $h = $map{$n};
		if (!$h) { next; }
		$h->{url} = $url;
	}

	my @ary;
	foreach(@links) {
		my $url  = $_->{url};
		my $text = $_->{text};
		if ($url ne '' && $url !~ m!^(?:https?://|mailto:|/)!i) { next; }

		$ROBJ->tag_escape($text, $url);
		$text =~ s/\t/ /g;
		push(@ary, "$text\t$url");
	}

	# 設定値
	my %h;
	$h{title} = $ROBJ->tag_escape($form->{title});
	$h{elements} = join("\n", @ary);

	return \%h;
}

