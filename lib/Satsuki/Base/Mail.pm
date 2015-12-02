use strict;
#------------------------------------------------------------------------------
# メール送受信モジュール
#						(C)2006-2009 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::Base::Mail;
our $VERSION = '1.03';
#------------------------------------------------------------------------------
# ●sendmailコマンドのDetect
#------------------------------------------------------------------------------
my $sendmail_cmd;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{mailer} = "Satsuki::Base::Mail";

	# sendmail コマンドのチェック
	my @search = qw(/usr/sbin /usr/bin /usr/lib);
	foreach(@search) {
		if (-x "$_/sendmail") { $sendmail_cmd = "$_/sendmail"; }
	}

	$self->{__CACHE_PM} = 1;
	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●メール送信
#------------------------------------------------------------------------------
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

	if ($to   eq '') { $ROBJ->message('"To" is invalid');   return 1; }
	# if ($from eq '') { $ROBJ->message('"From" is invalid'); return 2; }
	if ($sendmail_cmd eq '') { $ROBJ->message('"sendmail" command not found'); return -1; }
	my $from_orig = $from;

	# テキスト系
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

	# JISコード変換処理
	my $jcode = $ROBJ->load_codepm();
	foreach($from_name, $to_name, $cc_name, $subject, $text) {
		$_ = $jcode->from_to($_, $ROBJ->{System_coding}, $jcode->{email_default});
	}
	# MIME
	$self->mime_encode($from_name, $to_name, $cc_name, $subject);

	# from, to の加工
	if ($from_name) { $from = "$from_name <$from>"; }
	if ($to_name)   { $to   = "$to_name <$to>"; }
	if ($cc_name)   { $cc   = "$cc_name <$cc>"; }

	#-------------------------------------------------------
	# ○メール送信
	#-------------------------------------------------------
	if (!-x $sendmail_cmd) {
		$ROBJ->message('sendmail command not found');
		return 10;
	}
	my $fh;
	if (! open($fh, "| $sendmail_cmd -t -i -f '$from_orig'")) {
		$ROBJ->message('Internal Error'); return 11;
	}
	if ($cc)    { print $fh "Cc: $cc\n"; }
	if ($bcc)   { print $fh "Bcc: $bcc\n"; }
	if ($repto) { print $fh "Reply-To: $repto\n"; }
	if ($retph) { print $fh "Return-Path: $retph\n"; }
	if ($from)  { print $fh "From: $from\n"; }
print $fh <<END;
To: $to
Subject: $subject
Return-Path: $from_orig
MIME-Version: 1.0
Content-Type: text/plain; charset="$jcode->{email_default}"
Content-Transfer-Encoding: 7bit
X-Mailer: $self->{mailer}
END
	if ($h->{x}){ chomp($h->{x}); print $fh "$h->{x}\n"; }
	print $fh "\n$text";
	close($fh);
	return 0;
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
 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0,62,  0, 0, 0,63,	# 0x20〜0x2f
52,53,54,55, 56,57,58,59,  60,61, 0, 0,  0, 0, 0, 0,	# 0x30〜0x3f
 0, 0, 1, 2,  3, 4, 5, 6,   7, 8, 9,10, 11,12,13,14,	# 0x40〜0x4f
15,16,17,18, 19,20,21,22,  23,24,25, 0,  0, 0, 0, 0,	# 0x50〜0x5f
 0,26,27,28, 29,30,31,32,  33,34,35,36, 37,38,39,40,	# 0x60〜0x6f
41,42,43,44, 45,46,47,48,  49,50,51, 0,  0, 0, 0, 0	# 0x70〜0x7f
);

#------------------------------------------------------------------------------
# ●エンコード
#------------------------------------------------------------------------------
sub mime_encode {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(\e\$[\@B].*?\e\([BJ])/ '=?ISO-2022-JP?B?' . $self->base64encode($1) . '?=' /eg;
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
	my ($i, $j, $x, $y);
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

sub base64decode {
	my $self = shift;
	my $str  = shift;

	my $ret;
	my $buf;
	my $f;
	if (substr($str, -1) eq  '=') { $f=1; }
	if (substr($str, -2) eq '==') { $f=2; }
	for(my $i=0; $i<length($str); $i+=4) {
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i  ,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+1,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+2,1)) ];
		$buf  = ($buf<<6) + $base64ary[ ord(substr($str,$i+3,1)) ];
		$ret .= chr(($buf & 0xff0000)>>16) . chr(($buf & 0xff00)>>8) . chr($buf & 0xff);

	}
	if ($f>0) { chop($ret); }
	if ($f>1) { chop($ret); }
	return $ret;
}

###############################################################################
# ●sendmailコマンドの存在確認
###############################################################################
sub get_sendmail_cmd {
	return $sendmail_cmd;
}

1;
