#-----------------------------------------------------------------------------
# WebPush 通知モジュール
#					Copyright(C)2017 nabe@abk / AGPLv3
#-----------------------------------------------------------------------------
sub {

use strict;
#-----------------------------------------------------------------------------
my $ECC_NAME = 'prime256v1';
my $VAPID = 1;
my $UNIT  = 50;		# 1度に送信する単位
my $TTL   = 86400;
my @SITES = map { qr/$_/ }	# white list
	qw(	^https://fcm\.googleapis\.com/
		^https://updates\.push\.services\.mozilla\.com/
		^https://\w+\.notify\.windows\.com/
	);

###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●コンストラクタ（無名クラスを生成する）
#------------------------------------------------------------------------------
my $mop;
my $name;
{
	my $aobj = shift;
	$name = shift;
	my $ROBJ = $aobj->{ROBJ};
	my $self = $ROBJ->loadpm('MOP', $aobj->{call_file});	# 無名クラス生成用obj

	# Global var
	$self->{aobj} = $aobj;
	$self->{data_file} = $aobj->{blog_dir} . 'webpush.dat';

	#-----------------------------------------------------------------------
	# ●イベント処理（新記事公開）
	#-----------------------------------------------------------------------
	if ($aobj->{event_name} eq 'ARTICLE_FIRST_VISIBLE_PING') {
		my $art  = shift;

		# 新着記事で送信しない
		if (!$aobj->load_plgset($name, 'ping')) { return; }

		# 購読者がいなければ何もしない
		my $cnt = $aobj->load_plgset($name, 'cnt');
		if (!$cnt) { return; }

		$ROBJ->notice('sending webpush');

		# 公開情報登録（通知処理は遅延実行）
		my $url = $art->{absolute_url};
		if (!$url) { return; }
		my $title = $art->{title} ne '' ? $art->{title} : 'new article';

		$aobj->update_plgset($name, 'url',   $url   );
		$aobj->update_plgset($name, 'title', $title );
		$aobj->update_plgset($name, 'tag',   'art-' . $art->{pkey} . '-' . $art->{update_tm} );
		return 0;
	}
	$mop = $self;
}

###############################################################################
# ■スケルトン用サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●登録
#------------------------------------------------------------------------------
$mop->{regist} = sub {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my %h;
	my $endp = $ROBJ->encode_uri( $form->{endp_txt} );
	my $cpub = $form->{key_txt};
	my $auth = $form->{auth_txt};
	$cpub =~ s/[^\w\-]//g;
	$auth =~ s/[^\w\-]//g;

	# Firefoxで http でテストしていると、後ろに :443 が付く
	$endp =~ s|^(https://[^/:]+):443|$1|;

	# URL white list check
	my $ok;
	if (! $aobj->load_plgset($name, 'unknown_server')) {
		foreach(@SITES) {
			if ($endp =~ /$_/) { $ok=1; last; }
		}
		if (!$ok) { return -1; }
	}

	# 重複チェック
	my ($fh, $list) = $ROBJ->fedit_readlines($self->{data_file});
	foreach(@$list) {
		my $url = substr($_,0,index($_,' '));
		if ($url eq $endp) {	# すでに登録済
			$ROBJ->fedit_exit($fh);
			return 0;
		}
	}

	# 最大数チェック
	my $max = $aobj->load_plgset($name, 'max') || 1000;
	if (($#$list+1) > $max) {
		$ROBJ->fedit_exit($fh);
		return 1;
	}

	push(@$list, "$endp $cpub $auth\n");
	$self->save_list($fh, $list);
	return 0;
};

#------------------------------------------------------------------------------
# ●登録リセット
#------------------------------------------------------------------------------
$mop->{reset} = sub {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	# 中身を空にする
	my ($fh, $list) = $ROBJ->fedit_readlines($self->{data_file});
	$self->save_list($fh, []);

	# ファイルを削除する
	$ROBJ->file_delete($self->{data_file});

	# ServerKeyの再生成
	require Crypt::PK::ECC;
	my $pk = Crypt::PK::ECC->new();
	$pk->generate_key($ECC_NAME);
	$aobj->update_plgset($name, 'spub', $self->base64urlsafe($pk->export_key_raw('public' )) );
	$aobj->update_plgset($name, 'sprv', $self->base64urlsafe($pk->export_key_raw('private')) );

	return 0;
};

###############################################################################
# ■通知送信処理
###############################################################################
#------------------------------------------------------------------------------
# ●送信
#------------------------------------------------------------------------------
$mop->{send} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};
	my $blog = $aobj->{blog};
	my $ps   = $aobj->load_plgset($name);

	my %h;
	$h{spub} = $self->base64decode( $ps->{spub} );
	$h{sprv} = $self->base64decode( $ps->{sprv} );
	$h{mpub} = $self->base64decode( $ps->{mpub} );
	$h{mprv} = $self->base64decode( $ps->{mprv} );

	# 送信データ
	my $data;
	my $tag = $ps->{tag};
	{
		my $bname = $blog->{blog_name};
		my $title = $ps->{title};
		$ROBJ->tag_unescape($bname, $title);

		my $msg = $ps->{msg} || $ps->{ping_txt} || "new article\n\n%t";
		$msg  =~ s/%t/$title/g;		# 記事タイトル
		$msg  =~ s/%u/$ps->{url}/g;	# URL

		my $icon = $aobj->{blog}->{iconfile}
			|| $aobj->{pubdist_dir} . 'icon.png';
		$icon .= '?' . $ROBJ->get_lastmodified($icon);
		$data = $ROBJ->generate_json({
			title => $bname,
			body  => $msg,
			tag   => $tag,
			icon  => $ROBJ->{Basepath} . $icon,
			data  => { url => $ps->{url} }
		});
	}

	my ($fh, $list) = $ROBJ->fedit_readlines($self->{data_file}, { NB=>1 });
	if (!$fh) {		# lock に失敗したら何もしない
		return $ROBJ->{Develop} ? 'lock fail' : undef;
	}

	#-----------------------------------------------
	# 送信処理
	#-----------------------------------------------
	my @log;
	my ($send, $_tag) = split(' ', shift(@$list), 2);
	chomp($_tag);
	if ($_tag ne $ps->{tag}) { $send=0; }	# タグが異なれば新しい通知

	# 送信済分を除く
	my @ary = ($send, splice(@$list, 0, $send));

	my $c=0;
	while(@$list) {
		my $x = shift(@$list);
		my ($endp, $cpub, $auth) = split(' ', $x, 3);
		chomp($auth);
		$h{endp} = $endp;
		$h{cpub} = $self->base64decode( $cpub );
		$h{auth} = $self->base64decode( $auth );

		my $r;
		eval { $r = $self->webpush(\%h, $data) };
		push(@log, "POST $r : $@ $endp\n");
		if (!$r && !$@) {		# errorなし
			push(@ary, $x);		# 次回も送信する
		}
		$c++;
		if ($c >= $UNIT) { last; }	# $UNIT = 一回当たりの送信数
	}
	$send = $#ary;		# 送信済数

	# 残り
	if (@$list) {
		push(@ary, @$list);
		$ary[0] = $send . ($send ? ' ' . $ps->{tag} : '') . "\n";
	} else {
		# 送信終了
		$aobj->update_plgset($name, 'url',   undef );
		$aobj->update_plgset($name, 'title', undef );
		$aobj->update_plgset($name, 'msg',   undef );
		push(@log, "name=$name\n");

		$ary[0] = "0\n";
	}
	$self->save_list($fh, \@ary);

	return $ROBJ->{Develop} ? ("send=$send\n",@log) : 0;
};

#------------------------------------------------------------------------------
# ●通知を送信
#------------------------------------------------------------------------------
$mop->{webpush} = sub {
	my $self = shift;
	my $h    = shift;
	my $data = shift;
	my $ROBJ = $self->{ROBJ};

	# Require
	require Crypt::PK::ECC;
	require Crypt::AuthEnc::GCM;
	require Crypt::Mac::HMAC;
	require Crypt::Digest::SHA256;

	# Parameters
	my $url  = $h->{endp};
	my $spub = $h->{spub};	# ServerKey
	my $sprv = $h->{sprv};
	my $mpub = $h->{mpub};	# Message
	my $mprv = $h->{mprv};
	my $cpub = $h->{cpub};	# Client pub key
	my $auth = $h->{auth};
	my $salt = $ROBJ->get_rand_string(16);

	my $secret;
	{
		my $pk1 = Crypt::PK::ECC->new();
		my $pk2 = Crypt::PK::ECC->new();
		$pk1->import_key_raw($mprv, $ECC_NAME);
		$pk2->import_key_raw($cpub, $ECC_NAME);
		$secret = $pk1->shared_secret($pk2);
	}

	#-------------------------------------------------------------------
	# Encryption (aes128gcm)
	#-------------------------------------------------------------------
	my $header;
	my $body;
	{
		my $prk   = $self->hkdf($auth, $secret, "WebPush: info\x00$cpub$mpub"    , 32);
		my $cek   = $self->hkdf($salt, $prk,    "Content-Encoding: aes128gcm\x00", 16);
		my $nonce = $self->hkdf($salt, $prk,    "Content-Encoding: nonce\x00",     12);

		$data = substr($data, 0, 3992);		# limiter

		# body header / N is 4byte network byte order (big eddian)
		$body  = $salt . pack('N', 4096) . pack('C', length($mpub)) . $mpub;

		# AES-GCM
		my $ae = Crypt::AuthEnc::GCM->new('AES', $cek);
		$ae->iv_add($nonce);
		$body	.= $ae->encrypt_add($data . "\x02\x00")
		  	.  $ae->encrypt_done();		# tag (16byte)

		$header = {
			'Content-Encoding' => 'aes128gcm'
		}
	}

	#-------------------------------------------------------------------
	# VAPID
	#-------------------------------------------------------------------
	my $vapid_jwt;
	if ($VAPID) {
		my $info = '{"typ":"JWT", "alg":"ES256"}';
		my $data = {
			sub => $ROBJ->{Server_url} . $self->{aobj}->{myself},
			exp => time() + $TTL
		};
		if ($url =~ m|^(\w+://[^/]*)|) {
			$data->{aud} = $1;
		}
		$data = $ROBJ->generate_json($data);

		my $jwt = $self->base64urlsafe($info) . '.' . $self->base64urlsafe($data);

		my $pk3 = Crypt::PK::ECC->new();
		$pk3->import_key_raw($sprv, $ECC_NAME);
		my $sign_der = $pk3->sign_message($jwt, 'SHA256');
		my $sign     = $self->parse_ANS1_der( $sign_der );	# ASN.1 DER format to Binary

		$vapid_jwt  = $jwt . '.' . $self->base64urlsafe($sign);

		$header->{'Crypto-Key'} .= ($header->{'Crypto-Key'} ? ';' : '') . 'p256ecdsa=' . $self->base64urlsafe($spub);
		$header->{Authorization} = 'Webpush ' . $vapid_jwt;
	}

	#-------------------------------------------------------------------
	# POST
	#-------------------------------------------------------------------
	my $http = $ROBJ->loadpm('Base::HTTP');
	
	$header->{TTL} = $TTL;

	my $r  = $http->post($url, $header, $body);
	my $st = $http->{status};

	return (200<=$st && $st<300) ? 0 : $http->{status};
};

#------------------------------------------------------------------------------
# ●HMAC
#------------------------------------------------------------------------------
$mop->{hkdf} = sub {
	my $self = shift;
	my $salt = shift;
	my $ikm  = shift;
	my $info = shift;
	my $len  = shift;

	my $prk  = Crypt::Mac::HMAC::hmac('SHA256', $salt, $ikm);
	my $info = Crypt::Mac::HMAC::hmac('SHA256', $prk,  "$info\x01");
	return substr($info, 0, $len);
};

#------------------------------------------------------------------------------
# ●Parse ASN.1 DER format
#------------------------------------------------------------------------------
#	+00h	30h	SEQUENCE
#	+01h	--	SEQUENCE Length
#	+02h	02h	Tag
#	+03h	x	R Length
#	+04h	--	R
#	x+4	02h	Tag
#	x+5	y	S Length
#	x+6	--	S
$mop->{parse_ANS1_der} = sub {
	my $self = shift;
	my $der  = shift;

	my $x = ord(substr($der,   3,1));
	my $y = ord(substr($der,$x+5,1));
	my $r = substr(substr($der,    4, $x), -32);
	my $s = substr(substr($der, $x+6, $y), -32);
	return $r . $s;
};

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●dataファイルロード
#------------------------------------------------------------------------------
$mop->{load_list} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $self->{list}
	   || ($self->{list} = $ROBJ->fread_lines_no_error( $self->{data_file} ));
};

#------------------------------------------------------------------------------
# ●オープン済のdataファイルに書き込み
#------------------------------------------------------------------------------
$mop->{save_list} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};
	my ($fh, $list) = @_;

	if ($list->[0] !~ /^\d+/) {
		unshift(@$list, "0\n");		# 送信済数
	}
	$ROBJ->fedit_writelines($fh, $list);
	$aobj->update_plgset($name, 'cnt', $#$list);
};

