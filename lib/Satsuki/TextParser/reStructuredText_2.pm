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
		option => [ qw(alt height width scale align target) ],
		method => 'image_directive'
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
# image directive
#------------------------------------------------------------------------------
sub image_directive {
	my $self  = shift;
	my $arg   = shift;
	my $opt   = shift;
	my $block = shift;

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
