use strict;
#-------------------------------------------------------------------------------
# 匿名クラス生成のためのモジュール
#					(C)2013-2017 nabe@abk
#-------------------------------------------------------------------------------
# Class::MOP簡易なまね事です。
package Satsuki::MOP;
our $VERSION = '1.01';
our $AUTOLOAD;
#------------------------------------------------------------------------------
# ●コンストラクタ / デストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift, _FILENAME => shift}, $class);
}
sub Finish {
	my $self = shift;
	my $func = $self->{'Finish'};
	if (ref($func) eq 'CODE') { return &$func($self,@_); }
}

#------------------------------------------------------------------------------
# ●親class
#------------------------------------------------------------------------------
sub superclass {
	my $self = shift;
	$self->{ISA} = shift;
}
sub super {
	my $self = shift;
	return $self->{ISA};
}

#------------------------------------------------------------------------------
# ●呼び出し機構
#------------------------------------------------------------------------------
sub AUTOLOAD {
	if ($AUTOLOAD eq '') { return; }
	my $self = shift;
	my $name = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
	my $func = $self->{ $name };
	if (ref($func) eq 'CODE') { return &$func($self,@_); }

	# superclass object
	my $super = $self->{ISA};
	if ($super->can($name)) { return $super->$name(@_); }

	# error
	my ($pack, $file, $line) = caller;
	if ($self->{_FILENAME}) { $file = $self->{_FILENAME}; }
	die "[MOP] Can't find method '$name' at $file line $line";
}

1;
