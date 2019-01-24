use strict;
#-------------------------------------------------------------------------------
# 更新通知Ping Server / XML-RPC for adiary only
#							(C)2013 nabe@abk
#-------------------------------------------------------------------------------
# [UTF-8]
package SatsukiApp::ping_server;
use Encode;
#-------------------------------------------------------------------------------
our $VERSION = '2.00';
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{post_max_size} = 8192;
	return $self;
}

###############################################################################
# ■メイン処理
###############################################################################
sub main {
	my $self = shift;
	if ($ARGV[0] eq 'update') {
		my $r = $self->update_bloglist();
		if ($r) { print "$r\n"; }
		return 0;
	}
	#-------------------------------------------------------------
	# ページ出力
	#-------------------------------------------------------------
	my $skelton = $self->{get_skelton};
	if ($ENV{REQUEST_METHOD} eq 'POST') {
		$skelton = $self->{post_skelton};
	}
	$self->output_html($skelton);

	# debug
	if ($self->{debug_log}) {
		my $ROBJ = $self->{ROBJ};
		my $ary  = $ROBJ->{Debug} || [];
		my $ary2 = $ROBJ->{Error} || [];
		$ROBJ->fappend_lines( $self->{debug_log}, join("\n", "\n\n$ROBJ->{Timestamp}", @$ary, @$ary2));
	}
	return 0;
}

###############################################################################
# ■表示部
###############################################################################
#------------------------------------------------------------------------------
# ●HTMLの生成と出力
#------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($skelton) = @_;

	my $out = $ROBJ->call($skelton);
	$ROBJ->output($out, $self->{content_type});	# HTML出力
}

#------------------------------------------------------------------------------
# ●blogリストのアップデート
#------------------------------------------------------------------------------
sub update_bloglist {
	my $self = shift;
	if ($self->{outputDB}) {
		return $self->update_adiaryDB( @_ );
	}
	return $self->update_html( @_ );
}

sub update_html {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $out = $ROBJ->call( $self->{output_skelton} );
	$ROBJ->fwrite_lines( $self->{output_file}, $out );
	return 0;
}

#------------------------------------------------------------------------------
# ●blogリストのアップデート（adiaryの記事更新）
#------------------------------------------------------------------------------
sub update_adiaryDB {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $out = $ROBJ->call( $self->{output_skelton} );
	if ($self->{outputDB_charset}) {
		my $jcode = $ROBJ->load_codepm();
		$jcode->from_to(\$out, $ROBJ->{System_coding}, $self->{outputDB_charset});
	}

	my $DB = $self->{outputDB};
	my $blogid = $self->{outputDB_blogid};
	my $table = "${blogid}_art";
	# ブログの確認
	if (! $DB->find_table($table)) {
		return "Blog '$blogid' not found.";	# Error
	}
	# update
	my %h = (text => $out, _text => $out, update_tm => $ROBJ->{TM});
	my $r = $DB->update_match($table, \%h, 'pkey', $self->{outputDB_apkey} );
	if (! $r) {
		return "Article update fail.";
	}

	return 0;
}

