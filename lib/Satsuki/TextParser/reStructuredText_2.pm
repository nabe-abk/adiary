use strict;
#------------------------------------------------------------------------------
# Split from Satsuki::TextParser::reStructuredText.pm for AUTOLOAD.
#------------------------------------------------------------------------------
use Satsuki::TextParser::reStructuredText ();
package Satsuki::TextParser::reStructuredText;
###############################################################################
# ■ディレクティブのパース
###############################################################################
my %Directive;
my $NONE     = 0;
my $ANY      = 1;
my $REQUIRED = 2;
#------------------------------------------------------------------------------
# parse directive
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
		while(@$block && $block->[0] ne ''
		  && ($block->[0] !~ /^:((?:\\.|[^:\\])+):(?: +(.*)|$)/  || substr($1,0,1) eq ' ' ||  substr($1,-1) eq ' ')
		) {
			$arg .= ' ' . shift(@$block);
		}
		$arg =~ s/^ +//;
		$arg =~ s/ +$//;
		$arg =~ s/  +/ /g;
		if ($arg eq '' && $d->{arg}==$REQUIRED) {
			$arg = $d->{default};
			if (!defined $arg) {
				$self->parse_error('"%s" directive argument required', $type);
				return;
			}
		} elsif ($d->{arg_max}) {
			my @a = split(/ /, $arg);
			my $c = $#a +1;
			if ($d->{arg_max} < $c) {
				$self->parse_error('"%s" maximum %d argument(s) allowed, %d supplied: %s', $type, $d->{arg_max}, $c, $arg);
				return;
			}
		}
	}

	#-----------------------------------------
	# option
	#-----------------------------------------
	my $opt = {};
	if ($d->{option}) {
		while(@$block && $block->[0] =~ /^:((?:\\.|[^:\\])+):(?: +(.*)|$)/  && substr($1,0,1) ne ' ' &&  substr($1,-1) ne ' ') {
			shift(@$block);
			my $k = $1;
			my $v = $2;
			$k =~ tr/A-Z/a-z/;
			$self->backslash_process($k);

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
		if (%$opt && @$block && $block->[0] ne '') {
			$self->parse_error('"%s" invalid option block: %s', $type, $block->[0]);
			return;
		}
	}
	$opt->{_subst} = ($subst ne '');

	#-----------------------------------------
	# content
	#-----------------------------------------
	while(@$block && $block->[0] eq '') { shift(@$block); }

	if ($d->{content}==$NONE && @$block) {
		$self->parse_error('"%s" directive no content permitted: %s', $type, $block->[0]);
		return;
	}
	if ($d->{content}==$REQUIRED && !@$block) {
		$self->parse_error('"%s" directive content required', $type);
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
	$name =~ tr/-/_/;
	my $ret  = $self->$name($arg, $opt, $block, $type);
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
	# option values
	#----------------------------------------------------------------------
	my $OPT_DEFAULT = { map { $_ => 1} qw(class name) };
	my $OPT_NONE    = undef;

	#----------------------------------------------------------------------
	# Admonitions
	#----------------------------------------------------------------------
	{
		my @ary = qw(attention caution danger error hint important note tip warning class name);
		my $h = {
			arg     => $NONE,
			content => $REQUIRED,
			method  => 'admonition_directive',
			option  => $OPT_DEFAULT
		};
		foreach(@ary) {
			$Directive{$_} = $h;
		}
	}
	$Directive{admonition} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		method  => 'topic_directive',
		option  => $OPT_DEFAULT
	};

	#----------------------------------------------------------------------
	# Images
	#----------------------------------------------------------------------
	$Directive{image} = {
		arg     => $REQUIRED,
		content => $NONE,
		option  => [ qw(alt height width scale align target class name) ]
	};
	$Directive{figure} = {
		arg     => $REQUIRED,
		content => $ANY,
		option  => [ qw(alt height width scale align target class name figwidth figclass) ]
	};

	#----------------------------------------------------------------------
	# Body Elements
	#----------------------------------------------------------------------
	$Directive{topic} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		option  => $OPT_DEFAULT
	};
	$Directive{'parsed-literal'} = {
		arg     => $NONE,
		content => $REQUIRED,
		option  => $OPT_DEFAULT
	};
	$Directive{code} = {
		arg     => $ANY,
		arg_max => 1,
		content => $REQUIRED,
		option  =>  [ qw(number-lines name class) ]
	};
	$Directive{math} = {
		arg     => $ANY,
		content => $ANY,
		option  =>  [ qw(name) ]
	};
	$Directive{rubric} = {
		arg     => $REQUIRED,
		content => $NONE,
		option  => $OPT_DEFAULT
	};
	# Quote directive
	{
		my @ary = qw(epigraph highlights pull-quote);
		my $h = {
			arg     => $NONE,
			content => $REQUIRED,
			method  => 'quote_directive',
			option  => $OPT_NONE
		};
		foreach(@ary) {
			$Directive{$_} = $h;
		}
	};
	$Directive{compound} = {
		arg     => $NONE,
		content => $REQUIRED,
		method  => 'div_directive',
		option  => $OPT_DEFAULT
	};
	$Directive{container} = {
		arg     => $ANY,
		content => $REQUIRED,
		method  => 'div_directive',
		option  => [ qw(name) ]
	};

	#----------------------------------------------------------------------
	# Tables
	#----------------------------------------------------------------------

	#----------------------------------------------------------------------
	# Document Parts
	#----------------------------------------------------------------------

	#----------------------------------------------------------------------
	# References
	#----------------------------------------------------------------------

	#----------------------------------------------------------------------
	# for Substitution Definitions
	#----------------------------------------------------------------------
	$Directive{replace} = {
		subst   => 1,
		arg     => $NONE,
		content => $REQUIRED,
		parse   => 'p',
		option  => [ qw(alt height width scale align target) ]
	};
	$Directive{unicode} = {
		subst   => 1,
		arg     => $REQUIRED,
		content => $NONE,
		option  => [ qw(ltrim rtrim trim) ]
	};
	$Directive{date} = {
		subst   => 1,
		arg     => $REQUIRED,
		default => '%Y-%m-%d',
		content => $NONE
	};

	#----------------------------------------------------------------------
	# Miscellaneous
	#----------------------------------------------------------------------

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
# ■各ディレクティブの処理
###############################################################################
#//////////////////////////////////////////////////////////////////////////////
# ●Admonitions
#//////////////////////////////////////////////////////////////////////////////
sub admonition_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;
	my $type  = shift;

	my $at = $self->make_name_and_class_attr($opt, "admonition $type");
	my @ary;
	push(@ary, "<div$at>\x02");
	push(@ary, "<p class=\"admonition-title\">$type:</p>");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</div>\x02", '');
	return \@ary;
}

