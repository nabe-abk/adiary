use strict;
#-------------------------------------------------------------------------------
# Markdown parser
#                                              (C)2014-2024 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
# [M]	is compatible to Markdown.pl.
# [GFM] is compatible to GitHub Flavored Markdown.
# [S]	is Satsuki syntax extension.
#
package Satsuki::TextParser::Markdown;
our $VERSION = '1.30';
#-------------------------------------------------------------------------------
################################################################################
# Constructor
################################################################################
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{section_hnum} = 3;	# H3から使用する
	$self->{tab_width} = 4;		# タブの幅
	$self->{escape_spchar} = 1;	# タグではない <, > をエスケープする

	$self->{lf_patch} = 1;		# 日本語のpタグ中の改行を消す
	$self->{md_in_htmlblk} = 1;	# Markdown Inside HTML Blocksを許可する / PHP Markdown Extra
	$self->{sectioning}   = 1;	# sectionタグを適時挿入する
	$self->{gfm_ext}      = 1;	# GitHub Flavored Markdown拡張を使用する
	$self->{strict_list}  = 1;	# リスト開始記号が異なる時、違うブロックと判定する（標準非準拠）
	$self->{section_link} = 0;	# 見出しタグにリンクを挿入する

	$self->{satsuki_tags}     = 0;	# satsuki記法のタグを有効にする
	$self->{satsuki_syntax_h} = 1;	# syntaxハイライトをsatsuki記法に準拠させる
	$self->{satsuki_seemore}  = 1;	# 「続きを読む」記法
	$self->{satsuki_footnote} = 0;	# (())による注釈
	$self->{satsuki_in_htmlblk}= 1;	# HTML Blocks中のsatsuki記法を許可する

	$self->{qiita_math}       = 1;	# Qiitaのmathブロック記法

	# 処理する記事ごとに設定
	$self->{thisurl}  = '';		# 記事のURL
	$self->{thispkey} = '';		# 記事のpkey = unique id = [0-9]+

	return $self;
}

################################################################################
# Main
################################################################################
# 行末記号
#	\x01	これ以上、行処理しない
#	\x02	これ以上、行処理も記法処理もしない
# 特殊記号
#	\x00	not use
#	\x03	escape character
#	\x04	for HTML comment
#
#-------------------------------------------------------------------------------
# parse
#-------------------------------------------------------------------------------
sub parse {
	my ($self, $text) = @_;

	my $sobj = $self->{satsuki_tags} && $self->{satsuki_obj};	# Satsuki parser
	$self->{sobj} = $sobj;

	# Delete special character
	$text =~ s/[\x00-\x04]//g;
	$self->save_comments($text);

	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# Init internal variables
	if ( $sobj ) {
		$sobj->{thisurl}  = $self->{thisurl};
		$sobj->{thispkey} = $self->{thispkey};
	}
	$self->{sections} = [];
	$self->{links}    = {};
	$self->{ids}      = {};

	# parse main
	$lines = $self->parse_block ($lines);
	$lines = $self->parse_inline($lines);

	#-----------------------------------------
	# post process
	#-----------------------------------------
	my $all = join("\n", @$lines);
	$all =~ s|\n+\n</section>\x02|\n</section>\x02\n|g;

	# [S] <toc>
	if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
		$sobj->{sections} = $self->{sections};
		$sobj->post_process( \$all );
	}

	# [S] See More
	my $short = '';
	if ($all =~ /^((.*?)\n?<p class="seemore">.*)<!--%SeeMore%-->\x02?\n(.*)$/s ) {
		$short = $1;
		$all = $2 . "<!--%SeeMore%-->" . $3;
		if ($short =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
			$short .= "\n</section>";
		}
	}

	$self->restore_comments($all, $short);
	$all   =~ s/[\x00-\x04]//g;
	$short =~ s/[\x00-\x04]//g;

	return wantarray ? ($all, $short) : $all;
}

