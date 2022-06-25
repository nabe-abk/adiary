use strict;
#-------------------------------------------------------------------------------
# Boolean型モジュール
#						(C)2013 nabe / nabe@abk
#-------------------------------------------------------------------------------
# JSON::Boolean の機能コピー
package Satsuki::Boolean;
our $VERSION = '1.00';
################################################################################
# ■コンストラクタ
################################################################################
sub new {
	my $class = shift;
	my $self = (shift) ? 1 : 0;	# 引数
	return bless($self, $class);
}

################################################################################
# ■定義とオーバーロード
################################################################################
our $true  = do { bless \(my $bool = 1), "Satsuki::Boolean" };
our $false = do { bless \(my $bool = 0), "Satsuki::Boolean" };

sub is_bool {
	defined $_[0] and UNIVERSAL::isa($_[0], "Satsuki::Boolean");
}

use overload (
	"0+"     => sub { ${$_[0]} },
	"++"     => sub { ${$_[0]} += 1 },
	"--"     => sub { ${$_[0]} -= 1 },
	fallback => 1
);

sub true  { $true  }
sub false { $false }
sub null  { undef; }

1;
