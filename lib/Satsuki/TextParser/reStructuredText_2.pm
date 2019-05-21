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
	my $opt = {};
	while(@$block && $block->[0] =~ /^:(\w+):(?: +(.*)|$)/) {
		shift(@$block);
		my $k = $1;
		my $v = $2;
		$k =~ tr/A-Z/a-z/;
		while(@$block && $block->[0] =~ /^ +(.*)/) {
			shift(@$block);
			$v .= ($v ne '' ? ' ' : '') . $1;
		}
		if (! $d->{option}->{$k}) {
			$self->parse_error('"%s" directive unknown option: %s', $type, $k);
			return;
		}
		if (exists($opt->{$k})) {
			$self->parse_error('"%s" directive duplicate option: %s', $type, $k);
			return;
		}
		$opt->{$k} = $v;
	}
	$opt->{_subst} = ($subst ne '');

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
	my $ret  = $self->$name($block, $arg, $opt, $type);
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
			ltrim => exists($opt->{trim}) || exists($opt->{ltrim}),
			rtrim => exists($opt->{trim}) || exists($opt->{rtrim})
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
	$Directive{figure} = {
		arg     => 1,
		content => 1,
		option  => [ qw(alt height width scale align target class name figwidth figclass) ]
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
	}
	$attr .= " alt=\"$alt\"";

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
	my $wp;
	if (exists($opt->{width})) {
		if ($opt->{width} !~ /^(\d+|\d*\.\d+) *(%?)$/) {
			return $self->invalid_option_error($opt, 'width');
		}
		$w = $1;
		$wp= $2;
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
			$self->ignore_option_error('scale');
		} else {
			$w = $w * $scale;
			$h = $h * $scale;
		}
	}
	if ($w ne '') {
		$attr .= " width=\"$w$wp\"";
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
	my $self = shift;
	my $file = $self->{ROBJ}->get_filepath( shift );

	my $cache = $self->{_image_size_cache} ||= {};
	if (! $cache->{$file}) {
		eval {
			require Image::Magick;
			my $im = Image::Magick->new(@_);
			$im->Read( $file );
			my ($x,$y) = $im->Get('width', 'height');
			$cache->{$file} = [ $x, $y ];
		};
	}
	return @{ $cache->{$file} }
}

#------------------------------------------------------------------------------
# figure
#------------------------------------------------------------------------------
sub figure_directive {
	my $self  = shift;
	my $block = shift;
	my $_file = shift;
	my $opt   = shift;
	$_file =~ s/ //g;
	my $file = $self->{image_path} . $_file;

	my $attr='';
	my $class='';
	my $center;
	if (exists($opt->{align})) {
		my $a = $opt->{align};
		$a =~ tr/A-Z/a-z/;
		if ($a ne 'left' && $a ne 'center' && $a ne 'right') {
			return $self->invalid_option_error($opt, 'align');
		}
		$class .= " align-$a";
		$center = ($a eq 'center');
		delete $opt->{align};
	}

	if (exists($opt->{figwidth})) {
		if ($opt->{figwidth} =~ /^image$/i) {
			my ($x,$y) = $self->get_image_size($file);
			if ($x eq '') {
				$self->ignore_option_error('figwidth');
			} else {
				$attr .= " style=\"width: ${x}px;\"";
			}
		} else {
			if ($opt->{figwidth} !~ /^(\d+|\d*\.\d+) *(%?)$/) {
				return $self->invalid_option_error($opt, 'figwidth');
			}
			my $unit = $2 ? $2 : 'px';
			$attr .= " style=\"width: $1$unit;\"";
		}
	} elsif ($center) {
		my ($x,$y) = $self->get_image_size($file);
		if ($x eq '') {
			$self->ignore_option_error('align');
		} else {
			$attr .= " style=\"width: ${x}px;\"";
		}
	}
	if ($opt->{figclass} ne '') {
		my $c = $self->normalize_class_string( $opt->{figclass} );
		$class .= " $c";
	}

	my $img = $self->image_directive($block, $_file, $opt);
	if ($img eq '') { return; }

	if ($class) {
		$attr .= ' class="' . substr($class,1) . '"';
	}

	if (!@$block) {
		return qq|<figure$attr>$img</figure>|;
	}

	#---------------------------------------------------------
	# figcaption and legend
	#---------------------------------------------------------
	my @caption;
	while(@$block && $block->[0] ne '') {
		push(@caption, shift(@$block));
	}

	my $caption='';
	my $content='';
	my $text = join(' ', @caption);
	if ($text ne '..') {
		my ($ary, $blocks) = $self->do_parse_block([], \@caption, 'list-item');
		if ($#$blocks != 0 || $blocks->[0] ne 'p') {
			$self->parse_error('"%s" directive caption must be a paragraph or empty comment: %s', $self->{directive}, $text);
			return;
		}
		$caption = '<figcaption>' . join("\n", @$ary) . '</figcaption>';
		while(@$block && $block->[0] eq '') {
			shift(@$block);
		}
	}

	if (@$block) {
		my $ary = $self->parse_nest_block_with_tag([], $block, "<div class=\"legend\">", "</div>");
		$content = join("\n", @$ary);
	}
	$caption .= ($caption && $content ne '') ? "\n" : '';

	return qq|<figure$attr>$img\n$caption$content</figure>|;
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
	my $self  = shift;
	my $opt   = shift;
	my $class = shift || '';

	my $attr = '';
	#-----------------------------------------
	# option check
	#-----------------------------------------
	if ($opt->{name} ne '') {
		my $label = $opt->{name};
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
	if ($opt->{class} ne '') {
		my $c = $self->normalize_class_string( $opt->{class} );
		$class .= " $c";
	}
	if ($class ne '') {
		$class =~ s/^ +//;
		$attr .= " class=\"$class\"";
	}
	return $attr;
}

#------------------------------------------------------------------------------
# class name
#------------------------------------------------------------------------------
sub normalize_class_string {
	my $self  = shift;
	my $class = shift;
	$class =~ tr/A-Z/a-z/;
	$class =~ s/[^\w\-\.\x80-\xff ]+/-/g;
	$class =~ s/  +/ /g;
	return $class;
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

#------------------------------------------------------------------------------
# ignore option
#------------------------------------------------------------------------------
sub ignore_option_error {
	my $self = shift;
	my $opt  = shift;
	my $name = shift;
	my $v = $opt->{$name};
	$v = $v eq '' ? '(none)' : $v;
	$self->parse_error('"%s" directive ignore "%s" option: %s', $self->{directive}, $name, $v);
	return;
}


1;
