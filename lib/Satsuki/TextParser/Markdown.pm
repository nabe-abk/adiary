use strict;
#------------------------------------------------------------------------------
# markdown記法
#                                              (C)2014-2015 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
# コメント中に [M] とあるものは、Markdown.pl 準拠。
# [GitHub] とあるものは、GitHub Flavored Markdown 準拠。
# [S] とあるものは、adiary拡張（Satsuki記法互換機能）
#
package Satsuki::TextParser::Markdown;
our $VERSION = '1.02';
#------------------------------------------------------------------------------
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{h_start} = 3;		# H3から使用する
	$self->{tab_width} = 4;		# タブの幅

	$self->{lf_patch} = 1;		# 日本語のpタグ中の改行を消す
	$self->{md_in_htmlblk} = 1;	# Markdown Inside HTML Blocksを許可する
	$self->{sectioning}   = 1;	# sectionタグを適時挿入する

	$self->{span_sanchor} = 0;	# 見出し先頭に span.sanchor を挿入する
	$self->{section_link} = 0;	# 見出しタグにリンクを挿入する

	$self->{satsuki_tags}     = 0;	# satsuki記法のタグを有効にする
	$self->{satsuki_syntax_h} = 1;	# syntaxハイライトをsatsuki記法に準拠させる
	$self->{satsuki_seemore}  = 1;	# 「続きを読む」記法を使用する

	$self->{load_SyntaxHighlighter} = '<module name="load_SyntaxHighlight">';

	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
