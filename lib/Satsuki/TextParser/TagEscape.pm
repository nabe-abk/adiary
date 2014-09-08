use strict;
#-------------------------------------------------------------------------------
# TAG escape module
#						(C)2005-2006 nabe / nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagEscape;
our $VERSION = '1.22';
#-------------------------------------------------------------------------------
# ●オプション一覧
#-------------------------------------------------------------------------------
# _allow_anytag		すべてのタグを許可する
# _style_secure		style属性内のXSS（IE固有）を防止する
# _force_absolute_path	相対パスを絶対パスに書き換え
# _force_absolute_uri	URIをFQDN付のURIに書き換え
#
#-------------------------------------------------------------------------------
# プロトコル を確認する属性
#-------------------------------------------------------------------------------
my %PROTOCOL_CHECK = (
	href => 1, src => 1, site => 1, cite => 1, background => 1, action => 1
);
my %DATA_PROTOCOL_CHECK = (
	src => 1, url => 1
);
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	foreach(@_) {
		$self->init($_);
	}

	return $self;
}

###############################################################################
# ■タグ処理
###############################################################################
#------------------------------------------------------------------------------
# ●初期化処理
#------------------------------------------------------------------------------
sub init {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	my $lines = $ROBJ->fread_lines_cached($file, {DelCR => 1});
	my %tag_allow;
	my @allow_tags;
	while(@$lines) {
		my $x = shift(@$lines);
		chomp($x);
		if ($x eq '' || ord($x) == 0x23) { next; }	# '#'で始まる行はコメント
		my ($tag, $attr) = split(/\s+/, $x, 2);
		if ($attr eq '') {		# 標準許可のみ
			$tag_allow{$tag} = [];
		} elsif ($attr eq '*') {	# すべて不許可
			$tag_allow{$tag} = {};
		} else {
			my @ary = split(/\s*,\s*/, $attr);
			$tag_allow{$tag} = \@ary;
		}
		if ($tag_allow{_module_start}) { last; }
	}
	$self->{file_load} = %tag_allow ? 1 : 0;
	
	# モジュールデータのロード
	my %modules;
	my ($name, $html);
	# 外部モジュールファイルのロード
	my $include  = [];
	my $mod_file = $tag_allow{_include_module}->[0];
	if ($mod_file ne '') {
		# 相対パスを解釈
		$mod_file = $ROBJ->get_relative_path($file, $mod_file);
		$include  = $ROBJ->fread_lines_cached($mod_file, {DelCR => 1});
	}
	push(@$lines, "\n");
	foreach(@$lines, @$include) {
		chomp($_);
		if (ord($_) == 0x23) { next; }	# '#'で始まる行はコメント
		if (defined $name) {
			if ($_ ne '') { $html .= "$_\n"; next; }
			# モジュール確定
			chomp($html);
			$modules{$name} = $html;
			$name = $html = undef;
		}
		if (ord($_) != 0x2a) { next; }		# * で始まらない行は無視
		# *name という行
		$name = substr($_,1);
	}
	# 値保存
	if ($tag_allow{_base}) { $self->{allow_base} = join(', ', @{ $tag_allow{_base} }); }
	if ($tag_allow{_protocol}) {
		my $p = $tag_allow{_protocol};
		$self->{allow_protocol} = join(', ', @$p);
		$tag_allow{_protocol} = { map {$_=>1} @$p };
	}
	$self->{allow_anytag}        = (exists $tag_allow{_allow_anytag});
	$self->{force_absolute_path} = (exists $tag_allow{_force_absolute_path});
	$self->{force_absolute_uri}  = (exists $tag_allow{_force_absolute_uri});
	$self->{tag_allow} = \%tag_allow;
	$self->{modules}   = \%modules;
}

#------------------------------------------------------------------------------
# ●すべてのタグを許可する
#------------------------------------------------------------------------------
sub allow_anytag {
	my $self = shift;
	my $s = shift;
	$self->{allow_anytag} = ($s ne '') ? $s : 1;
}

