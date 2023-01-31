use strict;
#-------------------------------------------------------------------------------
# for Compatibility
#-------------------------------------------------------------------------------
package Satsuki::DB_mysql;

sub new {
	shift(@_);	# this class name
	require Satsuki::DB::mysql;
	return new Satsuki::DB::mysql(@_);
}

1;
