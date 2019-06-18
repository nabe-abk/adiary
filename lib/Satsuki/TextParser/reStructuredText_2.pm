use strict;
#------------------------------------------------------------------------------
# Split from Satsuki::TextParser::reStructuredText.pm for AUTOLOAD.
#------------------------------------------------------------------------------
use Satsuki::TextParser::reStructuredText ();
package Satsuki::TextParser::reStructuredText;
###############################################################################
# ■Interpreted Text Roles
###############################################################################
my %Roles;
my $DefaultRole = 'title';
#------------------------------------------------------------------------------
# inline text role
#------------------------------------------------------------------------------
sub text_role {
	my $self  = shift;
	my $whole = shift;
	my $name  = shift;
	my $str   = shift;
	if ($name eq '') { $name = $self->{default_role}; }
	$name =~ tr/A-Z/a-z/;
	$str  =~ s/\x01//g;
	if ($name eq '') { $name = $DefaultRole; }

	my $roles = $self->load_roles();
	my $role  = $roles->{$name};
	if (!$role) {
		my $msg = $self->parse_error('Unknown interpreted text role: %s', $name);
		return $self->make_problematic_span($whole, $msg);
	}

	#-----------------------------------------
	# check and format
	#-----------------------------------------
	if ($role->{check} && $str !~ /$role->{check}/) {
		my $msg = $self->parse_error('"%s" role invalid integer: %s', $name, $str);
		return $self->make_problematic_span($whole, $msg);
	}
	if ($role->{literal}) {
		$self->backslash_escape_cancel_with_tag_escape($str);
	}

	#-----------------------------------------
	# load class
	#-----------------------------------------
	my $class = $role->{class};
	if ($role->{opt}) {
		$class = ($class ne '' ? ' ' : '') . $role->{opt}->{_class};
	}

	#-----------------------------------------
	# method
	#-----------------------------------------
	if ($role->{method}) {
		my $method = $role->{method};
		return $self->$method($whole, $name, $str, $role->{opt}, $class);
	}

	if ($class ne '') { $class = " class=\"$class\""; }
	#-----------------------------------------
	# link replace
	#-----------------------------------------
	if ($role->{link}) {
		my $link = $role->{link};
		my $text = $role->{text};
		$link =~ s/%s/$str/g;
		$text =~ s/%s/$str/g;
		return "<a$class href=\"$link\">$text</a>";
	}

	#-----------------------------------------
	# tag replace
	#-----------------------------------------
	my $tag = $role->{tag};
	if ($tag) {
		return "<$tag$class>$str</$tag>";
	}

	#-----------------------------------------
	# other
	#-----------------------------------------
	my $msg = $self->parse_error('Internal error role: %s', $name);
	return $self->make_problematic_span($whole, $msg);
}

#------------------------------------------------------------------------------
# load roles
#------------------------------------------------------------------------------
sub load_roles {
	my $self  = shift;
	if ($self->{roles}) {
		return $self->{roles};
	}
	if (!%Roles) {
		$self->init_roles();
	}
	my %r = %Roles;		# Copy default roles
	return ($self->{roles} = \%r);
}
#------------------------------------------------------------------------------
# define Roles
#------------------------------------------------------------------------------
sub init_roles {
	my $self = shift;

	$Roles{emphasis} = {
		tag => 'em'
	};
	$Roles{strong} = {
		tag => 'strong'
	};
	$Roles{literal} = {
		tag   => 'span',
		class => 'pre'
	};
	$Roles{code} = {
		method  => 'code_role',
		literal => 1,
		class   => 'code',
		options => [ qw(class language) ]
	};
	$Roles{math} = {
		literal => 1,
		tag     => 'span',
		class   => 'math'
	};
	$Roles{'pep-reference'} = 
	$Roles{pep} = {
		check => qr/^-?\d+$/,
		text  => "PEP %s",
		link  => "https://www.python.org/dev/peps/pep-%s",
		class => 'pep'
	};
	$Roles{'rfc-reference'} = 
	$Roles{rfc} = {
		check => qr/^-?\d+$/,
		text  => "RFC %s",
		link  => "https://tools.ietf.org/html/rfc%s.html",
		class => 'rfc'
	};
	$Roles{subscript} =
	$Roles{sub} = {
		tag   => 'sub'
	};
	$Roles{superscript} =
	$Roles{sup} = {
		tag   => 'sub'
	};
	$Roles{'title-reference'} = 
	$Roles{title} = 
	$Roles{t} = {
		tag   => 'cite'
	};
	$Roles{raw} = {
		method  => 'raw_role',
		options => [ qw(class format) ]
	};
	foreach(keys(%Roles)) {
		my $r = $Roles{$_};
		if (ref($r->{options}) eq 'ARRAY') {
			$r->{options} = { map {$_ => 1} @{$r->{options}} };
		} else {
			$r->{options} = { class => 1 };
		}
	}
}
#//////////////////////////////////////////////////////////////////////////////
# Roles
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# code
#------------------------------------------------------------------------------
sub code_role {
	my $self  = shift;
	my $whole = shift;
	my $name  = shift;
	my $str   = shift;
	my $opt   = shift;
	my $class = shift;

	my $lang = $opt->{language};
	if ($lang ne '') {
		$class = $self->append_and_normalize_class_string($class, $lang);
	}

	if ($class ne '') { $class = " class=\"$class\""; }
	return "<code$class>$str</code>";
}

