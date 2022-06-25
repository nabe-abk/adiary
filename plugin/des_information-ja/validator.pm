#-------------------------------------------------------------------------------
# Informationモジュールの設定フォーム値チェック
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	# フリーテキストの最大長
	my $free_txt_max = 1024;

	# 値を持たないモジュールの一覧
	my %simple = map { $_ => 1 } qw(
		description
		artlist-link
		comlist-link
		artcomlist-link
		print-link
		print-link_blank
		bicon
		rssicon
	);

	my $elements = $form->{ele_ary} || [];
	my @ary;
	my $err=0;
	foreach(@$elements) {
		if ($_ !~ /^\d+,([\w\-]+)/) { next; }
		my $name = $1;
		if ($simple{$name}) {
			push(@ary, $name);
			next;
		}
		my $val = $form->{$_};

		# はてなブックマークカウンタ
		if ($name eq 'bcounter') {
			if ($val !~ /^[a-z][a-z]$/) { next; }
			push(@ary, "$name,$val");
			next;
		}

		# WebPush登録ボタン
		if ($name eq 'webpush_btn') {
			$ROBJ->trim($val);
			$ROBJ->tag_escape($val);
			push(@ary, "$name,$val");
			next;
		}

		# フリーテキスト
		if ($name eq 'free_txt' || $name eq 'freebr_txt') {
			if ($name eq 'free_txt') {
				if ($val !~ /<!--/) { $val =~ s/\n/<!--br-->/g; }
			} else {
				$val =~ s/\n/<br>/g;
			}
			if (length($val) > $free_txt_max) {
				$err++;
				$ROBJ->message("'%s' is too long. (maximum %d chars)", $_, $free_txt_max);
				next;
			}
			my $esc = $self->load_tag_escaper( 'usertext' );
			$esc->escape($val);
			$val =~ s/\n//g;	# 念のため
			push(@ary, "$name,$val");
			next;
		}
	}
	if ($err) { return $err; }

	# 設定値
	my %h;
	$h{title} = $ROBJ->tag_escape($form->{title});
	$h{title_hidden} = $form->{title_hidden} ? 1 : 0;
	$h{elements} = join("\n", @ary);
	$h{print_theme}  = $form->{print_theme};
	$h{print_theme} =~ s/[^\w]//g;

	return \%h;
}

