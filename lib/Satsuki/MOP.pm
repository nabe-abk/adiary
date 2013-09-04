use strict;
#-------------------------------------------------------------------------------
# 匿名クラス生成のためのモジュール
#					(C)2013 nabe / ABK project
#-------------------------------------------------------------------------------
# Class::MOPのまね事です。
package Satsuki::MOP;
our $VERSION = '1.00';
our $AUTOLOAD;
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift}, $class);
}
#------------------------------------------------------------------------------
# ●メソッドの追加
#------------------------------------------------------------------------------
sub add_method {
	my $self = shift;
	while(@_) {
		my $n = shift;
		$self->{$_} = shift;
	}
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
	
	# error
	my ($pack, $file, $line) = caller;
	if ($self->{this_filename}) { $file = $self->{this_filename}; }
	die "[MOP] Can't find method '$name' at $file line $line"; 	
}

1;
