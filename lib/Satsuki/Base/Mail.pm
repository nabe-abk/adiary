use strict;
#------------------------------------------------------------------------------
# メール送受信モジュール
#						(C)2006-2019 nabe / nabe@abk
#------------------------------------------------------------------------------
package Satsuki::Base::Mail;
our $VERSION = '1.20';
#------------------------------------------------------------------------------
use Socket;
#------------------------------------------------------------------------------
my $TIMEOUT = 5;
my $CODE    = 'UTF-8';
my $DEBUG   = 0;
my %Auth;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{mailer} = "Satsuki-Base-Mail Version $VERSION";

	$CODE = $Satsuki::SYSTEM_CODING || 'UTF-8';

	$self->{__CACHE_PM} = 1;

	$Auth{PLAIN} = \&auth_plain;
	$Auth{LOGIN} = \&auth_login;
	$Auth{'CRAM-MD5'} = \&auth_cram_md5;
	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●メール送信
#------------------------------------------------------------------------------
# smtp_auth parameter: auth_name / auth_pass
# 
sub send {
	return &send_mail(@_);
}
sub send_mail {
	my ($self, $h) = @_;
	my $ROBJ = $self->{ROBJ};

	# 宛先確認
	my $from = $self->check_mail_address($h->{from}) ? $h->{from} : '';
	my $to   = $self->check_mail_address($h->{to}  ) ? $h->{to}   : '';
	my $cc   = $self->check_mail_address($h->{cc}  ) ? $h->{cc}   : '';
	my $bcc  = $self->check_mail_address($h->{bcc} ) ? $h->{bcc}  : '';
	my $repto= $self->check_mail_address($h->{reply_to}) ? $h->{reply_to} : '';
	my $retph= $self->check_mail_address($h->{return_path}) ? $h->{return_path} : '';

	if ($to eq '') { $ROBJ->message('"To" is invalid'); return 1; }

	#----------------------------------------------------------------------
	# message body
	#----------------------------------------------------------------------
	my $msg='';
	{
		my $from_name = $h->{from_name};
		my $to_name   = $h->{to_name};
		my $cc_name   = $h->{cc_name};
		my $subject   = $h->{subject};
		my $text      = $h->{text};
		foreach($from_name, $to_name, $cc_name) {
			$_ =~ s/[\x00-\x1f<>\"]//g;
		}
		$subject =~ s/[\x00-\x08\x0a-\x1f]//g;		# TAB以外
		$text    =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;	# TAB, LF, CR以外

		# MIME
		$self->mime_encode($from_name, $to_name, $cc_name, $subject);

		# from, to の加工
		$from_name = $from_name ? "$from_name <$from>"	: $from;
		$to_name   = $to_name   ? "$to_name <$to>"	: $to;
		$cc_name   = $cc_name   ? "$cc_name <$cc>"	: $cc;

		if ($from)  { $msg .= "From: $from_name\n"; }
		if ($to)    { $msg .= "To: $to_name\n"; }
		if ($cc)    { $msg .= "Cc: $cc_name\n"; }
		if ($repto) { $msg .= "Reply-To: $repto\n"; }
		if ($retph) { $msg .= "Return-Path: $retph\n"; }
		$msg .= "Subject: $subject\n";
		$msg .= "Date: " . $self->mail_date_local($ROBJ->{TM}) . "\n";
		$msg .= "MIME-Version: 1.0\n";
		$msg .= "Content-Type: text/plain; charset=\"$CODE\"\n";
		$msg .= "X-Mailer: $self->{mailer}\n";
		if ($h->{x}) { chomp($h->{x}); $msg .= "$h->{x}\n"; }
		$msg .= "\n$text";
	}

	#----------------------------------------------------------------------
	# mail server
	#----------------------------------------------------------------------
	my $host = $h->{host};
	my $port = $h->{port};
	if ($host =~ /^(.*):(\d+)$/) {
		$host = $1;
		$port = $port || $2;
	}
	$host ||= '127.0.0.1';
	$port ||= 25;

	#----------------------------------------------------------------------
	# original SMTP
	#----------------------------------------------------------------------
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
		$self->send_data_check($sock, "MAIL FROM:$from", 250);
		$self->send_data_check($sock, "RCPT TO:$to", 250);
		if ($cc) {
			$self->send_data_check($sock, "RCPT TO:$cc", 250);
		}
		if ($bcc) {
			$self->send_data_check($sock, "RCPT TO:$bcc", 250);
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
#------------------------------------------------------------------------------
# socket
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# Authentication
#------------------------------------------------------------------------------
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

	require Digest::HMAC_MD5;
	my $md5 = Digest::HMAC_MD5::hmac_md5_hex($str,$pass);

	$self->send_data_check($sock, $self->base64encode("$user $md5"), 235);
}

###############################################################################
# ■サブルーチン
###############################################################################
sub check_mail_address {
	my $self = shift;
	my @adr = split(/,/, shift);
	if (!@adr) { return 0; }
	foreach(@adr) {
		if ($_ !~ /^[-_\.a-zA-Z0-9]+\@(?:[-\w]+\.)+[-\w]+$/) { return 0; }
	}
	return 1;	# success
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

###############################################################################
# ■メールの解析
###############################################################################
#------------------------------------------------------------------------------
# ●メールの解析
#------------------------------------------------------------------------------
sub parse_mail {
	my $self = shift;
	my $ary  = shift;
	
	# 文字コード変換
	my $ROBJ  = $self->{ROBJ};
	my $code  = shift || $ROBJ->{System_coding};
	my $jcode = $ROBJ->load_codepm();
	
	# ヘッダ解析
	my $mail = $self->parse_mail_header($ary, $code);
	# 追加解析（From, Toを判別（最初の１人のみ））
	if ($mail->{from} =~ /<([\w\.\-]+\@[\w\.\-]+)>/ || $mail->{from} =~ /([\w\.\-]+\@[\w\.\-]+)/) {
		$mail->{from_address} = $1;
	}
	if ($mail->{to} =~ /<([\w\.\-]+\@[\w\.\-]+)>/ || $mail->{to} =~ /([\w\.\-]+\@[\w\.\-]+)/) {
		$mail->{to_address} = $1;
	}
	if ($mail->{reply_to} =~ /<([\w\.\-]+\@[\w\.\-]+)>/ || $mail->{reply_to} =~ /([\w\.\-]+\@[\w\.\-]+)/) {
		$mail->{reply_to_address} = $1;
	}

	#----------------------------------------
	# 本文の解析
	#----------------------------------------
	my $boundary;
	{
		my $from_code='JIS';
		my $type = $mail->{content_type};
		if ($type =~ /charset="(.*?)"/i) { $from_code=$1; }
		if ($type !~ m#^multipart/\w+;\s*boundary=(?:"(.*?)"|([^\s]*))#i) {
			if ($self->{debug}) { print "[Mail.pm] mail is simple\n"; }
			my $text = join('', @$ary);
			$text = $self->decode_quoted_printable($mail->{content_transfer_encoding}, $text);
			$jcode->from_to(\$text, $from_code, $code);
			$text = $self->decode_rfc3676( $type, $text );
			$mail->{text} = $text;
			return $mail;
		}
		$boundary = "--$1$2";
	}

	#----------------------------------------
	# マルチパートの解析
	#----------------------------------------
	my $b1 = $boundary;
	my $b2 = "$boundary--";
	if ($self->{debug}) { print "[Mail.pm] mail is multipart\n"; }

	my @attaches;
	$mail->{attaches} = \@attaches;
	my $count=0;
	while(@$ary) {
		my $x = shift(@$ary);
		$x =~ s/[\r\n]//g;
		if ($x ne $boundary && $x ne $b2) { next; }
		while(@$ary) {
			my $h = $self->parse_mail_header($ary);
			my $type   = $h->{content_type};
			my $encode = $h->{content_transfer_encoding};
			# 添付ファイル
			$encode =~ tr/A-Z/a-z/;
			if ($encode eq 'base64') {
				$h->{filename} = 'file' . (++$count);
				# 添付ファイル名は Content-Disposition を優先する
				my $x = $self->parse_header_line( $h->{content_disposition}, $code );
				if (exists $x->{filename}) {
					$h->{filename} = $x->{filename};
				} else {
					# Content-type からファイル名取得
					my $x = $self->parse_header_line( $type, $code );
					if (exists $x->{name}) {
						$h->{filename} = $x->{name};
					}
				}
				$h->{data} = $self->read_until_boundry($ary, $boundary, 1);
				if ($self->{debug}) {
					print "[Mail.pm] Attachement file: $h->{filename} ",length($h->{data})," byte\n\n";
				}
				push(@attaches, $h);

			# textメール文、htmlメール文
			} elsif (($encode eq '' || $encode eq '7bit' || $encode eq '8bit' || $encode =~ /quoted-printable/)
			      && ($type =~ m|^(text)/plain;| || $type =~ m|^text/(html);|)) {
				my $ctype = $1;
				my $v = $self->read_until_boundry($ary, $boundary);
				$v = $self->decode_quoted_printable($encode, $v);
				# 文字コード変換
				my $from_code = 'JIS';
				if ($type =~ /charset="(.*?)"/i || $type =~ /charset=([^\s;]*)/i) { $from_code=$1; }
				$jcode->from_to(\$v, $from_code, $code);
				$v = $self->decode_rfc3676( $type, $v );
				$mail->{$ctype} = $v;
				if ($self->{debug}) {
					print "\n\n$ctype=$v\n";
				}
			}
		}
	}
	return $mail;
}

#-----------------------------------------------------------
# ○multipart を境界まで読む
#-----------------------------------------------------------
sub read_until_boundry {
	my ($self, $ary, $boundary, $base64) = @_;
	my $b2 = "$boundary--";
	my $data;
	while(@$ary) {
		my $x = shift(@$ary);
		$x =~ s/[\r\n]//g;
		if ($x eq $boundary || $x eq $b2) { last; }
		if ($base64) { $data .= $self->base64decode($x); next; }
		$data .= "$x\n";
	}
	return $data;
}

#------------------------------------------------------------------------------
# ●メールヘッダの解析
#------------------------------------------------------------------------------
sub parse_mail_header {
	my ($self, $ary, $code) = @_;
	my %h;
	my ($n, $v);
	while(@$ary) {
		my $x = shift(@$ary);
		$x =~ s/[\r\n]//g;
		if ($x =~ /^([ \t]+.*)/) { $v.=$1; next; } # RFC 2822 FWS / RFC 2234 WSP
		if (defined $n) {
			$n =~ tr/A-Z\-/a-z_/;
			if (defined $code) {
				$v = $self->mime_decode_line($v, $code);
			}
			$h{$n} = $v;
			if ($self->{debug}) {
				print "[Mail.pm] Header: $n=$v\n";
			}
			undef $n;
		}
		# 新たなヘッダ
		if ($x =~ /^([\w\-]+):\s*(.*)/) {
			$n = $1;
			$v = $2;
		}
		if ($x eq '') { last; }
	}
	return \%h;
}

###############################################################################
# ■MIME base64エンコード/デコード
###############################################################################
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

#------------------------------------------------------------------------------
# ●エンコード
#------------------------------------------------------------------------------
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
#------------------------------------------------------------------------------
# ●デコード
#------------------------------------------------------------------------------
sub mime_decode_line {
	my $self = shift;
	my $line = shift;
	my $code = shift;
	my $ROBJ = $self->{ROBJ};

	if ($line !~ /=\?.*\?=/) { return $line; }
	$line =~ s/\x00//g;
	my @buf;
	my $mime_code;
	# MIMEデコードをしてエスケープ表記"\0 num \0"に置き換え
	$line =~ s/=\?([\w\-]*)\?[Bb]\?([A-Za-z0-9\+\/=]*)\?=/
		$mime_code = $1;
		push(@buf, $self->base64decode($2));
		"\x00$#buf\x00";
	/eg;
	# RFC 2047
	$line =~ s/\x00[\t ]+\x00/\x00\x00/g;
	# buffer復元
	$line =~ s/\x00(\d+)\x00/$buf[$1]/g;
	# 文字コード変換
	if ($mime_code && $code) {
		my $jcode = $ROBJ->load_codepm();
		$jcode->from_to(\$line, $mime_code, $code);
	}
	return $line;
}
sub parse_header_line {		# RFC2231準拠
	my $self = shift;
	my $line = shift;
	my $code = shift;
	my $ROBJ = $self->{ROBJ};
	my $jcode = $ROBJ->load_codepm();

	# stringの保存
	my @str;
	$line =~ s/"(.*?)"/push(@str, $1), "\x00$#str\x00"/eg;

	my %h;
	foreach(split(/\s*;\s*/, $line)) {
		# str復元
		$_ =~ s/\x00(\d+)\x00/$str[$1]/g;
		if ($_ =~ /^\s*(.*?)=(.*?)\s*$/) {
			my $key = $1;
			my $val = $2;
			$key =~ tr/-/_/;
			if ($key =~ /^(.*?\*)\d+\*?$/) {
				$key = $1;
				$h{$key} .= $val;
			} else {
				$h{$key} = $val;
			}
		} elsif (!exists $h{_}) {
			$h{_} = $_;
		}
	}
	foreach(keys(%h)) {
		# RFC2231 '*'表記の展開とMIME処理
		#（例）filename*=iso-2022-jp''%1B%24B%3CL%3F%3F%1B%28B.jpg
		my $val = $h{$_};
		if ($_ =~ /^(.*?)\*$/) {
			my $key = $1;
			delete $h{$_};
			if ($val =~ /^(.*?)'.*?'(.*)$/) {
				my $val_code = $1;
				$val = $2;
				$val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
				$jcode->from_to(\$val, $val_code, $code);
			}
			$h{$key} = $val;
		} else {
			$h{$_} = $self->mime_decode_line($val, $code);
		}
	}
	return \%h;
}

sub decode_rfc3676 {		# RFC2231準拠
	my $self = shift;
	my $type = shift;
	my $text = shift;

	if ($type !~ m|text/plain|i || $type !~ /format=flowed/i) {
		return $text;
	}
	$text =~ s/(^|\n) /$1/g;
	if ($type =~ /delsp=yes/i) {
		$text =~ s/ \r?\n//g;
	} else {
		$text =~ s/ \r?\n/ /g;
	}
	return $text;
}

sub decode_quoted_printable {	# Content-Transfer-Encoding: quoted-printable
	my $self = shift;
	my $ct_enc = shift;
	my $text = shift;

	if ($ct_enc !~ m|quoted-printable|i) {
		return $text;
	}
	$text =~ s/=([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
	$text =~ s/=\r?\n//sg;
	return $text;
}

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
