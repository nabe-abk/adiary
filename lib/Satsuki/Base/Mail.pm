use strict;
#-------------------------------------------------------------------------------
# メール送受信モジュール
#						(C)2006-2020 nabe / nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::Base::Mail;
our $VERSION = '1.30';
#-------------------------------------------------------------------------------
use Socket;
#-------------------------------------------------------------------------------
my $TIMEOUT = 5;
my $CODE;
my $DEBUG = 0;
my %Auth;
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	my $ROBJ = shift;
	$self->{ROBJ}   = $ROBJ;
	$self->{mailer} = "Satsuki-Base-Mail Version $VERSION";

	$CODE = $ROBJ->{SystemCoding} || 'UTF-8';

	$self->{__CACHE_PM} = 1;

	$Auth{PLAIN} = \&auth_plain;
	$Auth{LOGIN} = \&auth_login;
	eval {
		require Digest::HMAC_MD5;
		$Auth{'CRAM-MD5'} = \&auth_cram_md5;
	};
	return $self;
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●メール送信
#-------------------------------------------------------------------------------
# smtp_auth parameter: auth_name / auth_pass
# 
sub send {
	return &send_mail(@_);
}
sub send_mail {
	my ($self, $h) = @_;
	my $ROBJ = $self->{ROBJ};

	# 宛先確認
	my $to    = $self->check_mail_addresses($h->{to}  );
	my $cc    = $self->check_mail_addresses($h->{cc}  );
	my $bcc   = $self->check_mail_addresses($h->{bcc} );
	my $from  = $self->check_mail_address($h->{from}       );
	my $repto = $self->check_mail_address($h->{reply_to}   );
	my $retph = $self->check_mail_address($h->{return_path});

	if (!$to) { $ROBJ->message('"To" is invalid'); return 1; }

	#-----------------------------------------------------------------------
	# message body
	#-----------------------------------------------------------------------
	my $msg='';
	{
		my $to_name   = ref($h->{to_name})   ? $h->{to_name}        : [ $h->{to_name} ];
		my $cc_name   = ref($h->{cc_name})   ? $h->{cc_name}        : [ $h->{cc_name} ];
		my $from_name = ref($h->{from_name}) ? $h->{from_name}->[0] : $h->{from_name};

		my $subject   = $h->{subject};
		my $text      = $h->{text};
		$subject =~ s/[\x00-\x08\x0a-\x1f]//g;		# TAB以外
		$text    =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;	# TAB, LF, CR以外

		# To, Cc Headers
		$msg .= $self->make_to_header('To', $to, $to_name);
		$msg .= $self->make_to_header('Cc', $cc, $cc_name);

		if ($from) {
			if ($from_name ne '') {
				$msg .= "From: " . $self->mime_encode($from_name) . " <$from>\n";
			} else {
				$msg .= "From: $from\n";
			}
		}
		if ($repto) { $msg .= "Reply-To: $repto\n"; }
		if ($retph) { $msg .= "Return-Path: $retph\n"; }
		$msg .= "Subject:" . $self->mime_encode($subject)        . "\n";
		$msg .= "Date: "   . $self->mail_date_local($ROBJ->{TM}) . "\n";
		$msg .= "MIME-Version: 1.0\n";
		$msg .= "Content-Type: text/plain; charset=\"$CODE\"\n";
		$msg .= "X-Mailer: $self->{mailer}\n";
		if ($h->{x}) { chomp($h->{x}); $msg .= "$h->{x}\n"; }
		$msg .= "\n$text";
	}

	#-----------------------------------------------------------------------
	# mail server
	#-----------------------------------------------------------------------
	my $host = $h->{host};
	my $port = $h->{port};
	if ($host =~ /^(.*):(\d+)$/) {
		$host = $1;
		$port = $port || $2;
	}
	$host ||= '127.0.0.1';
	$port ||= 25;

	#-----------------------------------------------------------------------
	# original SMTP
	#-----------------------------------------------------------------------
	my $sock;
	{
		my $ip_bin = inet_aton($host);
		if ($ip_bin eq '') {
			$ROBJ->message("Can't find host '%s'", $host);
			return 20;
		}
		my $addr = pack_sockaddr_in($port, $ip_bin);
		socket($sock, Socket::PF_INET(), Socket::SOCK_STREAM(), 0);
		{
			local $SIG{ALRM} = sub { close($sock); };
			alarm( $TIMEOUT );
			my $r = connect($sock, $addr);
			alarm(0);
			if (!$r) {
				close($sock);
				$ROBJ->message("Can't connect '%s'", $host);
				return 21;
			}
		}
		binmode($sock);
	}
	$self->{buf}='';
	eval {
		$self->status_check($sock, 220);
		my $status = $self->send_ehlo($sock, 'localhost.localdomain');
		if ($h->{auth_name} ne '') {
			my $type;
			foreach(split(/ /, $status->{'AUTH'})) {
				if ($Auth{$_}) {
					$type = $_;
					last;
				}
			}
			if (!$type) {
				my $mechanisms = join(', ', sort(keys(%Auth)));
				die("AUTH mechanisms miss match! support: $mechanisms");
			}
			my $str = $self->send_data_check($sock, "AUTH $type", 334);
			eval {
				$str =~ s/^\d+ //;
				&{ $Auth{$type} }($self, $sock, $h->{auth_name}, $h->{auth_pass}, $str);
			};
			if ($@) {
				die("AUTH $type failed: \"$h->{auth_name}\" / \"$h->{auth_pass}\" : $@")
			}
		}
		$from ||= $to;
		$self->send_data_check($sock, "MAIL FROM:$from", 250);
		foreach(@$to,@$cc,@$bcc) {
			$self->send_data_check($sock, "RCPT TO:$_", 250);
		}
		$self->send_data_check($sock, "DATA", 354);
		$msg =~ s/(^|\n)\./$1../g;
		$msg =~ s/[\r\n]*$/\r\n/g;
		$msg .= ".";
		$self->send_data_check($sock, $msg, 250);
		$self->send_quit($sock);
	};
	close($sock);
	if ($@) {
		$ROBJ->message('SMTP Error: %s', $@);
		return 200;
	}
	return 0;
}

