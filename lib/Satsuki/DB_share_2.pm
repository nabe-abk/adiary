use strict;
#------------------------------------------------------------------------------
# DB_share_2.pm for AutoLoader
#------------------------------------------------------------------------------
package Satsuki::DB_share_2;
our $VERSION = '1.00';

# use Satsuki::Exporter 'import';
use Exporter 'import';
our @EXPORT = qw(begin rollback commit);

###############################################################################
# ■ begin/rollback/commitの入れ子発行防止機構
###############################################################################
sub begin {
	my $self = shift;
	$self->{__begin_count}++;
	if ($self->{__begin_count} == 1) {
		$self->{__rollback}=0;
		return $self->begin(@_);
	}
}

sub rollback {
	my $self  = shift;
	my $count = $self->{__begin_count};
	if ($count<1) { return -2; }

	$self->{__begin_count} = --$count;	# 1つ戻す
	if ($count==0) {
		return $self->rollback();
	}
	$self->{__rollback}=1;
	return -3;
}

sub commit {
	my $self  = shift;
	my $count = $self->{__begin_count};
	if ($count<1) { return -2; }

	$self->{__begin_count} = --$count;	# 1つ減らす
	if ($count==0) {
		return $self->commit();
	}
	return 0;	# 成功したことにする
}



1;
