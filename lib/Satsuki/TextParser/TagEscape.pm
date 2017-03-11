use strict;
#-------------------------------------------------------------------------------
# TAG escape module
#						(C)2005-2017 nabe / nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagEscape;
our $VERSION = '1.30';
#-------------------------------------------------------------------------------
# ●オプション一覧
#-------------------------------------------------------------------------------
# _allow_anytag		すべてのタグを許可する
# _style_secure		style属性内のXSSを防止する（for IE9）
# _absolute_path	相対パスを絶対パスに書き換え
# _absolute_uri		URIをFQDN付のURIに書き換え
#
#-------------------------------------------------------------------------------
# プロトコル を確認する属性
#-------------------------------------------------------------------------------
my %PROTOCOL_CHECK = (
	href => 1, src => 1, site => 1, cite => 1, background => 1, action => 1,
	'data-src' => 1,
	'data-url' => 1
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

	my %allow;
	my $lines = $ROBJ->fread_lines_cached($file, {DelCR => 1});
	if (@$lines) { $self->{file_load}=1; }	# for skeleton
	while(@$lines) {
		my $x = shift(@$lines);
		chomp($x);
		if ($x eq '' || ord($x) == 0x23) { next; }	# '#'で始まる行はコメント
		my ($tag, $attr) = split(/\s+/, $x, 2);
		if ($tag eq '_module_start') { last; }

		if ($attr eq '') {		# 標準許可のみ
			$allow{$tag} = [];
		} elsif ($attr eq '*') {	# すべて不許可
			$allow{$tag} = '*';
		} else {
			my @ary = split(/\s*,\s*/, $attr);
			$allow{$tag} = \@ary;
		}
	}

	# モジュールデータのロード
	my %modules;
	my ($name, $html);
	# 外部モジュールファイルのロード
	my $include  = [];
	my $mod_file = $allow{_include_module}->[0];
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
	$self->{allow}   = \%allow;
	$self->{modules} = \%modules;
	$allow{_base}      ||= [];
	$allow{_base_deny} ||= [];
	$allow{_protocol}  ||= [];

	my $c = $self->{cache} = {};
	$c->{_base}      = { map { $_ => 1 } @{ $allow{_base}      } };
	$c->{_base_deny} = { map { $_ => 1 } @{ $allow{_base_deny} } };
	$c->{_protocol}  = { map { $_ => 1 } @{ $allow{_protocol}  } };
}

#------------------------------------------------------------------------------
# ●すべてのタグを許可する
#------------------------------------------------------------------------------
sub allow_anytag {
	my $self = shift;
	my $s = shift;
	$self->{allow}->{_anytag} = (defined $s) ? $s : 0;
}

#------------------------------------------------------------------------------
# ●タグ処理
#------------------------------------------------------------------------------
sub escape {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $inp  = shift;
	my $wrapper = shift || {};

	my $test = '';
	for(my $i=0x20; $i<0x7f; $i++) {
		$test .= "&#$i;";
		if (($i & 15) == 15) { $test .= "\n"; }
	}
	$inp =~ s/<test>/$test/g;



	# HTML解析
	my $html = $self->parse($inp);

	# ユーザー指定フィルタ
	if ($wrapper->{filter}) {
		&{ $wrapper->{filter} }($html);
	}

	# 許可タグ処理
	$self->filter($html);

	# URLのフィルタ処理
	$self->url_filter($html, $wrapper->{url});

	return $html->toString();
}