sub make_to_header {
	my $self = shift;
	my $type = shift;
	my $adr  = shift || [];
	my $name = shift || [];
	my @ary;
	foreach(0..$#$adr) {
		my $a = $adr ->[$_];
		my $n = $name->[$_];
		if ($a eq '') { next; }
		if ($n eq '') {
			push(@ary, $a);
			next;
		}
		# exists name
		$n =~ s/[\x00-\x1f<>\"]//g;
		$self->mime_encode($n);
		push(@ary, "$n <$a>");
	}
	if (!@ary) { return ''; }
	return "$type: " . join(",\n\t", @ary) . "\n";
}

#-------------------------------------------------------------------------------
# socket
#-------------------------------------------------------------------------------
sub send_ehlo {
	my $self = shift;
	my $sock = shift;
	my $host = shift;
	$self->send_data_check($sock, "EHLO $host", 250);

	my $in='';
	my $fno = fileno($sock);
	vec($in, $fno, 1) = 1;
	my %h;
	while(1) {
		if ($self->{buf} eq '') {
			select(my $x = $in, undef, undef, 0);
			if (!vec($x, $fno, 1)) { last; }
		}

		my ($code, $y) = $self->recive_line($sock);
		if (!$code) { die("broken response! / EHLO"); }

		$y =~ s/^\d+[ \-]//;
		$y =~ s/[\r\n]//g;
		my ($a,$b) = split(/ /, $y, 2);
		$h{$a} = $b || 1;
	}
	return \%h;
}

sub send_data_check {
	my $self = shift;
	my $sock = shift;
	my $data = shift;
	my $code = shift;
	$self->send_cmd($sock, $data);
	return $self->status_check($sock, $code, $data);
}

sub send_cmd {
	my $self = shift;
	my $sock = shift;
	my $data = (shift) . "\r\n";
	$DEBUG && print STDERR "--> $data";	# debug-safe
	syswrite($sock, $data, length($data));
}

sub status_check {
	my $self = shift;
	my $sock = shift;
	my $code = shift;
	my $data = shift;
	my ($c, $line) = $self->recive_line($sock);
	if ($c == $code) { return $line; }

	$self->send_quit($sock);
	die ($data ? "$line / $data" : $line);
}

sub send_quit {
	my $self = shift;
	my $sock = shift;
	my $quit = "QUIT\r\n";
	$DEBUG && print STDERR "--> $quit";	# debug-safe
	syswrite($sock, $quit, length($quit));
}

sub recive_line {
	my $self = shift;
	my $sock = shift;

	my $buf = $self->{buf};
	if ($buf eq '') {
		vec(my $in, fileno($sock), 1) = 1;
		my $r = select($in, undef, undef, $TIMEOUT);
		if ($r <= 0) { return; }
		if (!sysread($sock, $buf, 4096, length($buf))) { return; }
	}
	my $line;
	{
		my $x = index($buf, "\n");
		if ($x < 0) { return; }
		$line = substr($buf, 0, $x);
		$line =~ s/\r//;
		$self->{buf} = substr($buf, $x+1);
	}
	$DEBUG && print STDERR "<-- $line\n";	# debug-safe
	my $code;
	if ($line =~ /^(\d+)/) { $code=$1; }
	return wantarray ? ($code, $line) : $code;
}

#-------------------------------------------------------------------------------
# Authentication
#-------------------------------------------------------------------------------
sub auth_plain {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;

	my $plain = $self->base64encode("\0$user\0$pass");
	$self->send_data_check($sock, $plain, 235);
}

sub auth_login {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;

	$self->send_data_check($sock, $self->base64encode($user), 334);
	$self->send_data_check($sock, $self->base64encode($pass), 235);
}

sub auth_cram_md5 {
	my $self = shift;
	my $sock = shift;
	my $user = shift;
	my $pass = shift;
	my $str  = $self->base64decode(shift);

	my $md5 = Digest::HMAC_MD5::hmac_md5_hex($str,$pass);

	$self->send_data_check($sock, $self->base64encode("$user $md5"), 235);
}

################################################################################
# ■サブルーチン
################################################################################
sub check_mail_address {
	my $self = shift;
	my $adr  = shift;
	if ($adr !~ /^[-\w\.]+\@(?:[-\w]+\.)+[-\w]+$/) { return; }
	return $adr;
}
sub check_mail_addresses {
	my $self = shift;
	my $adr  = shift;

	my $ary  = ref($adr) ? $adr : [ split(/\s*,\s*/, $adr) ];
	if (!@$ary) { return; }
	foreach(@$ary) {
		if ($_ !~ /^[-\w\.]+\@(?:[-\w]+\.)+[-\w]+$/) { return; }
	}
	return \@$ary;
}

sub get_timezone {
	require Time::Local;
	my @tm = (0,0,0,1,0,100);	# 2000-01-01
	my $d  = Time::Local::timegm(@tm) - Time::Local::timelocal(@tm);
	my $pm = ($d<0) ? '-' : '+';
	$d = ($d<0) ? -$d : $d;

	my $m = int($d/60);
	my $h = int($m/60);
	$m = $m - $h*60;
	return $pm . substr("0$h", -2) . substr("0$m", -2);
}

# Sun, 06 Nov 1994 08:49:37 +0900
sub mail_date_local {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d %s",
		, $mday, $year+1900, $hour, $min, $sec, $self->get_timezone());
}

