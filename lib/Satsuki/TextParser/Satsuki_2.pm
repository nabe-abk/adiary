use strict;
package Satsuki::TextParser::Satsuki;
################################################################################
# ■特殊タグの一覧取得
################################################################################
#-------------------------------------------------------------------------------
# ●タグの一覧作成（特殊タグ）
#-------------------------------------------------------------------------------
sub load_tags {
	my $self = shift;
	my $ROBJ  = $self->{ROBJ};
	my $jcode = $ROBJ->load_codepm();

	# 現在の設定ロード
	my $tags    = $self->{tags};
	my $titles  = $self->{titles};

	my @keys = sort keys(%$tags);
	my @ary;
	my %alias;
	foreach(@keys) {
		if (substr($_,0,1) eq '&') { next; }	# 先頭 & は特殊処理なので無視

		my %tag = %{ $tags->{$_} };
		if ($tag{alias}) {
			my $x = $alias{ $tag{alias} } ||= [];
			push(@$x, $_);
			next;
		}
		if ($tag{html}) {
			# html 単純置換
			$tag{url} = $self->html_tag(\%tag, ['$$']);
			$tag{title} = '(html)'
		} elsif ($tag{plugin}) {
			# plugin
			#
		} else {
			$tag{url} = $tag{data};
		}
		$ROBJ->tag_escape( $tag{url} );
		$tag{name} = $_;
		push(@ary, \%tag);
	}

	# alias情報を設定
	foreach(@ary) {
		my $name = $_->{name};
		if (!exists $alias{$name}) { next; }
		$_->{alias} = $alias{$name};
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●タグの一覧作成（html置換タグ）
#-------------------------------------------------------------------------------
sub load_htmltags {
	my $self      = shift;
	my $separator = shift || ', ';
	my $ROBJ = $self->{ROBJ};

	my $tags  = $self->{tags};
	my @keys = sort keys(%$tags);
	my @ary;
	foreach(@keys) {
		if (ord($_) == 0x3d) { next; }	# 先頭 = は無視
		my $tag = $tags->{$_};
		if (! $tag->{html}) { next; }		# html 以外は無視

		my ($html_tag, $class) = split('\.', $tag->{html});
		my %h;
		$h{name}      = $_;
		$h{html}      = $html_tag;
		$h{class}     = $class;
		$h{attribute} = $tag->{attribute};
		push(@ary, \%h);
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●タグの一覧作成（alias）
#-------------------------------------------------------------------------------
sub load_aliases {
	my $self      = shift;
	my $separator = shift || ', ';
	my $ROBJ = $self->{ROBJ};

	my %aliases;
	my $tags  = $self->{tags};
	while(my($k,$v) = each(%$tags)) {
		if (ord($k) == 0x3d) { next; }	# 先頭 = は無視
		my $alias = $v->{alias};
		if (! $alias) { next; }	# alias 以外は無視
		# 別名
		my $ary = $aliases{$alias} ||= [];
		push(@$ary, $k);
	}

	my @ary;
	my @keys = sort keys(%aliases);
	foreach(@keys) {
		my %h;
		$h{tag}    = $_;
		$h{alias}  = join($separator, @{ $aliases{$_} });
		push(@ary, \%h);
	}
	return \@ary;
}

################################################################################
# ■その他のルーチン
################################################################################



1;
