use strict;
#-------------------------------------------------------------------------------
# for Compatibility
#-------------------------------------------------------------------------------
package Satsuki::DB_pg;

sub new {
	shift(@_);	# this class name
	require Satsuki::DB::pg;
	return new Satsuki::DB::pg(@_);
}

1;
