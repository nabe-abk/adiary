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
			$arg = $self->join_line($arg, shift(@$block));
		}
		$arg =~ s/\n/ /g;
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

			# multi line option
			{
				my @ary;
				my $min;
				while(@$block && $block->[0] =~ /^( +)/) {
					push(@ary, shift(@$block));
					my $l = length($1);
					if (!defined $min || $l<$min) {
						$min = $l;
					}
				}

				if ($d->{keep_lf}->{$k}) {	# 改行を保持する
					foreach(@ary) {
						$_ = substr($_, $min);
						$v = $self->join_line($v, $_);
					}
				} else {
					foreach(@ary) {
						$_ =~ s/^ +//;
						$v = $self->join_line($v, $_, ' ');
					}
				}
			}

			if (! $d->{option}->{$k}) {
				$self->parse_error('"%s" directive unknown option: %s', $type, $k);
				return;
			}
			if (exists($opt->{$k})) {
				$self->parse_error('"%s" directive duplicate option: %s', $type, $k);
				return;
			}
			if (! $d->{keep_lf}->{$k}) {
				$v =~ s/\n/ /g;
			}
			$opt->{$k} = $v;
		}
		if (%$opt && @$block && $block->[0] ne '') {
			$self->parse_error('"%s" invalid option block: %s', $type, $block->[0]);
			return;
		}
		if (exists($opt->{class})) {
			my $c = $self->normalize_class_string( $opt->{class} );
			if ($c eq '') {
				return $self->invalid_option_error($opt, 'class');
			}
			$opt->{_class} = $c;
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
	$Directive{table} = {
		arg     => $ANY,
		content => $REQUIRED,
		parse   => 'table',
		option  => $OPT_DEFAULT
	};
	$Directive{'csv-table'} = {
		arg     => $ANY,
		content => $REQUIRED,
		option  => [ qw(widths header-rows stub-columns header file url encoding delim quote keepspace escape class name) ],
		keep_lf => [ qw(header) ]
	};

	#----------------------------------------------------------------------
	# Document Parts
	#----------------------------------------------------------------------
	$Directive{contents} = {
		arg     => $ANY,
		content => $NONE,
		option  => [ qw(depth local backlinks class) ]
	};

	#----------------------------------------------------------------------
	# References
	#----------------------------------------------------------------------
	# NOT IMPLEMENTED YET on Sphinx
	#	footnotes, citations

	#----------------------------------------------------------------------
	# HTML-Specific
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
		if (ref($d->{option}) eq 'ARRAY') {
			$d->{option} = { map {$_ => 1} @{$d->{option}} };
		}
		if (ref($d->{keep_lf}) eq 'ARRAY') {
			$d->{keep_lf} = { map {$_ => 1} @{$d->{keep_lf}} };
		}
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
	my $file = $self->check_and_load_file_path($_file);
	if (!defined $file) { return; }

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
			$self->ignore_option_error($opt, 'scale');
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
	my $file = $self->check_and_load_file_path($_file);
	if (!defined $file) { return; }

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
				$self->ignore_option_error($opt, 'figwidth');
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
			$self->ignore_option_error($opt, 'align');
		} else {
			$attr .= " style=\"width: ${x}px;\"";
		}
	}
	if ($opt->{figclass} ne '') {
		my $c = $self->normalize_class_string( $opt->{figclass} );
		if ($c eq '') {
			return $self->invalid_option_error($opt, 'figclass');
		}
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
	push(@ary, "<p class=\"$type-title\">$title</p>");
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
		$class = $self->append_and_normalize_class_string( $class, $lang );
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
		$class = $self->append_and_normalize_class_string( $class, $arg );
	}
	my $at = $self->make_name_and_class_attr($opt, $class);
	my @ary;
	push(@ary, "<div$at>\x02");
	$self->do_parse_block(\@ary, $block, 'nest');
	push(@ary, "</div>\x02", '');
	return \@ary;
}