################################################################################
# ■MIME base64エンコード/デコード
################################################################################
my $base64table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
my @base64ary = (
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x00〜0x1f
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x10〜0x1f
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0,62,  0,62, 0,63,	# 0x20〜0x2f
52,53,54,55, 56,57,58,59,  60,61, 0, 0,  0, 0, 0, 0,	# 0x30〜0x3f
 0, 0, 1, 2,  3, 4, 5, 6,   7, 8, 9,10, 11,12,13,14,	# 0x40〜0x4f
15,16,17,18, 19,20,21,22,  23,24,25, 0,  0, 0, 0,63,	# 0x50〜0x5f
 0,26,27,28, 29,30,31,32,  33,34,35,36, 37,38,39,40,	# 0x60〜0x6f
41,42,43,44, 45,46,47,48,  49,50,51, 0,  0, 0, 0, 0	# 0x70〜0x7f
);

#-------------------------------------------------------------------------------
# ●エンコード
#-------------------------------------------------------------------------------
sub mime_encode {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/([^\x00-\x7f]+)/ "=?$CODE?B?" . $self->base64encode($1) . '?=' /eg;
	}
	return $_[0];
}
sub base64encode {
	my $self = shift;
	my $str  = shift;
	my $ret;

	# 2 : 0000_0000 1111_1100
	# 4 : 0000_0011 1111_0000
	# 6 : 0000_1111 1100_0000
	my ($i, $j, $x);
	for($i=$x=0, $j=2; $i<length($str); $i++) {
		$x    = ($x<<8) + ord(substr($str,$i,1));
		$ret .= substr($base64table, ($x>>$j) & 0x3f, 1);

		if ($j != 6) { $j+=2; next; }
		# j==6
		$ret .= substr($base64table, $x & 0x3f, 1);
		$j    = 2;
	}
	if ($j != 2)    { $ret .= substr($base64table, ($x<<(8-$j)) & 0x3f, 1); }
	if ($j == 4)    { $ret .= '=='; }
	elsif ($j == 6) { $ret .= '=';  }

	return $ret;
}
#-------------------------------------------------------------------------------
# ●デコード
#-------------------------------------------------------------------------------
sub base64decode {	# 'normal' or 'URL safe'
	my $self = shift;
	my $str  = shift;

	my $ret;
	my $buf;
	my $f;
	$str =~ s/[=\.]+$//;
	for(my $i=0; $i<length($str); $i+=4) {
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i  ,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+1,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+2,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+3,1)) ];
		$ret .= chr(($buf & 0xff0000)>>16) . chr(($buf & 0xff00)>>8) . chr($buf & 0xff);

	}
	my $f = length($str) & 3;	# mod 4
	if ($f >1) { chop($ret); }
	if ($f==2) { chop($ret); }
	return $ret;
}

1;
