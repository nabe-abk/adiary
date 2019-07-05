use strict;
#------------------------------------------------------------------------------
# HTTPモジュール
#						(C)2006-2019 nabe / nabe@abk
#------------------------------------------------------------------------------
# 簡易実装の HTTP モジュールです。
#
package Satsuki::Base::HTTP;
our $VERSION = '1.40';
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
	$self->{ROBJ} = $ROBJ;

	$self->{cookie}     = {};
	$self->{use_cookie} = 0;
	$self->{timeout}    = 30;
	$self->{redirect}   = 5;	# リダイレクト処理を行う回数
	$self->{use_sni}    = 1;	# use SNI

	$self->{http_agent} = "Simple HTTP agent $VERSION";
	# $self->{log_file} = 'http.log';	# (DEBUG) connection log

	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ホストに対して処理する
#------------------------------------------------------------------------------
sub get_data {
	my $self = shift;
	return $self->do_get_data('send_http_request',  @_);
}
sub get_data_ssl {
	my $self = shift;
	return $self->do_get_data('send_https_request', @_);
}
sub do_get_data {
	my $self = shift;
	my $func = shift;
	my $host = shift;
	my $port = shift;
	$self->{error} = undef;

	my $sock = $self->connect_host($host, $port);
	if (!defined $sock) { return ; }
	my $res = $self->$func($sock, $host, @_);
	if (!defined $res) { return ; }
	close($sock);

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
	my $sh;
	if (! socket($sh, Socket::PF_INET(), Socket::SOCK_STREAM(), 0)) {
		return $self->error(undef, "Can't open socket");
	}
	{
		local $SIG{ALRM} = sub { close($sh); };
		alarm( $self->{timeout} );
		my $r = connect($sh, $sockaddr);
		alarm(0);
		$r || return $self->error($sh, "Can't connect %s", $host);
	}

	binmode($sh);
	return $sh;
}

