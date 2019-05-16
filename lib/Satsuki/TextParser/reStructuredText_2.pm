use strict;
#------------------------------------------------------------------------------
# Split from Satsuki::TextParser::reStructuredText.pm for AUTOLOAD.
#------------------------------------------------------------------------------
use Satsuki::TextParser::reStructuredText ();
package Satsuki::TextParser::reStructuredText;
###############################################################################
# ■ディレクティブのロード
###############################################################################
my %Directive;
#------------------------------------------------------------------------------
# ○directiveの処理
#------------------------------------------------------------------------------
sub parse_directive {
	my $self  = shift;
	my $out   = shift;
	my $lines = shift;
	my $subst = shift;
	my $type  = shift;
	my $first = shift;
	$type =~ tr/A-Z/a-z/;

	my @pre;
	if ($first ne '') {
		push(@pre, $first);
	}
	if (@$lines && $lines->[0] eq '') {
		push(@pre, shift(@$lines));
	}
	my $block = $self->extract_block( $lines, 0 );
	unshift(@$block, @pre);

	my $d = $self->load_directive($type);
	if (!$d) {
		$self->parse_error('Unknown directive type: %s', $type);
		return;
	}

	#-----------------------------------------
	# type check
	#-----------------------------------------
	if ($type ne 'image' && ($subst eq '' && $d->{substitution})) {
		$self->parse_error('"%s" directive can only be used within a substitution definition', $type);
		return;
	}
	if ($type ne 'image' && ($subst ne '' && !$d->{substitution})) {
		$self->parse_error('Substitution definition "%s" empty or invalid', $subst);
		$subst='';
	}

	#-----------------------------------------
	# argument
	#-----------------------------------------
	my @arg;
	if ($d->{arg}) {
		while(@$block && $block->[0] ne '' && $block->[0] !~ /^:/) {
			my $v = shift(@$block);
			while(@$block && $block->[0] =~ /^ +(.*)/) {
				shift(@$block);
				$v .= ($v ne '' ? ' ' : '') . $1;
			}
			push(@arg, $v);
		}
		if (!@arg) {
			$self->parse_error('"%s" directive argument(s) required', $type);
			return;
		}
	}

	#-----------------------------------------
	# option
	#-----------------------------------------
	my $option = {};
	my $err;
	while(@$block && $block->[0] =~ /^:(\w+):(?: +(.*)|$)/) {
		shift(@$block);
		my $opt = $1;
		my $v   = $2;
		while(@$block && $block->[0] =~ /^ +(.*)/) {
			shift(@$block);
			$v .= ($v ne '' ? ' ' : '') . $1;
		}
		if (! $d->{option}->{$opt}) {
			$self->parse_error('"%s" directive invalid option: %s', $type, $opt);
			return;
		}
		if (exists($option->{$opt})) {
			$self->parse_error('"%s" directive duplicate option: %s', $type, $opt);
			return;
		}
		$option->{$opt} = $v;
	}

	#-----------------------------------------
	# content
	#-----------------------------------------
	while(@$block && $block->[0] eq '') { shift(@$block); }

	if ($d->{content} eq '0' && @$block) {
		$self->parse_error('"%s" directive no content permitted: %s', $type, $block->[0]);
		return;
	}

	#-----------------------------------------
	# parse
	#-----------------------------------------
	my $p = $d->{parse};
	if ($p) {
		my ($ary, $blocks) = $self->do_parse_block([], $block, 'list-item');
		if ($#$blocks != 0 || $blocks->[0] ne $p) {
			$self->parse_error('"%s" directive may contain a single %s only', $type, $p);
			return;
		}
		$block = $ary;
	} else {
		#foreach(@$block) {
		#	$self->backslash_escape($_);
		#	$self->tag_escape($_);
		#}
	}

	#-----------------------------------------
	# call directive
	#-----------------------------------------
	my $name = $d->{method} || $type . '_directive';
	my $ary  = $self->$name($block, \@arg, $option);

	if ($subst ne '') {
		my $text = join('', @$ary);
		my $ss   = $self->{substitutions};
		if (exists($ss->{$subst})) {
			$self->parse_error('Duplicate substitution definition name: %s', $subst);
		}
		$self->{substitutions}->{$subst} = $text;
	} else {
		push(@$out, @$ary);
	}
}

#------------------------------------------------------------------------------
# load directive
#------------------------------------------------------------------------------
sub load_directive {
	my $self = shift;
	my $type = shift;
	if (%Directive) { return $Directive{$type}; }

	#----------------------------------------------------------------------
	$Directive{image} = {
		substitution => 1,
		arg    => 1,
		content=> 0,
		option => [ qw(alt height width scale align target) ]
	};
	$Directive{replace} = {
		substitution => 1,
		arg    => 0,
		content=> 1,
		parse  => 'p',
		option => [ qw(alt height width scale align target) ]
	};

	#----------------------------------------------------------------------
	$Directive{caution} = {
		arg    => 0,
		content=> 1,
		option => [ qw(class name) ]
	};

	#======================================================================
	#======================================================================
	foreach(keys(%Directive)) {
		my $d = $Directive{$_};
		$d->{option} = { map {$_ => 1} @{$d->{option}} };
	}
	#======================================================================
	return $Directive{$type};
}
###############################################################################
# ■ディレクティブの処理
###############################################################################
#------------------------------------------------------------------------------
# image
#------------------------------------------------------------------------------
sub image_directive {
	my $self  = shift;
	my $block = shift;
	my $arg   = shift;
	my $opt   = shift;

	my $file = join('', @$arg);
	$file =~ s/ //g;
	
	my @ary;
	push(@ary, "file = $file<br>");
	foreach(keys(%$opt)) {
		push(@ary, "	opt $_=$opt->{$_}<br>");
	}
	foreach(@$block) {
		push(@ary, "	>> $_<br>");
	}
	return \@ary;
}

#------------------------------------------------------------------------------
# replace
#------------------------------------------------------------------------------
sub replace_directive {
	my $self  = shift;
	my $block = shift;
	return $block;
}

#------------------------------------------------------------------------------
# caution
#------------------------------------------------------------------------------
sub caution_directive {
	my $self  = shift;
	my $block = shift;
	my $arg   = shift;
	my $opt   = shift;

	my $file = join('', @$arg);
	$file =~ s/ //g;
	
	my @ary;
	push(@ary, "file = $file<br>");
	foreach(keys(%$opt)) {
		push(@ary, "	opt $_=$opt->{$_}<br>");
	}
	foreach(@$block) {
		push(@ary, "	>> $_<br>");
	}
	return \@ary;
}


1;
