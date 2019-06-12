use strict;
#------------------------------------------------------------------------------
# reStructuredText
#	                                              (C)2019 nabe@abk
#------------------------------------------------------------------------------
#
package Satsuki::TextParser::reStructuredText;
our $VERSION = '0.10';
#------------------------------------------------------------------------------
use Satsuki::AutoLoader;
use Encode ();
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	my $ROBJ = $self->{ROBJ} = shift;

	$self->{section_hnum}   = 3;	# H3から使用する
	$self->{tab_width}      = 8;	# タブの幅
	$self->{system_coding}  = $ROBJ ? $ROBJ->{System_coding} : 'utf8';

	$self->{ambiguous_full} = 0;	# Ambiguousな文字コードをfullwidthとして扱う
	$self->{lf_patch}       = 1;	# 日本語のpタグ中の改行を消す

	$self->{file_secure}= 'files/';	# ファイル参照をセキュアにする
	$self->{image_path} = '';	# ↑をこのパスに置き換える

	$self->{footnote_symbols} = [ qw(
		* &dagger; &Dagger; &sect; &para; # &spades; &hearts; &diams; &clubs;
	)];

	$self->{thisurl}        = '';	# 処理する記事のURL
	$self->{thispkey}       = '';	# 処理する記事のpkey = unique id = [0-9]+

	# 引用符マークの組
	# https://en.wikipedia.org/wiki/Quotation_mark#Summary_table
	# https://github.com/sphinx-doc/sphinx/blob/master/sphinx/util/smartypants.py
	$self->{quotes}     = "'' &quot;&quot; &lt;&gt; () [] {} «» »« »» ‘’ ‘‚ ’’ ‚‘ ‚’ “” “„ ”“ ”” „“ „” ‹› ›‹ ›› 「」 『』 ";
	$self->{invalid_po} = '#%&*@';


	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
# 行末記号
#	\x02		これ以上、処理しない
#	\x02\x02	セクションの終わり
# 文中記号
#	\x01		pブロック処理やブロック処理で使用 
#	\x01		インラインマークアップの区切り
#	\x02		link/toc等の後処理に使用
#	\x03		文字(\)エスケープに使用
#	\x08		trimマーク
#
# マルチバイト処理で使用 / ブロック処理のみで使用
#	\x04-\x07
#
#------------------------------------------------------------------------------
# ●記事本文の整形
#------------------------------------------------------------------------------
sub text_parser {
	my $self = shift;
	my $text = shift;

	# 特殊文字削除, 変更時は reStructuredText_2.pm も修正すること
	$text =~ s/[\x00-\x08]//g;

	# 行に分解
	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# 内部変数初期化
	$self->{footnotes_auto} = [];
	$self->{links}          = {};	# link target hash
	$self->{anonymous_links}= [];	# Anonymouse hyperlinks
	$self->{substitutions}  = {};	# Substitution
	$self->{ids}            = {};	# all id hash

	# 記事固有変数
	$self->{unique_id} = 'k' . $self->{thispkey};
	{
		my $attr = $self->{image_attr};
		$attr =~ s/%k/$self->{unique_id}/g;
		if ($attr ne '' && substr($attr,0,1) ne ' ') {
			$attr = ' ' . $attr;
		}
		$self->{current_image_attr} = $attr;
	}

	# セクション情報の初期化
	$self->{sections} = [];
	$self->{local_sections} = [];
	$self->{current_section}= { children => $self->{sections} };
	$self->{sectnums} = [];

	#-------------------------------------------
	# ○処理スタート
	#-------------------------------------------
	# [00] 前処理
	$lines = $self->preprocess($lines);

	# [01] ブロックのパース
	$lines = $self->parse_block($lines);

	# [02] インライン記法の処理
	$lines = $self->parse_inline($lines);

	# [03] 最終処理
	$lines = $self->parse_finalize($lines);

	#-------------------------------------------
	# ○後処理
	#-------------------------------------------
	my $all = join("\n", @$lines);
	my $short = '';
	$self->post_process(\$all);

	# 特殊文字の除去
	$all   =~ s/[\x00-\x08]//g;
	$short =~ s/[\x00-\x08]//g;
	return wantarray ? ($all, $short) : $all;
}

###############################################################################
# ■パーサー本体
###############################################################################
###############################################################################
# ●[00] 初期処理
###############################################################################
sub preprocess {
	my $self  = shift;
	my $lines = shift;

	my $tw = $self->{tab_width};
	foreach(@$lines) {
		$_ =~ s/\s+$//g;		# 行末スペース除去

		# TAB to SPACE 8つ
		$_ =~ s/(.*?)\t/$1 . (' ' x ($tw - (length($1) % $tw)))/eg;
	}
	return $lines;
}

###############################################################################
# ●[01] ブロックのパース
###############################################################################
sub parse_block {
	my $self  = shift;
	my $lines = shift;

	$self->{footnote_symc}  = 0;	# footnote symbols counter
	$self->{enum_cache}     = {};
	$self->{transion_cache} = {'' => 0};

	my @out;
	my $r = $self->do_parse_block(\@out, $lines);

	#----------------------------------------------------------------------
	# footnote number / generate id
	#----------------------------------------------------------------------
	{
		my $links = $self->{links};
		my $auto  = $self->{footnotes_auto};
		my $num   = 1;
		foreach(@$auto) {
			while($links->{$num}) {
				$num++;
			}
			$links->{$num} = $_;
			$_->{label} = $num;
		}
		foreach(keys(%$links)) {
			my $h = $links->{$_};
			if (!ref($h) || $h->{id}) { next; }

			my $label = $h->{_label} || $h->{label};
			$h->{id} = $self->generate_link_id( ($h->{type} eq 'footnote' ? 'fn-' : '') . $label );
		}
	}
	#----------------------------------------------------------------------

	return $r;
}