###############################################################################
# ■スケルトン用サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●更新通知Pingの受信処理
#------------------------------------------------------------------------------
# 文字コード加工処理
sub post_action {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $r = &_post_action($self, @_);
	# 旧Verのバグ。強制的に EUC-JP で送信する
	if (0<$self->{adiary_version} && $self->{adiary_version}<1.44) {
		my $jcode = $ROBJ->load_codepm();
		$self->{message} = $jcode->from_to($self->{message}, $ROBJ->{System_coding}, 'EUC-JP');
	}
	return $r;
}
#------------------------------------------------------------------------------
sub _post_action {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	#---------------------------------------------------
	# XML Parse（簡易実装）
	#---------------------------------------------------
	my $agent = $ENV{HTTP_USER_AGENT};
	my $adiary_version;
	if ($agent =~ /^adiary\s+(\d\.\d+)/) {
		$adiary_version = $1;
	} else {
		$self->{message} = 'This ping server for adiary only';
		return 1;
	}

	#---------------------------------------------------
	# XML content の読み出し
	#---------------------------------------------------
	my $length = $ENV{CONTENT_LENGTH};
	if ($length > $self->{post_max_size}) { $length=$self->{post_max_size}; }
	my $xml;
	read(STDIN, $xml, $length);

	#---------------------------------------------------
	# XML Parse（簡易実装）
	#---------------------------------------------------
	# 前処理
	$xml =~ s/[\r\n]//g;
	$xml =~ s|<value>(.*?)</value>|$1|g;
	# methodの確認
	my $method;
	if ($xml =~ m|<methodName>(.*?)</methodName>|) { $method = $1; }
	if ($method ne 'weblogUpdates.adiary-extendedPing') {
		$self->{message} = 'Unknown method (This server is adiary only)';
		return 2;
	}
	# 引数取得
	my @params;
	$xml =~ s|<param>(.*?)</param>|push(@params, $1)|eg;
	# 長さ制限
	my $max_len = $self->{max_param_length} || 64;
	my $url = $params[1];
	$url = substr($url, 0, 128);
	my $jcode = $ROBJ->load_codepm();
	foreach(@params) {
		if ($jcode->jlength($_) > $max_len) {
			$_ = $jcode->jsubstr($_, 0, $max_len) . '...';
		}
	}
	# ホスト名逆引き
	if ($self->{resolve_host}) { $ROBJ->resolve_host(); }
	#---------------------------------------------------
	# 結果を確認
	#---------------------------------------------------
	my %blog;
	$blog{ip}   = $ENV{REMOTE_ADDR};
	$blog{host} = $ENV{REMOTE_HOST};
	$ROBJ->tag_escape_for_xml(@params, $blog{ip}, $blog{host}, $url);
	$blog{blog_name}     = $params[0];
	$blog{url}           = $url;
	$blog{newest_title}  = $params[2];
	$blog{update_tm}     = $ROBJ->{TM};
	$blog{version}       = $adiary_version;
	$self->{adiary_version} = $adiary_version;
	if ($self->{check_local_url}) {	# 外部公開ページか確認する
		if ($url =~ m[^https?://(?:192|10|172)\.\d+\.\d+\.\d+/] || $url =~ m|^https?://[\w\-]+(?:\:\d+)?/|) {
			$self->{message} = '公開されたページから送信してください';
			return 3;
		}
	}
	if ($self->{lookup_url_host}) {
		if ($url !~ m|^https?://([\w\-\.]*)/| || !gethostbyname($1)) {
			$self->{message} = '公開されたページから送信してください';
			return 4;
		}
	}

	#---------------------------------------------------
	# 結果を保存
	#---------------------------------------------------
	# DBに保存
	my $DB = $ROBJ->{DB};
	if (!ref($DB)) { $self->{message} = 'サーバエラー(-1)'; return -1; }
	my $r  = $DB->update_match("blogs", \%blog, 'url', $blog{url});
	if (!$r) {	# 更新失敗 →新規登録
		$blog{enable} = 1;
		$blog{regist_tm} = $ROBJ->{TM};
		$r = $DB->insert("blogs", \%blog);
	}
	if (!$r) { $self->{message} = "サーバエラー(-2)"; return -2; }

	#---------------------------------------------------
	# 成功メッセージ
	#---------------------------------------------------
	$self->{message} = 'Thank you for ping by adiary';
	my $lines = $ROBJ->fread_lines_cached( $self->{ping_message_file} );
	foreach(@$lines) {
		chomp($_);
		if ($_ =~ /^\s*\#/) { next; }
		my ($v, $msg) = split('=', $_);
		if ($v <= 0) { next; }
		if ($adiary_version <= $v) { $self->{message}=$msg; last; }
	}
	return 0;	# 成功
}

#------------------------------------------------------------------------------
# ●リストのロード
#------------------------------------------------------------------------------
sub load_ping_list {
	my $self  = shift;
	my $loads = shift || 50;	# ロード件数
	my $ROBJ  = $self->{ROBJ};
	my $DB    = $ROBJ->{DB};
	if (!ref($DB)) { return []; }

	#---------------------------------------------------
	# DBからロード
	#---------------------------------------------------
	my %h;
	$h{flag}      = {enable => 1};	# 表示可能なもののみ
	$h{sort}      = 'update_tm';
	$h{sort_rev}  = 1;			# 新しい順
	$h{limit}     = int($loads);
	return $DB->select("blogs", \%h);
}

1;