#-------------------------------------------------------------------------------
# save comments
#-------------------------------------------------------------------------------
sub save_comments {
	my $self = shift;
	my @ary;
	foreach(@_) {
		$_ =~ s/(<!(?:--.*?--\s*)+>)/push(@ary, $1),"\x04" . $#ary . "\x04"/esg;
	}
	foreach(@ary) {
		# remove %SeeMore% in comment
		$_ =~ s/<\!--%SeeMore%-->/<\!--%SeeMore% -->/;
	}
	$self->{comments_ary} = \@ary;
}

sub restore_comments {
	my $self = shift;
	my $ary = $self->{comments_ary};
	foreach(@_) {
		$_ =~ s/\x04(\d+)\x04/$ary->[$1]/g;
	}
}

################################################################################
# Markdown Block Parser
################################################################################
sub parse_nest_block {
	return &parse_block($_[0], $_[1], 1);
}
sub parse_block {
	my ($self, $lines, $nest) = @_;

	my $block_tags = qr!
		# original
		p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|
		script|noscript|form|fieldset|iframe|math|ins|del|
		# append tags
		style|article|section|nav|aside|header|footer|details|
		audio|video|figure|canvas|map|
		# GFM https://github.github.com/gfm/#html-block
		address|aside|base|hr|option|source
	!x;

	my $pmode      = ($nest && !grep { $_ eq '' } @$lines) ? 0 : 1;
	my $sectioning = $nest ? 0 : $self->{sectioning};
	my $in_section = 0;
	my $seemore    = 1;
	my $tab_width  = $self->{tab_width};
	my $links      = $self->{links};

	my @p_block;

	#-----------------------------------------------------------------------
	# main loop
	#-----------------------------------------------------------------------
	my @ary;
	push(@$lines, '');
	while(@$lines) {
		my $x = shift(@$lines);

		# HTML comment only
		if ($x =~ /^\s*(?:\x04\d+\x04\s*)+$/) {
			push(@ary, "\x02");
			next;
		}

		# [M] TAB to SPACE
		$x =~ s/(.*?)\t/$1 . (' ' x ($tab_width - (length($1) % $tab_width)))/eg;

		#---------------------------------------------------------------
		# HTML block
		#---------------------------------------------------------------
		if (!$nest && $x =~ /^<($block_tags)\b[^>]*>/i) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
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
			next;
		}

		#---------------------------------------------------------------
		# [Qiita] MathJax
		#---------------------------------------------------------------
		if ($self->{qiita_math} && $x =~ /^```math\s*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my @code;
			$x = shift(@$lines);
			while(@$lines && $x !~ /^```\s*$/) {
				push(@code, "$x\x02");
				$x = shift(@$lines);
			}
			push(@ary, "<div class=\"math\">\x02");
			push(@ary, @code);
			push(@ary, "</div>\x02");
			next;
		}

		#---------------------------------------------------------------
		# [GFM] Fenced code blocks
		#---------------------------------------------------------------
		if ($self->{gfm_ext} && $x =~ /^(```+|~~~+)([^`]*?)\s*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $fence = $1;
			my ($lang,$file) = split(':', $2, 2);
			my @code;
			while(@$lines) {
				$x = shift(@$lines);
				if (substr($x,0,length($fence)) eq $fence && $x =~ /^[`~]+\s*$/) { last; }
				$self->escape_in_code($x);
				push(@code, "$x\x02");
			}

			$self->tag_escape($lang, $file);
			my $class='';
			if ($self->{satsuki_syntax_h}) {	# [S]
				if ($lang ne '') {
					$class = ' ' . $lang;
				}
				$class = " class=\"syntax-highlight$class\"";
			}
			if ($file ne '') {
				$file = " title=\"$file\"";
			}
			my $first = shift(@code);
			push(@ary, "<div class=\"highlight\"><pre$class$file>$first");
			push(@ary, @code);
			push(@ary, "</pre></div>\x02");
			next;
		}

		#---------------------------------------------------------------
		# Header syntax
		#---------------------------------------------------------------
		# ==/--
		# [M] 2個以上の連なりで文末にスペース以外の文字がない
		if ($x =~ /^===*\s*$/ && $#p_block == 0) {
			$x = '# '  . pop(@p_block);
		}
		if ($x =~ /^---*\s*$/ && $#p_block == 0) {
			$x = '## ' . pop(@p_block);
		}

		if ($x =~ /^(#+)\s*(.*?)\s*\#*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $level = length($1);
			my $title = $2;
			if ($level == 1 && $sectioning && @ary) {
				push(@ary, "</section>\x02");
				push(@ary, "<section>\x02");
				$in_section=1;
			}

			# generate section
			my $base = '';
			my $secs = $self->{sections};
			foreach(2..$level) {
				my $s = @$secs ? $secs->[$#$secs] : undef;
				if (!$s) {
					if ($base eq '') { $base='0'; }
					$s = {
						num	=> "${base}.0",
						title	=> '(none)',
						count	=> 0
					};
					push(@$secs, $s);
				}
				$base = $s->{num};
				$secs = $s->{children} ||= [];
			}
			my $count = $#$secs<0 ? 1 : $secs->[$#$secs]->{count} + 1;
			my $num   = $base . ($level>1 ? '.' : '') . $count;
			my $id    = $self->generate_id_from_string($title, 'p' . $num);

			# save section information
			my $sec = {
				id	=> $id,
				num	=> $num,
				number  => undef,
				title	=> $self->parse_oneline($title),
				count	=> $count
			};
			push(@$secs, $sec);

			# output html
			my $h  = $self->{section_hnum} + $level -1;
			if (6 < $h) { $h=6; }
			push(@ary, "$self->{indent}<h$h id=\"$id\"><a href=\"$self->{thisurl}#$id\">$title</a></h$h>\x01");
			push(@ary,'');
			next;
		}

		#---------------------------------------------------------------
		# [S] Satsuki macro
		#---------------------------------------------------------------
		if ($self->{satsuki_tags} && $self->{satsuki_obj}) {
			if ($x =~ m!(.*?)\[\*toc(\d*)(?:|:(.*?))\](.*)!) {
				if ($1 ne '') { push(@ary,$1); }
				push(@ary,'',"<toc>depth=$2:$3</toc>\x01");
				if ($3 ne '') { push(@ary,$4); }
				next;
			}
		}

		#===============================================================
		# paragraph
		#===============================================================
		my $blank = !@p_block;
		if ($x =~ /^\s*$/) { $x=''; }

		# blank line
		if ($x eq '') {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, $x);
			next;
		}

		#---------------------------------------------------------------
		# list block
		#---------------------------------------------------------------
		if ($x =~ /^ ? ? ?(\*|\+|\-|\d+\.) /) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my $ulol = length($1)<2 ? 'ul' : 'ol';
			my $mark = $self->{strict_list} ? $1 : undef;
			$mark = ($mark =~ /^\d+\./) ? '0' : $mark;
			my @list=($x);
			my $blank=0;
			while(@$lines) {
				$x = shift(@$lines);
				if ($x ne '' && ord(substr($x, -1)) < 4) { last; }
				if ($blank && $x !~ /^ ? ? ?(\*|\+|\-|\d+\.) |^ /) { last; }
				if ($blank && $1 && $mark) {	# リストの開始文字判定
					my $m = $1;
					$m = ($m =~ /^\d+\./) ? '0' : $m;
					if ($mark ne $m) { last; }
				}
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
				if ($x =~ /^( ? ? ?)(?:\*|\+|\-|\d+\.) +(.*)$/
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

			# [GFM] checkbox list
			if ($self->{gfm_ext}) {
				foreach my $li (@ul) {
					if ($li->[0] =~ /^\[( |x)\](.*)/) {
						$li->[0] = '<label><input type="checkbox"'
							 . ($1 eq 'x' ? ' checked>' : '>')
							 . $li->[0] . '</label>';
					}
				}
			}

			# nest
			foreach my $li (@ul) {
				if ($#$li == 0) {
					push(@ary, $p{$li} ? "<li><p>$li->[0]</p></li>" : "<li>$li->[0]</li>");
					next;
				}
				# [M] リストネスト時は先頭スペースを最大4つ除去する
				foreach(@$li) {
					$_ =~ s/^  ? ? ?//;
				}

				my $blk = $self->parse_nest_block( $li );
				if ($blk->[$#$blk] eq '') { pop(@$blk); }
				$blk->[0] = '<li>' . $blk->[0];
				$blk->[$#$blk] .= '</li>';
				push(@ary, @$blk);
			}
			push(@ary, "</$ulol>\x01");
			next;
		}

		#---------------------------------------------------------------
		# [M] blockquote
		#---------------------------------------------------------------
		if ($x =~ /^ ? ? ?>/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, '<blockquote>');
			my $p = 0;
			my @block;
			while(@$lines && $x ne '') {
				$x =~ s/^ ? ? ?>\s?(.*)$/$1/;	# [M] '>'後の除去するスペースは1つまで
				if ($x ne '' || $block[$#block] ne '') {
					push(@block, $x);
				}
				$x = shift(@$lines);
			}
			# [M] 入れ子処理する
			my $blk = $self->parse_nest_block( \@block );
			push(@ary, @$blk);
			push(@ary, '</blockquote>');
			next;
		}

		#---------------------------------------------------------------
		# [M] コードブロック
		#---------------------------------------------------------------
		if ($blank && $x =~ /^    (.*)/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			my @code = ($x);
			while(@$lines && (substr($lines->[0],0,4) eq '    ' || $lines->[0] =~ /^\s*$/)) {
				push(@code, shift(@$lines));
			}
			# 最後の空行を無視
			while (@code && $code[$#code] =~ /^\s*$/) {
				unshift(@$lines, pop(@code));
			}
			foreach(@code) {
				$x = substr($_, 4);
				$self->escape_in_code($x);
				$_ = "$x\x02";
			}
			my $first = shift(@code);
			push(@ary, "<pre><code>$first\x02");
			push(@ary, @code);
			push(@ary, "</code></pre>\x02");
			next;
		}

		#---------------------------------------------------------------
		# [GFM] テーブル
		#---------------------------------------------------------------
		if ($self->{gfm_ext} && $blank
		 && $x =~ /^\s*\|/
		 && $lines->[0] =~ /^\s*|(?:\s*:?\-{3,}:?\s*\|)+\s*$/
		) {
			my @buf = ($x);
			while(@$lines && $lines->[0] =~ /\|/) {
				push(@buf, shift(@$lines));
			}
			my @tbl = @buf;	# copy

			# 行頭と行末の | と空白を除去
			foreach(@tbl) {
				$_ =~ s/^\s*\|?//;
				$_ =~ s/\|?\s*$//;
			}
			my @th = split(/\s*\|\s*/, shift(@tbl));	# 1行目
			my @hr = split(/\s*\|\s*/, shift(@tbl));	# 2行目
			my $err = ($#th > $#hr);			# [GFM] カラム数不一致
			my @class;
			foreach(@hr) {
				if ($#class >= $#th) { next; }		# [GFM] thの分しか読み込まない
				if ($_ !~ /^(:)?-*(:)?/) { $err=1; last; }

				my $c;
				if ($1 && $2) {
					$c = 'c';
				} elsif ($1) {
					$c = 'l';
				} elsif ($2) {
					$c = 'r';
				}
				push(@class, $c);
			}

			# 書式が正しくない時は無効
			if ($err) {
				shift(@buf);
				unshift(@$lines, @buf);
			} else {
				# テーブル展開
				push(@ary, "<table><thead><tr>\x02");
				push(@ary, "\t<th>" . join("</th>\n\t<th>", @th) . "</th>");
				push(@ary, "</tr></thead>\x02");
				if (@tbl) { push(@ary, "<tbody>\x02"); }
				foreach(@tbl) {
					my @cols = split(/\s*\|\s*/, $_);
					push(@ary, "<tr>\x02");
					foreach(@class) {
						my $t = shift(@cols);
						my $c = $_ ? " class=\"$_\"" : '';
						push(@ary, "\t<td$c>$t</td>");
					}
					push(@ary, "</tr>\x02");
				}
				if (@tbl) { push(@ary, "</tbody>\x02"); }
				push(@ary, "</table>\x02");
				next;
			}
		}

		#---------------------------------------------------------------
		# 続きを読む記法
		#---------------------------------------------------------------
		if ($blank && $seemore && $self->{satsuki_seemore} && ($x eq '====' || $x eq '=====')) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, <<TEXT);
<p class="seemore"><a class="seemore" href="$self->{thisurl}">$self->{seemore_msg}</a></p><!--%SeeMore%-->\x02
TEXT
			chomp($ary[$#ary]);
			$seemore=0;
			next;
		}

		#---------------------------------------------------------------
		# <hr />
		#---------------------------------------------------------------
		my $y = $x;
		$y =~ s/\s//g;
		if ($y =~ /^\*\*\*\**$|^----*$|^____*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, "<hr />\x01");
			next;
		}

		#---------------------------------------------------------------
		# リンク定義。[M] 参照名が空文字の場合は無効
		#---------------------------------------------------------------
		if ($x =~ /^ ? ? ?\[([^\]]+)\]:\s*(.*?)\s*(?:\s*("[^\"]*"|'[^\']*')\s*)?\s*$/) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
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

		#---------------------------------------------------------------
		# 通常文字
		#---------------------------------------------------------------
		$x =~ s/^ ? ? ?//;	# [M] 手前スペース3つまで削除
		push(@p_block, $x);	# 段落ブロック

	}
	while(@ary && $ary[$#ary] eq '') { pop(@ary); }

	# sectioning
	if ($sectioning && grep { $_ =~ /[^\s]/ } @ary) {
		unshift(@ary, "<section>\x02");
		push(@ary, "</section>\x02");
	}
	return \@ary;
}

sub p_block_end {
	my $self = shift;
	my $ary  = shift;
	my $blk  = shift;
	my $pmode= shift;
	my $lf_patch = $self->{lf_patch};
	if (!@$blk) { return; }

	my $line = ($pmode ? '<p>' : '') . shift(@$blk);
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
	# \> によるエスケープ
	$line =~ s/\\>/&gt;/g;

	push(@$ary, $line . ($pmode ? '</p>' : ''));
	@$blk = ();
}

################################################################################
# Markdown Inline Parser
################################################################################
sub parse_oneline {
	my ($self, $text) = @_;
	my $lines = $self->parse_inline( [$text] );
	return $lines->[0];
}

sub parse_inline {
	my ($self, $lines) = @_;

	# 強調タグ処理避け
	sub escape_special_char {
		my $s = shift;
		$s =~ s/([\*\~\`_])/"\x03". ord($1) ."\x03"/eg;
		return $s;
	}

	# Satsuki parser obj
	my $satsuki = $self->{satsuki_obj};

	# 注釈
	my @footnote;
	my %note_hash;

	my $links = $self->{links};
	foreach(@$lines) {
		if (substr($_,-1) eq "\x02") { next; }

		# エスケープ処理
		$_ =~ s/\\([\\`'\*_\{\}\[\]\(\)>#\+\-\.\~!])/"\x03" . ord($1) . "\x03"/eg;

		# inline code
		$_ =~ s|(`+)([^`]+?)\1|
			my $s = $2;
			$self->escape_in_code($s);
			$s =~ s/([\\`'\*_\{\}\[\]\(\)>#\+\-\.\~!])/"\x03" . ord($1) . "\x03"/eg;
			"<code>$s</code>";
		|eg;

		# 注釈処理 ((xxxx))
		if ($self->{satsuki_footnote}) {
			$_ =~ s/\(\((.*?)\)\)/ $satsuki->footnote($1, \@footnote, \%note_hash) /eg;
			if (substr($_,-2) eq "\x02\x01") {
				# section end
				my $ary = $satsuki->output_footnote(undef, \@footnote, \%note_hash);
				$_ = join('', @$ary) . $_;
			}
		}

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
		if ($self->{satsuki_tags}) {
			$_ = $satsuki->parse_tag( $_, \&escape_special_char );
			$satsuki->un_escape( $_ );
		}

		# タグ中の文字を処理しないようにエスケープ
		# <a href="http://example.com/_hoge_">_hoge_</a>
		$_ =~ s!(<\w(?:"[^\"]*"|'[^\"]*'|[^>])*>)!&escape_special_char($1)!eg;

		# 強調
		$_ =~ s|\*\*(.*?)\*\*|<strong>$1</strong>|xg;
		$_ =~ s|  __(.*?)__  |<strong>$1</strong>|xg;
		$_ =~ s| \*([^\*]*)\*|<em>$1</em>|xg;

		if ($self->{gfm_ext}) {
			$_ =~ s#(^|\W)_([^_]*)_(\W|$)#$1<em>$2</em>$3#g;		# [GFM]
		} else {	
			$_ =~ s|_( [^_]*)_ |<em>$1</em>|xg;				# [M]
		}

		# [GFM] Strikethrough
		if ($self->{gfm_ext}) {
			$_ =~ s|~~(.*?)~~|<del>$1</del>|xg;
		}

		# escape special charactor "<" ">"
		if ($self->{escape_spchar}) {
			$_ =~ s!(.*?)(</[\w\-]+>|<[\w\-]+(?:\s+[\w\-]+(?:\s*=\s*(?:[^\s\"]+|"[^\"]*"))?)*\s*/?>|$)!
				(($1 =~ s/</&lt;/rg) =~ s/>/&gt;/rg) . $2;
			!eg;
		}
	}

	#---------------------------------------------------
	# エスケープを戻す
	#---------------------------------------------------
	$self->un_escape(@$lines);

	return $lines;
}

# エスケープを戻す
sub un_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03(\d+)\x03/chr($1)/eg;
	}
	return $_[0];
}

################################################################################
# Subroutine
################################################################################
#-------------------------------------------------------------------------------
# ●コードブロック中のエスケープ
#-------------------------------------------------------------------------------
sub escape_in_code {
	my $self = shift;
	$self->restore_comments(@_);
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●タグのエスケープ
#-------------------------------------------------------------------------------
sub tag_escape {
	my $self = shift;
	$self->restore_comments(@_);
	foreach(@_) {
		# $_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●メールアドレス難読化エンコード
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# ●ラベル等からidを生成
#-------------------------------------------------------------------------------
sub generate_id_from_string {
	my $self  = shift;
	my $label = shift;
	my $default = shift || 'id';
	$label =~ tr/A-Z/a-z/;
	$label =~ s/[^\w\-\.\x80-\xff]+/-/g;
	return $self->generate_link_id($label eq '' ? $default : $label);
}

sub generate_link_id {
	my $self  = shift;
	my $base  = shift;
	my $ids   = $self->{ids};

	my $id = $base;
	my $i  = 1;
	while($ids->{$id}) {
		$id = $base . "-" . (++$i);
	}
	$ids->{$id} = 1;
	return $id;
}

1;