# 行末記号
#	\x01	これ以上、行処理しない
#	\x02	これ以上、行処理も記法処理もしない
# 特殊記号
#	\x00	tag_escape_ampで使用
#	\x03E	文字エスケープ
#	\x03C	コメント退避
#
#------------------------------------------------------------------------------
# ●記事本文の整形
#------------------------------------------------------------------------------
sub text_parser {
	my ($self, $text) = @_;
	my $sobj = $self->{satsuki_tags} && $self->{satsuki_obj};	# Satsuki parser

	# コメントの退避
	my @comment;
	$text =~ s/[\x00-\x03]//g;		# 特殊文字削除
	$text =~ s/(\n?(?:<!(?:--.*?--\s*)+>))/push(@comment, $1),"\x03C" . $#comment . "\x03"/esg;

	# 行に分解
	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# 内部変数初期化
	$self->{links} = {};
	$self->init_unique_link_name();
	if ( $sobj ) {
		$sobj->{thisurl}  = $self->{thisurl};
		$sobj->{thispkey} = $self->{thispkey};
		$sobj->init_unique_link_name();
	}

	#-------------------------------------------
	# ○処理スタート
	#-------------------------------------------
	# [01] 特殊ブロックのパースと空行の整形
	$lines = $self->parse_special_block($lines);

	# [02] その他のブロックのパース
	$lines = $self->parse_block($lines);

	# [03] インライン記法の処理
	$lines = $self->parse_inline($lines);

	#-------------------------------------------
	# ○後処理
	#-------------------------------------------
	my $sec;
	if ($lines->[$#$lines] eq "</section>\x02") { $sec=pop(@$lines); }
	while($lines->[$#$lines] eq '') { pop(@$lines); }
	if ($sec) { push(@$lines, $sec); }

	# [S] <toc>の後処理
	my $all = join("\n", @$lines);
	if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
		$sobj->{sections} = $self->{sections};
		$sobj->{subsections} = $self->{subsections};
		$sobj->post_process( \$all );
	}

	# [S] Moreの処理
	my $short = '';
	if ($all =~ /^((.*?)\n?<p class="seemore">.*)<!--%SeeMore%-->\x02?\n(.*)$/s ) {
		$short = $1;
		$all = $2 . "<!--%SeeMore%-->" . $3;
		if ($short =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
			$short .= "\n</section>";
		}
	}

	# コメントの復元
	foreach(@comment) {
		# コメント中の %SeeMore% 除去
		$_ =~ s/<\!--%SeeMore%-->/<\!--%SeeMore% -->/;
	}
	$all   =~ s/\x03C(\d+)\x03/$comment[$1]/g;
	$short =~ s/\x03C(\d+)\x03/$comment[$1]/g;

	# 特殊文字の除去
	$all   =~ s/[\x00-\x03]//g;
	$short =~ s/[\x00-\x03]//g;

	# 内部変数復元
	$self->restore_unique_link_name();

	return wantarray ? ($all, $short) : $all;
}

#------------------------------------------------------------------------------
# ●unique_link_nameの生成と破棄
#------------------------------------------------------------------------------
sub init_unique_link_name {
	my $self = shift;
	$self->{unique_linkname_bak} = $self->{unique_linkname};
	$self->{unique_linkname} ||= $self->{thispkey} ? "k$self->{thispkey}" : '';
}
sub restore_unique_link_name {
	my $self = shift;
	$self->{unique_linkname} = $self->{unique_linkname_bak};
}

###############################################################################
# ■ Markdownパーサー
###############################################################################
#------------------------------------------------------------------------------
# ●[01] 特殊ブロックのパースと空行の整形
#------------------------------------------------------------------------------
sub parse_special_block {
	my ($self, $lines, $sectioning) = @_;
	$sectioning = defined $sectioning ? $sectioning : $self->{sectioning};

	my @ary;
	#
	# セクション情報
	#
	my @sections;
	my @subsections;
	$self->{sections} = \@sections;
	$self->{subsections} = \@subsections;
	#
	# 連続する空行を1つの空行にする。特殊ブロックをブロックとして切り出す。
	#
	my $in_section;
	my $newblock=1;
	my $tw = $self->{tab_width};
	my $block_tags = qr/
		p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|
		script|noscript|form|fieldset|iframe|math|ins|del|
		# 以下、追加した要素
		style|article|section|nav|aside|header|footer|details|
		audio|video|figure|canvas|map
	/x;
	push(@$lines, '');
	while(@$lines) {
		my $x = shift(@$lines);
		if ($x =~ /^\s*$/) { $x = ''; }

		# [M] TAB to SPACE 4つ
		$x =~ s/(.*?)\t/$1 . (' ' x ($tw - (length($1) % $tw)))/eg;

		# HTMLブロック
		if ($x =~ /<($block_tags)\b[^>]*>/i) {
			my $tagend = qr|</$1\s*>\s*$|;
			my $endmark = "\x02";
			if ($self->{md_in_htmlblk} && $x =~ /markdown\s*=\s*"1"/) {
				$x =~ s/\s*markdown\s*=\s*"1"//g;
				$endmark = '';
			}
			my $first=1;
			while(@$lines && $x !~ /$tagend/i) {
				push(@ary, $x . ($first ? "\x01" : $endmark));
				$first=0;
				$x = shift(@$lines);
			}
			push(@ary, $x . ($endmark ? $endmark : "\x01"));
			push(@ary,'');
			$newblock=1;
			next;
		}

		# h3などの見出し
		if ($x =~ /^(#+)\s*(.*?)\s*\#*$/) {
			if (!$newblock) { push(@ary,''); }
			my $level = length($1);
			my $n = $self->{h_start} + $level - 1;
			if ($n>6) { $n=6; }
			if ($level == 1 && $sectioning) {
				push(@ary, "</section>\x02");
				push(@ary, "<section>\x02");
				$in_section=1;
			}
			# アンカー処理
			my $text = $2;
			if ($level==1) {	# [S] h3
				my $anchor = $self->{section_anchor};
				my $scount = $#sections+2;
				my $name   = "$self->{unique_linkname}p" . $scount;
				$anchor =~ s/%n/$scount/g;
				push(@sections, {
					name => $name,
					title => $text,
					anchor => $anchor,
					section_count => $scount
				});
				if ($self->{span_sanchor}) {
					$text = "<span class=\"sanchor\">$anchor</span>$text";
				}
				if ($self->{section_link}) {
					$text = "<a href=\"$self->{thisurl}#$name\" id=\"$name\" class=\"linkall\">$text</a>";
				}
			} elsif ($level==2) {	# [S] h4
				my $anchor = $self->{subsection_anchor};
				my $scount = $#sections+1;
				my $ss_ary = $subsections[$scount] ||= [];
				my $sscount= $#$ss_ary +2;
				my $name   = "$self->{unique_linkname}p" . "$scount.$sscount";
				$anchor =~ s/%n/$scount/g;
				$anchor =~ s/%s/$sscount/g;
				push(@$ss_ary, {
					name => $name,
					title => $text,
					anchor => $anchor,
					section_count => $scount,
					subsection_count => $sscount
				});
				$text = "<span class=\"sanchor\">$anchor</span>$text";
				if ($self->{section_link}) {
					$text = "<a href=\"$self->{thisurl}#$name\" id=\"$name\" class=\"linkall\">$text</a>";
				}
			}
			push(@ary,"<h$n>$text</h$n>\x01");
			push(@ary,'');
			$newblock=1;
			next;
		}

		# 下線==による見出し
		# [M] 2個以上の連なりで文末にスペース以外の文字がない
		if ($x =~ /^===*\s*$/ && !$newblock) {
			my $prev = pop(@ary);
			my $n = $self->{h_start};
			push(@ary, '');
			if ($sectioning) {
				push(@ary, "</section>\x02");
				push(@ary, "<section>\x02");
				$in_section=1;
			}
			push(@ary,"<h$n>$prev</h$n>\x01");
			push(@ary, '');
			$newblock=1;
			next;
		}

		# 下線--による見出し
		# [M] 2個以上の連なりで文末にスペース以外の文字がない
		if ($x =~ /^---*\s*$/ && !$newblock) {
			my $prev = pop(@ary);
			my $n = $self->{h_start}+1;
			push(@ary, '');
			push(@ary,"<h$n>$prev</h$n>\x01");
			push(@ary, '');
			$newblock=1;
			next;
		}

		# ただの空行
		if ($x eq '') {
			if (!$newblock) { push(@ary,''); }
			$newblock=1;
			next;
		}

		# 文章行
		$newblock=0;

		# [S] Satsukiタグのマクロ展開
		if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
			if ($x =~ m!(.*?)\[\*toc(?:|:(.*?))\](.*)!) {
				if ($1 ne '') { push(@ary,$1); }
				push(@ary,'',"<toc>$2</toc>\x01");
				if ($3 ne '') { push(@ary,$3); }
				next;
			}
		}
		push(@ary, $x);
	}
	# 文末空行の除去
	while($ary[$#ary] eq '') { pop(@ary); }

	# セクショニングを行う
	if ($sectioning && grep { $_ =~ /[^\s]/ } @ary) {
		unshift(@ary, "<section>\x02");
		push(@ary,'',"</section>\x02");
	}
	return \@ary;
}

#------------------------------------------------------------------------------
# ●[02] ブロックのパース
#------------------------------------------------------------------------------
sub parse_block {
	my ($self, $lines, $rec) = @_;

	my $pmode=1;
	my $seemore = 1;
	if ($rec && !grep{ $_ eq '' } @$lines) { $pmode=0; }

	my @ary;
	if ($lines->[$#$lines] ne '') { push(@$lines, ''); }
	my $links = $self->{links};
	my @p_block;
	while(@$lines) {
		my $x = shift(@$lines);
		if (ord(substr($x, -1)) < 3) {
			$self->p_block_end(\@ary, \@p_block);
			push(@ary, $x);
			next;
		}
		if ($x eq '') {
			$self->p_block_end(\@ary, \@p_block);
			push(@ary, $x);
			next;
		}

		#----------------------------------------------
		# リストブロック
		#----------------------------------------------
		if ($x =~ /^ ? ? ?(\*|\+|\-|\d+\.) /) {
			$self->p_block_end(\@ary, \@p_block);
			my $ulol = length($1)<2 ? 'ul' : 'ol';
			my @list=($x);
			my $blank=0;
			while(@$lines) {
				$x = shift(@$lines);
				if ($x ne '' && ord(substr($x, -1)) < 4) { last; }
				if ($blank && $x !~ /^ ? ? ?(?:\*|\+|\-|\d+\.) |^    /) { last; }
				push(@list, $x);
				$blank = ($x eq '');
			}
			unshift(@$lines, $x);
			if ($list[$#list] eq '') { pop(@list); }

			# listの構成
			push(@ary, "<$ulol>\x01");
			my @ul;
			my $li = [];
			my $blank=0;
			my $ul_indent = -1;
			my %p;
			while(@list) {
				$x = shift(@list);
				if ($x =~ /^( ? ? ?)(?:\*|\+|\-|\d+\.) (.*)$/
				 && ($ul_indent == -1 || length($1) == $ul_indent)) {
					if (@$li) {
						push(@ul, $li);
					}
					$li = [$2];
					$ul_indent = length($1);
					if ($blank) { $p{$li} = 1; }
					$blank=0;
					next;
				} elsif ( $x eq '' )  {
					$blank=1;
					$p{$li} = 1;
				} else {
					$blank=0;
					for(my $i=0; $i<$ul_indent; $i++) {
						# そのブロックのインデント除去
						if (ord($x) != 0x20) { next; }
						$x = substr($x,1);
					}
				}
				push(@$li, $x);
			}
			if (@$li) { push(@ul, $li); }

			# ネスト処理
			foreach my $li (@ul) {
				if ($#$li == 0) {
					push(@ary, $p{$li} ? "<li><p>$li->[0]</p></li>" : "<li>$li->[0]</li>");
					next;
				}
				# [M] リストネスト時は先頭スペースを最大1つ除去する
				foreach(@$li) {
					$_ =~ s/ //;
				}
				my $blk = $self->parse_block($li, 1);
				if ($blk->[$#$blk] eq '') { pop(@$blk); }
				$blk->[0] = '<li>' . $blk->[0];
				$blk->[$#$blk] .= '</li>';
				push(@ary, @$blk);
			}
			push(@ary, "</$ulol>\x01");
			next;
		}

		#----------------------------------------------
		# 引用ブロック [M] ブロックは入れ子処理する
		#----------------------------------------------
		if ($x =~ /^>/) {
			$self->p_block_end(\@ary, \@p_block);
			push(@ary, '<blockquote>');
			my $p = 0;
			my @block;
			while(@$lines && $x ne '') {
				$x =~ s/^>\s?(.*)$/$1/;		# [M] 除去するスペースは1つまで
				if ($x ne '' || $block[$#block] ne '') {
					push(@block, $x);
				}
				$x = shift(@$lines);
			}
			# [M] 入れ子処理する
			my $blk = $self->parse_block( $self->parse_special_block(\@block, 0) );
			push(@ary, @$blk);
			push(@ary, '</blockquote>');
			push(@ary, '');
			next;
		}

		#----------------------------------------------
		# [M] コードブロック
		#----------------------------------------------
		if ($x =~ /^    (.*)/) {
			$self->p_block_end(\@ary, \@p_block);
			my @code;
			unshift(@$lines, $x);
			while(substr($lines->[0],0,4) eq '    ') {
				$x = substr(shift(@$lines),4);
				$self->escape_in_code($x);
				push(@code, "$x\x02");
			}
			my $first = shift(@code);
			push(@ary, "<pre><code>$first\x02");
			push(@ary, @code);
			push(@ary, "</code></pre>\x02");
			next;
		}

		#----------------------------------------------
		# [GitHub] シンタックスハイライト
		#----------------------------------------------
		if ($x =~ /^```([^`]*?)\s*$/) {
			$self->p_block_end(\@ary, \@p_block);
			my ($lang,$file) = split(':', $1, 2);
			my @code;
			$x = shift(@$lines);
			while(@$lines && $x !~ /^```\s*$/) {
				$self->escape_in_code($x);
				push(@code, "$x\x02");
				$x = shift(@$lines);
			}
			my $class='';
			my $add='';
			if ($self->{satsuki_syntax_h}) {	# [S] Satsuki記法準拠
				if ($lang ne '') {
					$class = ' ' . $lang;
				}
				$class = " class=\"syntax-highlight$class\"";
				$add = $self->{load_SyntaxHighlighter};
			}
			my $first = shift(@code);
			push(@ary, "<div class=\"highlight\"><pre$class>$first");
			push(@ary, @code);
			push(@ary, "</pre></div>$add\x02");
			next;
		}

		#----------------------------------------------
		# 続きを読む記法
		#----------------------------------------------
		if ($seemore && $self->{satsuki_seemore} && ($x eq '====' || $x eq '=====')) {
			$self->p_block_end(\@ary, \@p_block);
			push(@ary, <<TEXT);
<p class="seemore"><a class="seemore" href="$self->{thisurl}">$self->{seemore_msg}</a></p><!--%SeeMore%-->\x02
TEXT
			chomp($ary[$#ary]);
			$seemore=0;
			next;
		}

		#----------------------------------------------
		# <hr />
		#----------------------------------------------
		my $y = $x;
		$y =~ s/\s//g;
		if ($y =~ /^\*\*\*\**$|^----*$|^____*$/) {
			$self->p_block_end(\@ary, \@p_block);
			push(@ary, "<hr />\x01");
			next;
		}

		#----------------------------------------------
		# リンク定義。[M] 参照名が空文字の場合は無効
		#----------------------------------------------
		if ($x =~ /^ ? ? ?\[([^\]]+)\]:\s*(.*?)\s*(?:\s*("[^\"]*"|'[^\']*')\s*)?\s*$/) {
			$self->p_block_end(\@ary, \@p_block);
			my $name = $1;
			my $url  = $2;
			my $title = substr($3,1);
			chop($title);
			$url =~ s/^<\s*(.*?)\s*>$/$1/;
			$name =~ tr/A-Z/a-z/;
			$self->tag_escape($url, $title);
			$links->{$name} = { url => $url, title => $title };

			# 次が空行なら除去する
			if ($lines->[0] eq '') { shift(@$lines); }
			next;
		}

		#----------------------------------------------
		# 通常文字
		#----------------------------------------------
		$x =~ s/^ ? ? ?//;	# [M] 手前スペース3つまで削除
		if (!$pmode) {
			push(@ary, $x);
			next;
		}
		# 段落ブロック
		push(@p_block, $x);
	}
	# 文末空行の除去
	while($ary[$#ary] eq '') { pop(@ary); }
	return \@ary;
}

sub p_block_end {
	my $self = shift;
	my $ary = shift;
	my $blk = shift;
	my $lf_patch = $self->{lf_patch};
	if (!@$blk) { return; }

	my $line = '<p>' . shift(@$blk);
	foreach my $x (@$blk) {
		$line =~ s|   *$| <br />|;	# 行末スペース2つ以上は強制改行
		if ($lf_patch && 0x7f < ord(substr($line,-1)) &&  0x7f < ord($x)) {
			# 日本語文章中に改行が含まれるとスペースになり汚いため行連結する。
			$line .= $x;
			next;
		}
		push(@$ary, $line);
		$line = $x;
	}
	push(@$ary, $line . '</p>');
	push(@$ary, '');
	$blk = [];
}

#------------------------------------------------------------------------------
# ●[03] インライン記法の処理
#------------------------------------------------------------------------------
sub parse_inline {
	my ($self, $lines) = @_;

	# さつき記法のタグを処理する？
	my $satsuki_parser = $self->{satsuki_tags} ? $self->{satsuki_obj} : undef;

	my $links = $self->{links};
	foreach(@$lines) {
		if (substr($_,-1) eq "\x02") { next; }

		# エスケープ処理
		$_ =~ s/\\([\\'\*_\{\}\[\]\(\)>#\+\-\.!])/"\x03E" . ord($1) . "\x03"/eg;

		# 自動リンク記法
		$_ =~ s!<((?:https?|ftp):[^'"> ]+)>!<a href="$1">$1</a>!ig;

		# 自動リンク記法のメールアドレス展開
		$_ =~ s|<(?:mailto:)?([\w\.\-\+]+\@[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]+)>|
			my $mail = $1;
			$self->un_escape($mail);
			my $mailto = $self->encode_email('mailto:');
			$mail = $self->encode_email($mail);
			"<a href=\"$mailto$mail\">$mail</a>";
		|eg;

		# 直接リンク記法
		$_ =~ s{(!?)\[([^\]]*)\]\(([^\)\"\']*?)(?:\s*("[^\"]*"|'[^\']*')\s*)?\)}
		{
			my $is_img= $1;
			my $text  = $2;
			my $url   = $3;
			my $title = substr($4,1);
			chop($title);
			$self->tag_escape($url, $title);
			if ($title ne '') { $title = " title=\"$title\""; }
			$is_img ? "<img src=\"$url\" alt=\"$text\"$title />"
				: "<a href=\"$url\"$title>$text</a>";
		}eg;

		# 参照リンク記法の処理 [M] 間に許されるのはスペース1個のみ
		$_ =~ s{(!?)(\[([^\]]*)\] ?\[([^\]]*)\])}
		{
			my $is_img= $1;
			my $org   = $2;
			my $text  = $3;
			my $name  = $4 eq '' ? $3 : $4;
			$name =~ tr/A-Z/a-z/;
			if ($name ne '' && exists($links->{$name}) ) {
				my $url   = $links->{$name}->{url};
				my $title = $links->{$name}->{title};
				if ($title ne '') { $title = " title=\"$title\""; }
				$is_img ? "<img src=\"$url\" alt=\"$text\"$title />"
					: "<a href=\"$url\"$title>$text</a>";
			} else {
				# 参照名が存在しないときはそのまま（書き換えない）
				$org;
			}
		}eg;

		# [S] さつき記法のタグ処理
		if ($satsuki_parser) {
			my $post_process = sub {
				# 強調タグ処理避け
				my $s = shift;
				$s =~ s/([\*\~\`_])/"\x03E". ord($1) ."\x03"/eg;
				return $s;
			};
			$_ = $satsuki_parser->parse_tag( $_, $post_process );
			$satsuki_parser->un_escape( $_ );
		}

		# 強調
		$_ =~ s|\*\*(.*?)\*\*|<strong>$1</strong>|xg;
		$_ =~ s|  __(.*?)__  |<strong>$1</strong>|xg;
		$_ =~ s| \*([^\*]*)\*|<em>$1</em>|xg;
		$_ =~ s|  _( [^_]*)_ |<em>$1</em>|xg;

		# [GitHub] Strikethrough
		$_ =~ s|~~(.*?)~~|<del>$1</del>|xg;
		
		# inline code
		$_ =~ s|(`+)(.+?)\1|
			my $s = $2;
			$self->escape_in_code($s);
			"<code>$s</code>";
		|eg;

		# タグ以外の &amp; やタグ以外の<>のエスケープ
		$_ =~ s{<([A-Za-z][\w]*(?:\s*[A-Za-z_][\w\-]*(?:=".*?"|='.*?'|[^\s>]*))*\s*/?)>}{\x03E60\x03$1\x03E62\x03}g;
		$_ =~ s{<(/[A-Za-z][\w]*\s*)>}{\x03E60\x03$1\x03E62\x03}g;
		$_ =~ s/&(\w+|\#\d+|\#[Xx][\dA-Fa-f]+);/\x00$1;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/&/&amp;/g;
		$_ =~ tr/\x00/&/;
	}
	
	#-----------------------------------------------
	# エスケープを戻す
	#-----------------------------------------------
	$self->un_escape(@$lines);

	return $lines;
}

# エスケープを戻す
sub un_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03E(\d+)\x03/chr($1)/eg;
	}
	return $_[0];
}


###############################################################################
# サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●コードブロック中のエスケープ
#------------------------------------------------------------------------------
sub escape_in_code {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●タグのエスケープ
#------------------------------------------------------------------------------
sub tag_escape {
	my $self = shift;
	foreach(@_) {
		# $_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●メールアドレス難読化エンコード
#------------------------------------------------------------------------------
sub encode_email {
	my $self = shift;
	my $str  = shift;
	$str =~ s[(.)][
		my $r = int(rand(10));
		if (!$r) { $1; }
		if ($r<5) { '&#'  . ord($1) .';'; }
		     else { '&#x' . sprintf('%X',ord($1)) .';'; }
	]eg;
	return $str;
}

#------------------------------------------------------------------------------
# ●デバッグ
#------------------------------------------------------------------------------
sub debug {
	my $self = shift;
	$self->{ROBJ}->debug($_[0], 1);		# debug-safe
}


1;
