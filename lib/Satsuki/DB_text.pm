use strict;
#------------------------------------------------------------------------------
# for Compatibility
#------------------------------------------------------------------------------
package Satsuki::DB_text;

sub new {
	shift(@_);	# this class name
	require Satsuki::DB::text;
	return new Satsuki::DB::text(@_);
}

1;
