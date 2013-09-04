use strict;
#------------------------------------------------------------------------------
# 日本語文字列変換
#						(C)2006-03 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::Code::Jcode;
our $VERSION = '2.00';
#------------------------------------------------------------------------------
# http://homepage2.nifty.com/hobbit/html/jcode.html
# にある UTF-8 変換表問題に対応する動的パッチを内部的に実行する。
#		Windows実装	Unicode
#	〜	EFBD9E		E3809C
#	‐	EFBC8D		E28892
#	‖	E288A5		E28096
# 下記は一応表示可能な模様
#	¬	EFBFA2		E080AC
#	¢	EFBFA0		E080A2
#	£	EFBFA1		E080A2
#
my $EXTRA_UTF8_PATCH = 1;

###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);

	$self->{ROBJ} = shift;
	$self->{EXTRA_UTF8_PATCH} = $EXTRA_UTF8_PATCH;
	$self->{__CACHE_PM} = 1;
	$self->{email_default} = 'ISO-2022-JP';

	$self->init();
	return $self;
}

#------------------------------------------------------------------------------
# ●初期化処理
#------------------------------------------------------------------------------
sub init {
	if ($Encode::VERSION) { return ; }
	eval {
		require Encode;
		require Encode::Guess; import Encode::Guess qw(euc-jp shiftjis iso-2022-jp);
	};
	if ($@) { die "Load failed Encode::*"; }
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●日本語変換
#------------------------------------------------------------------------------
sub from_to {
	my $self = shift;
	my ($str, $from, $to) = @_;
	if (ref($str) ne 'SCALAR') { my $s=$str; $str=\$s; }
	if ($$str =~ /^[\x00-\x0D\x10-\x1A\x1C-\x7E]*$/) { return $$str; }

	# 元の文字コードが不明
	if ($from eq '') { $from = $self->get_codename( $str ); }

	# 変換前と変換後が同じでも不正文字がないことを保証するため
	# 変換処理はパスしてはいけない。
	# if ($from eq $to) { return $$str; }

	# 変換処理
	if ($self->{EXTRA_UTF8_PATCH} && $from =~ /UTF.*8/i) {
		$$str =~ s/\xEF\xBD\x9E/\xE3\x80\x9C/g;	# 〜 EFBD9E E3809C
		$$str =~ s/\xEF\xBC\x8D/\xE2\x88\x92/g;	# ‐ EFBC8D E28892
		$$str =~ s/\xE2\x88\xA5/\xE2\x80\x96/g;	# ‖ E288A5 E28096
	}
	if ($from =~ /UTF.*8/i) {	# from が UTF8 のとき
		Encode::_utf8_on($$str);
		eval { $$str = Encode::encode($to, $$str); };
	} else {
		eval { Encode::from_to($$str, $from, $to); };
	}
	if ($self->{EXTRA_UTF8_PATCH} && $to =~ /UTF.*8/i) {
		$$str =~ s/\xE3\x80\x9C/\xEF\xBD\x9E/g;	# 〜 E3809C EFBD9E
		$$str =~ s/\xE2\x88\x92/\xEF\xBC\x8D/g;	# ‐ E28892 EFBC8D
		$$str =~ s/\xE2\x80\x96/\xE2\x88\xA5/g;	# ‖ E28096 E288A5
	}
	return $$str;
}

#------------------------------------------------------------------------------
# ●文字コード判別
#------------------------------------------------------------------------------
sub get_codename {
	my $self = shift;
	my $str = shift;
	if (!ref $str) { my $s=$str; $str=\$s; }

	my $code = Encode::Guess::guess_encoding($$str);
	if (ref $code) { return $code->name(); }
	return 'UTF-8';		# if unknown, return UTF-8(default)
}

#------------------------------------------------------------------------------
# ●マルチバイトsubstr();
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●マルチバイトlength();
#------------------------------------------------------------------------------
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