sub do_parse_block {
	my $self  = shift;
	my $out   = shift;
	my $lines = shift;
	my $nest  = shift;

	while(@$lines && $lines->[0] eq '') {
		shift(@$lines);			# 先頭空行除去
	}
	if ($nest && !@$lines) { return; }	# 空データ

	#
	# セクション情報
	#
	my $seclv       = 0;
	my $seclv_cache = {};
	my $sectioning  = !$nest;

	# 入れ子要素、かつ、空行を含まない時は行処理をしない
	my $ptag = ($nest && !(grep {$_ eq '' } @$lines)) ? '' : 'p';

	# リストアイテムモード
	my $item_mode = ($ptag && $nest eq 'list-item') ? $#$out+1 : undef;
	my @blocks;
	if ($item_mode ne '') {
		$ptag = "\x01p";
	}

	my @p_block;
	my @dl_block;
	unshift(@$lines, '');
	push(@$lines, '');
	while(@$lines) {
		my $x = shift(@$lines);
		my $y = $lines->[0];

		#--------------------------------------------------------------
		# 空行
		#--------------------------------------------------------------
		if ($x eq '') {
			if (@p_block) {
				$self->block_end($out, \@p_block, $ptag);
				push(@blocks, 'p');
			}
			next;
		}

		#--------------------------------------------------------------
		# タイトル or トランジション : title or transition
		#--------------------------------------------------------------
		if (my $m = $self->test_transition($x)) {
			my $title = '';
			my $mark;		# overline/underline

			if ($#p_block == 0) {
				$title = shift(@p_block);
				$mark  = "/$m";
			} elsif ($y ne '') {
				$title = shift(@$lines);
				$mark  = "$m/";
				my $z = shift(@$lines);
				if ($self->test_transition($z)) {
					if ($x eq $z) {
						$mark = "$m/$m";
					} else {
						$self->parse_error('Title overline & underline mismatch: %s', $title);
						next;
					}
				} else {	# overline のみ
					$self->parse_error('Title overline without underline: %s', $title);
					next;
				}
			}
			#----------------------------------------------
			# トランジション : transition
			#----------------------------------------------
			$title =~ s/^\s+//;
			if ($title eq '') {
				push(@blocks, 'transition');
				if ($nest) {
					$self->parse_error('Transition only allowed at the top level: %s', $x);
				} else {
					push(@$out, '', "<hr />\x02", '');
				}
				next;
			}

			#----------------------------------------------
			# タイトル : title
			#----------------------------------------------
			push(@blocks, 'title');
			if ($nest) {
				$self->parse_error('Title only allowed at the top level: %s', $x);
				next;
			}
			my $level = $seclv_cache->{$mark} ||= ++$seclv;

			$self->backslash_escape($title);
			$self->tag_escape($title);
			my $h = $self->{section_hnum} + $level -1;
			if (6 < $h) { $h=6; }

			if ($level == 1 && $sectioning && @$out) {
				push(@$out, "</section>\x02\x02");
				push(@$out, "<section>\x02");
			}

			# セクション情報の生成
			my $base = '';
			my $secs = $self->{sections};
			my $err;
			foreach(2..$level) {
				my $s = @$secs ? $secs->[$#$secs] : undef;
				if (!$s) {
					$err = 1;
					last;
				}
				$base = $s->{_num};
				$secs = $s->{children} ||= [];	# 修正時は current_section 初期化も修正する
			}
			if ($err) {
				$self->parse_error('Title level inconsistent: %s', $title);
				next;
			}
			my $count = $#$secs<0 ? 1 : $secs->[$#$secs]->{count} + 1;
			my $num   = $base . ($level>1 ? '.' : '') . $count;
			my $base  = $self->generate_id_from_string($title, 'h' . $num);
			my $id    = $self->generate_implicit_link_id( $base );

			# generate section number
			my $number='';
			foreach(@{ $self->{sectnums} }) {
				my $depth = $_->{depth};
				if (1<$level && $depth ne '' && $depth<$level) { next; }

				my $start = $_->{start};
				if ($start ne '' && $start != 1) {
					$num =~ s/^(\d+)/
						$1 +$start -1
					/eg;
				}
				$number .= "$_->{prefix}$num$_->{suffix} ";
			}
			my $_title = $title;
			my $num_text = '';
			if ($number ne '') {
				chop($number);
				$num_text = " <span class=\"section-number\">``$number``</span> ";
			}

			# save section information
			my $sec = {
				id	=> $id,
				_num	=> $num,
				number  => $number,
				title	=> $title,
				count	=> $count
			};
			push(@$secs, $sec);
			$self->{current_section} = $sec;

			push(@$out, '', "<h$h id=\"$id\"><a href=\"$self->{thisurl}#$id\">$num_text$title</a></h$h>", '');
			next;
		}

		#--------------------------------------------------------------
		# Doctestブロック : doctest_block
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^>>> /) {
			my @block = ($x);
			while(@$lines && $lines->[0] ne '') {
				push(@block, shift(@$lines));
			}

			push(@$out, "<pre class=\"syntax-highlight\">\x02");
			foreach(@block) {
				$self->tag_escape($_);
				$_ =~ s/\\/&#92;/g;	# escape backslash
				push(@$out, "$_\x02");
			}
			push(@$out, "</pre>\x02", '');
			next;
		}

		#--------------------------------------------------------------
		# ラインブロック : line_block
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^\| /) {
			push(@blocks, 'line-block');
			unshift(@$lines, $x);

			$self->parse_line_block($out, $lines);
			next;
		}

		#--------------------------------------------------------------
		# グリッドテーブル : grid_table
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^\+(?:\-+\+){2,}/ && $y =~ /^[\+\|]/) {
			push(@blocks, 'table');
			unshift(@$lines, $x);

			$self->parse_grid_table($out, $lines);
			next;
		}

		#--------------------------------------------------------------
		# シンプルテーブル
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^=+(?: +=+)+$/) {
			push(@blocks, 'table');
			unshift(@$lines, $x);

			$self->parse_simple_table($out, $lines);
			next;
		}

		#--------------------------------------------------------------
		# 脚注 : footnote_references
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^\.\. +\[(\d+|#?[^\]]*|\*)\](?: +(.*))?$/ && $self->check_footnote_label($1)) {
			push(@blocks, 'footnote');

			my $label = $1;
			my $body  = $2;
			my $links = $self->{links};
			my $key   = $label;
			$key =~ tr/A-Z/a-z/;

			while(@$lines && $lines->[0] =~ /^ /) {
				$body = $self->join_line($body, shift(@$lines));
			}
			$self->backslash_escape($body);
			$self->tag_escape($body);

			my $h = {
				type  => 'footnote',
				label => $label,
				body  => $body
			};
			if ($label eq '*') {
				my $symbol = $self->get_footnote_symbol( $self->{footnote_symc} );
				$self->{footnote_symc}++;
				$h->{_label} = "s$self->{footnote_symc}";
				$h->{label}  = $symbol;
				$links->{$symbol} = $h;

			} elsif ($label =~ /^#/) {		# auto-number
				push(@{$self->{footnotes_auto}}, $h);
				if ($label ne '#') {
					$links->{$key} = $h;
				}

			} elsif ($label =~ /^(\d+)$/) {		# footnote [1], [2]...
				if ($links->{$key}) {
					my $msg = $self->parse_error('Duplicate footnote target name: %s', $label);
					$links->{$key}->{error} = $msg;
					$links->{$key}->{duplicate} = 1;
				} else {
					$links->{$key} = $h;
				}

			} else {				# hyperlink
				$h->{type} = 'citation';
				if ($links->{$key}) {
					my $msg = $self->parse_error('Duplicate link target name: %s', $label);
					$links->{$key}->{error} = $msg;
					$links->{$key}->{duplicate} = 1;
				} else {
					$links->{$key} = $h;
				}
			}
			push(@$out, $h);
			next;
		}

		#--------------------------------------------------------------
		# リンクターゲット : target
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^\.\. +_|^__(?: |$)/) {
			unshift(@$lines, $x);
			my $links = $self->{links};

			my $h = { type => 'link' };
			my $label;
			while(@$lines && $lines->[0] =~ /^\.\. +_|^__(?: |$)/) {
				my $z = shift(@$lines);
				if ($z !~ /^\.\. +_(`(?:\\.|[^`\\])+` ?|(?:\\.|[^:\\])*):(?: +(.*)|$)|^_(_)(?: +(.*)|$)/) {
					$self->parse_error('Malformed hyperlink target: %s', $z);
					next;
				}
				$label = $1 || $3;
				my $url = $3 ? $4 : $2;

				# labelの加工
				$label =~ s/ $//g;		# 最後のスペース1つだけは取り除く
				$self->backslash_process($label);
				$self->normalize_label($label);
				my $key = $self->generate_key_from_label_with_tag_escape($label);

				if ($label eq '_') {
					push(@{ $self->{anonymous_links} }, $h);

				} elsif ($label =~ /^ / || $label =~ / $/ || $label eq '') {
					my $msg = $self->parse_error('Malformed hyperlink target: %s', $label);
					if ($label ne '') {
						$links->{$key}->{error} = $msg;
					}

				} elsif ($links->{$key}) {
					my $msg = $self->parse_error('Duplicate link target name: %s', $label);
					$links->{$key}->{error} = $msg;
					$links->{$key}->{duplicate} = 1;
				} else {
					$links->{$key} = $h;
				}

				# URLがある
				while(@$lines && $lines->[0] =~ /^ +(.*)/) {
					$url .= " $1";
					shift(@$lines);
				}
				if ($url =~ /^ *$/) { next; }

				$self->backslash_escape($url);
				$self->normalize_link_url($url);

				$h->{url} = $url;
				# $self->debug("link /$label/ --> $url");
				last;
			}
			# ターゲットがないリンク（この場所へのリンク）
			if (!$h->{url}) {
				my $id = $self->generate_id_from_string( $label );
				$h->{id} = $id;
				push(@$out, $h);
				push(@blocks, 'link');
				# $self->debug("link here /$label/ #$id");
			}
			next;
		}

		#--------------------------------------------------------------
		# 置換定義       : definition substitution
		# ディレクティブ : directive
		#--------------------------------------------------------------
		my $substitution;
		if (!@p_block && $x =~ /^\.\. +(\|.*)/) {
			my $z = $1;
			if ($z !~ /^\|((?:\\.|[^\\\|])+|)\|(?: +(.*)|$)/ || substr($1,0,1) eq ' ' ||  substr($1,-1) eq ' ') {
				$self->parse_error('Malformed substitution definition: %s', $x);
				next;
			}
			$substitution = $1;
			$substitution =~ tr/A-Z/a-z/;
			if ($2 eq '' && $y =~ /^ /) {	# |example|
				$x = '..' . $y;		# 	image::
				shift(@$lines);		#		filename.jpg
			} else {
				$x = '.. ' . $2;
			}
		}
		if (!@p_block && $x =~ /^\.\. +([A-Za-z0-9]+(?:[\-_\.][A-Za-z0-9]+)*) ?::(?: +(.*)|$)/) {
			$self->parse_directive($out, $lines, $substitution, "$1", "$2");
			next;
		}
		if ($substitution ne '') {
			$self->extract_block( $lines, 0 );
			$self->parse_error('Substitution definition empty or invalid: %s', $substitution);
			next;
		}

		#--------------------------------------------------------------
		# コメント : comment
		#--------------------------------------------------------------
		if (!@p_block && $x =~ /^\.\.(?: |$)/) {
			$self->extract_block( $lines, 0 );
			next;
		}

		#--------------------------------------------------------------
		# 特殊ブロック判定
		#--------------------------------------------------------------
		my ($btype, $bopt) = !@p_block && $self->test_block($nest, $x, $lines, 0, 'first');
		if ($btype) {
			push(@blocks, $btype eq 'enum' ? 'list' : $btype);
		}

		#--------------------------------------------------------------
		# 箇条書きリスト : bullet_list
		#--------------------------------------------------------------
		if ($btype eq 'list') {
			my $mark = $bopt->{mark};
			unshift(@$lines, $x);

			push(@$out, "<ul>\x02");
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines, 1);
				if ($type ne 'list' || $opt->{mark} ne $mark) { last; }
				shift(@$lines);

				my $item = $self->extract_block($lines, $opt->{len}, $opt->{first});

				$self->parse_nest_block_with_tag($out, $item, '<li>', '</li>', 'list-item');
			}

			push(@$out, "</ul>\x02", '');
			next;
		}

		#--------------------------------------------------------------
		# 列挙リスト : enumerated_list
		#--------------------------------------------------------------
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
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines, 1, $mode);
				if ($type ne 'enum' || $opt->{subtype} ne $subtype
				 || $opt->{numtype} ne 'auto' && ($opt->{numtype} ne $numtype || $opt->{num} != $num)
				) {
					last;
				}
				shift(@$lines);

				my $item = $self->extract_block($lines, $opt->{len}, $opt->{first});
				$self->parse_nest_block_with_tag($out, $item, '<li>', '</li>', 'list-item');

				$num++;
			}

			push(@$out, "</ol>\x02", '');
			next;
		}

		#--------------------------------------------------------------
		# フィールドリスト : field_list / table
		#--------------------------------------------------------------
		if ($btype eq 'field') {
			unshift(@$lines, $x);

			my @fields;
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines, 1);
				if ($type ne 'field') { last; }
				shift(@$lines);

				my $name = $opt->{name};
				my $body = $self->extract_block($lines, $opt->{len}, '');
				$body->[0] = $opt->{value};	# 最初の行は最小インデントに合わせる

				# dt classifier
				$self->backslash_escape($name);
				$self->tag_escape($name);
				push(@fields, "<tr><th>$name:</th>");

				$self->parse_nest_block_with_tag(\@fields, $body, '<td>', '</td>');
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

		#--------------------------------------------------------------
		# オプションリスト : option_list / table
		#--------------------------------------------------------------
		if ($btype eq 'option') {
			unshift(@$lines, $x);

			push(@$out, "<table class=\"option-list\">\x02");
			push(@$out, "<tbody>\x02");

			my $mode = 'option';
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines, 1, $mode);
				if ($type ne 'option') {
					if ($mode eq 'option') {	# ブランク行なしでオプションリストが終わっている
						$self->parse_error('Option list ends without a blank line: %s', $lines->[0]);
					}
					last;
				}
				shift(@$lines);

				my $body = $self->extract_block($lines, $opt->{len}, '');
				$body->[0] = $opt->{value};	# 最初の行は最小インデントに合わせる
				$mode = $body->[$#$body] eq '' ? '' : 'option';

				# dt classifier
				push(@$out, "<tr><th>$opt->{option}</th>");	# {option} is tag escaped

				$self->parse_nest_block_with_tag($out, $body, '<td>', '</td>');
				push(@$out, "</tr>\x02");
			}

			push(@$out, "</tbody>\x02");
			push(@$out, "</table>\x02");
			next;
		}

		#--------------------------------------------------------------
		# 定義リスト : definition_list
		#--------------------------------------------------------------
		if ($btype eq 'definition') {
			unshift(@$lines, $x);
			push(@$out, "<dl>\x02");
			while(@$lines) {
				my ($type, $opt) = $self->test_block($nest, $lines->[0], $lines, 1);
				if ($type ne 'definition') { last; }

				my $dt = shift(@$lines);
				my $dd = $self->extract_block($lines, $opt->{len}, shift(@$lines));

				# dt classifier
				$self->backslash_escape($dt);
				$self->tag_escape($dt);
				my @c = split(/ +: +/, $dt);
				$dt = shift(@c);
				foreach(@c) {
					$dt .= ' <span class="classifier-delimiter">:</span> ' . '<span class="classifier">' . $_ . '</span>';
				}

				push(@$out, "<dt>$dt</dt>");
				$self->parse_nest_block_with_tag($out, $dd, '<dd>', '</dd>');
			}
			push(@$out, "</dl>\x02", '');
			next;
		}

		#--------------------------------------------------------------
		# リテラルブロック : literal_block    ※先に処理してはいけない
		#--------------------------------------------------------------
		if ($x =~ /^((?:\\.|[^\\])*)::$/ && $y eq '') {
			$x = $1;

			if ($x ne '') {
				# "Paragraph ::" to "Paragraph"
				# "Paragraph::"  to "Paragraph:"
				if (substr($x,-1) ne ' ') { $x .= ':'; }
				$self->backslash_escape($x);
				$x =~ s/ +$//;
				$self->backslash_escape_cancel($x);
				unshift(@$lines, '::');
				unshift(@$lines, '');
			} else {
				$self->block_end($out, \@p_block, $ptag);
				push(@blocks, 'literal');

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
						$_ =~ s/\\/&#92;/g;	# escape backslash
						push(@$out, "$_\x02");
					}
					push(@$out, "</pre>\x02", '');
					next;
				}
			}
		}

		#--------------------------------------------------------------
		# 引用ブロック : block_quote	※先に処理してはいけない
		#--------------------------------------------------------------
		if ($x =~ /^( +)/) {
			$self->block_end($out, \@p_block, $ptag);
			push(@blocks, 'quote');

			# block抽出
			my $block = $self->extract_block( $lines, 0, $x );

			# Doctest check
			if ($block->[0] =~ /^>>>/ && !(grep { $_ eq '' } @$block)) {
				unshift(@$lines, @$block);
				next;	# goto Doctest
			}
			if ($out->[$#$out] ne '') { push(@$out, ''); }
			push(@$out, "<blockquote>\x02");
			$self->do_parse_block($out, $block, 'nest');
			push(@$out, "</blockquote>\x02", '');
			next;
		}

		#--------------------------------------------------------------
		# 通常行
		#--------------------------------------------------------------
		if (!$btype) {
			push(@p_block, $x);	# 段落ブロック
			next;
		}

		#--------------------------------------------------------------
		# エラー
		#--------------------------------------------------------------
		$self->{ROBJ}->error("Internal Error: Unknown block type '$btype'");
	}

	#----------------------------------------------------------------------
	# loop end
	#----------------------------------------------------------------------
	# 文末空行の除去
	while(@$out && $out->[$#$out] eq '') { pop(@$out); }

	# セクショニングを行う
	if ($sectioning) {
		unshift(@$out, "<section>\x02");
		push(@$out,'',"</section>\x02\x02");
	}

	# リストアイテム要素の特殊処理
	if ($item_mode ne '') {
		while($blocks[$#blocks] eq 'link') { pop(@blocks); }

		if ($#blocks==0 && ($blocks[0] eq 'p' || $blocks[0] eq 'list')
		 || $#blocks==1 && ($blocks[0] eq 'p' && $blocks[1] eq 'list')
		) {
			# <p>を除去
			for(my $i=$item_mode; $i <= $#$out; $i++) {
				$out->[$i] =~ s|</?\x01p>||g;
			}
		} else {		# <p>を有効化
			for(my $i=$item_mode; $i <= $#$out; $i++) {
				$out->[$i] =~ s|(</?)\x01p>|${1}p>|g;
			}
		}
	}

	#----------------------------------------------------------------------
	return wantarray ? ($out, \@blocks) : $out;
}

#//////////////////////////////////////////////////////////////////////////////
#------------------------------------------------------------------------------
# ラインブロックの処理
#------------------------------------------------------------------------------
sub parse_line_block {
	my $self  = shift;
	my $out   = shift;
	my $lines = shift;

	my @block;
	while(@$lines) {
		my $x = $lines->[0];
		if ($x =~ /^\| / || $x eq '|') {
			push(@block, substr($x, 2));
			shift(@$lines);
			next;
		}
		if ($x =~ /^ +(.*)/) {
			push(@block, $self->join_line(pop(@block), $1));
			shift(@$lines);
			next;
		}
		last;
	}
	$self->parse_line_block_step2($out, \@block);
}

sub parse_line_block_step2 {
	my $self  = shift;
	my $out   = shift;
	my $block = shift;
	if (!@$block) { return; }

	my $indent = 0x7ffffffff;
	foreach(@$block) {		# 最小インデントを調べる
		if ($_ !~ /^( +)/) { $indent=0; last; }

		my $x = length($1);
		if ($x<$indent) { $indent=$x; }
	}
	# remove indent
	$block = [ map { substr($_, $indent) } @$block ];

	# output
	push(@$out, "<div class=\"line-block\">\x02");
	while(@$block) {
		my $x = shift(@$block);
		if ($x eq '') {
			push(@$out, "<div><br></div>");
			next;
		}
		if (substr($x,0,1) ne ' ') {
			$self->backslash_escape($x);
			$self->tag_escape($x);
			push(@$out, "<div>$x</div>");
			next;
		}
		# indent found
		my @ary = ($x);
		while(@$block && substr($block->[0],0,1) eq ' ') {
			push(@ary, shift(@$block));
		}
		$self->parse_line_block_step2($out, \@ary);		# nest line-block
	}
	push(@$out, "</div>\x02");
}

#------------------------------------------------------------------------------
# グリッドテーブルの処理
#------------------------------------------------------------------------------
sub parse_grid_table {
	my $self  = shift;
	my $out   = shift;
	my $lines = shift;

	my @table;
	my @table_hack;
	my @separator;
	my $len = length($lines->[0]);	# first border
	my $malformed;
	my $err=0;
	while(@$lines && $lines->[0] =~ /^[\+\|]/) {
		my $x = shift(@$lines);
		if ($x =~ /^\+[\+=]*\+$/) {	# header split border
			push(@separator, $#table+1);
			$x =~ tr/=/-/;
		}
		push(@table, $x);
		my $bak = $x;
		$self->mb_hack($x);
		push(@table_hack, $x);

		# check length
		if ($len != length($x)) {
			if ($len < length($x)) {
				$self->parse_error('Table width over: %s', $bak);
			} else {
				$self->parse_error('Table width under: %s', $bak);
			}
			$err++;
		}
		if ($x !~ /[\+|]$/) {
			$malformed = 1;
		}
	}

	#------------------------------------------------------
	# エラー処理
	#------------------------------------------------------
	if ($#separator > 0) {
		$err++;
		$self->parse_error('Multiple table head/body separators, only one allowed');
	} elsif ($separator[0] == $#table) {
		$err++;
		$self->parse_error('Table head/body row separator not allowed at the end');
	}
	if ($malformed) {
		$err++;
		$self->parse_error('Malformed table');
	}
	if ($err) {
		return;
	}

	#------------------------------------------------------
	# parse table structure
	#------------------------------------------------------
	my %colp;
	my %rowp;
	my %box;

	$self->grid_table_split_row(\@table_hack, \%box, \%colp, \%rowp, 0, 0, $len, $#table+1, 1);

	#------------------------------------------------------
	{
		my $n=1;
		foreach(sort {$a <=> $b} keys(%colp)) {
			$colp{$_} = $n++;
		}
		$n=1;
		foreach(sort {$a <=> $b} keys(%rowp)) {
			$rowp{$_} = $n++;
		}
	}

	#------------------------------------------------------
	# output table
	#------------------------------------------------------
	my $thead = $separator[0];
	push(@$out, "<table>\x02");
	push(@$out, $thead ? "<thead>\x02" :  "<tbody>\x02");

	my $td = $thead ? 'th' : 'td';
	foreach my $y0 (0..$#table) {
		my $r = $box{$y0};
		if (!$r) { next;}
		my @cols = sort {$a <=> $b} keys(%$r);

		if ($thead && $y0 == $thead) {
			push(@$out, "</thead>\x02");
			push(@$out, "<tbody>\x02");
			$td = 'td';
		}

		push(@$out, "<tr>\x02");
		foreach my $x0 (@cols) {
			my ($xl, $yl) = @{ $r->{$x0} };
			my @column;
			my $indent = 0x7fffffff;
			foreach(1..$yl-2) {
				my $s = $self->mb_substr($table[$y0+$_], $x0+1, $xl-2);
				$s =~ s/ +$//;
				if ($s =~ /^( +)/) {
					my $l = length($1);
					$indent = ($l<$indent) ? $l : $indent;
				}
				push(@column, $s);
			}
			foreach(@column) {
				$_ = substr($_, $indent);
			}

			my $colspan = $colp{$x0+$xl-1} - $colp{$x0};
			my $rowspan = $rowp{$y0+$yl-1} - $rowp{$y0};
			$colspan = $colspan<2 ? '' : " colspan=\"$colspan\"";
			$rowspan = $rowspan<2 ? '' : " rowspan=\"$rowspan\"";

			$self->parse_nest_block_with_tag($out, \@column, "<$td$colspan$rowspan>", "</$td>");
		}
		push(@$out, "</tr>\x02");
	}
	push(@$out, "</tbody>\x02");
	push(@$out, "</table>\x02");
}

#------------------------------------------------------
# parse grid table structure
#------------------------------------------------------
sub grid_table_split_row {
	my $self = shift;
	my $rows = shift;
	my $box  = shift;
	my $colp = shift;
	my $rowp = shift;

	my $x0   = shift;	# view start  (x0,y0)
	my $y0   = shift;
	my $xl   = shift;	# view length (xl,yl)
	my $yl   = shift;
	my $first= shift;	# first call flag
	if ($yl<2) { return; }

	my $p=$y0;
	$rowp->{$p}=1;

	foreach(1..($yl-1)) {
		my $yp = $y0 + $_;
		my $s  = substr($rows->[$yp], $x0, $xl);
		if ($s !~ /^\+[\+\-]*\+$/) { next; }

		if (!$first && $p == $y0 && $_ == ($yl-1)) {	# no split --> one column box
			$box->{$y0}->{$x0} = [$xl, $yl];
			# $self->debug("box ($x0,$y0) length ($xl,$yl)");
			last;
		}

		# found row spliter
		$self->grid_table_split_col($rows, $box, $colp, $rowp, $x0, $p, $xl, $yp-$p+1);

		$p = $yp;
		$rowp->{$p} = 1;
	}
}

sub grid_table_split_col {
	my $self = shift;
	my $rows = shift;
	my $box  = shift;
	my $colp = shift;
	my $rowp = shift;

	my $x0   = shift;	# view start  (x0,y0)
	my $y0   = shift;
	my $xl   = shift;	# view length (xl,yl)
	my $yl   = shift;
	if ($xl<2) { return; }

	my $p=$x0;
	$colp->{$p}=1;

	foreach(1..($xl-1)) {
		my $xp = $x0 + $_;
		if (substr($rows->[$y0], $xp, 1) ne '+') { next; }

		my $f=0;
		foreach my $i (1..($yl-1)) {
			my $c = substr($rows->[$y0+$i], $xp, 1);
			if ($c ne '+' && $c ne '|') { $f=1; last; }
		}
		$f && next;

		if ($p == $x0 && $_ == ($xl-1)) {	# no split --> one column box
			$box->{$y0}->{$x0} = [$xl, $yl];
			# $self->debug("box ($x0,$y0) length ($xl,$yl)");
			last;
		}

		# found col spliter
		$self->grid_table_split_row($rows, $box, $colp, $rowp, $p, $y0, $xp-$p+1, $yl);

		$p = $xp;
		$colp->{$p}=1;
	}
}

#------------------------------------------------------------------------------
# シンプルテーブル
#------------------------------------------------------------------------------
sub parse_simple_table {
	my $self  = shift;
	my $out   = shift;
	my $lines = shift;

	my $x = shift(@$lines);
	if ($x !~ /^(=+)(.*)$/) { return; }

	my $len  = length($x);
	my @cols = (length($1));
	my @margins;
	{
		my $z = $2;
		while ($z =~ /^( +)(=+)(.*)/ ){
			push(@margins, length($1));
			push(@cols,    length($2));
			$z = $3;
		}
	}
	push(@margins, 0);	# 最後のカラム用

	my @table;
	my $thead;
	{
		my @ary;
		my $cnt=0;
		while(@$lines) {
			my $t = shift(@$lines);
			push(@ary, $t);
			if ($t !~ /^=[ =]*$/) {
				next;
			}
			# border found
			push(@table, @ary);
			undef @ary;
			if ($cnt || $lines->[0] eq '') {
				$cnt++;
				last;
			}
			if (!$cnt) {
				$thead=1;
				push(@table, { thead=>1 });
			}
			$cnt++;
		}
		if (@ary) {
			unshift(@$lines, @ary);
		}
	}

	# blank skip
	@table = grep { $_ ne '' } @table;

	#------------------------------------------------------
	# scan table
	#------------------------------------------------------
	my @buf;
	my @rows;
	my $err = 0;
	my $r_cols    = \@cols;
	my $r_margins = \@margins;
	my $r_spans   = [];
	while(@table) {
		my $t = shift(@table);
		my $bak = $t;
		if (ref($t)) {
			push(@rows, 'thead');
			next;
		}
		$self->mb_hack($t, \@buf);

		my $border;	# --------等によるカラム連結
		if ($table[0] =~ /^-[ -]+$/ || $table[0] =~ /^=[ =]+$/) {
			my $b = shift(@table);
			if ($len != length($b)) {
				if ($len < length($b)) {
					$self->parse_error('Table width over: %s', $b);
				} else {
					$self->parse_error('Table width under: %s', $b);
				}
				$err++;
				next;
			}
			my $pat = $b;
			$pat =~ tr/-/=/;
			my @cols2;
			my @margins2;
			my @spans2;
			my $add =0;
			my $span=1;
			foreach(0..$#cols) {
				my $c = $cols[$_];
				my $m = $margins[$_];
				my $ct = substr($pat,  0, $c);
				my $sp = substr($pat, $c, $m);

				if ($ct =~ /[^=]/ || $sp =~ / =|= /) {
					$self->parse_error('Column span alignment problem: %s', $b);
					$err++;
					last;
				}
				if ($sp =~ /^=+$/) {	# chain
					$add += $c + $m;
					$span++;
				} else {		# margin is space
					push(@cols2, $add + $c);
					push(@margins2, $m);
					push(@spans2,   $span);
					$add=0;
					$span=1;
				}
				$pat = substr($pat, $cols[$_] + $margins[$_]);
			}
			if (!$pat) {	# no error
				$r_cols    = \@cols2;
				$r_margins = \@margins2;
				$r_spans   = \@spans2;
			}

			# border行が連続している場合の処理
			if ($table[0] =~ /^-[ -]+$/ || $table[0] =~ /^=[ =]+$/) {
				unshift(@table, '');
			}
		}

		my @row;
		foreach(0..$#$r_cols) {
			my $sp = substr($t, $r_cols->[$_], $r_margins->[$_]);
			if ($sp =~ /[^ ]/) {
				$err++;
				undef @row;
				$self->parse_error('Text in column margin: %s', $bak);
				last;
			}
			my $text = substr($t, 0, $r_cols->[$_]);
			$text =~ s/^ +//;
			push(@row, {
				span => $r_spans->[$_],
				text => $text
			});
			$t = substr($t, $r_cols->[$_] + $r_margins->[$_]);
		}
		if ($t ne '' && @row) { $row[$#row]->{text} .= $t; }
		push(@rows, \@row);
	}

	if ($err) { return; }

	#------------------------------------------------------
	# output table
	#------------------------------------------------------
	push(@$out, "<table>\x02");
	push(@$out, $thead ? "<thead>\x02" :  "<tbody>\x02");

	my $td = $thead ? 'th' : 'td';
	foreach my $row (@rows) {
		if ($thead && !ref($row)) {
			push(@$out, "</thead>\x02");
			push(@$out, "<tbody>\x02");
			$td = 'td';
			next;
		}

		push(@$out, "<tr>\x02");
		foreach(@$row) {
			my $text = $_->{text};
			my $span = $_->{span};
			$self->mb_hack_recovery($text, \@buf);

			my $colspan = $span<2 ? '' : " colspan=\"$span\"";
			$self->parse_nest_block_with_tag($out, [ $text ], "<$td$colspan>", "</$td>");
		}
		push(@$out, "</tr>\x02");
	}
	push(@$out, "</tbody>\x02");
	push(@$out, "</table>\x02");
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
# トランジション or titleの判定
#------------------------------------------------------------------------------
sub test_transition {
	my $self  = shift;
	my $x     = shift;
	my $cache = $self->{transion_cache};
	if (exists($cache->{$x})) { return $cache->{$x}; }
	return ($cache->{$x} = ($x =~ /^([!"#\$%&'\(\)\*\+,\-\.\/:;<=>\?\@\[\\\]^_`\{\|\}\~])\1{3,}$/) ? $1 : undef);
}