#//////////////////////////////////////////////////////////////////////////////
# ●Iamges
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# image
#------------------------------------------------------------------------------
sub image_directive {
	my $self  = shift;
	my $_file = shift;
	my $opt   = shift;
	my $block = shift;
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
	my $_file = shift;
	my $opt   = shift;
	my $block = shift;
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

	my $img = $self->image_directive($_file, $opt, $block);
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
# ●Body Elements
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# topic
#------------------------------------------------------------------------------
sub topic_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;
	my $block = shift;
	my $type  = shift;

	$self->backslash_escape($title);
	$self->tag_escape($title);
	if ($type eq 'admonition') {
		$title .= ':';
	}

	my $at = $self->make_name_and_class_attr($opt, $type);
	my @ary;
	push(@ary, "<div$at>\x02");
	push(@ary, "<p class=\"$type-title\">$title:</p>");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</div>\x02", '');
	return \@ary;
}

#------------------------------------------------------------------------------
# parsed-literal
#------------------------------------------------------------------------------
sub parsed_literal_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;

	$self->backslash_escape(@$block);
	$self->tag_escape(@$block);

	my $at = $self->make_name_and_class_attr($opt, 'parsed-literal');
	my @ary;
	push(@ary, "<pre$at>\x02");
	push(@ary, @$block);
	push(@ary, "</pre>\x02", '');
	return \@ary;
}