#------------------------------------------------------------------------------
# ●タグ処理
#------------------------------------------------------------------------------
sub escape {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $inp  = shift;
	my $url_wrapper = shift;
	## $ROBJ->{Timer}->start('tag');

	# タグ処理
	my @out;
	my $tag;
	my $tag_list  = $self->{tag_allow};
	my $mod_list  = $self->{modules};
	my $tag_check = (! $self->{allow_anytag});
	my $attrs_all = $tag_list->{_base};
	my $protocols = $tag_list->{_protocol};
	my $style_secure = $tag_list->{_style_secure};
	# 相対パス／URI書き換え？
	my $abs_uri  = (exists $tag_list->{_force_absolute_uri});
	my $abs_path = (exists $tag_list->{_force_absolute_path}) || $abs_uri;
	my $basepath = $ROBJ->{Basepath};
	my $server_url;
	if ($abs_uri) { $server_url = $ROBJ->{Server_url}; }

	# 前処理
	# escapeキャラ除去, \x05-\x08はユーザーに解放
	$inp =~ s/[\x01-\x08]//g;

	### DOCTYPE退避
	my $doctype;
	$inp =~ s/(<!DOCTYPE.*?>)/$doctype=$1,"\x01doctype\x01"/ei;

	### コメント退避(保存) or 除去
	my @comments;
	if (exists $tag_list->{_comment}) {		# 退避
		# 正しくは <!(--.*?--\s*)+> だけど、ブウラザの対応がまちまちなので。
		$inp =~ s/<!--(.*?)--\s*>/push(@comments,$1),"\x01$#comments\x01"/seg;
		foreach(@comments) {	# security対策
			$_ =~ s/--/==/g;
		}
	} else {		# 除去
		$inp =~ s/<!--.*?--\s*>//sg;
	}

	# & の正規化
	&escape_amp( $inp );	# & → &amp;

	### print "Content-Type: text/plain;\n\n";
	while($inp =~ /^(.*?)<([A-Za-z][\w]*)((?:\s*[A-Za-z_][\w\-]*(?:=".*?"|='.*?'|[^\s>]*))*)\s*(\/)?>(.*)/s) {
		my $x   = $1;		# 前部分
		$inp    = $5;		# 残り
		my $tag_name = $2;
		my $tag      = $3;	# タグ部分
		my $tag_end  = $4 ? ' /' : '';	# " />" 部分

		my $y;
		$x   =~ s[</(.+?)\s*>][
				$y=$1; (!$tag_check || ($y=~tr/A-Z/a-z/,exists $tag_list->{$y})) && "\x02/$y\x03"
			]seg;
		$x   =~ s/</&lt;/g;
		$x   =~ s/>/&gt;/g;
		&escape_amp( $x );	# & → &amp;
		push(@out, $x);
		$tag =~ s/</&lt;/g;
		$tag =~ s/>/&gt;/g;

		# 文字列を認識しつつ属性に分解
		my @x; my %at;
		while($tag =~ /\G[\n\s]*([A-Za-z][\w\-]*)(?:="(.*?)"|='(.*?)'|=[^\s"'>]+|)/sg) {
			my $x=$1;
			$x =~ tr/A-Z/a-z/;	# 小文字変換
			push(@x, $x);
			if ($2 ne '' || $3 ne '') { $at{$x}="$2$3"; }
		};

		# モジュールタグ？
		if ($tag_name eq 'module') {
			my $data     = {};
			my $data_uri = {};
			my $data_int = {};
			foreach(@x) {
				my $v = $at{$_};
				$v =~ s/</&lt;/g;
				$v =~ s/>/&gt;/g;
				$v =~ s/\"/&quot;/g;
				$v =~ s/\'/&#39;/g;
				$data->{$_} = $v;
				# uri エンコード
				$v =~ s/([^\.\/\~\*\-\w\#:;=\+\?&% ])/'%' . unpack('H2',$1)/eg;
				$v =~ s/script:/script%3a/i;
				$data_uri->{$_} = $v;
			}
			my $name = $data->{name};

			# 置換処理
			my $html = $mod_list->{ $name };
			$html =~ s/\#\{([\w\-]+)(?:\|([^\}]*))?\}/$data->{$1}     ne '' ? $data->{$1}     : $2/eg;
			$html =~ s/\$\{([\w\-]+)(?:\|([^\}]*))?\}/$data_uri->{$1} ne '' ? $data_uri->{$1} : $2/eg;
			$html =~ s/\$(euc|sjis|utf8)\{([\w\-]+)\}/ &code_conv($ROBJ,$data->{$2},$1) /eg;
			push(@out, $html);
			next;
		}

		# 許可されたタグか？
		my $attrs = $tag_list->{$tag_name};
		if ($tag_check && !defined $attrs) {
			if ($tag_name eq 'script') {
				# scriptタグを見つけ出力したら閉じタグまで削除する
				$inp =~ s|^.*?</script[^>]*>||;
			}
			next;
		}
		my @y = ();

		my ($last_at, $last_val);
		foreach(@x) {
			my $v = $at{$_};
			my $data_attr;
			if ($_ eq '') { next; }	# 空属性は無視

			if (ref($attrs) eq 'ARRAY') {	# ハッシュに変換
				$attrs = { map { $_ => 1 } @$attrs };
				map { $attrs->{$_}=1 } @$attrs_all;
			}
			if ($attrs->{'data-'} && substr($_,0,5) eq 'data-' && length($_)>5) {
				$attrs->{$_}=1;
				$_ =~ m/-([^-]*)$/;
				$data_attr = $1;	# data-xxxx-url の最後の "url" を抽出
			}
			if ($tag_check && !$attrs->{$_}) { next; }	# 属性を無視

			# 値無し属性 （例）selected
			if (!exists $at{$_}) { unshift(@y, $_); next; }
			# 文字列復元
			my $v = $at{$_};
			if ($v eq '') { next; }	# 空属性値は無視

			# リンクプロトコル確認 href, src など（XSS対策）
			if (($PROTOCOL_CHECK{$_} || $DATA_PROTOCOL_CHECK{$data_attr})
			 && ($tag_check || $v !~ /^javascript:/i)) {
				if ($url_wrapper) { $v = &$url_wrapper($_, $v); }	# URLラッパー
				# URLの実際参照をデコード
				my $p = &decode_ncr($v);
				# 特殊文字のエンコード
				$v =~ s/([^\x01-\x08\.\/\~\*\-\w\#:;=\+\?&%\@,])/'%' . unpack('H2',$1)/eg;
				if ($p =~ /^([\w\+\-\.]+):/) {	# scheme by RFC2396 Sec3.1
					my $x = $1;
					$x =~ tr/A-Z/a-z/;
					if ($tag_check && !$protocols->{$x}) { next; }	# 無視
				} elsif (ord($v) == 0x23) {	# 先頭 #
					# anchor はそのまま。$pでは判定しないこと。
				} elsif ($abs_path) {
					# 相対パス/URIを絶対パス/URIに書き換え
					if (ord($p) != 0x2f) { $v = $basepath . $v; }	# / で始まっていない
					$v =~ s|([^\.])\./|$1|g;
					$v = $server_url . $v;
				} elsif (ord($p) != 0x2f && substr($p, 0, 2) ne './') {
					$v = './' . $v;
				}
			}

			# スタイルシート指定のXSS対策
			if ($tag_check && $style_secure && $_ eq 'style') {
				$v =~ s|[\\\@\x00-\x1f\x80-\xff]||g;	# ASCII文字以外や危険文字を除去
				# 危険文字の除去
				while($v =~ m[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include]i) {
					$v =~ s[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include][]ig;
				}
			}
			# 許可属性
			$v =~ s/\"/&quot;/g;
			push(@y, "$_=\"$v\"");
			$last_at  = $_;
			$last_val = $v;
		}
		unshift(@y, $tag_name);
		if ($#y >= 0) {
			push(@out, '<' . join(' ', @y) . $tag_end . '>');
		}
		# scriptタグを見つけ出力したら閉じタグまでそのまま出力する
		if ($tag_name eq 'script') {
			$inp =~ s|^(.*?</script[^>]*>)||;
			push(@out, $1);
		}
	}
	$inp =~ s[</(.+?)>][(!$tag_check || exists $tag_list->{$1}) && "\x02/$1\x03"]seg;
	$inp =~ s/</&lt;/g;
	$inp =~ s/>/&gt;/g;
	my $out = join('', @out) . $inp;

	# DOCTYPE復元
	$out =~ s/\x01doctype\x01/$doctype/;
	# コメント復元
	$out =~ s/\x01(\d+?)\x01/<!--$comments[$1]-->/g;
	# 閉じタグ復元
	$out =~ tr/\x02\x03/<>/;

	# CSSXSS対策
	if (exists $tag_list->{_escape_cssxss}) {
		$out =~ s/{/&#123;/g;
	}
	# 結果
	## $ROBJ->debug(int($ROBJ->{Timer}->stop('tag')*10000)/10);
	return $out;
}

#------------------------------------------------------------------------------
# ●文字コード変換
#------------------------------------------------------------------------------
my $jcode;
sub code_conv {
	my ($ROBJ, $value, $code) = @_;
	$jcode ||= $ROBJ->load_codepm();
	$jcode->from_to(\$value, $ROBJ->{System_coding}, $code);
	$ROBJ->encode_uricom( $value );
	return $value;
}

#------------------------------------------------------------------------------
# ●& の表記を正規化
#------------------------------------------------------------------------------
sub escape_amp {
	$_[0] =~ s/&(\w+|\#\d+|\#[Xx][\dA-Fa-f]+);/\x05$1;/g;
	$_[0] =~ s/&/&amp;/g;
	$_[0] =~ tr/\x05/&/;
	return $_[0];
}

#------------------------------------------------------------------------------
# ●数値文字参照を戻す
#------------------------------------------------------------------------------
sub decode_ncr {
	my $s = shift;
	$s =~ s/&\#(\d+);/chr($1)/eg;
	$s =~ s/&\#[Xx]([0-9A-Za-z]+);/chr(hex($1))/eg;
	return $s;
}

#------------------------------------------------------------------------------
# ●許可タグリストを生成
#------------------------------------------------------------------------------
sub load_allowtags {
	my ($self, $skelton) = @_;
	my $tags = $self->{tag_allow};
	my @keys = sort keys(%$tags);

	my @ary;
	foreach(@keys) {
		if (substr($_, 0, 1) eq '_') { next; }
		my %h;
		$h{tag}  = $_;
		$h{attr} = join(", ", @{ $tags->{$_} });
		push(@ary, \%h);
	}
	return \@ary;
}

1;