#------------------------------------------------------------------------------
# 特殊ブロックの開始判定
#------------------------------------------------------------------------------
sub test_block {
	my $self = shift;
	my $nest = shift;
	my $x    = shift;
	my $lines= shift;
	my $l_num= shift;
	my $mode = shift;
	my $y = $lines->[$l_num];

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
	if ($x =~ /^:((?:\\.|[^:\\])+):(?: +|$)(.*)/ && substr($1,0,1) ne ' ' &&  substr($1,-1) ne ' ') {
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
		my $err;
		foreach(split(/, /, $o)) {
			if ($_ =~ /^(-[A-Za-z0-9])( ?)(.*)/ || $_ =~ /^((?:--|\/)\w[\w-]*)([= ]?)(.*)/) {
				my $op  = $1;
				my $sp  = $2;
				my $arg = $3;
				if ($arg eq '' || $arg =~ /^[a-zA-Z][a-zA-Z0-9_-]*$/ || $arg =~ /^<(\d+)>$/) {
					if ($1 ne '') { $arg = $buf[$1]; }
					$self->backslash_escape($op, $arg);
					$self->tag_escape($op, $arg);
					$option .= ($option ? ', ' : '') . "$op$sp<var>$arg</var>";
					next;
				}
			}
			$err=1;
			last;
		}
		if ($v eq '' && !$err) {
			foreach($l_num..$#$lines) {
				if ($lines->[$_] eq '') { next; }
				$err = ($lines->[$_] !~ /^ /);
				last;
			}
		}
		if (!$err) {
			return ('option', {
				option=> $option,
				value => $v
			});
		}
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

	my @block = defined $first ? ($first) : ();
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
# ネストブロックの処理
#------------------------------------------------------------------------------
sub parse_nest_block_with_tag {
	my $self  = shift;
	my $out   = shift;
	my $block = shift;
	my $tag0  = shift;
	my $tag1  = shift;
	my $mode  = shift || 'nest';

	my $n = $#$out+1;
	$self->do_parse_block($out, $block, $mode);
	my $m = $#$out;
	while(ref($out->[$n])         ) { $n++; }
	while(ref($out->[$m]) && $m>=0) { $m--; }
	if ($m<$n) {
		push(@$out, "$tag0$tag1");
		return;
	}
	$out->[$n]  = $tag0 . $out->[$n];
	$out->[$m] .= $tag1;
	return $out;
}

#------------------------------------------------------------------------------
# ブロックの後処理
#------------------------------------------------------------------------------
sub block_end {
	my $self = shift;
	my $out  = shift;
	my $blk  = shift;
	my $tag  = shift;
	if (!@$blk) { return; }

	# ブロック末空行の除去
	while(@$blk && $blk->[$#$blk] eq '') { pop(@$blk); }

	my $line = shift(@$blk);
	foreach(@$blk) {
		$line = $self->join_line($line, $_);
	}

	$self->backslash_escape($line);
	$self->tag_escape($line);
	push(@$out, ($tag ? "<$tag>" : '') . $line . ($tag ? "</$tag>" : ''));
	push(@$out, '');
	@$blk = ();
}

#------------------------------------------------------------------------------
# 行連結処理
#------------------------------------------------------------------------------
sub join_line {
	my $self = shift;
	my $x    = shift;
	my $y    = shift;
	my $z    = shift || "\n";
	if ($x eq '') { return $y; }
	if (! $self->{lf_patch}) { return "$x$z$y"; }

	# 日本語文章中に改行が含まれるとスペースになり汚いため改行を除去する。
	my $sp = 0x7f<ord(substr($x,-1)) &&  0x7f<ord($y) ? '' : $z;
	return "$x$sp$y";
}

###############################################################################
# ●[02] インライン記法の処理
###############################################################################
my %Markup;
sub parse_inline {
	my $self  = shift;
	my $lines = shift;

	#-----------------------------------------------------------------
	# substitution
	#-----------------------------------------------------------------
	{
		my $ss = $self->{substitutions};
		$self->{substitution_mode} = 1;
		foreach(keys(%$ss)) {
			$self->{substitution_label} = $_;
			$self->parse_oneline($ss->{$_}->{text});
		}
		$self->{substitution_mode} = 0;
	}
	#-----------------------------------------------------------------
	# main text
	#-----------------------------------------------------------------
	my $out = [];
	my @footnote_buf;	# footnote buffer

	my $id;
	while(@$lines) {
		my $x = shift(@$lines);
		my $type = ref($x) ? $x->{type} : undef;

		#---------------------------------------------------------
		# insert 4 id
		#---------------------------------------------------------
		if ($type eq 'link') {
			$id = " id=\"$x->{id}\"";
			# $self->debug("Found id : $id");
			next;
		}
		if ($id && !ref($x) && $x =~ /^(.*)<(\w+(?: \w+ += +\"[^\"]\")*)>(.*)/) {
			$x = "$1<$2$id>$3";
			$id='';
		}

		#---------------------------------------------------------
		# footnote / citation
		#---------------------------------------------------------
		if ($type eq 'footnote' || $type eq 'citation') {
			my $div = 1;
			my $o   = $out;
			if ($type eq 'footnote') {
				$div = 0;
				$o = \@footnote_buf;
			}
			$div && push(@$o, "<div class=\"$type\"$id>\x02");
			$id='';
			unshift(@$lines, $x);
			while(@$lines) {
				my $y = $lines->[0];
				if (!ref($y) || $y->{type} ne $type) { last; }

				my $h = shift(@$lines);
				$h->{body} = $self->parse_oneline($h->{body});
				push(@$o, $h);
			}
			$div && push(@$o, "</div>\x02");
			next;
		}

		#---------------------------------------------------------
		# normal line
		#---------------------------------------------------------
		if (@footnote_buf && substr($x,-2) eq "\x02\x02") {
			# section end
			push(@$out, "<footer>\x02");
			push(@$out, @footnote_buf);
			push(@$out, "</footer>\x02");
			next;
		}
		if (substr($x,-1) ne "\x02") {
			$self->parse_oneline($x);
		}
		#---------------------------------------------------------
		push(@$out, $x);
	}
	return $out;
}

#------------------------------------------------------------------------------
# インラインマークアップの処理
#------------------------------------------------------------------------------
sub parse_oneline {
	my $self  = shift;
	my $quots = $self->{quotes};
	my $invalid_po = $self->{invalid_po};	# 無効なPoマーク（）
	Encode::_utf8_on($quots);

	foreach(@_) {
		#--------------------------------------------------------
		# インラインマークアップ認識準備
		#--------------------------------------------------------
		# http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html#inline-markup-recognition-rules
		# simple-inline-markup is False (default)

		Encode::_utf8_on($_);
		$_ =~ s!
			(^|&quot;|&lt;|[ \n>\-:/\'\(\[\p{gc:Ps}\p{gc:Pi}\p{gc:Pf}\p{gc:Pd}\p{gc:Po}])
			(?=[\[\*`\|_])
		!
			($1 eq '' || index($invalid_po, $1) < 0) ? "$1\x01" : $1
		!exg;
		$_ =~ s!
			(^|&quot;|&lt;|[ \n>\-:/\'\(\[\p{gc:Ps}\p{gc:Pi}\p{gc:Pf}\p{gc:Pd}\p{gc:Po}])
			(?=[A-Za-z0-9\p{gc:L}\p{gc:N}]+(?:[\-_\.][A-Za-z0-9\p{gc:L}\p{gc:N}]+)*_)
		!
			($1 eq '' || index($invalid_po, $1) < 0) ? "$1\x01" : $1
		!exg;
		$_ =~ s!
			([\]\*`\|_])
			(?=($|&quot;|&gt;|[ \n\x03<\-\.,:;\!\?/\'\)\]\}\p{gc:Pe}\p{gc:Pi}\p{gc:Pf}\p{gc:Pd}\p{gc:Po}]))
		!
			($2 eq '' || index($invalid_po, $2) < 0) ? "$1\x01" : $1
		!exg;

		# 開始記号が "**"強調** や 「``」リテラル`` のように囲まれてないか確認
		$_ =~ s!(&quot;|&lt;|.)\x01(?=(\*\*|``|_`|[\*`\|\[])\x01?(&quot;|&gt;|.))!
			if (index($quots, "$1$3 ") < 0) {
				"$1\x01";
			} else {
				$1;
			}
		!seg;
		Encode::_utf8_off($_);

		# my $d = $_; $d =~ s/\x01/1/g; $self->debug($d);

		my $x= $_;
		$_='';

		while ($x =~ m!^(.*?)\x01
			(	\*\*
				|\*
				|``
				|[`\[\|]
				|([A-Za-z0-9\x80-\xff]+(?:\x01?[\-_\.]\x01?[A-Za-z0-9\x80-\xff]+)*)(__?)
			)\x01?(.*?)$
		!xs) {
			$_ .= $1;
			$x  = $5;
			my $m = $2;

			# シンプルなインラインリンク
			if ($3 ne '') {
				my $y = $3;
				my $m = $4;
				if ($x eq '' || $x =~ /^[ <]/) {
					$_ .= $self->inline_link($y, '', $m);
				} else {
					$_ .= $y . $m;
				}
				next;
			}

			# 開始記号直後がスペース or 開始記号が行末である
			if ($x =~ m!^[ \n]! || $x =~ m!^(?:</\w+>)*\n?$!) {
				$_ .= $m;
				next;
			}

			# lookup markup table
			my $h   = $Markup{$m};
			my $pt  = $h->{pt};

			# seacrh end markup
			if ($x =~ /$pt/) {
				my $xbak = $x;
				$x = $3;
				if ($h->{func}) {
					my $r = &{$h->{func}}($self, $1, $2);
					if (! defined $r) {
						$_ .= $m;	# 開始文字を無視
						$x  = $xbak;
						next;
					}
					$_ .= $r;
				} else {
					my $tag = $h->{tag};
					my $c = $h->{class} ? " class=\"$h->{class}\"" : '';
					$_ .= "<$tag$c>$1</$tag>";
				}
			} elsif ($h->{ignore_start}) {
				$_ .= $m;
				next;
			} else {
				my $msg = $self->parse_error('Inline "%s" start-string without end-string', $m);
				$_ .= $self->make_problematic_span($m, $msg);
				$x = "\x01" . $x;
			}
		}
		$_ .= $x;
		$_ =~ s/\x01//g;
	}
	return $_[0];
}
#------------------------------------------------------------------------------
# マークアップの定義
#------------------------------------------------------------------------------
BEGIN{
	$Markup{'**'} = {
		pt  => qr/^(.*?[^ \n\x01])\x01?(\*\*)\x01(.*)/s,
		tag => 'strong'
	};
	$Markup{'*'} = {
		pt  => qr/^(.*?[^ \n\x01])\x01?(\*)\x01(.*)/s,
		tag => 'em'
	};
	$Markup{'``'} = {
		pt   => qr/^(.*?[^ \n\x01])\x01?(``)\x01(.*)/s,
		func => sub {
			my $self = shift;
			my $str  = shift;
			$self->backslash_escape_cancel_with_tag_escape($str);
			return "<span class=\"pre\">$str</span>";
		}
	};
	$Markup{'`'} = {
		pt   => qr/^(.*?[^ \n\x01])\x01?(`_?_?)\x01(.*)/s,
		func => sub {
			my $self = shift;
			my $str  = shift;
			my $m    = shift;

			if ($m eq '`') {
				return "<span class=\"\">$str</span>";
			}
			return $self->inline_link($str, "`", $m);
		}
	};
	$Markup{'|'} = {
		pt   => qr/^(.*?[^ \n\x01])\x01?(\|_?_?)\x01(.*)/s,
		func => sub {
			my $self  = shift;
			my $label = shift;
			my $m     = shift;
			return $self->inline_substitution($label, $m);
		}
	};
	$Markup{'['} = {
		ignore_start => 1,
		pt   => qr/^(\d+|\x01?\*\x01?|\#?[^\]]*)\](_)\x01(.*)/s,
		func => sub {
			my $self  = shift;
			my $label = shift;
			$label =~ s/\x01//g;

			if ($self->check_footnote_label($label)) {
				my $y = $self->inline_reference($label);
				return ($y ? $y : "[$label]");
			}
			return;
		}
	};
};

#------------------------------------------------------------------------------
# footnote/citationの処理
#------------------------------------------------------------------------------
sub inline_reference {
	my $self  = shift;
	my $label = shift;
	if ($self->{substitution_mode}) {
		return $self->error_in_substitution("[$label]_");
	}
	$label =~ s/\x01//g;
	$self->backslash_un_escape($label);
	return "\x02ref\x02$label\x02";
}
sub output_inline_reference {
	my $self  = shift;
	my $label = shift;
	$self->backslash_un_escape($label);

	my $key = $label;
	$key =~ tr/A-Z/a-z/;

	my $links = $self->{links};
	my $auto  = $self->{footnotes_auto};

	my $h;
	if ($label eq '*') {
		my $symbol = $self->get_footnote_symbol( $self->{footnote_symc} );
		$self->{footnote_symc}++;
		$h = $links->{$symbol};
		if (!$h) {
			$self->parse_error('Too many symbol footnote references');
			return "<a href=\"#**error\" title=\"Too many symbol footnote references\">[$label]_</a>";
		}
	} elsif ($label =~ /^#/ && $links->{$key}) {
		$h = $links->{$key};

	} elsif ($label =~ /^#/) {
		$h = shift(@$auto);
		while($h && ref($h) && $h->{used}) {
			$h = shift(@$auto);
		}
		if (!$h) {
			my $msg = $self->parse_error('Too many autonumbered footnote references');
			return $self->make_problematic_link("[$label]_", $msg);
		}
	} else {
		$h = $links->{$key};
		if (!$h) {
			my $msg = $self->parse_error('Citation not found: %s', $label);
			return $self->make_problematic_span("[$label]", $msg);
		}
	}
	if ($h->{error}) {
		my $err = $h->{error};
		if ($h->{duplicate}) {
			$err = $self->parse_error('Duplicate target name is defined: %s', $label);
		}
		return $self->make_problematic_link("[$label]_", $h->{error});
	}
	if ($h->{type} ne 'footnote' && $h->{type} ne 'citation') {
		my $msg = $self->parse_error('Target is not footnote/citation: %s', $label);
		return $self->make_problematic_span("[$label]", $msg);
	}
	$h->{used} = 1;
	my $type = $h->{type};
	my $name = $h->{_label} || $h->{label};
	my $backref_id = $self->generate_link_id("backref-$name");
	push(@{ $h->{backrefs} ||= [] }, $backref_id);

	return "<span class=\"$type rest-$type\" id=\"$backref_id\"><a href=\"$self->{thisurl}#$h->{id}\">[$h->{label}]</a></span>";
}

#------------------------------------------------------------------------------
# リンクの参照処理
#------------------------------------------------------------------------------
sub inline_link {
	my $self  = shift;
	my $label = shift;
	my $mark0 = shift || '';
	my $mark1 = shift || '_';
	my $text  = shift;
	$label =~ s/\x01//g;

	if ($mark0 eq '`'
	 && $label =~ /^(?:(.*) +|)&lt;(.+?)&gt;$/s
	 && substr($2,0,1) ne ' '
	 && substr($2,-1)  ne ' '
	 && index($2, '&lt;')<0 && index($2, '&gt;')<0) {

		if ($self->{substitution_mode}) {
			return $self->error_in_substitution("$mark0$label$mark1");
		}

		#---------------------------------------------
		# Embedded URIs
		#---------------------------------------------
		my $url = $2;
		$label = $1;
		$label =~ s/ +$//;
		my $key = $label;

		my $links = $self->{links};
		my $anonymous = ($mark1 eq '`__');

		$self->normalize_label($key);
		$self->normalize_link_url($url);

		if ($key ne '' && !$anonymous && $links->{$key}) {
			my $msg = $self->parse_error('Duplicate link target name: %s', $label);
			$links->{$label}->{error} = $msg;
			$links->{$label}->{duplicate} = 1;
		} elsif (!$anonymous) {
			my $k = $key ne '' ? $key : $url;
			$links->{$k} = {
				type => 'link',
				url  => $url
			};
		}

		$label = $label eq '' ? $url : $label;
		if ($anonymous) {
			return "<a href=\"$url\">${label}</a>";
		}
	}
	$self->backslash_un_escape($label);
	return "\x02link\x02$label\x02$text\x02\x02$mark0\x02$mark1\x02";
}

sub output_inline_link {
	my $self  = shift;
	my $label = shift;
	my $text  = shift;
	my $attr  = shift;
	my $mark0 = shift || '';
	my $mark1 = shift || '_';
	my $orig  = shift;
	my $check = shift || {};
	my $nest  = shift;

	$self->backslash_un_escape($label);
	my $err_label = $orig eq '' ? $label : "\"$label\" from \"$orig\"";
	$orig = $orig ne '' ? $orig : $label;

	# for image-link
	if ($mark0 eq 'img') {
		$orig = $mark1;
		$mark0 = $mark1 = '';
	}

	# 循環参照チェック
	if ($check->{$label}) {
		my $err = $self->parse_error('Indirect hyperlink target is circular reference: %s', $err_label);
		return $self->make_problematic_link("$mark0$orig$mark1", $err);
	}
	$check->{$label} = 1;

	my $key = $self->generate_key_from_label($label);

	my $h = $self->{links}->{$key};
	if (!$nest && substr($mark1,-2) eq '__') {
		$h = $self->{anonymous_links}->[ $self->{anonymous_linkc} ];
		$self->{anonymous_linkc}++;
		if (!$h) {
			my $err = $self->parse_error('Too many anonymous hyperlink references');
			return $self->make_problematic_link("$mark0$orig$mark1", $err);
		}
	}
	if ($h->{duplicate}) {
		my $err = $self->parse_error('Duplicate target name is defined: %s', $err_label);
		return $self->make_problematic_link("$mark0$orig$mark1", $err);
	}
	my $url = exists($h->{url}) ? $h->{url} : ('#' . $h->{id});
	if ($url eq '' || $url eq '#') {
		my $err = $self->parse_error('Unknown target name: %s', $err_label);
		return $self->make_problematic_link("$mark0$orig$mark1", $err);
	}

	# link
	if ((my $x = $self->check_link_label($url)) ne '') {
		return $self->output_inline_link($x, $text, $attr, $mark0, $mark1, $orig, $check, 'nest');
	}

	$url =~ s/ //g;
	$self->tag_escape($label, $url);
	$text = $text eq '' ? $orig : $text;
	return "<a href=\"$url\">$text</a>";
}

#------------------------------------------------------------------------------
# 置換参照の処理
#------------------------------------------------------------------------------
sub inline_substitution {
	my $self  = shift;
	my $label = shift;
	my $mark  = shift;

	if ($self->{substitution_mode}) {
		return $self->error_in_substitution("|$label$mark");
	}

	my $key = $self->generate_key_from_label($label);
	my $ss  = $self->{substitutions};
	if (!exists($ss->{$key})) {
		my $err = $self->parse_error('Undefined substitution referenced: %s', $label);
		return $self->make_problematic_span("|$label$mark", $err);
	}

	my $subst = $ss->{$key};
	my $text  = $subst->{text};
	my $ltrim = $subst->{ltrim} ? "\x08" : '';
	my $rtrim = $subst->{rtrim} ? "\x08" : '';
	if (substr($mark,-1) eq '_') {
		return $ltrim . $self->inline_link($label, '|', $mark, $text) . $rtrim;
	}

	return "$ltrim$text$rtrim";
}

sub error_in_substitution {
	my $self = shift;
	my $text = shift;
	my $msg = $self->parse_error('Substitution definition contains illegal element: %s', $self->{substitution_label});
	return $self->make_problematic_span($text, $msg);
}

###############################################################################
# ●[03] 最終処理
###############################################################################
sub parse_finalize {
	my $self  = shift;
	my $lines = shift;

	$self->{footnote_symc}   = 0;
	$self->{anonymous_linkc} = 0;

	#---------------------------------------------------------
	# footnote/citation/link の出力処理
	#---------------------------------------------------------
	foreach(@$lines) {
		if (!ref($_)) {
			$self->output_link_footnote_citation($_);
			next;
		}
		my $type  = $_->{type};
		my $label = '[' . $_->{label} . ']';
		my $body  = $_->{body};
		my $bid   = $_->{backrefs};	# array
		my $brefs = '';
		$self->output_link_footnote_citation($body);

		if ($bid) {
			$label = "<a href=\"$self->{thisurl}#$bid->[0]\">$label</a>";
		}
		if ($bid && $#$bid>0) {		# multi back reference
			my @a;
			foreach(0..$#$bid) {
				push(@a, "<a href=\"#$bid->[$_]\">" . ($_+1) . "</a>");
			}
			$brefs = '<span class="fn-backref">(' .	join(', ', @a) . ')</span> ';
		}
		$_ = "<p class=\"$type\" id=\"$_->{id}\">$label</a> $brefs$body</p>";
		
	}

	#---------------------------------------------------------
	# trim
	#---------------------------------------------------------
	foreach(@$lines) {
		$_ =~ s/[ \n]+\x08//g;
		$_ =~ s/\x08[ \n]*//g;
	}

	#---------------------------------------------------------
	# check anonymous link count
	#---------------------------------------------------------
	if (($#{$self->{anonymous_links}}+1) > $self->{anonymous_linkc}) {
		$self->parse_error('Too many anonymous hyperlink targets: ref=%d / def=%d',
				 $self->{anonymous_linkc}, $#{$self->{anonymous_links}}+1);
	}

	#---------------------------------------------------------
	# escapeを戻す
	#---------------------------------------------------------
	$self->backslash_un_escape(@$lines);

	return $lines;
}

sub output_link_footnote_citation {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x02ref\x02([^\x02]*)\x02/
			$self->output_inline_reference($1)
		/eg;
		# link / image directiveでも使用しているので注意
		$_ =~ s/\x02link\x02([^\x02]*)\x02([^\x02]*)\x02([^\x02]*)\x02([^\x02]*)\x02([^\x02]*)\x02/
			$self->output_inline_link($1,$2,$3,$4,$5)
		/eg;
	}
	return $_[0];
}

###############################################################################
# サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ローマ数字の解析
#------------------------------------------------------------------------------
my %ROMAN_U;
my %ROMAN_L;
BEGIN {
	%ROMAN_U = (
		'I'  =>   1, 'II'  =>   2, 'III'  =>   3, 'IV' =>   4, 'V' =>   5,
		'VI' =>   6, 'VII' =>   7, 'VIII' =>   8, 'IX' =>   9,
		'X'  =>  10, 'XX'  =>  20, 'XXX'  =>  30, 'XL' =>  40, 'L' =>  50,
		'LX' =>  60, 'LXX' =>  70, 'LXXX' =>  80, 'XC' =>  90,
		'C'  => 100, 'CC'  => 200, 'CCC'  => 300, 'CD' => 400, 'D' => 500,
		'DC' => 600, 'DCC' => 700, 'DCCC' => 800, 'CM' => 900,
		'M'  =>1000, 'MM'  =>2000, 'MMM'  =>3000,'MMMM'=>4000
	);
	foreach(keys(%ROMAN_U)) {
		my $l = $_;
		$l =~ tr/A-Z/a-z/;
		$ROMAN_L{$l} = $ROMAN_U{$_};
	}
};
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
# ●simple label / footnote label check
#------------------------------------------------------------------------------
sub check_simple_label {
	my $self = shift;
	my $x    = shift;
	if ($x !~ /[\x80-\xff]/) {
		return ($x =~ /^[A-Za-z0-9]+(?:[\-_\.][A-Za-z0-9]+)*$/);
	}
	Encode::_utf8_on($x);
	return ($x =~ /^[A-Za-z0-9\p{gc:L}\p{gc:N}]+(?:[\-_\.][A-Za-z0-9\p{gc:L}\p{gc:N}]+)*$/)
}

sub check_footnote_label {
	my $self = shift;
	my $x    = shift;
	if ($x eq '*' || $x eq '#') { return 1; }
	$x =~ s/^#//g;
	return $self->check_simple_label($x);
}

sub check_link_label {
	my $self = shift;
	my $x    = shift;
	if (substr($x,-1) ne '_') { return; }
	chop($x);
	if ($x =~ /^`([^`]+)`$/) { return $1; }
	my $r = $self->check_simple_label($x);
	return $r ? $x : undef;
}

#------------------------------------------------------------------------------
# ●footnote symbolの取得
#------------------------------------------------------------------------------
sub get_footnote_symbol {
	my $self = shift;
	my $num  = shift;	# 0 to 

	my $sym  = $self->{footnote_symbols};
	my $syms = $#$sym+1;	# how many symbols

	my $d = int($num/$syms) +1;
	my $x = $num - $d*$syms;
	return $sym->[$x] x $d;
}

#------------------------------------------------------------------------------
# ●リンクlabel/keyを正規化
#------------------------------------------------------------------------------
sub normalize_label {
	my $self  = shift;
	foreach(@_) {
		$_ =~ s/^`(.*)`$/$1/;
	}
	return $_[0]
}

sub generate_key_from_label {
	my $self  = shift;
	foreach(@_) {
		$_ =~ s/  +/ /g;
		$_ =~ tr/A-Z/a-z/;
	}
	return $_[0];
}

sub generate_key_from_label_with_tag_escape {
	my $self  = shift;
	$self->generate_key_from_label(@_);
	return $self->tag_escape(@_);
}

#------------------------------------------------------------------------------
# ●リンクURLを正規化
#------------------------------------------------------------------------------
sub normalize_link_url {
	my $self  = shift;
	foreach(@_) {
		$_ =~ s/^ +//g;
		$_ =~ s/ +$//g;

		# alias
		if ($_ =~ /^((`?).*\1)_$/) {
			$_ = $2 . '_';
			$_ =~ s/ +/ /g;
		} else {
			$_ =~ s/ //g;
		}
	}
	return $_[0]
}

#------------------------------------------------------------------------------
# ●ラベル等からidを生成
#------------------------------------------------------------------------------
sub generate_id_from_string {
	my $self  = shift;
	my $label = shift;
	my $default = shift || 'id';
	$label =~ tr/A-Z/a-z/;
	$label =~ s/[^\w\-\.\x80-\xff]+/-/g;
	return $label eq '' ? $default : $label;
}

#------------------------------------------------------------------------------
# ●重複しないlink_idを生成
#------------------------------------------------------------------------------
# level=1 Implicit（暗黙的）
# level=2 Explicit（明示的）
sub generate_implicit_link_id {
	my $self  = shift;
	my $base  = shift;
	return $self->generate_link_id($base, 1);
}
sub generate_link_id {
	my $self  = shift;
	my $base  = shift;
	my $level = shift || 2;
	my $ids   = $self->{ids};

	my $id = $base;
	my $i  = 1;
	while($ids->{$id}) {
		$id = $base . "-" . (++$i);
	}
	$ids->{$id} = $level;
	return $id;
}

#------------------------------------------------------------------------------
# ●エラー記述を生成
#------------------------------------------------------------------------------
sub make_problematic_link {
	my $self = shift;
	my $span = $self->make_problematic_span(@_);
	my $id   = $self->generate_link_id('link-error');
	return "<a href=\"#$id\" class=\"problematic\">$span</a>";
}
sub make_problematic_span {
	my $self = shift;
	my $text = shift;
	my $err  = shift;
	$err = $err ? " title=\"$err\"" : '';
	return "<span class=\"problematic\"$err>$text</span>";
}

#------------------------------------------------------------------------------
# ●バックスラッシュのエスケープ
#------------------------------------------------------------------------------
sub backslash_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s!\\(.)|\\$!
			if ($1 eq '') {
				"\x03";
			} else {
				my $d = ord($1);
				index("\n .:*`|\\_<>", $1)<0 ? "\x03$1" : "\x03$d";
			}
		!seg;
	}
	return $_[0];
}

#----------------------------------------------------------
# エスケープを戻す
#----------------------------------------------------------
my %BackslashUnEscape;
BEGIN {
	%BackslashUnEscape = (
		ord(' ') => '',
		ord("\n")=> '',
		ord('<') => '&lt;',
		ord('>') => '&gt;'
	);	# unicode directive の関係で & を含めないこと
};
sub backslash_un_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03(\d+)/
			exists($BackslashUnEscape{$1}) ? $BackslashUnEscape{$1} : chr($1);
		/eg;
		$_ =~ s/\x03//g;
	}
	return $_[0];
}
#----------------------------------------------------------
# 処理をキャンセル
#----------------------------------------------------------
my %BackslashCancel;
BEGIN {
	%BackslashCancel = (
		ord('<') => '&lt;',
		ord('>') => '&gt;'
	);
};
sub backslash_escape_cancel {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03(\d+)/chr($1)/eg;
		$_ =~ s/\x03/\\/g;
	}
	return $_[0];
}

sub backslash_escape_cancel_with_tag_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/\x03(\d+)/
			"\\" . (exists($BackslashCancel{$1}) ? $BackslashCancel{$1} : chr($1));
		/eg;
		$_ =~ s/\x03/\\/g;
	}
	return $_[0];
}
#----------------------------------------------------------
# 処理後の結果を返す
#----------------------------------------------------------
sub backslash_process {
	my $self = shift;
	foreach(@_) {
		$_ =~ s!\\(.)|\\$!
			($1 eq ' ' || $1 eq "\n" || $1 eq '') ? '' : $1;
		!seg;
	}
	return $_[0];
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
	my $err  = '[RST] ' . shift;
	my $ROBJ = $self->{ROBJ};

	if ($ROBJ) {
		return $ROBJ->warn($err, @_);
	}
	return sprintf($err, @_);
}

###############################################################################
# ●[99] 後処理
###############################################################################
sub post_process {
	my $self = shift;
	my $rtxt = shift;

	# 目次の処理
	$$rtxt =~ s|\x02<toc>(.*?)</toc>\x02|$self->post_toc($1)|eg;
}

sub post_toc {
	my $self = shift;
	my $opt;
	foreach(split(':', shift)) {
		if ($_ =~ /^(\w+)=(.*)$/) {
			$opt->{$1} = $2;
			next;
		}
		$opt->{$_}=1;
	}
	$opt->{class} = "toc" . ($opt->{class} eq '' ? '' : ' ' . $opt->{class});

	my $secs = $self->{sections};
	if ($opt->{local} ne '' && $self->{local_sections}->[$opt->{local}]) {
		$secs = $self->{local_sections}->[$opt->{local}]->{children};
		if (!$secs) { return; }
	}
	return $self->generate_toc($secs, $opt, $opt->{depth}) . "\n";
}

sub generate_toc {
	my $self  = shift;
	my $secs  = shift;
	my $opt   = shift;
	my $depth = shift;
	my $level = shift || 0;

	my $tab = "\t" x $level;
	my $out = $level ? "$tab<ul>\n" : "<ul class=\"$opt->{class}\">\n";

	foreach(@$secs) {
		my $subs = $_->{children};
		my $num  = $_->{number};
		if ($num ne '') { $num .= ' '; }
		my $link = "<a href=\"$self->{thisurl}#$_->{id}\">$num$_->{title}</a>";
		if (!$subs || !@$subs) {
			$out .= "$tab\t<li>$link</li>\n";
			next;
		}

		$out .= "$tab\t<li>$link\n";
		if ($depth eq '' || 1<$depth) {
			if (1<$depth) { $depth=$depth-1; }
			$out .=	$self->generate_toc($subs, $opt, $depth, $level+1);
		}
		$out .= "</li>\n";
	}
	$out .= "$tab</ul>";
	return $out;
}

###############################################################################
# マルチバイト処理
###############################################################################
#------------------------------------------------------------------------------
# マルチバイト文字を文字幅ベースでsubstr
#------------------------------------------------------------------------------
sub mb_substr {
	my $self  = shift;
	my $str   = shift;
	my $start = shift;
	my $len   = shift;
	if ($str !~ /[^\x00-\x7f]/) { return substr($str, $start, $len); }

	my @buf;
	$self->mb_hack($str, \@buf);
	my $x = substr($str, 0, $start);
	my $y = substr($str, $start, $len);
	$self->mb_hack_recovery($x, \@buf);	# $y を正しく戻すために必要
	$self->mb_hack_recovery($y, \@buf);

	return $y;
}

#------------------------------------------------------------------------------
# マルチバイト文字を文字幅に合わせて置換
#------------------------------------------------------------------------------
sub mb_hack {
	my $self = shift;
	my $str  = $_[0];
	my $buf  = $_[1] || [];
	if ($str !~ /[^\x00-\x7f]/) { return $str; }

	Encode::_utf8_on($str);		# Fullwidth from EastAsianWidth-12.0.0.txt
	$str =~ s/([\x{1100}-\x{115F}\x{231A}-\x{231B}\x{2329}-\x{232A}\x{23E9}-\x{23EC}\x{23F0}\x{23F3}\x{25FD}-\x{25FE}\x{2614}-\x{2615}\x{2648}-\x{2653}\x{267F}\x{2693}\x{26A1}\x{26AA}-\x{26AB}\x{26BD}-\x{26BE}\x{26C4}-\x{26C5}\x{26CE}\x{26D4}\x{26EA}\x{26F2}-\x{26F3}\x{26F5}\x{26FA}\x{26FD}\x{2705}\x{270A}-\x{270B}\x{2728}\x{274C}\x{274E}\x{2753}-\x{2755}\x{2757}\x{2795}-\x{2797}\x{27B0}\x{27BF}\x{2B1B}-\x{2B1C}\x{2B50}\x{2B55}\x{2E80}-\x{303E}\x{3041}-\x{3247}\x{3250}-\x{4DBF}\x{4E00}-\x{A4C6}\x{A960}-\x{A97C}\x{AC00}-\x{D7A3}\x{F900}-\x{FAFF}\x{FE10}-\x{FE19}\x{FE30}-\x{FE6B}\x{FF01}-\x{FF60}\x{FFE0}-\x{FFE6}\x{16FE0}-\x{1B2FB}\x{1F004}\x{1F0CF}\x{1F18E}\x{1F191}-\x{1F19A}\x{1F200}-\x{1F320}\x{1F32D}-\x{1F335}\x{1F337}-\x{1F37C}\x{1F37E}-\x{1F393}\x{1F3A0}-\x{1F3CA}\x{1F3CF}-\x{1F3D3}\x{1F3E0}-\x{1F3F0}\x{1F3F4}\x{1F3F8}-\x{1F43E}\x{1F440}\x{1F442}-\x{1F4FC}\x{1F4FF}-\x{1F53D}\x{1F54B}-\x{1F54E}\x{1F550}-\x{1F567}\x{1F57A}\x{1F595}-\x{1F596}\x{1F5A4}\x{1F5FB}-\x{1F64F}\x{1F680}-\x{1F6C5}\x{1F6CC}\x{1F6D0}-\x{1F6D2}\x{1F6D5}\x{1F6EB}-\x{1F6EC}\x{1F6F4}-\x{1F6FA}\x{1F7E0}-\x{1F7EB}\x{1F90D}-\x{1F9FF}\x{1FA70}-\x{3FFFD}])/push(@$buf, $1), "\x04\x07"/eg;

	# Ambiguous
	my $amb = $self->{ambiguous_full} ? "\x05\x07" : "\x05";
	$str =~ s/([\x{2010}\x{2013}-\x{2016}\x{2018}-\x{2019}\x{201C}-\x{201D}\x{2020}-\x{2022}\x{2024}-\x{2027}\x{2030}\x{2032}-\x{2033}\x{2035}\x{203B}\x{203E}\x{2074}\x{207F}\x{2081}-\x{2084}\x{20AC}\x{2103}\x{2105}\x{2109}\x{2113}\x{2116}\x{2121}-\x{2122}\x{2126}\x{212B}\x{2153}-\x{2154}\x{215B}-\x{215E}\x{2160}-\x{216B}\x{2170}-\x{2179}\x{2189}\x{2190}-\x{2199}\x{21B8}-\x{21B9}\x{21D2}\x{21D4}\x{21E7}\x{2200}\x{2202}-\x{2203}\x{2207}-\x{2208}\x{220B}\x{220F}\x{2211}\x{2215}\x{221A}\x{221D}-\x{2220}\x{2223}\x{2225}\x{2227}-\x{222C}\x{222E}\x{2234}-\x{2237}\x{223C}-\x{223D}\x{2248}\x{224C}\x{2252}\x{2260}-\x{2261}\x{2264}-\x{2267}\x{226A}-\x{226B}\x{226E}-\x{226F}\x{2282}-\x{2283}\x{2286}-\x{2287}\x{2295}\x{2299}\x{22A5}\x{22BF}\x{2312}\x{2460}-\x{24E9}\x{24EB}-\x{254B}\x{2550}-\x{2573}\x{2580}-\x{258F}\x{2592}-\x{2595}\x{25A0}-\x{25A1}\x{25A3}-\x{25A9}\x{25B2}-\x{25B3}\x{25B6}-\x{25B7}\x{25BC}-\x{25BD}\x{25C0}-\x{25C1}\x{25C6}-\x{25C8}\x{25CB}\x{25CE}-\x{25D1}\x{25E2}-\x{25E5}\x{25EF}\x{2605}-\x{2606}\x{2609}\x{260E}-\x{260F}\x{261C}\x{261E}\x{2640}\x{2642}\x{2660}-\x{2661}\x{2663}-\x{2665}\x{2667}-\x{266A}\x{266C}-\x{266D}\x{266F}\x{269E}-\x{269F}\x{26BF}\x{26C6}-\x{26CD}\x{26CF}-\x{26D3}\x{26D5}-\x{26E1}\x{26E3}\x{26E8}-\x{26E9}\x{26EB}-\x{26F1}\x{26F4}\x{26F6}-\x{26F9}\x{26FB}-\x{26FC}\x{26FE}-\x{26FF}\x{273D}\x{2776}-\x{277F}\x{2B56}-\x{2B59}\x{3248}-\x{324F}\x{E000}-\x{F8FF}\x{FE00}-\x{FE0F}\x{FFFD}\x{1F100}-\x{1F10A}\x{1F110}-\x{1F12D}\x{1F130}-\x{1F169}\x{1F170}-\x{1F18D}\x{1F18F}-\x{1F190}\x{1F19B}-\x{1F1AC}\x{E0100}-\x{10FFFD}])/push(@$buf, $1), $amb/eg;

	$str =~ s/([^\x00-\x7f])/push(@$buf, $1), "\x06"/eg;
	Encode::_utf8_off($str);

	return ($_[0] = $str);
}

sub mb_hack_recovery {
	my $self = shift;
	my $str  = $_[0];
	my $buf  = $_[1];
	if ($str !~ /[\x04-\x07]/) { return $str; }

	Encode::_utf8_on($str);
	$str =~ s/\x07//g;
	$str =~ s/\x04/shift(@$buf)/eg;
	$str =~ s/\x05/shift(@$buf)/eg;
	$str =~ s/\x06/shift(@$buf)/eg;
	Encode::_utf8_off($str);

	return ($_[0] = $str);
}


1;