#//////////////////////////////////////////////////////////////////////////////
# ●Table Elements
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# table
#------------------------------------------------------------------------------
sub table_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;
	my $block = shift;

	if ($title eq '') { return $block; }
	if ($block->[0] !~ /^<table/i) {
		unshift(@$block, '!! Internal error on table directive !!');
		return $block;
	}

	$self->backslash_escape($title);
	$self->tag_escape($title);

	my $x = shift(@$block);
	unshift(@$block, "<caption>$title</caption>");
	unshift(@$block, $x);
	return $block;
}

#------------------------------------------------------------------------------
# csv-table
#------------------------------------------------------------------------------
sub csv_table_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;
	my $block = shift;

	my $delim  = exists($opt->{delim}) ? $opt->{delim} : ',';
	my $quote  = exists($opt->{quote}) ? $opt->{quote} : '"';
	my $escape = $opt->{escape};
	$self->decode_unicode_symbol($delim, $quote, $escape);

	if (exists($opt->{delim})  && (length($delim)  != 1 || $delim eq $quote || $delim eq $escape)) {
		return $self->invalid_option_error($opt, 'delim');
	}
	if (exists($opt->{quote})  && (length($quote)  != 1 || $quote eq $delim || $quote eq $escape)) {
		return $self->invalid_option_error($opt, 'quote');
	}
	if (exists($opt->{escape}) && (length($escape) != 1 || $delim eq $escape || $quote eq $escape)) {
		return $self->invalid_option_error($opt, 'escape');
	}
	if ($opt->{keepspace} ne '') {
		return $self->invalid_option_error($opt, 'keepspace');
	}
	
	if ($title ne '') {
		$self->backslash_escape($title);
		$self->tag_escape($title);
	}

	my $h_rows   = 0;
	my $stub_cols= 0;
	if (exists($opt->{'header-rows'})) {
		$h_rows = $opt->{'header-rows'};
		if ($h_rows !~ /^\d+$/) {
			return $self->invalid_option_error($opt, 'header-rows');
		}
	}
	if (exists($opt->{'stub-columns'})) {
		$stub_cols = $opt->{'stub-columns'};
		if ($stub_cols !~ /^\d+$/) {
			return $self->invalid_option_error($opt, 'stub-columns');
		}
	}

	my @widths;
	if (exists($opt->{widths})) {
		if ($opt->{widths} eq '') {
			return $self->invalid_option_error($opt, 'widths');
		}
		@widths = split(/ *, */, $opt->{widths});
		my $total  = 0;
		foreach(@widths) {
			if ($_ !~ /^\d+$/ || $_ == 0) {
				return $self->invalid_option_error($opt, 'widths');
			}
			$total += $_;
		}
		foreach(@widths) {
			$_ = int($_*100/$total + 0.5) . '%';
		}
	}

	#------------------------------------------------------
	# header
	#------------------------------------------------------
	my $header;
	my $h_max_cols;
	if ($opt->{header} ne '') {
		my ($rows, $min_cols, $max_cols) = $self->parse_cvs_data([ split(/\n/, $opt->{header}) ], ',', '"', '', exists($opt->{keepspace}));
		if (!$rows) { return; }
		$header = $rows;
		$h_max_cols = $max_cols;
	}

	#------------------------------------------------------
	# parse cvs
	#------------------------------------------------------
	my ($rows, $min_cols, $max_cols) = $self->parse_cvs_data($block, $delim, $quote, $escape, exists($opt->{keepspace}), 'delim check');
	if (!$rows) { return; }

	# stub-columns の $min_cols は body のみ判定
	# widths の $max_cols は header を含めて判定
	if ($header && $max_cols < $h_max_cols) {
		$max_cols = $h_max_cols;
	}

	#------------------------------------------------------
	# check header-rows, stub-columns, widths
	#------------------------------------------------------
	if ($h_rows && $#$rows < $h_rows) {
		return $self->invalid_option_error($opt, 'header-rows');
	}
	if ($stub_cols && $min_cols <= $stub_cols) {
		return $self->invalid_option_error($opt, 'stub-columns');
	}
	if (@widths) {
		if ($#widths+1 != $max_cols) {
			return $self->invalid_option_error($opt, 'widths');
		}
	}

	#------------------------------------------------------
	# output table
	#------------------------------------------------------
	if ($header) {
		unshift(@$rows, @$header);
		$h_rows += $#$header + 1;
	}

	my $out = [];
	push(@$out, "<table>\x02");
	if ($title ne '') {
		push(@$out, "<caption>$title</caption>");
	}
	if (@widths) {
		push(@$out, "<colgroup>\x02");
		foreach(@widths) {
			push(@$out, "\t<col style=\"width: $_\">\x02");
		}
		push(@$out, "</colgroup>\x02");
	}
	push(@$out, $h_rows ? "<thead>\x02" :  "<tbody>\x02");
	my $td = $h_rows ? 'th' : 'td';

	foreach my $y (0..$#$rows) {
		my $row = $rows->[$y];
		if ($h_rows && $y==$h_rows) {
			push(@$out, "</thead><tbody>");
			$td = 'td';
		}
		push(@$out, "<tr>\x02");
		foreach(0..($max_cols-1)) {
			my $text = $row->[$_];
			my $t = $_<$stub_cols ? 'th' : $td;
			if ($text =~ /^[\n ]*$/) {
				push(@$out, "<$t>&ensp;</$t>");
				next;
			}
			$self->parse_nest_block_with_tag($out, [ split(/\n/, $text) ], "<$t>", "</$t>");
		}
		push(@$out, "</tr>\x02");
	}
	push(@$out, "</tbody>\x02");
	push(@$out, "</table>\x02");
	return $out;
}

