use strict;
#-------------------------------------------------------------------------------
# 日本語文字列変換
#						(C)2021 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::Code::Jcode;
our $VERSION = '2.10';

################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);

	$self->{ROBJ}       = shift;
	$self->{__CACHE_PM} = 1;

	$self->init();
	return $self;
}

#-------------------------------------------------------------------------------
# ●初期化処理
#-------------------------------------------------------------------------------
sub init {
	if ($Encode::VERSION) { return ; }
	eval {
		require Encode;
		require Encode::Guess;
		import  Encode::Guess;
	};
	if ($@) { die "Load failed Encode::*"; }
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●日本語変換
#-------------------------------------------------------------------------------
sub from_to {
	my $self = shift;
	my ($str, $from, $to) = @_;
	if (ref($str) ne 'SCALAR') { my $s=$str; $str=\$s; }
	if ($$str =~ /^[\x00-\x0D\x10-\x1A\x1C-\x7E]*$/) { return $$str; }

	# 元の文字コードが不明
	if ($from eq '') { $from = $self->get_codename( $str ); }

	if ($from =~ /UTF.*8/i) {	# from が UTF8 のとき
		Encode::_utf8_on($$str);
		eval { $$str = Encode::encode($to, $$str); };
	} else {
		eval { Encode::from_to($$str, $from, $to); };
	}
	return $$str;
}

#-------------------------------------------------------------------------------
# ●文字コード判別
#-------------------------------------------------------------------------------
sub get_codename {
	my $self = shift;
	my $str = shift;
	if (!ref $str) { my $s=$str; $str=\$s; }

	my $code = Encode::Guess::guess_encoding($$str, qw/euc-jp shiftjis 7bit-jis/);
	if (ref $code) { return $code->name(); }
	return 'UTF-8';		# if unknown, return UTF-8(default)
}

#-------------------------------------------------------------------------------
# ●マルチバイトsubstr();
#-------------------------------------------------------------------------------
sub jsubstr {
	my $self = shift;
	return $self->jsubstr_code($self->{ROBJ}->{System_coding}, @_);
}
sub jsubstr_code {
	my $self = shift;
	my $code = shift;
	my $txt  = shift;
	my $substr = ($#_ == 0) ? sub { substr($_[0],$_[1]) } : sub { substr($_[0],$_[1],$_[2]) };
	if ($txt !~ /[\x7f-\xff]/) { return &$substr($txt, @_); }

	if ($code =~ /^UTF.*8/i) {
		Encode::_utf8_on($txt);
		$txt = &$substr($txt, @_);
		Encode::_utf8_off($txt);
		return $txt;
	}
	# UTF-8ではない場合
	my $utf8 = Encode::decode($code, $txt);
	$utf8 = &$substr($utf8, @_);
	return Encode::encode($code, $utf8);
}

#-------------------------------------------------------------------------------
# ●マルチバイトlength();
#-------------------------------------------------------------------------------
sub jlength {
	my $self = shift;
	return $self->jlength_code($self->{ROBJ}->{System_coding}, @_);
}
sub jlength_code {
	my $self = shift;
	my $code = shift;
	my $txt  = shift;
	if ($txt !~ /[\x7f-\xff]/) { return length($txt); }

	if ($code =~ /^UTF.*8/i) {
		Encode::_utf8_on($txt);
	} else {
		$txt = Encode::decode($code, $txt);
	}
	return length($txt);
}

1;
