use strict;
#-------------------------------------------------------------------------------
# AutoLoader for Satsuki-system
#							(C)2006-2020 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::AutoLoader;
our $VERSION = '1.00';

use Exporter 'import';
our @EXPORT = qw(AUTOLOAD);
our $AUTOLOAD;
#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
sub AUTOLOAD {
	if ($AUTOLOAD eq '') { return; }
	my $x     = rindex($AUTOLOAD, '::');
	my $class = substr($AUTOLOAD, 0, $x);
	my $func  = substr($AUTOLOAD, $x+2);
	if ($func eq 'DESTROY') { return; }

	my $pmfile = $class;
	$pmfile  =~ s|::|/|g;
	$pmfile .= '_';

	# ロード
	my $obj  = shift;
	my $ROBJ = ref($obj) ? $obj->{ROBJ} : {};
	my $can;
	foreach my $i (2..99) {
		my $file = $pmfile . $i . '.pm';
		if (exists $INC{$file}) { next; }

		my $dir;
		foreach(@INC) {
			if (-e "$_/$file") { $dir=$_; last; }
		}
		if (!$dir) { last; }		# File not found

		eval { require $file; };
		if ($ROBJ->{AutoLoader_debug}) {
			my $msg = "[AutoLoader] Try load $file for $func.";
			warn $msg; $ROBJ->debug($msg);	# debug-safe
		}
		if ($@) {	# require failed
			delete $INC{$file};
			die "[AutoLoader] $@\n";
		}

		if (defined &$AUTOLOAD) {
			return $obj->$func(@_);
		}
	}

	my ($pack, $file, $line) = caller(0);
	die "[AutoLoader] Can't find method '$func' in '$class' at $file line $line\n";
}

1;