#------------------------------------------------------------------------------
# raw
#------------------------------------------------------------------------------
sub raw_role {
	my $self  = shift;
	my $whole = shift;
	my $name  = shift;
	my $str   = shift;
	my $opt   = shift;
	my $class = shift;

	my $format = $opt->{format};
	if ($format ne 'html') {
		my $msg = $self->parse_error('"%s" role supports only "html" format: %s', $name, $format);
		return $self->make_problematic_span($whole, $msg);
	}

	$self->backslash_escape_cancel($str);
	$self->tag_escape_cancel($str);

	if ($class ne '') { $class = " class=\"$class\""; }
	return "<span$class>$str</span>";
}

#//////////////////////////////////////////////////////////////////////////////
# Role Directives
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# [Directive] default-role
#------------------------------------------------------------------------------
sub default_role_directive {
	my $self  = shift;
	my $role  = shift;
	$role =~ tr/A-Z/a-z/;

	my $roles = $self->load_roles();
	if ($role ne '' && !$roles->{$role}) {
		$self->parse_error('"%s" directive unknown text role: %s', $self->{directive}, $role);
		return;
	}
	return {
		type => 'default-role',
		role => $role
	};
}

#------------------------------------------------------------------------------
# [Directive] role
#------------------------------------------------------------------------------
sub role_directive {
	my $self  = shift;
	my $role  = shift;
	my $opt   = shift;
	# $role =~ tr/A-Z/a-z/;		# compatible for Sphinx v1.4.9

	return {
		type => 'role',
		role => $role,
		opt  => $opt
	};
}
sub do_role_directive {
	my $self = shift;
	my $role = shift;
	my $opt  = shift;
	my $type = 'role';

	my $inherit;
	if ($role =~ /^([^ ]+) *\( *([^ ]+) *\)$/) {
		$role = $1;
		$inherit = $2;
	}
	if ($role !~ /[A-Za-z0-9]+(?:\x01?[\-_\+:\.]\x01?[A-Za-z0-9]+)*$/) {
		$self->parse_error('"%s" directive arguments not valid role names: %s', $type, $role);
		return;
	}

	#-----------------------------------------
	# load original role
	#-----------------------------------------
	my %r;
	my $roles = $self->load_roles();
	if ($inherit ne '') {
		if (! $roles->{$inherit}) {
			$self->parse_error('"%s" directive unknown text role: %s', $type, $inherit);
			return;
		}
		%r = %{ $roles->{$inherit} };	# copy
	} else {
		%r = (
			tag     => 'span',
			options => { class => 1}
		);
		$inherit = $role;
	}

	#-----------------------------------------
	# option check
	#-----------------------------------------
	foreach(keys(%$opt)) {
		if ($_ =~ /^_/) { next; }
		if (! $r{options}->{$_}) {
			$self->parse_error('"%s" role unknown option: %s', $role, $_);
			return;
		}
	}
	if (!exists($opt->{class})) {
		$opt->{class} = $role;
		my $c = $self->normalize_class_string( $opt->{class} );
		if ($c eq '') {
			$self->parse_error('"%s" role cannot make "%s" into a class name', $role, $role);
			return;
		}
		$opt->{_class} = $c;
	}

	#-----------------------------------------
	# save
	#-----------------------------------------
	$roles->{$role} = \%r;
	$r{opt} = $opt;
	return;
}

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
	$self->{directive} = $type;	# used by error message

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
		  && (!$d->{options} || $block->[0] !~ /^:((?:\\.|[^:\\])+):(?: +(.*)|$)/  || substr($1,0,1) eq ' ' ||  substr($1,-1) eq ' ')
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
	# options
	#-----------------------------------------
	my $opt = {};
	if ($d->{options}) {
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
			if ($d->{options} != $ANY) {
				if (! $d->{options}->{$k}) {
					$self->parse_error('"%s" directive unknown option: %s', $type, $k);
					return;
				}
				if (exists($opt->{$k})) {
					$self->parse_error('"%s" directive duplicate option: %s', $type, $k);
					return;
				}
			}
			if (! $d->{keep_lf}->{$k}) {
				$v =~ s/\n/ /g;
			}
			$opt->{$k} = $v;
		}
		if (%$opt && @$block && $block->[0] ne '') {
			$self->parse_error('"%s" directive invalid option block: %s', $type, $block->[0]);
			return;
		}
		#-----------------------------------------
		# options check
		#-----------------------------------------
		if (exists($opt->{class})) {
			my $c = $self->normalize_class_string( $opt->{class} );
			if ($c eq '') {
				return $self->invalid_option_error($opt, 'class');
			}
			$opt->{_class} = $c;
		}
		if (exists($opt->{file}) && $opt->{file} eq '') {
			return $self->invalid_option_error($opt, 'file');
		}
		if (exists($opt->{url}) && $opt->{url} eq '') {
			return $self->invalid_option_error($opt, 'url');
		}
		if (exists($opt->{encoding}) && $opt->{encoding} eq '') {
			return $self->invalid_option_error($opt, 'encoding');
		}
		if (exists($opt->{file}) && exists($opt->{url})) {
			$self->parse_error('"%s" directive may not both "file" and "url" options', $type);
			return;
		}
	}
	$opt->{_subst} = ($subst ne '');

	#-----------------------------------------
	# load external content: file/url
	#-----------------------------------------
	while(@$block && $block->[0] eq '') { shift(@$block); }

	my $external = ($opt->{file} ne '' || $opt->{url} ne '');
	if ($external && @$block) {
		$self->parse_error('"%s" directive may not both specify an external file/url and content: %s', $type, $opt->{url} || $opt->{file});
		return;
	}

	if ($opt->{file} ne '') {
		# import file
		my $file = $self->check_and_load_file_path($opt->{file});
		if (!defined $file) {
			return;
		}
		$block = $self->fread_lines($file);
		foreach(@$block) {
			chomp($_);
		}
		if (!$d->{file_raw}) {
			$block = $self->preprocess($block);
		}

		# encoding
		my $enc = $opt->{encoding};
		if ($enc) {
			my $data = join("\x00", @$block);
			eval {
				require Encode;
				Encode::from_to($data, $enc, $self->{system_coding});
			};
			if ($@) {
				$self->parse_error('"%s" directive file encoding error: "%s", file: "%s"', $type, $enc, $opt->{file});
				return;
			}
			$data =~ s/[\x01-\x08]//g;
			$block = [ split("\x00", $data) ];
		}
	}
	if ($opt->{url} ne '') {
		$block = [ "(\"$type\" directive not support url option)" ];
	}

	#-----------------------------------------
	# content
	#-----------------------------------------
	if ($d->{content}==$NONE && @$block) {
		$self->parse_error('"%s" directive no content permitted: %s', $type, $block->[0]);
		return;
	}
	if ($d->{content}==$REQUIRED && !@$block && !$external) {
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
	my $name = $d->{method} || $type . '_directive';
	$name =~ tr/-/_/;
	my $ret  = $self->$name($arg, $opt, $block, $type);
	my $ary = ref($ret) eq 'ARRAY' ? $ret : [$ret];

	if ($subst ne '') {
		my $text = join('', @$ary);
		my $ss   = $self->{substitutions};
		if (exists($ss->{$subst})) {
			$self->parse_error('Duplicate substitution definition name: %s', $subst);
		}
		my $key = $self->generate_key_from_label($subst);
		my $h   = {
			type  => 'substitution',
			text  => $text,
			ltrim => exists($opt->{trim}) || exists($opt->{ltrim}),
			rtrim => exists($opt->{trim}) || exists($opt->{rtrim})
		};
		$self->{substitutions}->{$subst} = $h;
		push(@$out, $h);
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
	$Directive{attention} = 
	$Directive{caution} = 
	$Directive{danger} = 
	$Directive{error} = 
	$Directive{hint} = 
	$Directive{important} = 
	$Directive{note} = 
	$Directive{tip} = 
	$Directive{warning} = {
		arg     => $NONE,
		content => $REQUIRED,
		method  => 'admonition_directive',
		options => $OPT_DEFAULT
	};
	$Directive{admonition} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		method  => 'topic_directive',
		options => $OPT_DEFAULT
	};

	#----------------------------------------------------------------------
	# Images
	#----------------------------------------------------------------------
	$Directive{image} = {
		arg     => $REQUIRED,
		content => $NONE,
		options => [ qw(alt height width scale align target class name) ]
	};
	$Directive{figure} = {
		arg     => $REQUIRED,
		content => $ANY,
		options => [ qw(alt height width scale align target class name figwidth figclass) ]
	};

	#----------------------------------------------------------------------
	# Body Elements
	#----------------------------------------------------------------------
	$Directive{topic} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		options => $OPT_DEFAULT
	};
	$Directive{sidebar} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		options => [ qw(subtitle class name) ]
	};
	$Directive{'parsed-literal'} = {
		arg     => $NONE,
		content => $REQUIRED,
		options => $OPT_DEFAULT
	};
	$Directive{code} = {
		arg     => $ANY,
		arg_max => 1,
		content => $REQUIRED,
		options =>  [ qw(number-lines name class) ]
	};
	$Directive{math} = {
		arg     => $ANY,
		content => $ANY,
		options =>  [ qw(name) ]
	};
	$Directive{rubric} = {
		arg     => $REQUIRED,
		content => $NONE,
		options => $OPT_DEFAULT
	};
	# Quote directive
	$Directive{epigraph} = 
	$Directive{highlights} = 
	$Directive{'pull-quote'} = {
		arg     => $NONE,
		content => $REQUIRED,
		method  => 'quote_directive',
		options => $NONE
	};
	$Directive{compound} = {
		arg     => $NONE,
		content => $REQUIRED,
		method  => 'div_directive',
		options => $OPT_DEFAULT
	};
	$Directive{container} = {
		arg     => $ANY,
		content => $REQUIRED,
		method  => 'div_directive',
		options => [ qw(name) ]
	};

	#----------------------------------------------------------------------
	# Tables
	#----------------------------------------------------------------------
	$Directive{table} = {
		arg     => $ANY,
		content => $REQUIRED,
		parse   => 'table',
		options => $OPT_DEFAULT
	};
	$Directive{'csv-table'} = {
		arg     => $ANY,
		content => $REQUIRED,
		options => [ qw(widths header-rows stub-columns header file url encoding delim quote keepspace escape class name) ],
		keep_lf => [ qw(header) ]
	};
	# Not support
	#	list-table

	#----------------------------------------------------------------------
	# Document Parts
	#----------------------------------------------------------------------
	$Directive{contents} = {
		arg     => $ANY,
		content => $NONE,
		options => [ qw(depth local backlinks class) ]
	};
	$Directive{sectnum} =
	$Directive{'section-numbering'} = {
		arg     => $NONE,
		content => $NONE,
		method  => 'sectnum_directive',
		options => [ qw(depth prefix suffix start) ]
	};

	$Directive{header} =
	$Directive{footer} = {
		arg     => $NONE,
		content => $REQUIRED,
		method  => 'no_work_directive'
	};

	#----------------------------------------------------------------------
	# References
	#----------------------------------------------------------------------
	# Not support
	#	target-notes
	# NOT IMPLEMENTED YET on Sphinx
	#	footnotes, citations

	#----------------------------------------------------------------------
	# HTML-Specific
	#----------------------------------------------------------------------
	$Directive{meta} = {
		arg     => $NONE,
		content => $NONE,
		options => $ANY,
		method  => 'no_work_directive'
	};
	# NOT IMPLEMENTED YET on Sphinx
	#	Imagemap

	#----------------------------------------------------------------------
	# for Substitution Definitions
	#----------------------------------------------------------------------
	$Directive{replace} = {
		subst   => 1,
		arg     => $NONE,
		content => $REQUIRED,
		parse   => 'p',
		options => [ qw(alt height width scale align target) ]
	};
	$Directive{unicode} = {
		subst   => 1,
		arg     => $REQUIRED,
		content => $NONE,
		options => [ qw(ltrim rtrim trim) ]
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
	$Directive{raw} = {
		arg     => $REQUIRED,
		content => $REQUIRED,
		file_raw=> 1,
		options => [ qw(file url encoding) ]
	};
	$Directive{role} = {
		arg     => $REQUIRED,
		content => $ANY,
		options => $ANY
	};
	$Directive{'default-role'} = {
		arg     => $ANY,
		content => $NONE,
		options => $NONE
	};
	$Directive{title} = {
		arg     => $REQUIRED,
		content => $NONE,
		options => $NONE,
		method  => 'no_work_directive'
	};
	$Directive{'restructuredtext-test-directive'} = {
		arg     => $NONE,
		content => $ANY,
		options => $NONE,
		method  => 'no_work_directive'
	};
	# Not support
	#	include, class

	#======================================================================
	#======================================================================
	foreach(keys(%Directive)) {
		my $d = $Directive{$_};
		if (ref($d->{options}) eq 'ARRAY') {
			$d->{options} = { map {$_ => 1} @{$d->{options}} };
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

	my $at2 = $self->make_image_attribute();
	return $url ne '' ? "<a href=\"$url\"$at$at2>$tag</a>" : "<span$at>$tag</span>";
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

sub make_image_attribute {
	my $self = shift;
	my $at   = $self->{image_attr};
	if ($at eq '') { return; }

	$at =~ s/%k/$self->{thispkey}/g;
	return ' ' . $at;
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
# sidebar
#------------------------------------------------------------------------------
sub sidebar_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;
	my $block = shift;
	my $type  = shift;

	my $subtitle;
	if (exists($opt->{subtitle})) {
		$subtitle = $opt->{subtitle};
		if ($subtitle eq '') {
			return $self->invalid_option_error($opt, 'subtitle');
		}
	}

	$self->backslash_escape($title, $subtitle);

	my $at = $self->make_name_and_class_attr($opt, 'sidebar');
	my @ary;
	push(@ary, "<div$at>\x02");
	push(@ary, "<p class=\"sidebar-title\">$title</p>");
	if ($subtitle ne '') {
		push(@ary, "<p class=\"sidebar-subtitle\">$subtitle</p>");
	}
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

#------------------------------------------------------------------------------
# sectnum
#------------------------------------------------------------------------------
sub sectnum_directive {
	my $self  = shift;
	my $title = shift;
	my $opt   = shift;

	if (exists($opt->{prefix}) && $opt->{prefix} eq '') {
		return $self->invalid_option_error($opt, 'prefix');
	}
	if (exists($opt->{suffix}) && $opt->{suffix} eq '') {
		return $self->invalid_option_error($opt, 'suffix');
	}

	if (exists($opt->{depth}) && $opt->{depth} !~ /^-?\d+$/) {
		return $self->invalid_option_error($opt, 'depth');
	}
	if (exists($opt->{start}) && $opt->{start} !~ /^-?\d+$/) {
		return $self->invalid_option_error($opt, 'start');
	}
	$self->tag_escape($opt->{prefix}, $opt->{suffix});

	unshift(@{ $self->{sectnums} }, $opt);
	return '';
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

#//////////////////////////////////////////////////////////////////////////////
# ●for Miscellaneous
#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# raw
#------------------------------------------------------------------------------
sub raw_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;
	$arg =~ tr/A-Z/a-z/;

	if ($arg ne 'html') {
		return;
	}

	foreach(@$block) {
		$_ .= "\x02";
	}
	return $block;
}

#//////////////////////////////////////////////////////////////////////////////
# ●no work directive
#//////////////////////////////////////////////////////////////////////////////
sub no_work_directive {
	my $self  = shift;
	return '';
}

###############################################################################
# ■ subroutine
###############################################################################
#------------------------------------------------------------------------------
# attribute
#------------------------------------------------------------------------------
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
		return;
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
# file read
#------------------------------------------------------------------------------
sub fread_lines {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};
	if ($ROBJ) {
		return $ROBJ->fread_lines_cached($file);
	}

	require Fcntl;
	my $fh;
	my @lines;
	if ( !sysopen($fh, $file, &Fcntl::O_RDONLY) ) {
		return [];
	}
	@lines = <$fh>;
	close($fh);
	return \@lines;
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