#------------------------------------------------------------------------------
# ●GET, POST, HEAD などを送り、データを受信する
#------------------------------------------------------------------------------
sub send_http_request {
	my $self = shift;
	my $sock = shift;
	my $host = shift;

	$self->save_log_spliter();
	$self->save_log(\@_);

	{
		my $request = join('', @_);
		syswrite($sock, $request, length($request));
	}
	my @response;
	my $vec_in = '';
	vec($vec_in, fileno($sock), 1) = 1;
	my ($r, $timeout);
	{
		local $SIG{ALRM} = sub { close($sock); $timeout=1; };
		alarm( $self->{timeout} );
		$r = select($vec_in, undef, undef, $self->{timeout});
		if (vec($vec_in, fileno($sock), 1) ) {
			@response = <$sock>;
		}
		alarm(0);
		close($sock);
	}
	$self->save_log(\@response);
	$self->save_log_spliter();
	if (! @response) {
		if (!$r || $timeout) {
			return $self->error($sock, "Connection timeout '%s' (timeout %d sec)", $host, $self->{timeout});
		}
		return $self->error($sock, "Connection closed by '%s'", $host);
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

#------------------------------------------------------------------------------
# ●https 
#------------------------------------------------------------------------------
sub send_https_request {
	my $self = shift;
	my $sock = shift;
	my $host = shift;

	$self->save_log_spliter();
	$self->save_log(\@_);

	eval { require Net::SSLeay; };
	if ($@) {
		return $self->error(undef, "Net::SSLeay module not found (please install this server)");
	}
	#----------------------------------------------------------------------
	my ($data, $errs, $written);

	my $ctx = Net::SSLeay::new_x_ctx();
	goto cleanup2 if $errs = Net::SSLeay::print_errs('CTX_new') or !$ctx;

	Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);
	goto cleanup2 if $errs = Net::SSLeay::print_errs('CTX_set_options');

	my $ssl = Net::SSLeay::new($ctx);
	goto cleanup if $errs = Net::SSLeay::print_errs('SSL_new') or !$ssl;

	if ($self->{use_sni} && 1.45<$Net::SSLeay::VERSION) {
		Net::SSLeay::set_tlsext_host_name($ssl, $host);
	}

	Net::SSLeay::set_fd($ssl, fileno($sock));
	goto cleanup if $errs = Net::SSLeay::print_errs('set_fd');

	Net::SSLeay::connect($ssl);
	goto cleanup if $errs = Net::SSLeay::print_errs('SSL_connect');

	my $server_cert = Net::SSLeay::get_peer_certificate($ssl);
	Net::SSLeay::print_errs('get_peer_certificate');

	($written, $errs) = Net::SSLeay::ssl_write_all($ssl, join('', @_));
	goto cleanup unless $written;

	($data, $errs) = Net::SSLeay::ssl_read_all($ssl);

cleanup:
	Net::SSLeay::free($ssl);

cleanup2:
	Net::SSLeay::CTX_free($ctx);
	close($sock);

	#----------------------------------------------------------------------
	# parse
	#----------------------------------------------------------------------
	my @response;
	while($data =~ /([^\n]*\n)(.*)/s) {
		push(@response, $1);
		$data = $2;
		if ($1 eq "\n") { last; }
	}
	if ($data ne '') {
		push(@response, $data)
	}
	#----------------------------------------------------------------------
	$self->save_log(\@response);
	if (! @response) {
		if ($self->{use_sni} && $errs =~ /sslv3 alert handshake failure/) {
			return $self->error(undef, "Net::SSLeay Ver$Net::SSLeay::VERSION not support SNI connection");
		}
		return $self->error(undef, "Net::SSLeay Ver$Net::SSLeay::VERSION fail connection: '%s'", $host);
	}

	$self->parse_status_line($response[0], $host);
	return \@response;
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
	$self->{redirect_cnt} = 0;
	while (1) {
		my $r = $self->do_request($method, $url, @_);
		# 正常終了
		my $status = $self->{status};
		if (!$self->{location} || $status<301 || 303<$status || (++$self->{redirect_cnt}) > $self->{redirect}) {
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
			my $dom   = $1;
			$dom =~ s/^\.*/./;
			if ($chost eq $host || index($host, $dom)>0 ) {
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

		# Net::SSLeay::post_https は自動付加するので付けない
		$header{'Content-Length'} = length($content);
		$header{'Content-Type'} ||= 'application/x-www-form-urlencoded';
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
	$header .= "Connection: close\r\n";
	$header .= $http_cookie;

	#----------------------------------------------------------------------
	# HTTPリクエストの発行
	#----------------------------------------------------------------------
	# $self->{ROBJ}->debug($header);
	# $self->{ROBJ}->debug($content);
	my $res;
	{
		my $func = $https ? 'get_data_ssl' : 'get_data';
		# Only HTTP/1.0, because chunked not support.
		my $request = "$method $path HTTP/1.0\r\n$header\r\n$content";

		$res = $self->$func($host, $port, $request);
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

#------------------------------------------------------------------------------
# ●USER-AGENTの設定
#------------------------------------------------------------------------------
sub save_log {
	my $self = shift;
	my $file = $self->{log_file};
	if (!$file) { return; }
	$self->{ROBJ}->fappend_lines($file, shift);
}
sub save_log_spliter {
	my $self = shift;
	$self->save_log("\n" . ('-' x 80) . "\n");
}

###############################################################################
# ■エラー処理
###############################################################################
sub error_to_root {
	my $self = shift;
	$self->{error_to_root} = shift;
}

sub error {
	my $self  = shift;
	my $sock  = shift;
	my $error = shift;
	my $ROBJ  = $self->{ROBJ};
	if (defined $sock) { close($sock); }
	if (defined $ROBJ) {
		if ($self->{error_to_root}) { return $ROBJ->error($error, @_); }
		$error = $ROBJ->message_translate($error, @_);
	} elsif (@_) {
		$error = sprintf($error, @_);
	}
	$self->{error} = $error;
	$self->save_log("\n[ERROR] $error\n");
	return undef;
}


1;
