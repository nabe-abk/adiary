use strict;
#------------------------------------------------------------------------------
# reStructuredText
#	                                              (C)2019 nabe@abk
#------------------------------------------------------------------------------
#
package Satsuki::TextParser::reStructuredText;
our $VERSION = '0.10';
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

	$self->{section_hnum} = 3;	# H3から使用する
	$self->{tab_width}    = 8;	# タブの幅

	$self->{lf_patch}     = 1;	# 日本語のpタグ中の改行を消す
	$self->{span_sanchor} = 0;	# 見出し先頭に span.sanchor を挿入する
	$self->{section_link} = 0;	# 見出しタグにリンクを挿入する

	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
# 行末記号
#	\x01	
#	\x02	これ以上、処理しない
#	\x03	ブロックの終わりマーク
# 文中記号
#	\x02	pブロック処理に使用
#
#------------------------------------------------------------------------------
# ●記事本文の整形
#------------------------------------------------------------------------------
sub text_parser {
	my ($self, $text) = @_;
	my $sobj = $self->{satsuki_tags} && $self->{satsuki_obj};	# Satsuki parser

	# 行に分解
	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# 内部変数初期化
	$self->{links} = {};
	$self->{enum_cache} = {};
	$self->init_unique_link_name();
	if ( $sobj ) {
		$sobj->{thisurl}  = $self->{thisurl};
		$sobj->{thispkey} = $self->{thispkey};
		$sobj->{thisymd}  = $self->{thisymd};
		$sobj->init_unique_link_name();
	}

	# セクション情報の初期化
	$self->{sections} = [];

	#-------------------------------------------
	# ○処理スタート
	#-------------------------------------------
	# [01] ブロックのパース
	$lines = $self->parse_block($lines);

	# [02] インライン記法の処理
	$lines = $self->parse_inline($lines);

	#-------------------------------------------
	# ○後処理
	#-------------------------------------------
	my $sec;
	if (substr($lines->[$#$lines],-2) eq "\x02\x01") { $sec=pop(@$lines); }
	while(@$lines && $lines->[$#$lines] eq '') { pop(@$lines); }
	if ($sec) { push(@$lines, $sec); }

	# [S] <toc>の後処理
	my $all = join("\n", @$lines);

	if (0 && $self->{satsuki_tags} && $self->{satsuki_obj}) {
		$sobj->{sections} = $self->{sections};
		$sobj->post_process( \$all );
	}

	# [S] Moreの処理
	my $short = '';
	if (0 && $all =~ /^((.*?)\n?<p class="seemore">.*)<!--%SeeMore%-->\x02?\n(.*)$/s ) {
		$short = $1;
		$all = $2 . "<!--%SeeMore%-->" . $3;
		if ($short =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
			$short .= "\n</section>";
		}
	}

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
# ■パーサー本体
###############################################################################
#//////////////////////////////////////////////////////////////////////////////
# ●[01] ブロックのパース
#//////////////////////////////////////////////////////////////////////////////
sub parse_block {
	my ($self, $lines) = @_;

	# 前処理
	my $tw = $self->{tab_width};
	foreach(@$lines) {
		$_ =~ s/[\v]/ /g;		# VTの処理
		$_ =~ s/\s+$//g;		# 行末スペース除去

		# TAB to SPACE 8つ
		$_ =~ s/(.*?)\t/$1 . (' ' x ($tw - (length($1) % $tw)))/eg;
	}

	my @out;
	return $self->do_parse_block(\@out, $lines);
}
sub do_parse_block {
	my ($self, $out, $lines, $nest) = @_;

	# 先頭空行除去
	while(@$lines && $lines->[0] eq '') { shift(@$lines); }

	# 空データ
	if ($nest && !@$lines) { return; }

	#
	# セクション情報
	#
	my $sections    = $self->{sections};
	my $subsections = [];
	my $in_section;

	# 入れ子要素、かつ、空行を含まない時は行処理をしない
	my $ptag = ($nest && !(grep {$_ eq '' } @$lines)) ? '' : 'p';

	# リストアイテムモード
	my $item_mode = ($ptag && $nest eq 'list-item') ? $#$out+1 : undef;
	my $blocks    = 0;
	if ($item_mode) {
		$ptag = "\x02p";
	}

	my @p_block;
	my @dl_block;
	push(@$lines, '');
	while(@$lines) {
		my $x = shift(@$lines);
		my $y = $lines->[0];

		#----------------------------------------------
		# 空行
		#----------------------------------------------
		if ($x eq '') {
			if (@p_block) {
				$self->block_end($out, \@p_block, $ptag);
				$blocks++;
			}
			next;
		}

		#----------------------------------------------
		# ブロック
		#----------------------------------------------
		if ($x =~ /^( +)/) {
			$self->block_end($out, \@p_block, $ptag);
			$blocks=999;

			# block抽出
			my $block = $self->extract_block( $lines, 0, $x );

			if ($out->[$#$out] ne '') { push(@$out, ''); }
			push(@$out, "<blockquote>\x02");
			$self->do_parse_block($out, $block, 'nest');
			push(@$out, "</blockquote>\x02", '');
			next;
		}

		#----------------------------------------------
		# リテラルブロック : literal_block
		#----------------------------------------------
		if ($x =~ /^(.*)::$/ && $y eq '') {
			$x = $1;
			$blocks=999;
			$self->block_end($out, \@p_block, $ptag);

			if ($x ne '') {
				# "Paragraph ::" to "Paragraph"
				# "Paragraph::"  to "Paragraph:"
				if (substr($x,-1) ne ' ') { $x .= ':'; }
				$x =~ s/ +$//;
				unshift(@$lines, '::');
				unshift(@$lines, '');
			} else {
				$self->skip_blank($lines);
				if ($lines->[0] =~ /^( )/ || $lines->[0] =~ /^([!"#\$%&'\(\)\*\+,\-\.\/:;<=>\?\@\[\\\]^_`\{\|\}\~])/) {
					my $block = [];
					if ($1 eq ' ') {
						$x = shift(@$lines);
						$block = $self->extract_block( $lines, 0, $x );
					} else {
						my $mark = $1;
						while(@$lines && substr($lines->[0],0,1) eq $mark) {
							push(@$block, shift(@$lines));
						}
					}

					if ($out->[$#$out] ne '') { push(@$out, ''); }
					push(@$out, "<pre class=\"syntax-highlight\">\x02");
					foreach(@$block) {
						$self->tag_escape($_);
						push(@$out, "$_\x02");
					}
					push(@$out, "</pre>\x02", '');
					next;
				}
			}
		}

		#----------------------------------------------
		# 特殊ブロック判定
		#----------------------------------------------
		my ($btype, $bopt) = !@p_block && $self->test_block($nest, $x, $y, 'first');
		if ($btype && $btype ne 'list' && $btype ne 'enum') {
			$blocks=999;
		}

		#----------------------------------------------
		# 通常行
		#----------------------------------------------
		if (!$btype) {
			push(@p_block, $x);	# 段落ブロック
			next;
		}

		#----------------------------------------------
		# 箇条書きリスト : bullet_list
		#----------------------------------------------
		if ($btype eq 'list') {
			my $mark = $bopt->{mark};
			unshift(@$lines, $x);

			push(@$out, "<ul>\x02");
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines->[1]);
				if ($type ne 'list' || $opt->{mark} ne $mark) { last; }
				shift(@$lines);

				my $item = $self->extract_block($lines, $opt->{len}, $opt->{first});

				my $n = $#$out+1;
				$self->do_parse_block($out, $item, 'list-item');
				$out->[$n] = '<li>' . $out->[$n];
				$out->[$#$out] .= '</li>';
			}

			push(@$out, "</ul>\x02", '');
			next;
		}

		#----------------------------------------------
		# 列挙リスト : enumerated_list
		#----------------------------------------------
		if ($btype eq 'enum') {
			my $subtype = $bopt->{subtype};
			my $numtype = $bopt->{numtype};
			my $num     = $bopt->{num};
			my $mode    = $bopt->{mode};
			unshift(@$lines, $x);

			{
				my $start = ($num != 1) ? " start=\"$num\"" : '';
				push(@$out, "<ol class=\"$bopt->{numtype}\"$start>\x02");
			}
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines->[1], $mode);
				if ($type ne 'enum' || $opt->{subtype} ne $subtype
				 || $opt->{numtype} ne 'auto' && ($opt->{numtype} ne $numtype || $opt->{num} != $num)
				) {
					last;
				}
				shift(@$lines);

				my $item = $self->extract_block($lines, $opt->{len}, $opt->{first});

				my $n = $#$out+1;
				$self->do_parse_block($out, $item, 'list-item');
				$out->[$n] = '<li>' . $out->[$n];
				$out->[$#$out] .= '</li>';

				$num++;
			}

			push(@$out, "</ol>\x02", '');
			next;
		}

		#----------------------------------------------
		# フィールドリスト : field_list / table
		#----------------------------------------------
		if ($btype eq 'field') {
			unshift(@$lines, $x);

			my @fields;
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines->[1]);
				if ($type ne 'field') { last; }
				shift(@$lines);

				my $name = $opt->{name};
				my $body = $self->extract_block($lines, $opt->{len}, '');
				$body->[0] = $opt->{value};	# 最初の行は最小インデントに合わせる

				# dt classifier
				$self->tag_escape($name);
				push(@fields, "<tr><th>$name</th>");
				my $n = $#fields+1;
				$self->do_parse_block(\@fields, $body, 'nest');
				$fields[$n] = '<td>' . $fields[$n];
				$fields[$#fields] .= "</td>";
				push(@fields, "</tr>\x02");
			}
			if (@fields && ($nest || @$out)) {	# 最初のフィールドリストは出力しない
				push(@$out, "<table class=\"field-list\">\x02");
				push(@$out, "<tbody>\x02");
				push(@$out, @fields);
				push(@$out, "</tbody>\x02");
				push(@$out, "</table>\x02");
			}
			next;
		}

		#----------------------------------------------
		# オプションリスト : option_list / table
		#----------------------------------------------
		if ($btype eq 'option') {
			unshift(@$lines, $x);

			push(@$out, "<table class=\"option-list\">\x02");
			push(@$out, "<tbody>\x02");

			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines->[1], 'option');
				if ($type ne 'option') { last; }
				shift(@$lines);

				my $body = $self->extract_block($lines, $opt->{len}, '');
				$body->[0] = $opt->{value};	# 最初の行は最小インデントに合わせる

				# dt classifier
				push(@$out, "<tr><th>$opt->{option}</th>");	# {option} is tag escaped
				my $n = $#$out+1;
				$self->do_parse_block($out, $body, 'nest');
				$out->[$n] = '<td>' . $out->[$n];
				$out->[$#$out] .= "</td>";
				push(@$out, "</tr>\x02");
			}

			push(@$out, "</tbody>\x02");
			push(@$out, "</table>\x02");
			next;
		}

		#----------------------------------------------
		# 定義リスト : definition_list
		#----------------------------------------------
		if ($btype eq 'definition') {
			unshift(@$lines, $x);
			push(@$out, "<dl>\x02");
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines->[1]);
				if ($type ne 'definition') { last; }

				my $dt = shift(@$lines);
				my $dd = $self->extract_block($lines, $opt->{len}, shift(@$lines));

				# dt classifier
				$self->tag_escape($dt);
				my @c = split(/ +: +/, $dt);
				$dt = shift(@c);
				foreach(@c) {
					$dt .= ' <span class="classifier-delimiter">:</span> ' . '<span class="classifier">' . $_ . '</span>';
				}

				push(@$out, "<dt>$dt</dt>");
				my $n = $#$out+1;
				$self->do_parse_block($out, $dd, 'nest');
				$out->[$n] = '<dd>' . $out->[$n];
				$out->[$#$out] .= '</dd>';
			}
			push(@$out, "</dl>\x02", '');
			next;
		}

		#----------------------------------------------
		# エラー
		#----------------------------------------------
		$self->{ROBJ}->error("Internal Error: Unknown block type '$btype'");
	}

	if ($item_mode) {
		if ($blocks <= 1) {	# <p>を除去
			for(my $i=$item_mode; $i <= $#$out; $i++) {
				$out->[$i] =~ s|</?\x02p>||g;
			}
		} else {		# <p>を有効化
			for(my $i=$item_mode; $i <= $#$out; $i++) {
				$out->[$i] =~ s|(</?)\x02p>|${1}p>|g;
			}
		}
	}

	# 文末空行の除去
	while(@$out && $out->[$#$out] eq '') { pop(@$out); }

	return $out;
}

#------------------------------------------------------------------------------
# ブランク行（空行）の除去
#------------------------------------------------------------------------------
sub skip_blank {
	my $self  = shift;
	my $lines = shift;
	while(@$lines && $lines->[0] eq '') {
		shift(@$lines);
	}
	return $lines;
}

#------------------------------------------------------------------------------
# 特殊ブロックの開始判定
#------------------------------------------------------------------------------
sub test_block {
	my $self = shift;
	my $nest = shift;
	my $x    = shift;
	my $y    = shift;
	my $mode = shift;

	# 箇条書きリスト
	if ($x =~ /^(([\*\+\-•‣⁃])( +|$))/) {
		return ('list', {
			first => $3 eq '' ? ''    : $x,
			len   => $3 eq '' ? undef : length($1),
			mark  => $2
		});
	}

	# 列挙リスト
	my ($enum, $opt) = $self->test_block_enumrate($x, $mode);
	if ($enum) {
		if ($y eq '' || $y =~ /^ /) {	# blank or indent
			return ($enum, $opt);
		}
		my ($type, $opt2) = $self->test_block_enumrate($y, $opt->{mode});
		if ($type
		 && $opt->{subtype} eq $opt2->{subtype}
		 && ($opt2->{numtype} eq 'auto'
		 	 || $opt->{numtype} eq $opt2->{numtype} && $opt->{num}+1 == $opt2->{num}
		    )
		) {
			return ($enum, $opt);
		}
	}

	# フィールドリスト
	if ($x =~ /^:(.+):(?: +|$)(.*)/ && substr($1,0,1) ne ' ' &&  substr($1,-1) ne ' ') {
		return ('field', {
			name  => $1,
			value => $2
		});
	}

	# オプションリスト
	if ($x =~ /^-[A-Za-z0-9]/ || $x =~ /^--\w/ || $x =~ m|^/\w|) {
		my $z = $x;
		my @buf;
		$z =~ s/(<[^>]+>)/push(@buf,$1), "<$#buf>"/eg;

		my ($o, $v) = split(/  +/, $z, 2);
		my $option;
		foreach(split(/, /, $o)) {
			if ($_ =~ /^(-[A-Za-z0-9])( ?)(.*)/ || $_ =~ /^((?:--|\/)\w[\w-]*)([= ]?)(.*)/) {
				my $op  = $1;
				my $sp  = $2;
				my $arg = $3;
				if ($arg eq '' || $arg =~ /^[a-zA-Z][a-zA-Z0-9_-]*$/ || $arg =~ /^<(\d+)>$/) {
					if ($1 ne '') { $arg = $buf[$1]; }
					$self->tag_escape($op, $arg);
					$option .= ($option ? ', ' : '') . "$op$sp<var>$arg</var>";
					next;
				}
			}
			if ($mode eq 'option') {
				$self->parse_error("Invalid option list : $x");
			}
			last;
		} 
		return ('option', {
			option=> $option,
			value => $v
		});
	}

	# 定義リスト（最後に処理）
	if ($x !~ /^ / && $y =~ /^( +)/) {
		return ('definition', {
			len => length($1)
		});
	}
	return;
}

#----------------------------------------------
# 列挙型の検出
#----------------------------------------------
sub test_block_enumrate {
	my $self = shift;
	my $x    = shift;
	my $mode = shift;

	my $key   = ($x =~ /^[A-Za-z]$/) ? "$mode:$x" : $x;
	my $cache = $self->{enum_cache};
	my $c = $cache->{$key} || [ $self->do_test_block_enumrate($x, $mode) ];
	$cache->{$key} = $c;

	## $self->debug("$x mode=$mode $c->[0] $c->[1]->{subtype} $c->[1]->{numtype} $c->[1]->{num}");

	return ($c->[0], $c->[1]);
}
sub do_test_block_enumrate {
	my $self = shift;
	my $x    = shift;
	my $mode = shift || 'other';

	if ($x !~ /^((\w+|#)\.( +|$))/ && $x !~ /^(\(?(\w+|#)\)( +|$))/) { return; }

	my $subtype = 'dot';
	if (substr($1,-1) eq ')') {
		$subtype = substr($1,0,1) eq '(' ? '(' : ')';
	}
	my $len = length($1);
	my $seq = $2;
	if ($3 eq '') { $x=''; $len=undef; }

	if ($seq eq '#') {	# auto
		return ('enum', {
			first   => $x,
			len     => $len,
			subtype => $subtype,
			numtype => 'auto'
		});
	}
	if ($seq =~ /^[1-9]\d*$/ || $seq eq '0') {
		return ('enum', {
			first   => $x,
			len     => $len,
			subtype => $subtype,
			numtype => 'arabic',
			num     => $seq
		});
	}
	if ( $mode eq 'first' && $seq =~ /^[A-HJ-Z]$/		# exclude 'I'
	  || $mode eq 'roman' && $seq =~ /^[ABE-KN-UWYZ]$/	# exclude [CDLMVX]
	  || $mode eq 'other' && $seq =~ /^[A-Z]$/) {
		return ('enum', {
			first   => $x,
			len     => $len,
			subtype => $subtype,
			numtype => 'upper-alpha',
			num     => ord($seq) - 0x40
		});
	}
	if ( $mode eq 'first' && $seq =~ /^[a-hj-z]$/		# exclude 'i'
	  || $mode eq 'roman' && $seq =~ /^[abe-kn-uwyz]$/	# exclude [cdlmvx]
	  || $mode eq 'other' && $seq =~ /^[a-z]$/) {
		return ('enum', {
			first   => $x,
			len     => $len,
			subtype => $subtype,
			numtype => 'lower-alpha',
			num     => ord($seq) - 0x60
		});
	}

	# ローマ数字
	my ($type, $num) = $self->parse_roman_number($seq);
	if ($type) {
		return ('enum', {
			first   => $x,
			len     => $len,
			subtype => $subtype,
			mode    => 'roman',
			numtype => $type,
			num     => $num
		});
	}
	return;
}

#------------------------------------------------------------------------------
# ブロックの抽出
#------------------------------------------------------------------------------
sub extract_block {
	my $self  = shift;
	my $lines = shift;
	my $len   = shift;
	my $first = shift;

	my @block = ($first);
	my $flex  = ($len == 0);	# 最小インデント検出
	if ($flex && $first =~ /^( +)/) {
		$len = length($1);
	}

	while(@$lines) {
		my $y = $lines->[0];
		if ($y eq '') {		# 空行
			if (@block) { push(@block, ''); }
		} elsif ($y =~ /^( +)/) {
			my $l = length($1);
			if (!$len || $len > $l) {
				if (!$flex) { last; }
				$len = $l;	# 最小インデントを検出
			}
			push(@block, $y);
		} else {
			last;
		}
		shift(@$lines);
	}
	# 文末空行の除去
	while(@block && $block[$#block] eq '') { pop(@block); }

	# インデント除去とタグエスケープ
	foreach(@block) {
		$_ = substr($_, $len);
	}
	return \@block;
}

#------------------------------------------------------------------------------
# ブロックの後処理
#------------------------------------------------------------------------------
sub block_end {
	my $self = shift;
	my $out  = shift;
	my $blk  = shift;
	my $tag  = shift;
	my $lf_patch = $self->{lf_patch};
	if (!@$blk) { return; }

	# ブロック末空行の除去
	while(@$blk && $blk->[$#$blk] eq '') { pop(@$blk); }

	my $line = shift(@$blk);
	foreach(@$blk) {
		if ($lf_patch && 0x7f < ord(substr($line,-1)) &&  0x7f < ord($_)) {
			# 日本語文章中に改行が含まれるとスペースになり汚いため行連結する。
			$line .= $_;
			next;
		}
		$line .= "\n" . $_;
	}

	$self->tag_escape($line);
	push(@$out, ($tag ? "<$tag>" : '') . $line . ($tag ? "</$tag>" : ''));
	push(@$out, '');
	@$blk = ();
}

#//////////////////////////////////////////////////////////////////////////////
# ●[02] ブロックのパース
#//////////////////////////////////////////////////////////////////////////////
sub xxxxxxxxx {
	my ($self, $lines, $rec) = @_;

	my $pmode=1;
	my $seemore = 1;
	my $next_blank;
	if ($rec && !grep{ $_ eq '' } @$lines) { $pmode=0; }

	my @p_block;
	my @ary;
	if ($lines->[$#$lines] ne '') { push(@$lines, ''); }
	my $links = $self->{links};
	while(@$lines) {
		my $blank = $next_blank;
		$next_blank = 0;

		my $x = shift(@$lines);
		if ($x =~ /^\s*$/) { $x=''; }

		# 空行
		if ($x eq '' ) {
			if (@p_block) {
				$self->p_block_end(\@ary, \@p_block, $pmode);
				push(@ary, $x);
			}
			$next_blank = 1;
			next;
		}
		# 特殊行
		if (ord(substr($x, -1)) < 3) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, $x);
			$next_blank = 1;
			next;
		}

		#----------------------------------------------
		# リストブロック
		#----------------------------------------------
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

			# ネスト処理
			foreach my $li (@ul) {
				if ($#$li == 0) {
					push(@ary, $p{$li} ? "<li><p>$li->[0]</p></li>" : "<li>$li->[0]</li>");
					next;
				}
				# [M] リストネスト時は先頭スペースを最大4つ除去する
				foreach(@$li) {
					$_ =~ s/^  ? ? ?//;
				}
				my $blk = $self->parse_block($li, 1);
				if ($blk->[$#$blk] eq '') { pop(@$blk); }
				$blk->[0] = '<li>' . $blk->[0];
				$blk->[$#$blk] .= '</li>';
				push(@ary, @$blk);
			}
			push(@ary, "</$ulol>\x01");
			$next_blank = 1;
			next;
		}

		#----------------------------------------------
		# 引用ブロック [M] ブロックは入れ子処理する
		#----------------------------------------------
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
			my $blk = $self->parse_block( $self->parse_special_block(\@block, 1) );
			push(@ary, @$blk);
			push(@ary, '</blockquote>');
			push(@ary, '');
			$next_blank = 1;
			next;
		}


		#----------------------------------------------
		# [GFM] テーブル
		#----------------------------------------------
		if ($self->{gfm_ext} && $blank
		 && $x =~ /|/
		 && $lines->[0] =~ /^[\s\|\-:]+$/
		 && $lines->[0] =~ /\s*(?:\-+)?\s*\|\s*\-+\s*/
		) {
			$self->p_block_end(\@ary, \@p_block, $pmode);

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
				$next_blank = 1;
				next;
			}
		}


		#----------------------------------------------
		# 続きを読む記法
		#----------------------------------------------
		if ($blank && $seemore && $self->{satsuki_seemore} && ($x eq '====' || $x eq '=====')) {
			$self->p_block_end(\@ary, \@p_block, $pmode);
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
			$self->p_block_end(\@ary, \@p_block, $pmode);
			push(@ary, "<hr />\x01");
			next;
		}

		#----------------------------------------------
		# リンク定義。[M] 参照名が空文字の場合は無効
		#----------------------------------------------
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

	}
	# 文末空行の除去
	while(@ary && $ary[$#ary] eq '') { pop(@ary); }
	return \@ary;
}

#//////////////////////////////////////////////////////////////////////////////
# ●[02] インライン記法の処理
#//////////////////////////////////////////////////////////////////////////////
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
		$s =~ s/([\*\~\`_])/"\x03E". ord($1) ."\x03"/eg;
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
		$_ =~ s/\\([\\'\*_\{\}\[\]\(\)>#\+\-\.\~!])/"\x03E" . ord($1) . "\x03"/eg;

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

		# inline code
		$_ =~ s|(`+)(.+?)\1|
			my $s = $2;
			$self->escape_in_code($s);
			"<code>$s</code>";
		|eg;
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
# ●ローマ数字の解析
#------------------------------------------------------------------------------
my %ROMAN_U = (
	'I'  =>   1, 'II'  =>   2, 'III'  =>   3, 'IV' =>   4, 'V' =>   5,
	'VI' =>   6, 'VII' =>   7, 'VIII' =>   8, 'IX' =>   9,
	'X'  =>  10, 'XX'  =>  20, 'XXX'  =>  30, 'XL' =>  40, 'L' =>  50,
	'LX' =>  60, 'LXX' =>  70, 'LXXX' =>  80, 'XC' =>  90,
	'C'  => 100, 'CC'  => 200, 'CCC'  => 300, 'CD' => 400, 'D' => 500,
	'DC' => 600, 'DCC' => 700, 'DCCC' => 800, 'CM' => 900,
	'M'  =>1000, 'MM'  =>2000, 'MMM'  =>3000,'MMMM'=>4000
);
my %ROMAN_L;
foreach(keys(%ROMAN_U)) {
	my $l = $_;
	$l =~ tr/A-Z/a-z/;
	$ROMAN_L{$l} = $ROMAN_U{$_};
}

sub parse_roman_number {
	my $self = shift;
	my $r    = shift;
	if ($r eq '') { return; }

	if ($r =~ /^(M|MM|MMM|MMMM)?(C|CC|CCC|CD|D|DC|DCC|DCCC|CM)?(X|XX|XXX|XL|L|LX|LXX|LXXX|XC)?(I|II|III|IV|V|VI|VII|VIII|IX)?$/) {
		return ('upper-roman', $ROMAN_U{$1} + $ROMAN_U{$2} + $ROMAN_U{$3} + $ROMAN_U{$4});
	}
	if ($r =~ /^(m|mm|mmm|mmmm)?(c|cc|ccc|cd|d|dc|dcc|dccc|cm)?(x|xx|xxx|xl|l|lx|lxx|lxxx|xc)?(i|ii|iii|iv|v|vi|vii|viii|ix)?$/) {
		return ('lower-roman', $ROMAN_L{$1} + $ROMAN_L{$2} + $ROMAN_L{$3} + $ROMAN_L{$4});
	}
	return;
}

#------------------------------------------------------------------------------
# ●タグのエスケープ
#------------------------------------------------------------------------------
sub tag_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●記法エラー
#------------------------------------------------------------------------------
sub parse_error {
	my $self = shift;
	my $err  = '[parse error] ' . shift;
	return $self->{ROBJ}->notice($err, @_);
}




1;