#------------------------------------------------------------------------------
# ●URL safe base64
#------------------------------------------------------------------------------
$mop->{base64urlsafe} = sub {
	my $self = shift;
	my $str  = shift;
	my $ret  = '';
	my $table='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

	# 2 : 0000_0000 1111_1100
	# 4 : 0000_0011 1111_0000
	# 6 : 0000_1111 1100_0000
	my ($i, $j, $x);
	for($i=$x=0, $j=2; $i<length($str); $i++) {
		$x    = ($x<<8) + ord(substr($str,$i,1));
		$ret .= substr($table, ($x>>$j) & 0x3f, 1);

		if ($j != 6) { $j+=2; next; }
		# j==6
		$ret .= substr($table, $x & 0x3f, 1);
		$j    = 2;
	}
	if ($j != 2) { $ret .= substr($table, ($x<<(8-$j)) & 0x3f, 1); }
	return $ret;
};

#------------------------------------------------------------------------------
# ●Base64 decode / normal and urlsafe
#------------------------------------------------------------------------------
$mop->{base64decode} = sub {
	my @table = (
	 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x00?0x1f
	 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0, 0,  0, 0, 0, 0,	# 0x10?0x1f
	 0, 0, 0, 0,  0, 0, 0, 0,   0, 0, 0,62,  0,62, 0,63,	# 0x20?0x2f
	52,53,54,55, 56,57,58,59,  60,61, 0, 0,  0, 0, 0, 0,	# 0x30?0x3f
	 0, 0, 1, 2,  3, 4, 5, 6,   7, 8, 9,10, 11,12,13,14,	# 0x40?0x4f
	15,16,17,18, 19,20,21,22,  23,24,25, 0,  0, 0, 0,63,	# 0x50?0x5f
	 0,26,27,28, 29,30,31,32,  33,34,35,36, 37,38,39,40,	# 0x60?0x6f
	41,42,43,44, 45,46,47,48,  49,50,51, 0,  0, 0, 0, 0	# 0x70?0x7f
	);
	my $self = shift;
	my $str  = shift;

	my $ret;
	my $buf;
	my $f;
	$str =~ s/[=\.]+$//;
	for(my $i=0; $i<length($str); $i+=4) {
		$buf  = ($buf<<6) + $table[ ord(substr($str,$i  ,1)) ];
		$buf  = ($buf<<6) + $table[ ord(substr($str,$i+1,1)) ];
		$buf  = ($buf<<6) + $table[ ord(substr($str,$i+2,1)) ];
		$buf  = ($buf<<6) + $table[ ord(substr($str,$i+3,1)) ];
		$ret .= chr(($buf & 0xff0000)>>16) . chr(($buf & 0xff00)>>8) . chr($buf & 0xff);
	}
	my $f = length($str) & 3;	# mod 4
	if ($f >1) { chop($ret); }
	if ($f==2) { chop($ret); }
	return $ret;
};

###############################################################################
###############################################################################
	return $mop;
}