#------------------------------------------------------------------------------
# ●タグを解析
#------------------------------------------------------------------------------
sub parse {
	my $self = shift;
	my $inp  = shift;
	my $html = Satsuki::TextParser::TagEscape::HTML->new();

	### escape用文字除去, \x05-\x08はユーザーに解放
	$inp =~ s/[\x01-\x08]//g;

	### コメント退避(保存) or 除去
	my @com;
	# 正しくは <!(--.*?--\s*)+> だけど、ブウラザの対応がまちまちなので。
	$inp =~ s/<!--(.*?)--\s*>/push(@com,$1),"<!--$#com-->"/seg;
	foreach(@com) {			# security対策
		$_ =~ s/^\[/ [/;	# <!--[if IE]>等の対策
		$_ =~ s/--/==/g;
	}

	$inp .= '<end>';
	while($inp =~ m{^(.*?)<([/\!A-Za-z][\w\-]*)((?:\s*(?:[A-Za-z][\w\-]*|".*?")(?:\s*=\s*(?:".*?"|'.*?'|[^\s>]*))?)*)\s*/?>(.*)}si) {
		my $text = $1;	# 前部分
		$inp  = $4;	# 残り
		my $name = $2;	# タグ名
		my $attr = $3;	# 属性
		$name =~ tr/A-Z/a-z/;

		#--------------------------------------------
		# 手前部分
		#--------------------------------------------
		{
			$text =~ s/</&lt;/g;
			$text =~ s/>/&gt;/g;
			&escape_amp( $text );	# & → &amp;
			$html->add('text', $text);
		}

		#--------------------------------------------
		# !DOCTYPE
		#--------------------------------------------
		if ($name eq '!doctype') {
			$attr =~ s/\s+/ /g;
			$html->add('doctype', "<!DOCTYPE$attr>");
			next;
		}

		#--------------------------------------------
		# コメント
		#--------------------------------------------
		if ($name =~ /^!--(\d+)--$/) {
			$html->add('comment', "<!--$com[$1]-->");
			next;
		}

		#--------------------------------------------
		# 属性分解
		#--------------------------------------------
		$attr =~ s/</&lt;/g;
		$attr =~ s/>/&gt;/g;

		my @order; my %at;
		while($attr =~ /\G[\n\s]*([A-Za-z][\w\-]*|(".*?"))(?:\s*=\s*(?:"(.*?)"|'(.*?)'|([^\s>]+))?|)/sg) {
			if ($2) { next; }
			my $k=$1;
			my $v="$3$4$5";
			$k =~ tr/A-Z/a-z/;
			push(@order, $k);

			&escape_amp( $v );	# &の正規化
			&decode_ncr($v);	# 一部のHTML数値文字参照を戻す
			$v =~ s/"/&quot;/g;

			if ($PROTOCOL_CHECK{$k}) {	# URIエンコード
				$v =~ s/([^\.\/\~\*\-\w\#:;=\+\?&%\@,])/'%' . unpack('H2', $1)/eg;
			}
			$at{$k} = $v;
		}

		#--------------------------------------------
		# 出力
		#--------------------------------------------
		$html->add('tag', {
			tag   => $name,
			attr  => \%at,
			order => \@order
		});

		#--------------------------------------------
		# scriptタグの処理
		#--------------------------------------------
		if ($name eq 'script') {
			$inp =~ s|^(.*?)</script\s*>||si;
			my $scr = $1;
			$scr =~ s|<!--(\d+)-->|<!--$com[$1]-->|g;
			$html->add('script', $scr);
			$html->add('tag', '/script');
		}
	}
	$html->pop();	# <end>を除去
	return $html;
}

#------------------------------------------------------------------------------
# ●許可タグ処理
#------------------------------------------------------------------------------
sub filter {
	my $self = shift;
	my $html = shift;
	if ($self->{allow}->{_anytag}) { return; }

	# タグ処理
	my $allow   = $self->{allow};
	my $modules = $self->{modules};
	my $base      = $self->load_allow_at('_base');
	my $base_deny = $self->load_allow_at('_base_deny');
	my $protocol  = $self->load_allow_at('_protocol');

	for(my $p=$html->first; $p; $p=$p->next) {
		my $type = $p->type();
		if ($type) {
			if ($type eq 'text' || $type eq 'doctype') {
				next;
			}
			if ($type eq 'comment') {
				if (!$allow->{_comment}) { $p->remove(); }
				next;
			}
			if ($type eq 'script') {
				if (!$allow->{script}) { $p->remove(); }
				next;
			}
		}

		#--------------------------------------------------------
		# タグ処理
		#--------------------------------------------------------
		if ($type ne 'tag') { next; }
		my $tag = $p->tag();

		#--------------------------------------------------------
		# モジュールタグ？
		#--------------------------------------------------------
		if ($tag eq 'module') {
			my $data     = {};
			my $data_uri = {};
			my $data_int = {};
			my $at = $p->attr();
			foreach(keys(%$at)) {
				my $v = $at->{$_};
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
			my $html = $modules->{ $name };
			$html =~ s/\#\{([\w\-]+)(?:\|([^\}]*))?\}/$data->{$1}     ne '' ? $data->{$1}     : $2/eg;
			$html =~ s/\$\{([\w\-]+)(?:\|([^\}]*))?\}/$data_uri->{$1} ne '' ? $data_uri->{$1} : $2/eg;
			$html =~ s/\$(euc|sjis|utf8)\{([\w\-]+)\}/ $self->code_conv($data->{$2},$1) /eg;
			$p->replace('html', $html);
			next;
		}

		#--------------------------------------------------------
		# 許可されたタグ？
		#--------------------------------------------------------
		if (! $allow->{$tag}) {
			$p->remove();
			next;
		}

		#--------------------------------------------------------
		# 属性チェック
		#--------------------------------------------------------
		my $allow_at = $self->load_allow_at($tag);
		my $at = $p->attr();
		foreach(keys(%$at)) {
			if (!$allow_at->{$_} || $base_deny->{$_}) {	# 不許可?
				my $f=1;
				# data- 等のワイルドカードチェック
				if (!$base_deny->{$_} && $allow_at->{_wild} && index($_,'-')>0) {
					foreach my $w (@{ $allow_at->{_wild} }) {
						if (substr($_, 0, length($w)) ne $w) { next; }
						$f=0; last;
					}
				}
				if ($f) {	# 不許可属性
					delete $at->{$_};
					next;
				}
			}

			#------------------------------------------------
			# 属性値チェック
			#------------------------------------------------
			my $v = $at->{$_};	# $_=属性名 $v=属性値

			#------------------------------------------------
			# リンクプロトコルチェック
			#------------------------------------------------
			if ($PROTOCOL_CHECK{$_} || $v !~ /^javascript:/i) {
				if ($v =~ /^([\w\+\-\.]+):/) {	# scheme by RFC2396 Sec3.1
					my $x = $1;
					$x =~ tr/A-Z/a-z/;
					if (!$protocol->{$x}) { $v="#$1: is not allow"; }
				}
			}


			#------------------------------------------------
			# スタイルシート指定のXSS対策
			#------------------------------------------------
			if ($allow->{_style_secure} && $_ eq 'style') {
				$v =~ s|[\\\@\x00-\x1f\x80-\xff]||g;	# ASCII文字以外や危険文字を除去
				# 危険文字の除去
				while($v =~ m[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include]i) {
					$v =~ s[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include][]ig;
				}
			}
			#------------------------------------------------
			$at->{$_} = $v;
		}
	}
}

#------------------------------------------------------------------------------
# 属性の許可情報ロード
#------------------------------------------------------------------------------
sub load_allow_at {
	my $self  = shift;
	my $tag   = shift;
	my $allow = $self->{allow};
	my $cache = $self->{cache};
	if ($cache->{$tag}) { return $cache->{$tag}; }

	my $h = $cache->{$tag} = {};
	my $x = $allow->{$tag};
	if ($x eq '*') { return $h; }	# すべて不許可

	my @wild;
	foreach(@{ $allow->{_base} }, @$x) {
		if (substr($_, -1) eq '-') {
			push(@wild, $_);
			next;
		}
		$h->{$_} = 1;
	}
	if (@wild) {
		$h->{_wild} = \@wild;
	}
	return $h;
}

#------------------------------------------------------------------------------
# ●URL書き換え処理
#------------------------------------------------------------------------------
sub url_filter {
	my $self = shift;
	my $html = shift;
	my $wrapper = shift;

	# 相対パス／URI書き換え？
	my $ROBJ     = $self->{ROBJ};
	my $allow    = $self->{allow};
	my $abs_uri  = (exists $allow->{_absolute_uri});
	my $abs_path = (exists $allow->{_absolute_path}) || $abs_uri;
	my $basepath = $ROBJ->{Basepath};
	my $server   = $ROBJ->{Server_url};

	# 書き換えの必要なし
	if (!$wrapper && !$abs_uri && !$abs_path) { return; }

	# 書き換え処理
	for(my $p=$html->first; $p; $p=$p->next) {
		if ($p->type ne 'tag') { next; }
		my $at = $p->attr;
		foreach(keys(%$at)) {
			if (! $PROTOCOL_CHECK{$_}) { next; }

			if ($wrapper) {		# URLラッパー
				$at->{$_} = &{$wrapper}($_, $at->{$_});
			}

			my $v = $at->{$_};
			if ($v =~ /^([\w\+\-\.]+):/) {	# scheme by RFC2396 Sec3.1
				next;
			}
			if (substr($v,0,2) eq '//') {	# //example.com/path/to
				next;
			}
			if (ord($v) == 0x23) {	# "#"=hash はそのまま。
				next;
			}

			if ($abs_path) {
				# 相対パス/URIを絶対パス/URIに書き換え
				if (ord($v) != 0x2f) { $v = $basepath . $v; }	# / で始まっていない
				$v =~ s|([^\.])\./|$1|g;
				if ($abs_uri) {
					$v = $server . $v;
				}

			} elsif (ord($v) != 0x2f && substr($v, 0, 2) ne './') {	# 念のためのsecurity対策
				$v = './' . $v;
			}

			$at->{$_} = $v;
		}
	}
}

#------------------------------------------------------------------------------
# ●文字コード変換
#------------------------------------------------------------------------------
sub code_conv {
	my ($self, $value, $code) = @_;
	my $ROBJ = $self->{ROBJ};
	$self->{jcode} ||= $ROBJ->load_codepm();
	$self->{jcode}->from_to(\$value, $ROBJ->{System_coding}, $code);
	$ROBJ->encode_uricom( $value );
	return $value;
}

#------------------------------------------------------------------------------
# ●& の表記を正規化
#------------------------------------------------------------------------------
sub escape_amp {
	$_[0] =~ s/&(\w+|\#\d+|\#[Xx][\dA-Fa-f]+);/\x01$1;/g;
	$_[0] =~ s/&/&amp;/g;
	$_[0] =~ tr/\x01/&/;
	return $_[0];
}

#------------------------------------------------------------------------------
# ●数値文字参照を戻す
#------------------------------------------------------------------------------
my $NSTR = '!#$%()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_'
	 . '`abcdefghijklmnopqrstuvwxyz{|}~';
my @NCR;
sub get_ncr() {
	my $code = shift;
	if (!@NCR) {
		for(my $i=0; $i<length($NSTR); $i++) {
			my $c = substr($NSTR,$i,1);
			$NCR[ord($c)]=$c;
		}
	}
	return $NCR[$code];
}
sub decode_ncr {
	$_[0] =~ s/(&\#(\d+);)/&get_ncr($2) || $1/eg;
	$_[0] =~ s/(&\#[Xx]([0-9A-Za-z]+);)/&get_ncr(hex($2)) || $1/eg;
	return $_[0];
}

#------------------------------------------------------------------------------
# ●許可タグリストを生成
#------------------------------------------------------------------------------
sub load_allowtags {
	my ($self, $skelton) = @_;
	my $tags = $self->{allow};

	my @ary;
	my %h;
	foreach(sort keys(%$tags)) {
		if (substr($_, 0, 1) eq '_') {
			$h{$_}=$tags->{$_} ? 1 : 0;
			next;
		}
		push(@ary, {
			tag  => $_,
			attr => join(", ", @{ $tags->{$_} })
		});
	}

	my $allow = $self->{allow};
	$h{base}      = join(', ', @{ $allow->{_base} });
	$h{base_deny} = join(', ', @{ $allow->{_base_deny} });
	$h{protocol}  = join(', ', @{ $allow->{_protocol} });
	return wantarray ? (\@ary, \%h) : \@ary;
}

################################################################################
# ●HTML/タグクラス
################################################################################
package Satsuki::TextParser::TagEscape::DOM;

sub new {
	my $self = bless({}, shift);
	my $type = shift;
	my $val  = shift;
	if ($type eq 'tag') {
		if (ref($val)) {
			foreach(keys(%$val)) {
				$self->{$_} = $val->{$_};
			}
			$val = $val->{tag};
		}
		my $c = $val =~ m|^/(.*)|;
		$self->{close} = $c;
		$self->{tag}   = $c ? $1 : $val;
		$self->{attr}  ||= {};
		$self->{order} ||= [];
	} elsif ($type eq 'comment' || $type eq 'text' || $type eq 'html' || $type eq 'script' || $type eq 'doctype') {
		$self->{type}  = $type;
		$self->{$type} = $val;
	} else {
		die "Unknown DOM type '$type'";
	}
	return $self;
}
sub type { return $_[0]->{type} || 'tag'; }
sub tag  { return $_[0]->{tag};  }
sub attr { return $_[0]->{attr}; }

sub toString {
	my $self = shift;
	if ($self->{type}) {
		return $self->{$self->{type}};
	}
	if ($self->{close}) {
		return "</$self->{tag}>";
	}
	# タグ復元
	my $order = $self->{order};
	my %at    = %{ $self->{attr} };
	my $tag   = '<' . $self->{tag};
	foreach(@$order) {
		if (!exists $at{$_}) { next; }
		$tag .= " $_" . ($at{$_} ne '' ? '="' . $at{$_} . '"' : '');
		delete $at{$_};
	}
	foreach(keys(%at)) {
		$tag .= " $_" . ($at{$_} ne '' ? '="' . $at{$_} . '"' : '');
	}
	$tag .= '>';
	return $tag;
}
#-------------------------------------------------------------------------------
sub next {
	my $self = shift;
	return $self->{next};
}
sub prev {
	my $self = shift;
	return $self->{prev};
}
sub remove {
	my $self = shift;
	my $prev = $self->{prev};
	my $next = $self->{next};
	delete $self->{prev};
	delete $self->{next};
	$prev->{next} = $next;
	$next->{prev} = $prev;
	return;
}
sub replace {
	my $self = shift;
	my $obj  = shift;
	if (!ref($obj)) {
		$obj = __PACKAGE__->new($obj, @_);
	}
	my $prev = $self->{prev};
	my $next = $self->{next};
	delete $self->{prev};
	delete $self->{next};
	$prev->{next} = $obj;
	$obj ->{prev} = $prev;
	$obj ->{next} = $next;
	$next->{prev} = $obj;
	return;
}


################################################################################
# ●HTMLクラス
################################################################################
package Satsuki::TextParser::TagEscape::HTML;

sub new {
	my $self = bless({}, shift);
	return $self;
}

sub add {
	my $self = shift;
	my $type = shift;
	my @ary;
	foreach(@_) {
		if ($_ eq '') { next; }
		push(@ary, Satsuki::TextParser::TagEscape::DOM->new($type, $_));
	}
	return $self->do_add(@ary);
}

sub getAll {
	my $self = shift;
	my @ary;
	my $p = $self->{first};
	while($p) {
		push(@ary, $p);
		$p = $p->{next};
	}
	return @ary;
}

sub toString {
	my $self = shift;
	my $str = '';
	my $p = $self->{first};
	while($p) {
		$str .= $p->toString();
		$p = $p->{next};
	}
	return $str;
}

sub first { return $_[0]->{first}; }
sub last  { return $_[0]->{last};  }

sub do_add {
	my $self = shift;

	$self->{first} ||= $_[0];
	my $p = $self->{last};
	foreach(@_) {
		$p->{next} = $_;
		$_->{prev} = $p;
		$p = $_;
	}
	$self->{last} = $p;
	return $self;
}

sub pop {
	my $self = shift;
	my $dom  = $self->{last};
	$self->{last} = $dom->{prev};
	$self->{last}->{next} = undef;
	return $dom;
}


1;