#------------------------------------------------------------------------------
# parsed-literal
#------------------------------------------------------------------------------
sub code_directive {
	my $self  = shift;
	my $lang  = shift;
	my $opt   = shift;
	my $block = shift;

	foreach (@$block) {
		$self->tag_escape($_);
		$_ =~ s/\\/&#92;/g;	# escape backslash
		$_ .= "\x02";
	}

	my $num='';
	my $class='syntax-highlight';
	if (exists($opt->{'number-lines'})) {
		$num = $opt->{'number-lines'};
		if ($num ne '') {
			if ($num !~ /^(-?\d+)$/) {
				$self->invalid_option_error($opt, 'number-lines');
			}
		} else {
			$num = 1;
		}
		$num = " data-number=\"$num\"";
		$class .= ' line-number';
	}

	# <pre class="syntax-highlight python"></pre>

	if ($lang ne '') {
		$self->normalize_class_string( $lang );
		$class .= " $lang";
	}

	my $at = $self->make_name_and_class_attr($opt, $class);
	my @ary;
	push(@ary, "<pre$at$num>\x02");
	push(@ary, @$block);
	push(@ary, "</pre>\x02", '');
	return \@ary;
}

#------------------------------------------------------------------------------
# math
#------------------------------------------------------------------------------
sub math_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;

	push(@$block, $arg);
	foreach (@$block) {
		$self->tag_escape($_);
		$_ .= ($_ ne '') ? "\x02" : '';
	}
	$arg = pop(@$block);

	if (@$block) {
		my $text = join('', @$block);
		if ($text =~ /\\\\/) {
			unshift(@$block, "\\begin{split}\x02");
			push   (@$block, "\\end{split}\x02");
		}
	}
	if ($arg ne '') {
		if (@$block) {
			unshift(@$block, "$arg\\\\\x02");
			unshift(@$block, "\\begin{align}\\begin{aligned}\x02");
			push   (@$block, "\\end{aligned}\\end{align}\x02");
		} else {
			$block = [ $arg ];
		}
	} 

	my $at = $self->make_name_and_class_attr($opt, 'math');
	my @ary;
	push(@ary, "<div$at>\x02");
	push(@ary, @$block);
	push(@ary, "</div>\x02", '');
	return \@ary;
}

#------------------------------------------------------------------------------
# 注釈 / rubric
#------------------------------------------------------------------------------
sub rubric_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;

	my $at = $self->make_name_and_class_attr($opt, 'rubric');
	return "<p$at>$arg</p>";
}

#------------------------------------------------------------------------------
# epigraph, highlights, pull-quote
#------------------------------------------------------------------------------
sub quote_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;
	my $type  = shift;

	my $at = $self->make_name_and_class_attr($opt, $type);
	my @ary;
	push(@ary, "<blockquote$at>\x02");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</blockquote>\x02", '');
	return \@ary;
}

#------------------------------------------------------------------------------
# compound, container
#------------------------------------------------------------------------------
sub div_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;
	my $class = shift;

	if ($arg ne '') {
		$class .= ' ' . $self->normalize_class_string($arg);
	}
	my $at = $self->make_name_and_class_attr($opt, $class);
	my @ary;
	push(@ary, "<div$at>\x02");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</div>\x02", '');
	return \@ary;
}

#//////////////////////////////////////////////////////////////////////////////
# ●for Substitution
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# replace
#------------------------------------------------------------------------------
sub replace_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;
	return $block;
}

#------------------------------------------------------------------------------
# unicode
#------------------------------------------------------------------------------
sub unicode_directive {
	my $self  = shift;
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
	my $arg   = shift;

	require POSIX;
	return POSIX::strftime($arg, localtime());
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
