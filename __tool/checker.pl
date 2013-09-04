#!/usr/bin/perl
use 5.6.0;
use strict;
BEGIN { unshift(@INC, './lib'); }

require Satsuki::Base;			# ベースシステム（標準関数）ロード
my $ROBJ = Satsuki::Base->new();	# ルートオブジェクト生成
###############################################################################
# adiary Release checker
###############################################################################
my $errors=0;
print "---adiary Release checker-------------------------------------------\n";

#------------------------------------------------------------------------------
# Design file check
#------------------------------------------------------------------------------
if (0) {
	my $lines = $ROBJ->fread_lines( "info/design_default.dat" );
	my $x = $lines->[0];
	if ($x =~ /Ver(\d+\.\d+)/) {
		print "## Design Version : $1\n";
	} else {
		print "## Design Version : not found!\n";
		$errors++;
	}
}
#------------------------------------------------------------------------------
# Debug check
#------------------------------------------------------------------------------
{
	open(my $fh, 'grep -ERni "debug\(|#\s*debug" skel/ lib/ plugin/ |');
	my @ary = <$fh>;
	close($fh);
	
	foreach(@ary) {
		my ($file, $linenum, $line) = split(/:/, $_, 3);
		if ($file !~ /\.(?:pm|html)$/) { next; }
		if ($line =~ /^\s*#/) { next; }
		if ($line =~ /{DEBUG}/) { next; }
		if ($line =~ /#\s*debug-safe/) { next; }
		if ($line =~ /{Debug_mode}/) { next; }

		print "## Debug error : $file\n";
		print "$linenum:$line";
		$errors++;
	}
}

#------------------------------------------------------------------------------
# CRLF check
#------------------------------------------------------------------------------
{
	open(my $fh, 'grep -r "\r\n" skel/ lib/ info/ plugin/|');
	my @ary = <$fh>;
	close($fh);

	my %files;
	foreach(@ary) {
		my ($file, $line) = split(/:/, $_, 2);
		if ($line =~ /\r\n/) {
			$files{$file} = 1;
		}
	}
	foreach(sort(keys(%files))) {
		print "## CRLF warning : $_\n";
	}
}

#------------------------------------------------------------------------------
# BOM check
#------------------------------------------------------------------------------
{
	open(my $fh, "grep -r '\xEF\xBB' skel/ lib/ info/ plugin/|");
	my @ary = <$fh>;
	close($fh);
	foreach(@ary) {
		print "## BOM warning : $_\n";
	}
}

#------------------------------------------------------------------------------
# exit
#------------------------------------------------------------------------------
{
	if ($errors) {
		print "\n## Total $errors errors.\n";
	} else {
		print "## error not found.\n";
	}
}