sub parse_cvs_data {
	my $self   = shift;
	my $lines  = shift;
	my $delim  = shift;
	my $quote  = shift;
	my $escape = shift;
	my $keepspace = shift;
	my $delim_chk = shift;

	my @rows;
	my $min_cols;
	my $max_cols = -1;
	while(@$lines) {
		my $x = shift(@$lines);
		my @a = split(//, $x);

		my @cols;
		my $col='';
		my $last_c;
		my $q;
		while(@a || $q) {
			if ($q && !@a) {
				if (!@$lines) { last; }
				my $y = "\n" . shift(@$lines);
				@a = split(//, $y);
				$x .= $y;
			}
			my $c = shift(@a);
			$last_c = $c;
			if ($q) {
				# in quote
				if ($c eq $escape) {
					$col .= shift(@a);
					next;
				}
				if ($c ne $quote) {
					$col .= $c;
					next;
				}
				if ($a[0] eq $quote) {	# "xxx""yyy" --> xxx"yyy
					$col .= $quote;
					shift(@a);
					next;
				}
				# Quote end
				$q=0;
				if ($delim_chk && @a && $a[0] ne $delim) {
					$self->parse_error('"%s" directive error in CSV data \'%s\' expected after \'%s\': %s', $self->{directive}, $delim, $quote, $x);
					return;
				}
				next;
			} elsif ($c eq $delim) {
				push(@cols, $col);
				$col='';
				if (!$keepspace) {
					while(@a && $a[0] eq ' ') {
						shift(@a);
					}
				}
				next;

			} elsif ($c eq $escape) {
				$col .= shift(@a);
				next;

			} elsif ($col ne '') {
				# in column
				$col .= $c;
				next;
			}

			# not in column
			if ($c eq ' ') { next; }
			if ($c eq $quote) {
				$q = 1;
				next;
			}
			$col .= $c;
		}
		if ($q) {	# in quote
			$self->parse_error('"%s" directive error in CSV data, unexpected end of data quoted: %s', $self->{directive}, $x);
			return;
		}
		if ($col ne '' || $last_c eq $delim) {
			push(@cols, $col);
		}
		push(@rows, \@cols);
		if ($max_cols <= $#cols) {
			$max_cols = $#cols+1;
		}
		if (!defined $min_cols || $#cols <= $min_cols) {
			$min_cols = $#cols+1;
		}
	}
	return (\@rows, $min_cols, $max_cols);
}

#//////////////////////////////////////////////////////////////////////////////
# ●Document Parts
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# contents
#------------------------------------------------------------------------------
sub contents_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;

	my $attr='';
	my $class='contents topic';
	if (exists($opt->{depth})) {
		my $d = $opt->{depth};
		if ($d !~ /^\d+$/) {
			return $self->invalid_option_error($opt, 'depth');
		}
		$attr .= "depth=$d:"
	}
	if (exists($opt->{backlinks})) {
		my $b = $opt->{backlinks};
		$b =~ tr/A-Z/a-z/;
		if ($b ne 'entry' && $b ne 'top' && $b ne 'none') {
			return $self->invalid_option_error($opt, 'backlinks');
		}
		$attr .= "backlinks=$b:"
	}
	if (exists($opt->{local})) {
		if ($opt->{local} ne '') {
			return $self->invalid_option_error($opt, 'local');
		}
		my $sec = $self->{current_section};
		my $ary = $self->{local_sections};
		push(@$ary, $sec);
		$attr .= "local=$#$ary:";
		$class .= ' local';
	} elsif ($title eq '') {
		$title = 'Contents';
	}
	chop($attr);

	#---------------------------------------------------------
	# output
	#---------------------------------------------------------
	my $at = $self->make_name_and_class_attr($opt, $class);

	my @out;
	push(@out, "<div$at>\x02");
	if ($title ne '') {
		push(@out, "<p class=\"topic-title toc-title\">$title</p>");
	}
	push(@out, "\x02<toc>$attr</toc>\x02");
	push(@out, "</div>\x02");
	return \@out;
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
	if ($opt->{_class}) {
		$class .= ($class eq '' ? '' : ' ') . $opt->{_class};
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
sub append_and_normalize_class_string {
	my $self  = shift;
	my $class = shift;
	foreach(@_) {
		my $c = $self->normalize_class_string( $_ );
		if ($c eq '') { next; }
		$class .= ($class eq '' ? '' : ' ') . $c;
	}
	return $class;
}

sub normalize_class_string {
	my $self  = shift;
	my $class = shift;
	$class =~ tr/A-Z/a-z/;
	$class =~ s/[^a-z0-9 ]+/-/g;
	$class =~ s/  +/ /g;
	$class =~ s/(^| )[\-\d]+/$1/g;
	return $class;
}

#------------------------------------------------------------------------------
# check file path
#------------------------------------------------------------------------------
sub check_and_load_file_path {
	my $self = shift;
	my $file = shift;
	my $orig = $file;

	if ($self->{file_secure}) {
		$file =~ s!(^|/)\.+/!$1!g;
		$file =~ s|/+|/|g;
		$file =~ s|^/||;
		$file =~ s|[\x00-\x1f]| |g;

		if ($file =~ m|^([^/]*/)(.*)| && $1 eq $self->{file_secure}) {
			$file = $self->{image_path} . $2;
		} else {
			$self->parse_error('"%s" directive file security error: %s', $self->{directive}, $orig);
			return;
		}
	}
	if ($self->{ROBJ}) {
		$self->{ROBJ}->fs_encode(\$file);
	}
	my $_file = $self->get_filepath($file);
	if (!-r $_file) {
		$self->parse_error('"%s" directive file not found: %s', $self->{directive}, $orig);
	}
	return $file;
}

#------------------------------------------------------------------------------
# get_filepath
#------------------------------------------------------------------------------
sub get_filepath {
	my $self = shift;
	my $file = shift;
	return $self->{ROBJ} ? $self->{ROBJ}->get_filepath( $file ) : $file;
}

#------------------------------------------------------------------------------
# decode unicode symbol
#------------------------------------------------------------------------------
sub decode_unicode_symbol {
	my $self  = shift;
	foreach(@_) {
		if ($_ !~ /^(?:0x|x|\\x|U\+|u|\\u|&#x)([A-Fa-f0-9]+)|(\d+)$/) { next; }
		my $d = $2 ne '' ? $2 : hex($1);
		$_ = chr($d);
	}
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
