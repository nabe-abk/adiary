use strict;
#-------------------------------------------------------------------------------
# モジュール分割のための AutoLoader for Satsuki-system
#							(C)2006 nabe@abk
#-------------------------------------------------------------------------------
#######################################################################
# オートローダーの仕様を変更した場合 AutoReload.pm も修正のこと。
#######################################################################
package Satsuki::AutoLoader;
our $VERSION = '1.00';

# use Satsuki::Exporter 'import';
use Exporter 'import';
our @EXPORT = qw(AUTOLOAD debug DESTROY ROBJ);
our $AUTOLOAD;

#------------------------------------------------------------------------------
# ●AutoLoader本体
#------------------------------------------------------------------------------
sub AUTOLOAD {
	if ($AUTOLOAD eq '') { return; }
	my $x     = rindex($AUTOLOAD, '::');
	my $class = substr($AUTOLOAD, 0, $x);
	my $func  = substr($AUTOLOAD, $x+2);
	my $pmfile = $class;
	$pmfile  =~ s|::|/|g;
	$pmfile .= '_';

	# ロード
	my $obj  = shift;
	my $ROBJ = ref $obj ? $obj->{ROBJ} : {};
	my $can;
	my $i=2;
	while(1) {
		my $file = $pmfile . $i . '.pm';
		if (!exists $INC{$file}) {
			my $dir;
			foreach(@INC) {
				if (-e "$_/$file") { $dir=$_; last; }
			}
			if (!$dir) { last; }		# 自動ロードファイルが見つからない

			eval { require $file; };
			if ($ROBJ->{AutoLoader_debug}) {
				my $msg = "[AutoLoader] Try load $file for $func.";
				warn $msg; $ROBJ->debug($msg);	# debug-safe
			}
			if ($@) {	#ロード失敗
				delete $INC{$file};
				die "[AutoLoader] $@\n";
			}
		}
		if (defined &$AUTOLOAD) { $can=1; last; }
		$i++;
	}

	if (! $can) {
		my ($pack, $file, $line) = caller(0);
		die "[AutoLoader] Can't find method '$func' in '$class' at $file line $line\n";
	}
	return $obj->$func(@_);
}
#------------------------------------------------------------------------------
sub debug {
	my $self = shift;
	$self->{ROBJ}->debug($_[0], 1);		# debug-safe
}
sub DESTROY {
	my $self = shift;
	$Satsuki::DESTROY_debug && print "DESTROY $self\n";
}

1;
