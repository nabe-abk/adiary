use strict;
#------------------------------------------------------------------------------
# HTTPモジュール
#						(C)2006-2017 nabe / nabe@abk
#------------------------------------------------------------------------------
# 簡易実装の HTTP モジュールです。
#
package Satsuki::Base::HTTP;
our $VERSION = '1.32';
#------------------------------------------------------------------------------
use Socket;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	my $ROBJ = shift;

	$self->{ROBJ}    = $ROBJ;
	$self->{cookie}  = {};	# 空の hash
	$self->{timeout} = 30;
	$self->{auto_redirect} = 1;	# リダイレクト処理を１回だけ追う
	if (defined $ROBJ) {
		$self->{http_agent} = "Satsuki-system $ROBJ->{VERSION} ";
	}
	$self->{http_agent} = "Simple HTTP agent $VERSION";
	$self->{use_cookie} = 0;
	return $self;
}
#------------------------------------------------------------------------------
# ●【デストラクタ】
#------------------------------------------------------------------------------
sub DESTROY {
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ホストに対して処理する
#------------------------------------------------------------------------------
sub get_data {
	my $self = shift;
	my $host = shift;
	my $port = shift;

	my $socket = $self->connect_host($host, $port);
	if (!defined $socket) { return ; }
	my $res = $self->send_http_request($socket, $host, @_);
	if (!defined $res) { return ; }
	close($socket);

	return $res;
}

#------------------------------------------------------------------------------
# ●指定ホストに接続する
#------------------------------------------------------------------------------
sub connect_host {
	my ($self, $host, $port) = @_;

	my $ip_bin = inet_aton($host);		# IP 情報に変換
	if ($ip_bin eq '') {
		return $self->error(undef, "Can't find host '%s'", $host);
	}
	my $sockaddr = pack_sockaddr_in($port, $ip_bin);
	my $sh; # = Symbol::gensym();
	if (! socket($sh, Socket::PF_INET(), Socket::SOCK_STREAM(), 0)) {
		return $self->error(undef, "Can't open socket");
	}
	{
		local $SIG{ALRM} = sub { close($sh); };
		alarm( $self->{timeout} );
		if (! connect($sh, $sockaddr)) {
			return $self->error($sh, "Can't connect %s", $host);
		}
		alarm(0);
	}

	return $sh;
}

#------------------------------------------------------------------------------
# ●GET, POST, HEAD などを送り、データを受信する
#------------------------------------------------------------------------------
sub send_http_request {
	my $self   = shift;
	my $socket = shift;
	my $host   = shift;
	my $ROBJ   = $self->{ROBJ};
	{
		my $request = join('', @_);
		syswrite($socket, $request, length($request));
		$self->{debug_file} && $ROBJ->fappend_lines($self->{debug_file}, $request);
	}
	my @response;
	my $vec_in = '';
	vec($vec_in, fileno($socket), 1) = 1;
	my ($r, $timeout);
	{
		local $SIG{ALRM} = sub { close($socket); $timeout=1; };
		alarm( $self->{timeout} );
		$r = select($vec_in, undef, undef, $self->{timeout});
		if (vec($vec_in, fileno($socket), 1) ) {
			@response = <$socket>;
		}
		alarm(0);
		close($socket);
	}
	$self->{debug_file} && $ROBJ->fappend_lines($self->{debug_file}, \@response);
	if (! @response) {
		if (!$r || $timeout) {
			return $self->error($socket, "Connection timeout '%s' (timeout %d sec)", $host, $self->{timeout});
		}
		return $self->error($socket, "Connection closed by '%s'", $host);
	}

	$self->parse_status_line($response[0], $host);
	return \@response;
}

#-------------------------------------------------
# ●status lineの処理
#-------------------------------------------------
sub parse_status_line {
	my $self   = shift;
	my $status = int( (split(' ', shift))[1] );
	my $host   = shift;
	$self->{status} = $status;
	if ($status != 200 && ($status<301 || 304<$status)) {
		return $self->error(undef, "Error response from '%s' (status %d)", $host, $status);
	}
}



###############################################################################
# ■上位サービスルーチン
###############################################################################
# Cookie実装ポリシー
#	・expires は無視（すべてsession cookieとして処理）
#------------------------------------------------------------------------------
# ●cookieのon/off（デフォルト:off）
#------------------------------------------------------------------------------
sub cookie_on {
	my $self = shift;
	$self->{use_cookie} = 1;
}
sub cookie_off {
	my $self = shift;
	$self->{use_cookie} = 0;
}

#------------------------------------------------------------------------------
# ●指定したURLからGET/POSTし、中身データを返す
#------------------------------------------------------------------------------
#-----------------------------------------------------------
# GET/POSTとRedirect処理
#-----------------------------------------------------------
sub get {
	my $self = shift;
	return $self->request('GET',  @_);
}
sub post {
	my $self = shift;
	return $self->request('POST', @_);
}
sub request {
	my $self = shift;
	my $method = shift;
	my $url = shift;
	$self->{redirects} = 0;
	while (1) {
		my $r = $self->do_request($method, $url, @_);
		# 正常終了
		my $status = $self->{status};
		if (!$self->{location} || $status<301 || 303<$status || (++$self->{redirects}) > $self->{auto_redirect}) {
			return wantarray ? ($status, $self->{header}, $r) : $r;
		}
		# Redirect
		$url = $self->{location};
	}
}
#-----------------------------------------------------------
# リクエスト処理本体
#-----------------------------------------------------------
sub do_request {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my ($method, $url, $_header, $post_data) = @_;
	my $cookie = $self->{cookie};
	my $https = ($url =~ m|^https://|i);

	if ($url !~ m|^https?://([^/:]*)(:(\d+))?(.*)|) {
		return $self->error(undef, "URL format error '%s'", $url);
	}
	my $host = $1;
	my $port = $3 || ($https ? 443 : 80);
	my $path = $4 || '/';
	#----------------------------------------------------------------------
	# Cookieの処理
	#----------------------------------------------------------------------
	my $http_cookie;
	if ($self->{use_cookie}) {
		my @send_cookies;
		while(my ($k,$v) = each(%$cookie)) {
			$k =~ /(.*);/;
			my $chost = $1;
			if ($chost eq $host
			 || (substr($chost, 0, 1) eq '.' && index($host, substr($chost, 1)) >=0) ) {
			 	if ($v->{path} && index($path, $v->{path}) < 0) { next; }
			 	if ($v->{value} eq '') { next; }	# 空のcookieは無視
				$http_cookie .= "$v->{name}=$v->{value};";
				# print "Cookie : $v->{name}=$v->{value}\n";
			}
		}
		if ($http_cookie) { $http_cookie = "Cookie: $http_cookie\r\n"; }
	}

	#----------------------------------------------------------------------
	# ヘッダの初期処理
	#----------------------------------------------------------------------
	my %header;
	if (ref($_header) eq 'HASH') { %header = %$_header; }	# copy
	$header{Host} ||= $host;
	$header{'User-Agent'} ||= $self->{http_agent};

	#----------------------------------------------------------------------
	# POSTリクエスト
	#----------------------------------------------------------------------
	my $content;
	if ($method eq 'POST') {
		if (ref($post_data) eq 'HASH') {
			while(my ($k,$v) = each(%$post_data)) {
				$ROBJ->encode_uricom($k,$v);
				$content .= "$k=$v&";
			}
			chop($content);
		} else {
			$content = $post_data;
		}
		if (!$https) {
			# Net::SSLeay::post_https は自動付加するので付けない
			$header{'Content-Length'} = length($content);
			$header{'Content-Type'} ||= 'application/x-www-form-urlencoded';
		}
	}

	#----------------------------------------------------------------------
	# ヘッダの構成初期処理
	#----------------------------------------------------------------------
	my $header;
	foreach(keys(%header)) {
		if ($_ eq '' || $_ =~ /[^\w\-]/) { next; }
		my $v = $header{$_};
		$v =~ s/^\s*//;
		$v =~ s/[\s\r\n]*$//;
		$header .= "$_: $v\r\n";
	}
	$header .= $http_cookie;

	#----------------------------------------------------------------------
	# HTTPリクエストの発行
	#----------------------------------------------------------------------
	# $self->{ROBJ}->debug($header);
	# $self->{ROBJ}->debug($content);
	my $res;
	if ($https) {
		eval { require Net::SSLeay; };
		if ($@) {
			return $self->error(undef, "Net::SSLeay module not found (please install this server)");
		}
		my ($page, $result, @headers);
		if ($method eq 'POST') {
			($page, $result, @headers) = Net::SSLeay::post_https($host, $port, $path, $header, $content);
		} else {
			($page, $result, @headers) = Net::SSLeay::get_https ($host, $port, $path, $header);
		}

		$self->parse_status_line($result, $host);

		$res = [ $result ];
		while(@headers) {
			my $name = shift(@headers);
			my $val  = shift(@headers);
			push(@$res, "$name: $val");
		}
		push(@$res, '');
		push(@$res, $page);
	} else {
		my $request = "$method $path HTTP/1.0\r\n$header\r\n$content";
		$res = $self->get_data($host, $port, $request);
		if (ref($res) ne 'ARRAY') { return $res; }	# fail to return
	}

	#----------------------------------------------------------------------
	# ヘッダの解析
	#----------------------------------------------------------------------
	delete $self->{location};
	my $header= $self->{header} = [];
	while(@$res) {
		my $line = shift(@$res);
		$line =~ s/[\r\n]//g;		# 改行除去
		if ($line eq '') { last; }	# ヘッダの終わり
		push(@$header, $line);
		# Cookie
		if ($self->{use_cookie} && $line =~ /^set-cookie:\s*(.*)$/i) {
			my @cookie = split(/\s*;\s*/, $1);
			my %h;
			my $cookie_dom = $host;
			my ($name, $value) = split("=", shift(@cookie));
			$h{name}  = $name;
			$h{value} = $value;
			foreach(@cookie) {
				if ($_ !~ /(.*?)=(.*)/) { next; }
				$h{$1} = $2;
				if ($1 eq 'domain') {
					my $dom = $2;
					if ($dom =~ /\.?([\w\-]+\.[\w\-]+\.[\w\-]+)\.?/) {
						$cookie_dom = '.' . $1;
					}
				}
			}
			$cookie->{"$cookie_dom;$h{name}"} = \%h;	# cookie保存
		}
		# Redirect 
		if ($line =~ /^location:\s*(.*)$/i) {
			$self->{location} = $1;
		}
	}
	return $res;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●タイムアウトの設定
#------------------------------------------------------------------------------
sub set_timeout {
	my ($self, $timeout) = @_;
	$self->{timeout} = $timeout+0 || 30;
}

#------------------------------------------------------------------------------
# ●USER-AGENTの設定
#------------------------------------------------------------------------------
sub set_agent {
	my $self = shift;
	$self->{http_agent} = shift || "Simple HTTP agent $VERSION";
}

###############################################################################
# ■エラー処理
###############################################################################
sub error_to_root {
	my $self = shift;
	$self->{error_to_root} = shift;
}

sub error {
	my $self   = shift;
	my $socket = shift;
	my $error  = shift;
	my $ROBJ   = $self->{ROBJ};
	if (defined $socket) { close($socket); }
	if (defined $ROBJ) {
		if ($self->{error_to_root}) { return $ROBJ->error($error, @_); }
		$error = $ROBJ->message_translate($error, @_);
	} elsif (@_) {
		$error = sprintf($error, @_);
	}
	$self->{error_msg} = $error;
	return undef;
}


1;
