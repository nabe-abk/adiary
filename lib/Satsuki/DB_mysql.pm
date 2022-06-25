use strict;
#-------------------------------------------------------------------------------
# for Compatibility
#-------------------------------------------------------------------------------
package Satsuki::DB_mysql;

sub new {
	shift(@_);	# this class name
	require Satsuki::DB::mysql;
	return new Sastuki::DB::mysql(@_);
}

1;
