use strict;
#-------------------------------------------------------------------------------
# Auto reload module
#						(C)2013-2020 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::AutoReload;
our $VERSION = '1.12';
#-------------------------------------------------------------------------------
my $Satsuki_pkg = 'Satsuki';
my $CheckTime;
my %Libs;
my @Packages;
#-------------------------------------------------------------------------------
my $MyPkg = __PACKAGE__ . '.pm';
$MyPkg =~ s|::|/|g;
################################################################################
# save library information
################################################################################
sub save_lib {
	if ($ENV{SatsukiReloadStop}) { return; }
	while (my ($pkg, $file) = each(%INC)) {
		if (exists $Libs{$file}) { next; }
		if (index($pkg, $Satsuki_pkg) != 0) {
			$Libs{$file} = 0;
			next;
		}
		$Libs{$file} = (stat($file)) [9];
		push(@Packages, $pkg);
	}
}

################################################################################
# check and unload
################################################################################
sub check_lib {
	my $tm = time();
	if ($CheckTime == $tm) { return ; }
	$CheckTime = $tm;

	my $flag = shift || $Satsuki::Base::RELOAD;
	if (!$flag) {
		if ($ENV{SatsukiReloadStop}) { return; }
		while(my ($file,$tm) = each(%Libs)) {
			if (!$tm || $tm == (stat($file))[9]) { next; }
			$flag=1;
			last;
		}
		if (!$flag) { return 0; }
	}

	# if exist update, unload all library
	foreach(@Packages) {
		if ($_ eq $MyPkg)       { next; }	# ignore myself
		delete $INC{$_};
		if ($_ =~ /_\d+\.pm$/i) { next; }	# ignore _2.pm _3.pm

		&unload($_);
	}
	undef %Libs;
	undef @Packages;

	# reload myself
	delete $INC{$MyPkg};
	require $MyPkg;

	return 1;
}

#-------------------------------------------------------------------------------
# unload
#-------------------------------------------------------------------------------
sub unload {
	no strict 'refs';

	my $pkg = shift;
	$pkg =~ s/\.pm$//;
	$pkg =~ s[/][::]g;
	my $names = \%{ $pkg . '::' };

	# delete from Namespace
	foreach(keys(%$names)) {
		substr($_,-2) eq '::' && next;
		if (ref($names->{$_})) {
			delete $names->{$_};
		} else {
			undef  $names->{$_};	# for scalar, do not "delete" it!
		}
	}
}

1;
