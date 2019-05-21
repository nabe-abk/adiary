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
	if ($type ne 'image' && ($subst eq '' && $d->{subst})) {
		$self->parse_error('"%s" directive can only be used within a substitution definition', $type);
		return;
	}
	if ($type ne 'image' && ($subst ne '' && !$d->{subst})) {
		$self->parse_error('Substitution definition empty or invalid: %s / %s directive', $subst, $type);
		$subst='';	# 置換定義は失敗だが、出力自体は行う
	}

	#-----------------------------------------
	# argument
	#-----------------------------------------
	my $arg;
	if ($d->{arg}) {
		while(@$block && $block->[0] ne '' && $block->[0] !~ /^:\w+:/) {
			$arg .= ' ' . shift(@$block);
		}
		$arg =~ s/^ +//;
		$arg =~ s/ +$//;
		$arg =~ s/  +/ /g;
		if ($arg eq '') {
			$arg = $d->{default};
			if (!defined $arg) {
				$self->parse_error('"%s" directive argument required', $type);
				return;
			}
		}
	}

	#-----------------------------------------
	# option
	#-----------------------------------------
	my $option = {};
	while(@$block && $block->[0] =~ /^:(\w+):(?: +(.*)|$)/) {
		shift(@$block);
		my $opt = $1;
		my $v   = $2;
		$opt =~ tr/A-Z/a-z/;
		while(@$block && $block->[0] =~ /^ +(.*)/) {
			shift(@$block);
			$v .= ($v ne '' ? ' ' : '') . $1;
		}
		if (! $d->{option}->{$opt}) {
			$self->parse_error('"%s" directive unknown option: %s', $type, $opt);
			return;
		}
		if (exists($option->{$opt})) {
			$self->parse_error('"%s" directive duplicate option: %s', $type, $opt);
			return;
		}
		$option->{$opt} = $v;
	}
	$option->{_subst} = ($subst ne '');

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
		my $text = join(' ', @$block);
		my ($ary, $blocks) = $self->do_parse_block([], $block, 'list-item');
		if ($#$blocks != 0 || $blocks->[0] ne $p) {
			$self->parse_error('"%s" directive may contain a single %s only: %s', $type, $p, $text);
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
	$self->{directive} = $type;		# used by error message
	my $name = $d->{method} || $type . '_directive';
	my $ret  = $self->$name($block, $arg, $option, $type);
	my $ary = ref($ret) ? $ret : [$ret];

	if ($subst ne '') {
		my $text = join('', @$ary);
		my $ss   = $self->{substitutions};
		if (exists($ss->{$subst})) {
			$self->parse_error('Duplicate substitution definition name: %s', $subst);
		}
		my $key = $self->generate_key_from_label($subst);
		$self->{substitutions}->{$subst} = {
			text  => $text,
			ltrim => exists($option->{trim}) || exists($option->{ltrim}),
			rtrim => exists($option->{trim}) || exists($option->{rtrim})
		};
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
	# image
	#----------------------------------------------------------------------
	$Directive{image} = {
		arg     => 1,
		content => 0,
		option  => [ qw(alt height width scale align target class name) ]
	};

	#----------------------------------------------------------------------
	# with substitution
	#----------------------------------------------------------------------
	$Directive{replace} = {
		subst   => 1,
		arg     => 0,
		content => 1,
		parse   => 'p',
		option  => [ qw(alt height width scale align target) ]
	};
	$Directive{unicode} = {
		subst   => 1,
		arg     => 1,
		content => 0,
		option  => [ qw(ltrim rtrim trim) ]
	};
	$Directive{date} = {
		subst   => 1,
		arg     => 1,
		default => '%Y-%m-%d',
		content => 0
	};

	#----------------------------------------------------------------------
	# admonition
	#----------------------------------------------------------------------
	{
		my @ary = qw(attention caution danger error hint important note tip warning admonition class name);
		my $h = {
			arg     => 0,
			content => 1,
			method  => 'admonition_directive',
			option  => [ qw(class name) ]
		};
		foreach(@ary) {
			$Directive{$_} = $h;
		}
	}

	#======================================================================
	#======================================================================
	foreach(keys(%Directive)) {
		my $d = $Directive{$_};
		if (ref($d->{option}) ne 'ARRAY') { next; }
		$d->{option} = { map {$_ => 1} @{$d->{option}} };
	}
	#======================================================================
	return $Directive{$type};
}
###############################################################################
# ■ディレクティブの処理
###############################################################################
#//////////////////////////////////////////////////////////////////////////////
# iamge
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# image
#------------------------------------------------------------------------------
sub image_directive {
	my $self  = shift;
	my $block = shift;
	my $_file = shift;
	my $opt   = shift;
	$_file =~ s/ //g;
	my $file = $self->{image_path} . $_file;

	my $attr='';
	my $class='';
	my $alt = $_file;
	if ($opt->{alt} ne '') {
		$alt = $opt->{alt};
		$self->tag_escape($alt);
		$attr .= " alt=\"$alt\"";
	}
	if (exists($opt->{align})) {
		my $a = $opt->{align};
		$a =~ tr/A-Z/a-z/;
		if (!$opt->{_subst} && $a ne 'left' && $a ne 'center' && $a ne 'right') {
			return $self->invalid_option_error($opt, 'align');
		}
		if ( $opt->{_subst} && $a ne 'top' && $a ne 'middle' && $a ne 'bottom') {
			return $self->invalid_option_error($opt, 'align');
		}
		$class .= " align-$a";
	}

	my $scale;
	if (exists($opt->{scale})) {
		if ($opt->{scale} !~ /^(\d+) *%?$/) {
			return $self->invalid_option_error($opt, 'scale');
		}
		$scale = $1 / 100;
	}
	my $w;
	my $h;
	if (exists($opt->{width})) {
		if ($opt->{width} !~ /^(\d+|\d*\.\d+)$/) {
			return $self->invalid_option_error($opt, 'width');
		}
		$w = $1;
	}
	if (exists($opt->{height})) {
		if ($opt->{height} !~ /^(\d+|\d*\.\d+)$/) {
			return $self->invalid_option_error($opt, 'height');
		}
		$h = $1;
	}
	if ($scale ne '') {
		if ($w eq '' || $h eq '') {
			my ($x,$y) = $self->get_image_size($file);
			$w = $w ne '' ? $w : $x;
			$h = $h ne '' ? $h : $y;
		}
		if ($w eq '' || $h eq '') {
			$self->parse_error('"%s" directive ignore "scale" option. Please use with "width" and "height" options');
		} else {
			$w = $w * $scale;
			$h = $h * $scale;
		}
	}
	if ($w ne '') {
		$attr .= " width=\"$w\"";
	}
	if ($h ne '') {
		$attr .= " height=\"$h\"";
	}

	my $at = $self->make_name_and_class_attr($opt, $class);
	my $tag = "<img src=\"$file\"$attr>";

	my $url = $opt->{_subst} ? '' : $file;
	if (exists($opt->{target})) {
		my $t = $opt->{target};
		if ($t eq '') {
			return $self->invalid_option_error($opt, 'target');
		}
		if ((my $z = $self->check_link_label($t)) ne '') {
			return "\x02link\x02$z\x02$tag\x02$at\x02img\x02$alt\x02";
		}
		$url = $t;
		$url =~ s/ //g;
	} else {
		$at .= $self->{current_image_attr};
	}

	return $url ne '' ? "<a href=\"$url\"$at>$tag</a>" : "<span$at>$tag</span>";
}

sub get_image_size {
	my $self  = shift;
	my $file  = $self->{ROBJ}->get_filepath( shift );

	my ($x,$y);
	eval {
		require Image::Magick;
		my $im = Image::Magick->new(@_);
		$im->Read( $file );
		($x,$y) = $im->Get('width', 'height');
	};
	return ($x,$y);
}

#//////////////////////////////////////////////////////////////////////////////
# with substitution
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# replace
#------------------------------------------------------------------------------
sub replace_directive {
	my $self  = shift;
	my $block = shift;
	return $block;
}

#------------------------------------------------------------------------------
# unicode
#------------------------------------------------------------------------------
sub unicode_directive {
	my $self  = shift;
	my $block = shift;
	my $text  = shift;
	my $opt   = shift;

	$text =~ s/ *\.\. .*//;
	$text =~ s/(?:^| +)(?:0x|x|\\x|U\+|u|\\u|&#x)([A-Fa-f0-9]+)|(\d+)(?= |$)/
		my $d = $2 ne '' ? $2 : hex($1);
		"\x{03}38#$d;";		# 38 = '&'
	/egi;
	$text =~ s/ +\x03/\x03/g;
	$text =~ s/(\x{03}38#\d+;) +/$1/g;

	foreach(qw(trim ltrim rtrim)) {
		if ($opt->{$_} eq '') { next; }
		return $self->invalid_option_error($opt, $_);
	}
	return $text;
}

#------------------------------------------------------------------------------
# date
#------------------------------------------------------------------------------
sub date_directive {
	my $self  = shift;
	my $block = shift;
	my $arg   = shift;

	require POSIX;
	return POSIX::strftime($arg, localtime());
}

#//////////////////////////////////////////////////////////////////////////////
# admonitions
#//////////////////////////////////////////////////////////////////////////////
sub admonition_directive {
	my $self  = shift;
	my $block = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $type  = shift;
	my $at    = $self->make_name_and_class_attr($opt);

	my @ary;
	push(@ary, "<div class=\"admonition $type\"$at>\x02");
	push(@ary, "<p class=\"admonition-title\">$type:</p>");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</div>\x02", '');
	return \@ary;
}

###############################################################################
# ■ subroutine
###############################################################################
sub make_name_and_class_attr {
	my $self   = shift;
	my $option = shift;
	my $class  = shift || '';

	my $attr = '';
	#-----------------------------------------
	# option check
	#-----------------------------------------
	if ($option->{name} ne '') {
		my $label = $option->{name};
		my $base = $self->generate_id_from_string( $label );
		my $id   = $self->generate_link_id( $base );
		my $key  = $self->generate_key_from_label_with_tag_escape( $label );

		my $links = $self->{links};
		if ($links->{$key}) {
			my $msg = $self->parse_error('Duplicate link target name: %s', $label);
			$links->{$key}->{error} = $msg;
			$links->{$key}->{duplicate} = 1;
		} else {
			$links->{$key} = {
				type => 'link',
				id   => $id
			};
			$attr .= " id=\"$id\"";
		}
	}
	if ($option->{class} ne '') {
		my $c = $self->generate_id_from_string( $option->{class} );
		$class .= " $c";
	}
	if ($class ne '') {
		$class =~ s/^ +//;
		$attr .= " class=\"$class\"";
	}
	return $attr;
}

#------------------------------------------------------------------------------
# invalid option
#------------------------------------------------------------------------------
sub invalid_option_error {
	my $self = shift;
	my $opt  = shift;
	my $name = shift;
	my $v = $opt->{$name};
	$v = $v eq '' ? '(none)' : $v;
	$self->parse_error('"%s" directive "%s" option invalid value: %s', $self->{directive}, $name, $v);
	return;
}


1;
