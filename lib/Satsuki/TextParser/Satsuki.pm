use strict;
#-------------------------------------------------------------------------------
# システム標準パーサー／Satsukiパーサー
#                                             (C)2006-2019 nabe / nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::TextParser::Satsuki;
# ※注意。パッケージ名変更時は78行目付近も修正のこと！

use Satsuki::AutoLoader;
our $VERSION = '2.30';
#-------------------------------------------------------------------------------
# \x00-\x03は内部で使用するため、処理の過程で除去されます。
#	\x00 文字列の一時退避用
#	\x01 インデント抑止用、処理済マークング（グローバル使用）
#	\x02 各処理プロセス内でのみ使用
#	\x03 未使用（プラグイン用）
#-------------------------------------------------------------------------------
my $TAG_PLUGIN_CLASS = 'TextParser::TagPlugin::Tag_';
my $CSS_CLASS_PREFIX = 'tag-';
my $INFO_BEGIN_MARK = '#---begin_plugin_info';
my $INFO_END_MARK   = '#---end';
#-------------------------------------------------------------------------------
# その記事だけの設定を許可する設定値（$self内変数）
#	1 文字列
#	2 数値
my %allow_override = (
	chain_line => 2,
	section_number => 2, section_start  => 2,
	section_prefix => 1, section_suffix => 1,
	timestamp_date => 1,
	br_mode => 2, p_mode => 2, p_class => 1, ls_mode => 1,
	seemore_msg => 1, list_br => 2, tex_mode => 2
);
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
# 引数のキャッシュファイルは省略しても動作します。
# 第２引数はプラグインdir
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{plugin_cache_file} = shift;

	$self->{br_mode} = 1;
	$self->{ls_mode} = 1;
	$self->{chain_line} = 1;

	$self->{section_hnum}   = 3;	# section level
	$self->{section_number} = 0;	# 章番号なし
	$self->{section_start}  = 1;	# 章の開始番号

	$self->{timestamp_date} = '%Y/%m/%d';
	$self->{indent} = '';		# indent all line
	$self->{seemore_msg} = '';	# default "See More..."
	$self->{image_attr}  = '';	# image link attribute for lightbox

	$self->{vars} = {};		# 内部自由変数

	$self->init_tags();
	$self->load_plugins(@_);

	# 処理する記事ごとに設定
	$self->{thisurl}  = '';		# 記事のURL
	$self->{thispkey} = '';		# 記事のpkey = unique id = [0-9]+

	return $self;
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●記事本文の整形
#-------------------------------------------------------------------------------
sub parse {
	my ($self, $lines, $opt) = @_;

	$lines =~ s/[\x00-\x03\r]//g;
	$lines = [ split(/\n/, $lines) ];
	$opt ||= {};	# オプション

	# 初期設定
	$self->{sections} = [];
	$self->{ids}      = {};

	# 内部変数の退避
	my %backup;
	foreach(keys(%allow_override)) { $backup{$_} = $self->{$_}; }
	my %backup_vars = %{ $self->{vars} };	# copy

	{
		# [01]ブロック処理、コメント除去処理
		$lines = $self->block_parser($lines);

		# [02]セクション、目次処理
		$lines = $self->parse_section($lines);

		# 内部変数復元（[01]での最終オーバーライド結果を[03]で使わないため）
		foreach(keys(%allow_override)) { $self->{$_} = $backup{$_}; }

		# [03]記法タグの処理
		$lines = $self->replace_original_tag($lines);

		# [04]段落/改行処理
		$lines = $self->paragraph_processing($lines);
	}

	# [99]後処理
	my $data = join('', @$lines);
	$self->post_process( \$data );

	# 内部変数の復元
	foreach(keys(%allow_override)) { $self->{$_} = $backup{$_}; }
	$self->{vars} = \%backup_vars;

	# SeeMoreの処理
	my $short;
	if ($data =~ /<!--%SeeMore%-->/) {
		$short = $data;
		$data  =~ s/\s*<p\s*class="seemore">.*?<!--%SeeMore%-->/<!--%SeeMore%-->/;
		$short =~ s|<!--%SeeMore%-->.*|\n</section>|sg;
	}
	return wantarray ? ($data, $short) : $data;
}

################################################################################
# ■[01] ブロック処理
################################################################################
# 行末改行のある行は処理終了とみなす。
sub block_parser {
	my ($self, $lines) = @_;
	my $st = {		# ブロックステータス
		start  =>undef, # ブロック開始判定（文字列 or 関数）
		end    => '',	# ブロック終了タグ
		tag    => '',	# ブロックタグ名
		class  => '',	# ブロックタグのclass
		p      => 1, 	# 段落処理有効モード、0:そのまま入力モード
		htag   => 1,	# htmlタグ有効？
		atag   => 1,	# adiaryタグ有効？
		bcom   => 0,	# ブロック中注釈機能 >> #{comment}
		br     => 0,	# 行末強制改行モード
		before => '',	# ブロック開始直後に出力するHTML
		after  => '',	# ブロック終了直前に出力するHTML
		pre    => 0,	# 1 = indent禁止
		top    => 1	# トップレベルのブロック
	};

	my @ary;
	$self->block_parser_main( \@ary, $lines, $st );
	foreach(@ary) {
		$_ =~ s/\x02//g;
	}
	return \@ary;
}

my @Blocks;
push(@Blocks, {
	start  => '>||script-defer',
	end    => '||<',
	tag    => 'script-defer',
	before => '<!--',
	after  => '-->',
	pre    => 1,
	htag   => 1
});
push(@Blocks, {
	start  => '>||script',
	end    => '||<',
	tag    => 'script',
	before => '<!--',
	after  => '-->',
	pre    => 1,
	htag   => 1
});
push(@Blocks, {
	start  => '>||comment',
	end    => '||<',
	tag    => '',
	before => '<!--',
	after  => '-->',
	pre    => 1
});
push(@Blocks, {
	start  => '>|aa|',
	end    => '||<',
	tag    => 'div',
	class  => 'ascii-art',
	br     => 1,
	pre    => 1
});
push(@Blocks, {
	start  => sub {		# syntax highlight >|js|
		my ($self, $line) = @_;
		if ($line !~ /^>\|([\w#\-]+)\|(.*)/) { return; }
		return [$1, $2];
	},
	end    => '||<',
	tag    => 'pre',
	class  => 'syntax-highlight',
	pre    => 1
});
push(@Blocks, {
	start  => '>|?|',
	end    => '||<',
	tag    => 'pre',
	class  => 'syntax-highlight',
	pre    => 1
});
push(@Blocks, {
	start  => '```math',
	end    => '```',
	tag    => 'div',
	class  => 'math'
});
push(@Blocks, {
	start  => '```',
	end    => '```',
	tag    => 'pre',
	class  => 'syntax-highlight',
	pre    => 1
});
push(@Blocks, {
	start  => '>||#',
	end    => '#||<',
	tag    => 'pre',
	bcom   => 1,
	pre    => 1
});
push(@Blocks, {
	start  => '>||',
	end    => '||<',
	tag    => 'pre',
	pre    => 1
});
push(@Blocks, {
	start  => '>|',
	end    => '|<',
	tag    => 'pre',
	htag   => 1,
	atag   => 1,
	pre    => 1
});
push(@Blocks, {
	start  => '>>>||',
	end    => '||<<<',
	tag    => 'div'
});
push(@Blocks, {
	start  => '>>>[',
	end    => ']<<<',
	tag    => 'div',
	htag   => 1,
	atag   => 0
});
push(@Blocks, {
	start  => '>>><',
	end    => '><<<',
	tag    => 'div',
	htag   => 0,
	atag   => 1
});
push(@Blocks, {
	start  => '>>>|',
	end    => '|<<<',
	tag    => 'div',
	htag   => 1,
	atag   => 1
});
push(@Blocks, {
	start  => '>>>',
	end    => '<<<',
	tag    => 'div',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {
	start  => '>>||',
	end    => '||<<',
	tag    => 'blockquote'
});
push(@Blocks, {
	start  => '>>|figure',
	end    => '|<<',
	tag    => 'figure',
	htag   => 1,
	atag   => 1
});
push(@Blocks, {
	start  => '>>|',
	end    => '|<<',
	tag    => 'blockquote',
	htag   => 1,
	atag   => 1
});
push(@Blocks, {
	start  => '>>del',
	end    => '<<',
	tag    => 'del',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {
	start  => '>>ins',
	end    => '<<',
	tag    => 'ins',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {
	start  => '>>figure',
	end    => '<<',
	tag    => 'figure',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {
	start  => '>>',
	end    => '<<',
	tag    => 'blockquote',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {		# Hatena's blockquote, >http://example.com/
	start  => sub {
		my ($self, $line) = @_;
		if ($line !~ m|^>(https?://[^>]*)>(.*)|) { return; }
		return ["[$1]", $2];
	},
	end    => '<<',
	tag    => 'blockquote',
	htag   => 1,
	atag   => 1,
	p      => 1
});
push(@Blocks, {
	start  => sub {
		my ($self, $line) = @_;
		if (!$self->{tex_mode} || $line !~ m|^\\\[(.*)|) { return; }
		return ['math'];
	},
	end    => '\]',
	tag    => 'div'
});
push(@Blocks, {
	start  => sub {
		my ($self, $line) = @_;
		if (!$self->{tex_mode} || $line !~ m|^\\begin\{([^\}]*)\}$|) { return; }
		return {
			before => $line,
			after  => "\\end{$1}",
			end    => "\\end{$1}",
			tag    => 'div',
			opt    => 'math'
		}
	},
});
foreach(@Blocks) {
	$_->{len} = length($_->{start});
}

#-------------------------------------------------------------------------------
# ●ブロックパース
#-------------------------------------------------------------------------------
sub block_parser_main {
	my $self   = shift;
	my $ary    = shift;
	my $lines  = shift;
	my $st     = shift;		# blockステータス
	my $macros = $self->{macros};	# マクロ情報

	# \x02 は >> -- <<などのブロック中のみ行末に付加される。
	# リストブロック内での項目連結処理を、項目内のブロックで行わないための細工。
	my $end      = $st->{end};
	my $blk_mark = $st->{top} ? '' : "\x02";

	my $in_comment;
	my $class;		# リストブロック用クラス指定
	my $list_mark;		# リスト記号
	my $list_ext;		# 拡張リスト記法
	my $ary_bak;		# $ary退避用
	my @table;		# table用バッファ

	while(@$lines || $list_mark) {		# $list_mark : 最終行がリスト項目の時にもう一度だけループを回す
		my $line = shift(@$lines);
		my $blank = ($line eq '');

		#-----------------------------------------------------
		# コメント中である
		#-----------------------------------------------------
		if ($in_comment) {
			my $x = index($line, '-->');
			if ($x < 0) { next; }		# コメント中は出力しない
			$in_comment = 0;
			$line = substr($line, $x +3);	# 残り
		}

		#-----------------------------------------------------
		# ブロック記法の開始 / \begin{}があるため先に処理
		#-----------------------------------------------------
		if ($st->{atag}) {
			my $blk;
			my $opt;
			foreach(@Blocks) {
				my $start = $_->{start};

				if (!ref($start)) {
					if (substr($line, 0, $_->{len}) ne $start) { next; }

					# ブロック発見
					my $len = $_->{len} + ($start =~ /\w$/ ? 1 : 0);
					$opt = substr($line, $len);
					$opt =~ s/^\s*(.*?)\s*$/$1/;
					$blk = $_;
					last;
				}
			  	if (my $ma = &$start($self, $line)) {
					if (ref($ma) eq 'ARRAY') {
						$opt = join(' ', @$ma);
						$blk = $_;
					} else {
						$opt = $ma->{opt};
						$blk = $ma;
					}
					last;
				}
			}
			# ブロック発見
			if ($blk) {
				my $tag   = $blk->{tag};
				my $after = $blk->{after};
				if ($blk->{opt2after}) {
					my $t = $blk->{opt2after};
					$after = "<$t>$opt</$t>";
				}

				my $attr  = '';
				if ($tag eq 'blockquote') {
					$opt =~ s|^(https?://[^\s\[\]]*)$|[$1]|;
					if ($opt =~ m|^(\[[^]]*\])(.*)|) {
						my $tag = $1;
						$opt = $2;
						if ($tag =~ m!^\[&?(https?://(?:\\:|[^:\"\]])*)!) {
							$attr = " cite=\"$1\"";
						}
						my %b = %$blk; $blk = \%b;
						$after = "<cite>$tag</cite>";
					}
				}
				if ($tag eq 'figure') {
					if ($opt =~ /^(.*)caption=\s*(.*?)\s*$/) {
						$opt = $1;
						$after = "<figcaption>$2</figcaption>";
					}
				}
				if ($blk->{class} eq 'syntax-highlight') {
					my ($lang,$file) = split(/[ :]/, $opt, 2);
					$self->tag_escape($lang, $file);
					$opt = $lang;	# set to class
					if ($file) {
						$attr = " title=\"$file\"";
					}
				}
				# クラス, ID指定
				my $class = $self->parse_class_id($blk->{class} . ' ' . $opt);
				my $mark  = $blk->{pre} ? "\x01" : '';
				push(@$ary, ($tag ? "<$tag$attr$class>" : '') . "$blk->{before}\n$mark");

				# ブロックの入れ子
				$self->block_parser_main($ary, $lines, $blk);

				push(@$ary, $after . ($tag ? "</$tag>" : '') . "\n$mark");
				next;
			}
		}

		#-----------------------------------------------------
		# エスケープ記法の置換処理
		#-----------------------------------------------------
		if ($st->{atag}) {
			# 行末 \ による行連結
			while($self->{chain_line} && substr($line, -1) eq "\\") {
				chop($line);
				$line  =~ s/ +$//;	# \ の手前のスペース除去
				$line .= shift(@$lines);
			}
			# TeXモード
			if ($self->{tex_mode}) {
				$line =~ s/\$\$(.*?)\$\$/'[[mathd:' . &tex_escape($1) . ']]'/eg;
				$line =~ s/\$(.*?)\$/    '[[math:'  . &tex_escape($1) . ']]'/eg;
				$line =~ s/\\ref(a)?\{([^\]\}]*)\}/[mref$1:$2]/g;
			}
			# mini verbatim表記  {xxx}, {<tag>}, {[xxx:tag]}
			$line =~ s/\\([\{\}])/ "\x01#" . ord($1) . ';'/eg;	# { } のエスケープ
			$line =~ s/\{\{(.*?)\s?\}\}|(\[\[.*?\]\])/
				$2 ? $2 : $self->mini_pre($1) /eg;		# mini pre {{ xxx }}
			$line =~ s/\{(.*?)\s?\}|(\[\[.*?\]*\]\])/
				$2 ? $2 : $self->mini_verbatim($1) /eg;		# mini varbatim {<xxx>}
			# $line =~ tr/\x01/&/;	# \x01 を & に戻す
			$line =~ s/\x01#(\d+);/chr($1)/eg;	# { } を戻す

			# マクロ展開
			$line =~ s!\[\*([^:\]]*)(:[^]]*)?\]!
				if ($macros->{$1}) {
					my @ary = @{ $macros->{$1} };
					my $opt = $2;
					if ($opt ne '') {
						foreach(@ary) {
							$_ =~ s/\#0/$opt/g;
						}
					}
					unshift(@$lines, @ary);
				}
				'';
			!eg;
		}
		#-----------------------------------------------------
		# コメント除去
		#-----------------------------------------------------
		if ($st->{atag}) {
			$line =~ s/<!--.*?-->//g;		# コメント除去
			my $x = index($line, '<!--');
			if ($x >= 0) {				# コメントがある
				$in_comment = 1;
				$line = substr($line, 0, $x);	# 手前
			}
		}

		#-----------------------------------------------------
		# 自由変数、内部変数書き換え処理
		#-----------------------------------------------------
		if ($st->{atag} && substr($line,0,3) eq ':::') {
			# 自由変数に設定
			# 記法タグの部分で処理する
			push(@$ary, $line);
			next;

		} elsif ($st->{atag} && $list_mark ne ':' && substr($line,0,2) eq '::' && length($line)>2) {
			# クラス指定表記 / 内部変数書き換え
			$class = substr($line, 2);
			if ($class =~ /^(\w+)\s*=\s*(.*)/) {
				# 一時的な内部変数書き換え（記法タグの時も処理する）
				if ($allow_override{$1}==1) {
					$self->{$1}=$2;
					push(@$ary, "::$1=$2");
					$self->tag_escape( $self->{$1} );
				} elsif ($allow_override{$1}==2) {
					$self->{$1}=int($2);
					push(@$ary, "::$1=$self->{$1}");
				}
				if (lc($1) ne 'id') {
					$class='';
					next;
				}
			}
			$class = $self->parse_class_id($class);
			next;
		}
		#-----------------------------------------------------
		# ブロックの終わり
		#-----------------------------------------------------
		my $block_end = ($end && $line eq $end);
		if ($block_end) {
			# リストブロックやテーブルを強制的に終わらせる
			$line = '';
			$blank = 1;
		}

		#-----------------------------------------------------
		# リストブロックの抽出
		#-----------------------------------------------------
		my $s1 = substr($line, 0, 1);
		my $s2 = substr($line, 0, 2);
		if ($s1 eq '+') { $s1='-'; }

		if ($st->{atag} && !$list_mark
		&& ($s1 eq '-' || ($s1 eq ':' && $s2 ne '::')) ) {
			$list_mark = $s1;
			$list_ext  = (length($line) == 1);	# 拡張リストブロック
			$ary_bak = $ary;
			$ary = [];
			if (!$list_ext) {
				push(@$ary, $line);
			}
			next;
		}
		# 今の行はリストではない
		if ($list_mark && ($blank || !$list_ext && $s1 ne $list_mark)) {
			my $list = $ary;
			$ary = $ary_bak;
			if ($list_mark eq ':') {
				$self->parse_list_dl($ary, $list, $class);
			}
			if ($list_mark eq '-') {
				$self->parse_list_ulol($ary, $list, 1, $class);
			}
			$list_mark='';
			$class='';
		}

		#-----------------------------------------------------
		# テーブルの処理
		#-----------------------------------------------------
		if ($st->{atag} && $s1 eq '|') {
			push(@table, $line);
		}
		if (@table) {
			if ($block_end || substr($lines->[0], 0, 1) ne '|') {
				$self->parse_table( $ary, \@table, $class );
				@table = ();
			}
			if (!$block_end) { next; }
		}

		#-----------------------------------------------------
		# ブロックの終わり
		#-----------------------------------------------------
		if ($block_end) {
			last;
		}

		#-----------------------------------------------------
		# 平文処理
		#-----------------------------------------------------
		# ブロック中は見出し記法を常に無効に
		if (! $st->{top} && $st->{atag}) {
			$line =~ s/^\*/&#42;/;
		}
		# htmlタグ無効
		if (! $st->{htag}) {
			$line =~ s/&/&amp;/g;
			$line =~ s/</&lt;/g;
			$line =~ s/>/&gt;/g;
		}

		# ブロック中コメント機能
		if ($st->{bcom}) {
			$line =~ s/##(\{(.+?)\}|\[(.+?)\]|\|(.+?)\|)/<strong class="comment">$2$3$4<\/strong>/g;
			$line =~  s/#(\{(.+?)\}|\[(.+?)\]|\|(.+?)\|)/<span class="comment">$2$3$4<\/span>/g;
		}

		# [tag] 形式の記法タグが無効
		if (! $st->{atag} && $st->{bcom}) {
			# ((?)) 注釈だけ有効にする：ブロック中コメント機能
			$line =~ s/([\[\]\{\}\|:])/'&#' . ord($1) . ';'/eg;
			$line =~ s/^([\-\+\*=])/   '&#' . ord($1) . ';'/e;
		} elsif (! $st->{atag}) {
			$line =~ s/([\[\]\{\}\|:\(\)])/'&#' . ord($1) . ';'/eg;
			$line =~ s/^([\-\+\*=])/       '&#' . ord($1) . ';'/e;
		} elsif ($end) {
			# ブロック中は続きを読む表記を無効化
			$line =~ s/^====/&#61;===/;
		}

		#-----------------------------------------------------
		# リストブロック中
		#-----------------------------------------------------
		if ($list_mark) {
			push(@$ary, $line);
			next;
		}

		#-----------------------------------------------------
		# 行処理
		#-----------------------------------------------------
		# 強制行末改行モード
		if ($st->{br}) {
			$line .= "<br>";
		}
		# 段落処理なしモード
		if (! $st->{p}) {
			push(@$ary, "$line\n\x01");	# \x01 インデント抑止マーク
			next;
		}

		if ($line eq '' ) {
			if (! $blank) { next; }
			my $c = 1;
			while($#$lines >= 0) {
				if ($lines->[0] ne '') { last; }
				shift(@$lines);
				$c++;
			}
			push(@$ary, {null_lines => $c});
			next;
		}
		#-----------------------------------------------------
		# 通常行
		#-----------------------------------------------------
		push(@$ary, "$line$blk_mark");
	}
	return $ary;
}

#-------------------------------------------------------------------------------
# ●ミニ verbatim 記法
#-------------------------------------------------------------------------------
sub mini_verbatim {
	my ($self, $line) = @_;
	$self->tag_syntax_escape($line);	# tagエスケープ
	return $line;
}

#-------------------------------------------------------------------------------
# ●ミニ pre 記法
#-------------------------------------------------------------------------------
sub mini_pre {
	my ($self, $line) = @_;
	$self->tag_syntax_escape($line);	# tagエスケープ
	return "<span class=\"mono\">$line</span>";
}

#-------------------------------------------------------------------------------
# ●リストブロックのパース (ul/ol)
#-------------------------------------------------------------------------------
sub parse_list_ulol {
	my $self = shift;
	my ($ary, $lines, $depth, $class) = @_;

	my $tag    = substr($lines->[0], 0, 1) eq '-' ? 'ul' : 'ol';
	my $indent = "\t" x ($depth-1);
	push(@$ary, "$indent<$tag$class>\n");

	my $li;
	while(@$lines) {
		if ($lines->[0] !~ /^([\+\-]+)\s*(.*)/) { last; }
		my $length = length($1);
		my $data   = $2;
		if ($length < $depth) { last; }
		if ($length > $depth) {
			if ($li) {
				if ($li !~ /^\t*$/) { push(@$ary, "$li\n"); }
				$li='';
				$self->parse_list_ulol($ary, $lines, $depth+1);
				push(@$ary, "$indent\t</li>\n");
				next;
			}
			$self->parse_list_ulol($ary, $lines, $depth+1);
			next;
		}
		shift(@$lines);
		if ($li) { push(@$ary, "$li</li>\n"); }

		if ($data =~ /^=(\d+)(?:\s+(.*))?/) {	# 項目値指定
			$li = "$indent\t<li value=\"$1\">$2";
		} else {
			$li = "$indent\t<li>$data";
		}

		# 拡張リスト処理
		my $out = $self->list_line_chain( $li, $lines, {'-' => 1, '+' => 1} );
		$li = pop(@$out);
		push(@$ary, @$out);
	}
	if ($li) { push(@$ary, "$li</li>\n"); }
	push(@$ary, "$indent</$tag>\n");
}

#-----------------------------------------------------------
# 拡張リストの行連結
#-----------------------------------------------------------
sub list_line_chain {
	my $self = shift;
	my ($str, $lines, $h) = @_;
	my @out = ($str);
	while(@$lines && !$h->{ substr($lines->[0],0,1) }) {
		my $line = shift(@$lines);
		if ($line =~ /[\n\x01\x02]$/ || ref($line) 
		 || $out[$#out] =~ /[\n\x01\x02]$/ || ref($out[$#out])) {
			push(@out, $line);
			next;
		}

		my $br;
		if ($self->{list_br}) { $br="<br>\n"; }
		else {
			$br = $self->acsii_line_chain($out[$#out], $line) ? "\n" : '';
		}
		$out[$#out] .= $br . $line;
	}
	if ($#out > 0) {	# うしろに連結するものがあったら
		$out[0] =~ s/\n*$/\n/;	# 最初の行を、行処理済とする。
	}
	return \@out;
}

#-------------------------------------------------------------------------------
# ●リストブロックのパース (dl)
#-------------------------------------------------------------------------------
sub parse_list_dl {
	my $self = shift;
	my ($ary, $lines, $class) = @_;

	push(@$ary, "<dl$class>\n");
	while(@$lines) {
		my $line = shift(@$lines);

		# タグ中の : を処理しないため、先にタグを処理する
		$line = $self->parse_tag($line);

		my ($dummy, $dt, $dd) = split(/\s*:\s*/, $line, 3);
		$dt = $dt ne '' ? $dt="<dt>$dt</dt>" : "\t";

		my $out = $self->list_line_chain( $dd, $lines, {':' => 1} );
		$dd = pop(@$out);
		if (@$out) {
			push(@$ary, "\t$dt<dd>" . shift(@$out));
			push(@$ary, @$out, "$dd</dd>\n");
		} else {
			if ($dd ne '') { $dd="<dd>$dd</dd>"; }
			if ($dt ne "\t" || $dd ne '') {
				push(@$ary, "\t$dt$dd\n");
			}
		}
	}
	push(@$ary, "</dl>\n");
}

#-------------------------------------------------------------------------------
# ●TABLEのパース
#-------------------------------------------------------------------------------
sub parse_table {
	my $self = shift;
	my ($ary, $lines, $class) = @_;

	my $caption;
	my $summary;

	#-------------------------------------------------------------
	# 各行処理
	#-------------------------------------------------------------
	my @rows;
	my $tr_class = '';
	my $td_class = [];
	foreach my $line (@$lines) {
		if (substr($line,0,3) eq '|::') {
			# th, td クラス指定
			my $class = substr($line,3);
			$class =~ s/[^\w\-\| ]//g;
			if (substr($class,0,1) ne '|') {
				$tr_class = $class;
				next;
			}
			$td_class = [ split(/\s*\|\s*/, $class) ];
			shift(@$td_class);
			next;
		}
		# caption / summary
		if (substr($line,-1) ne '|') {
			my $s9 = substr($line,0,9);
			if ($s9 eq '|caption=') {
				$caption = substr($line,9);
				next;
			}
			if ($s9 eq '|summary=') {
				$summary = substr($line,9);
				next;
			}
		}

		# |aa|bb|cc  → |aa|bb|cc|*
		# |aa|bb|cc| → |aa|bb|cc|*
		$line  =~ s/\|?\s*$/|/;
		$line .= '*';
		my @l = split(/\s*\|\s*/, $line);
		pop(@l);	# 最後を読み捨て
		shift(@l);	# 最初を読み捨て

		my @cols;
		foreach(0..$#l) {
			my $x = $l[$_];
			my $h = {cols=>1, rows=>1};
			$h->{class} = $td_class->[$_];

			if (substr($x,0,1) eq '*') {
				$h->{th}   = 1;
				$h->{data} = substr($x,1);
			} elsif ($x eq '<' && $#cols >= 0) {	# 左連結
				$h = $cols[$#cols];
				$h->{cols} ++; 
			} elsif (($x eq '~' || $x eq '^') && $#rows >= 0 && $_ < $#{ $rows[$#rows] }) {	# 上連結
				$h = $rows[$#rows]->[$_];
				$h->{rows} ++;
			} else {
				$h->{data} = $x;
			}
			push(@cols, $h);
		}
		if ($#cols > 0) {
			foreach(reverse(0..($#cols-1))) {
				if ($cols[$_]->{data} eq '>') {	# 右連結
					$cols[$_] = $cols[$_+1];
					$cols[$_]->{cols} ++;
				}
			}
		}
		push(@cols, $tr_class);
		push(@rows, \@cols);
	}
	if (!@rows) { return ; }

	# 下に連結？
	foreach my $row_num (reverse(0..($#rows-1))) {
		my $cols = $rows[$row_num];
		foreach(0..($#$cols-1)) {
			my $h = $cols->[$_];
			if ($h->{data} eq '_' && ref($rows[$row_num+1]->[$_])) {
				$h = $rows[$row_num]->[$_] = $rows[$row_num+1]->[$_];
				$h->{rows}++;
			}
		}
	}

	#-------------------------------------------------------------
	# テーブルの出力
	#-------------------------------------------------------------
	# caption & summary
	$self->tag_syntax_escape($summary);	# 記法タグも escape
	$self->tag_escape($caption);
	if ($summary ne '') { $summary="<!-- summary=$summary -->"; }

	# 出力
	push(@$ary, "<table$class>$summary\n");
	if ($caption ne '') { push(@$ary, "<caption>$caption</caption>\n"); }

	my $thead_flag;
	if (1 < $#rows) {
		# テーブルの行が２行以上あり、最初の行がすべて th ならば、
		# その部分を thead として認識する。
		my $cols=$rows[0];
		$thead_flag = 1;
		foreach(@$cols) {
			if (ref($_) && ! $_->{th}) { $thead_flag=0; last; }
		}
	}
	
	if ($thead_flag) { push(@$ary, "<thead>\n"); }
		    else { push(@$ary, "<tbody>\n"); }
	while(@rows) {
		my $cols = shift(@rows);
		my $tr_class = pop(@$cols);
		my $line;
		my $th_only = 1;
		foreach(0..$#$cols) {
			my $h = $cols->[$_];
			if ($h->{output}) { next; }	# １度出力したものは出力しない
			# 出力
			$h->{output} = 1;
			my $at;
			if ($h->{cols} >1) { $at .= " colspan=\"$h->{cols}\""; }
			if ($h->{rows} >1) { $at .= " rowspan=\"$h->{rows}\""; }
			if ($h->{class})   { $at .= " class=\"$h->{class}\"";  }
			if ($h->{th}) {
				$line .= "<th$at>$h->{data}</th>";
			} else {
				$th_only = 0;
				$line .= "<td$at>$h->{data}</td>";
			}
		}
		if ($thead_flag && !$th_only) {
			push(@$ary, "</thead><tbody>\n");
			$thead_flag = 0;
		}
		push(@$ary, "\t<tr class=\"$tr_class\">$line</tr>\n");
	}
	push(@$ary, "</tbody></table>\n");
}

################################################################################
# ■[02] セクション処理、目次処理
################################################################################
sub parse_section {
	my ($self, $lines) = @_;
	my @out;

	# 行頭改行無視
	if (ref($lines->[0]) eq 'HASH') { shift(@$lines); }

	#-----------------------------------------------------------------------
	# main loop
	#-----------------------------------------------------------------------
	my $seemore;
	my $cur_anchor='';
	while($#$lines >= 0) {
		my $line = shift(@$lines);

		#---------------------------------------------------------------
		# 処理済み行は飛ばす
		#---------------------------------------------------------------
		my $end_mark = substr($line, -1);		# \n/\x01 で終わる行は処理済み
		if (ref($line) eq 'HASH' || $end_mark eq "\n" || $end_mark eq "\x01") {
			push(@out, $line);
			next;
		}
		# 変数書き換え記法を読み飛ばす
		if (substr($line,0,2) eq '::') {
			push(@out, $line);
			next;
		}

		#---------------------------------------------------------------
		# セクション
		#---------------------------------------------------------------
		if ($line =~ m|^(\*+)(?:([\w\-\./: ]+)\*)?\s*(.*)|) {
			my $level = length($1);
			my $name  = $2;
			my $title = $3;

			if ($level==1 && @out) {
				push(@out, {section_end => 1});
				push(@out, "</section>\n");
				push(@out, "<section>\n");
			}

			# セクション情報の生成
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
			my $id    = $self->generate_id_from_string($name || $title, 'p' . $num);

			# generate section number
			my $number='';
			if ($self->{section_number}) {
				$number = $self->{section_prefix} . $num . $self->{section_suffix};
				my $start = $self->{section_start};
				if ($start ne '' && $start != 1) {
					$number =~ s/^(\d+)/
						$1 +$start -1
					/eg;
				}
			}
			my $num_text = '';
			if ($number ne '') {
				$num_text = " <span class=\"section-number\">$number</span> ";
			}

			# save section information
			my $sec = {
				id	=> $id,
				num	=> $num,
				number  => $number,
				title	=> $title,
				count	=> $count
			};
			$cur_anchor = $id;	# for seemore
			push(@$secs, $sec);

			# output html
			my $h  = $self->{section_hnum} + $level -1;
			my $tm = ($level==1) ? $self->make_section_timestamp($name) : '';

			if (6 < $h) { $h=6; }
			push(@out, "$self->{indent}<h$h id=\"$id\"><a href=\"$self->{thisurl}#$id\">$num_text$title</a>$tm</h$h>\n");

			# タグ処理
			$sec->{title} = $self->parse_tag( $sec->{title} );	# タグ処理
			$sec->{title} =~ s/\(\(.*?\)\)//g;			# 注釈の削除
			next;
		}

		#---------------------------------------------------------------
		# 続きを読む
		#---------------------------------------------------------------
		if ($line =~ /^=====?/) {
			if ($seemore) { next; }
			$seemore = 1;
			my $msg = $self->{seemore_msg} || 'See More...';
			push(@out, "$self->{indent}<p class=\"seemore\"><a href=\"$self->{thisurl}#$cur_anchor\">$msg</a></p><!--%SeeMore%-->\n");
			next;
		}

		#---------------------------------------------------------------
		# 行頭 - * の手前に半角スペースを置くエスケープ処理対応
		#---------------------------------------------------------------
		if (ord($line) == 0x20 && index(' - + * | : = > < #', substr($line, 0, 2)) > 0) {
			push(@out, substr($line, 1));
			next;
		}
		#---------------------------------------------------------------
		# 通常行
		#---------------------------------------------------------------
		push(@out, $line);
	}

	#-----------------------------------------------------------------------
	# 後処理
	#-----------------------------------------------------------------------
	unshift(@out, "<section>\n");
	push(@out, {section_end => 1});
	push(@out,'',"</section>\n");

	return \@out;
}

#-------------------------------------------------------------------------------
# ●section timestamp
#-------------------------------------------------------------------------------
sub make_section_timestamp {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $tm;
	if ($name >= 100000000) {	# 時刻記法
		my $ROBJ   = $self->{ROBJ};
		my $format = $self->{timestamp_date} || '%Y/%m/%d';
		$tm = $ROBJ->tm_printf($format, $name);
	} elsif (  $name =~ m|^\d+/\d+(?:/\d+)?(?: \d+:\d+)?$|
		|| $name =~ m|^\d+-\d+(?:-\d+)?(?: \d+:\d+)?$|
		|| $name =~ m|^\d+:\d+$|)
	{
		$tm = $name;
	} else {
		return;
	}
	return " <span class=\"timestamp\">$tm</span>";
}

################################################################################
# ■[03] 記法タグの処理
################################################################################
sub replace_original_tag {
	my ($self, $lines) = @_;

	sub tex_escape() {
		my $t = shift;
		$t =~ s/([\[\{])/"&#" . ord($1) . ';'/eg;
		return $t;
	}

	my @ary;
	foreach(@$lines) {
		if (ref($_)) { push(@ary, $_); next; }

		# 自由変数書き換え
		if ($_ =~ /^:::([^\s]+)\s*=\s*(.*)/) {
			my $n = $1;
			my $v = $2;	# 自由変数定義中の記法タグを処理
			$self->{vars}->{$n} = $self->parse_tag( $v );
			next;
		}
		# 内部変数書き換え
		if ($_ =~ /^::(\w+)=(.*)/ && $allow_override{$1}) {
			$self->{$1} = $2;
			next;
		}

		$_ = $self->parse_tag( $_ );

		# 記法置き換えで行が空になった
		if ($_ eq '') { next; }

		push(@ary, $_);
	}

	return \@ary;
}

#---------------------------------------------------------------------
# ○タグのパースと処理
#---------------------------------------------------------------------
sub parse_tag {
	my $self = shift;
	my $this = shift;
	my $post_process = shift;	# markdown記法で使用

	# [[ ]] タグを先行処理
	my $count=0;
	while ($this =~ /(.*?)(\[\[)(.*?)\]\](.*)/s || $this =~ /(.*?)(\[)((?:\\\[|\\\]|[^\[\]])+)\](.*)/s) {
		my $p0  = $1;
		my $cmd = $3;
		my $p1  = $4;
		$cmd = $self->special_command( $cmd, {verb => ($2 eq '[[')} );
		$cmd =~ s/\(/&#40;/g;
		$cmd =~ s/\[/&#91;/g;
		$cmd =~ s/\]/&#93;/g;
		$cmd =~ s/:/&#58;/g;
		if ($post_process) { $cmd = &$post_process($cmd); }
		$this = $p0 . $cmd . $p1;
		$count++;
		if ($count>99) { last; }
	}
	return $this;
}

#---------------------------------------------------------------------
# ○コマンドの処理
#---------------------------------------------------------------------
sub special_command {
	my $self     = shift;
	my $cmd_line = shift;
	my $opt  = shift || {};
	my $tags = $self->{tags};
	my $orig = $cmd_line;

	# 特殊コマンド処理
	# [&icon-name] → [icon:icon-name]
	$cmd_line =~ s/^&(\w+)$/icon:$1/g;
	# [&http://youtube.com/] → [filter:http://youtube.com]
	$cmd_line =~ s/^&([^#].*)$/filter:$1/g;

	# 自由変数置換
	if ($cmd_line =~ /^\$(.*)$/) {
		$cmd_line = $self->{vars}->{$1};
		$cmd_line =~ s/\$/&#36;/g;
		return $cmd_line;
	}

	# cmd:arg1:arg2 ... のパース
	if (!$opt->{verb}) {
		$cmd_line =~ s/\\([\[\]])/$1/g;
		$cmd_line =~ s/\\:/\x00/g;
	}
	
	my @cmd = map { s/\x00/:/g; $_ } split(':', $cmd_line);
	my $cmd = shift(@cmd);
	while (exists $tags->{ "$cmd:$cmd[0]" } && @cmd) {	# 連結コマンド
		$cmd = $cmd . ':' . shift(@cmd);
	}

	if (exists $tags->{ $cmd }) {
		my $tag = $self->load_tag($cmd);
		# verb環境？
		if ($opt->{verb}) {
			@cmd = ( join(':', @cmd) );
		}
		# alias 処理
		my $real_cmd = $cmd;
		if ($tag->{alias}) {
			$real_cmd = $tag->{alias};
			$tag      = $self->load_tag($real_cmd);
		}
		# 引数指定あり？
		my $arg_cmd = $real_cmd . '##' . ($#cmd +1);
		if (exists $tags->{ $arg_cmd }) {
			$tag = $tags->{ $arg_cmd };
		} else {
			my $x = $#cmd + 1;
			$x=0;
			foreach(@cmd) {
				if ($_ =~ /[\x80-\xff]/) { last }
				if (substr($_,-1) eq ' ') {	# 最後がスペースの引数
					chop($_);
					last;
				}
				$x++;
			}
			my $arg_cmd = $real_cmd . '#' . $x;
			if (exists $tags->{ $arg_cmd }) { $tag = $tags->{ $arg_cmd }; }
		}

		# 置換処理呼び出し
		my $data   = $tag->{data};
		my $option = $self->load_tag("&$tag->{option}");	# 特殊オプション？

		if (ref($option)) {		# 特殊オプションによる置換
			return &$option($self, $tag, $cmd, \@cmd);
		} elsif (ref($data)) {		# CODE ref のときは指定の専用ルーチンコール
			return &$data($self, $tag, $cmd, \@cmd);
		} elsif($tag->{html}) {		# HTML置換タグ
			return $self->html_tag($tag, \@cmd);
		} elsif($data) {		# それ以外のときは汎用検索置換ルーチンへ
			return $self->search($tag, $cmd, \@cmd);
		}
	}
	# 未知のコマンド
	return $opt->{verb} ? "[[$orig]]" : "[$orig]";
}

sub load_tag {
	my $self = shift;
	my $cmd = shift;
	my $tag = $self->{tags}->{$cmd};
	if (ref($tag) eq 'CODE') { return $tag; }
	if ($tag->{plugin}) {
		$self->eval_load_plugin( $tag->{plugin} );
	}
	return $self->{tags}->{$cmd};
}

#-------------------------------------------------------------------------------
# ●記法タグルーチン
#-------------------------------------------------------------------------------
#---------------------------------------------------------------------
# ●htmlタグ置換
#---------------------------------------------------------------------
sub html_tag {
	my ($self, $tag, $ary) = @_;
	my ($name, $class) = split('\.', $tag->{html});
	if ($class ne '') { $class=" class=\"$class\""; }
	if (!@$ary) { return "<$name$class$tag->{attribute}></$name>"; }
	return "<$name$class$tag->{attribute}>" . join(':', @$ary) . "</$name>";
}

#---------------------------------------------------------------------
# ●汎用リンク置換（記法タグ）
#---------------------------------------------------------------------
sub search {
	my ($self, $tag, $cmd, $ary) = @_;
	my $ROBJ = $self->{ROBJ};

	# Query 構成
	my $code = $tag->{option};
	my $argc = $tag->{argc};
	my $url  = $tag->{data};

	my @argv = splice(@$ary, 0, $argc);
	if ($#$ary>=0 && $tag->{replace_html}) {
		# タグそのままのとき、最後を連結。
		# 2引数 [color:red:xxx:yyy] を "red" / "xxx:yyy" にする
		$argv[$argc-1] .= ':' . join(':', @$ary);
		@$ary = ();
	}

	# リンク置換
	my $name = join(':', @argv);
	$url = $self->replace_link($url, \@argv, $argc, $code);

	# タグそのまま
	if ($tag->{replace_html}) {
		$url =~ s/&quot;/"/g;
		return $url;
	}

	# リンク構成
	my $class = $self->make_attr($ary, $tag, 'http');
	   $name  = $self->make_name($ary, $name);

	return "<a href=\"$url\"$class>$name</a>";
}

#---------------------------------------------------------------------
# ●link文字列の置換処理
#---------------------------------------------------------------------
sub replace_link {
	my $self = shift;
	my ($url, $ary, $argc, $code) = @_;
	my $ROBJ = $self->{ROBJ};
	my $rep  = $self->{vars};

	my @argv = splice(@$ary, 0, $argc);
	unshift(@argv, join(':', @argv));	# for $0/#0
	$url =~ s/\#(\d)/$argv[$1]/g;		# 文字コード変換前

	if ($code eq 'ASCII' || $code !~ /[A-Z]/) { $code=''; }
	my $jcode = $code ? $ROBJ->load_codepm() : undef;

	foreach(@argv) {
		if ($jcode) { $jcode->from_to(\$_, $ROBJ->{System_coding}, $code); }
		$self->encode_uricom($_);
	}
	$url =~ s/\$(\d)/$argv[$1]/g;		# 文字コード変換後
	$url =~ s/\$\{(\w+)\}/$rep->{$1}/g;	# 任意データ置換
	return $url;
}

#---------------------------------------------------------------------
# ●replace_varsのみ (for Tag-Plugin)
#---------------------------------------------------------------------
sub replace_vars {
	my $self = shift;
	my $url = shift;
	my $h = $self->{vars};
	$url =~ s/\$\{(\w+)\}/$h->{$1}/g;	# 任意データ置換
	return $url;
}

################################################################################
# ■[04] 段落/改行処理
################################################################################
sub paragraph_processing {
	my ($self, $lines) = @_;

	my $br_mode  = $self->{br_mode};
	my $p_mode   = $self->{p_mode};
	my $p_class  = $self->{p_class};
	my $ls_mode  = $self->{ls_mode};		# 行間処理モード
	my $indent   = $self->{indent};

	# p class処理
	$p_class =~ s/[^\w\-]//g;
	if ($p_class ne '') { $p_class = " class=\"$p_class\""; }

	# 処理前準備
	my ($prev, $next, $this, $prev_f, $this_f, $next_f);
	push(@$lines, "\x01");

	# 注釈準備
	my @footnote;
	my %note_hash;
	$self->init_footnote();

	my @ary;
	my $in_paragraph  = 0;
	foreach(@$lines) {
		# モジュールのみの行を段落処理しないでdivブロック化する
		if ($_ =~ /^\s*(?:<module [^>]*>\s*)+\s*$/) {
		 	$_ = "<div class=\"module\">$_</div>\n";
		}
		# figureのみの行を段落処理しない
		if ($p_mode && $_ =~ m|^\s*<figure>.*</figure>\s*$|) {
		 	$_ .= ($p_mode==1 || $br_mode==1 ? '<br>' : '') . "\n";
		}

		# 行送り措置
		$prev = $this; $prev_f = $this_f;
		$this = $next; $this_f = $next_f;
		$next = $_;    $next_f = 0;

		my $f = substr($_,-1);
		if ($f eq "\x01") { $next_f= 1; chop($next); }	# インデント抑止
		if ($f eq "\n")   { $next_f=10;  }
		if (ref($_))      { $next_f=256; }
		if (!defined $this) { next; }

		# 前後のどちらかがコマンド
		my $flag = $prev_f + $next_f;

		# Section(H3) の終わり
		if (ref($this) && $this->{section_end}) {
			$self->output_footnote(\@ary, \@footnote, \%note_hash);
			next;
		}
		# 空行？
		if (ref($this)) {
			my $null_lines = $this->{null_lines};
			if (! $ls_mode) {	# 行間処理をしないモード
				push(@ary, "$indent\n" x $null_lines);
				next;
			}
			if ($flag || $p_mode) { $null_lines--; } 
			push(@ary, "$indent<br>\n" x $null_lines);
			next;
		}
		# 注釈処理 ((xxxx))
		$this =~ s/\(\((.*?)\)\)/ $self->footnote($1, \@footnote, \%note_hash) /eg;

		# 段落処理
		if ($this_f==1) { push(@ary, $this);          next; } # インデントなし
		if ($this_f)    { push(@ary, "$indent$this"); next; } # 処理済み行はインデントのみ
		if ($p_mode==1) { push(@ary, "$indent<p$p_class>$this</p>\n"); next; } # １行＝１段落
		if (! $p_mode)  {	# 段落処理なし
			if ($br_mode==1) { push(@ary, "$indent$this<br>\n"); }	# 改行処理
			else  {
				if ($br_mode==2) { $this =~ s/\s\s+$/<br>/;  }	# 行末スペースを改行に変換
				push(@ary, "$indent$this\n");
			}
			next;
		}
		if ($p_mode==2) {	# 空行で段落処理
			my $head = '';
			if (! $in_paragraph) { $head="$indent<p$p_class>"; $in_paragraph=1; } # 段落の始まり 
			elsif ($br_mode==1)  { $head="$indent";   }                           # 改行処理モード
			if ($br_mode==2 && !$next_f) {		# 段落の終わりではない
				$this =~ s/\s\s+$/<br>/;	# 行末スペースを改行に変換
			}
			push(@ary, "$head$this");
			if ($next_f) {		# ここで段落の終わり
				push(@ary, "</p>\n");
				$in_paragraph=0;
				next;
			}
			if ($br_mode==1) { push(@ary, "<br>\n"); }	# 改行処理
			elsif ($self->acsii_line_chain($this,$next)) {
				# 行連結するとき、ASCII文字中である場合は改行を残す
				push(@ary, "\n");
			}
			next;
		}
	}
	return \@ary;
}
sub acsii_line_chain {
	my $self = shift;
	my ($prev, $this) = @_;
	return ord(substr($prev,-1))<0x80 && ord(substr($this,0,1))<0x80;
}

#---------------------------------------------------------------------
# ○脚注表記
#---------------------------------------------------------------------
sub init_footnote {
	my $self = shift;
	$self->{footnote_no} = 0;
}
sub footnote {
	my $self = shift;
	my $note = shift;
	my $buf  = shift;
	my $hash = shift || {};

	# 同じ内容は、同じfootnoteを参照する
	my $number;
	my $name;
	my $name_base = 'fn';
	if (exists $hash->{$note}) {	# 同じ内容注釈がある
		$number = $hash->{$note};
		$name   = "$name_base$number";
	} else {
		$hash->{$note} = $number = (++ $self->{footnote_no});
		$name   = "$name_base$number";
		push(@$buf, <<HTML);
	<p class="footnote"><a href="$self->{thisurl}#fnt-$name" id="fn-$name">*$number</a> : $note</p>
HTML
	}
	$self->tag_delete($note);
	$note =~ s/"/&quot;/g;

	return "<span class=\"footnote\"><a title=\"$note\" href=\"$self->{thisurl}#fn-$name\" id=\"fnt-$name\">*$number</a></span>";
}

#---------------------------------------------------------------------
# ○脚注表記の出力
#---------------------------------------------------------------------
sub output_footnote {
	my $self = shift;
	my $out  = shift || [];
	my $buf  = shift;
	my $hash = shift || {};
	my $indent = $self->{indent};
	if (@$buf) {
		push(@$out, "$indent<footer>\n");
		foreach(@$buf) {
			push(@$out, "$indent$_");
		}
		push(@$out, "$indent</footer>\n");
	}
	@$buf  = ();
	%$hash = ();
	return $out;	# used by Markdown.pm
}

################################################################################
# ■[99] ポストプロセス
################################################################################
sub post_process {
	my $self = shift;
	my $rtxt = shift;

	# エスケープした文字を復元
	$self->un_escape( $$rtxt );

	# 目次の処理
	$$rtxt =~ s|<toc>(.*?)</toc>|$self->post_toc($1)|eg;
}

sub post_toc {
	my $self = shift;
	my $arg  = shift;
	my $opt  = {};
	foreach(split(':', $arg)) {
		if ($_ =~ /^(\w+)=(.*)$/) {
			$opt->{$1} = $2;
			next;
		}
		$opt->{$_}=1;
	}
	my $c = $self->normalize_class_string( $opt->{class} );
	$opt->{class} = $self->chain_class("toc", $c, exists($opt->{none}) ? 'none' : '');

	my $secs = $self->{sections};
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
		if ($_->{id} eq '') { next; }

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
			my $d = $depth eq '' ? '' : $depth-1;
			$out .=	$self->generate_toc($subs, $opt, $d, $level+1);
		}
		$out .= "</li>\n";
	}
	$out .= "$tab</ul>";
	return $out;
}

################################################################################
# ■記法タグのロードルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●記法タグの初期化
#-------------------------------------------------------------------------------
sub init_tags {
	my $self = shift;
	$self->{tags} = {};
	$self->{macros} = {};
}

#-------------------------------------------------------------------------------
# ●プラグインをロードする
#-------------------------------------------------------------------------------
sub load_plugins {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir = shift;

	if (!$dir) {
		$INC{'Satsuki/TextParser/Satsuki.pm'} =~ m|(.*/)\w+\.\w+|;
		$dir=$1 . "TagPlugin/";
	}

	my $cfile = $self->{plugin_cache_file};
	my $x = $ROBJ->get_lastmodified($cfile);
	my $y = $ROBJ->get_lastmodified_in_dir($dir);
	if ($x < $y) {
		return $self->generate_plugin_cache($cfile, $dir);
	}
	my $h = $ROBJ->fread_hash_cached($cfile);
	foreach(keys(%$h)) {
		$self->{tags}->{$_} = { plugin => $h->{$_} };
	}
}

sub generate_plugin_cache {
	my $self = shift;
	my $cfile= shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};

	my $files = $ROBJ->search_files($dir, {ext => '.pm'});
	map { s/^Tag_(\w+)\.pm$/$1/ } @$files;

	# キャッシュファイルが設定されてない場合は全ロードして戻る
	if ($cfile eq '') {
		foreach(@$files) {
			$self->eval_load_plugin($_);
			next;
		}
		return;
	}

	# キャッシュの生成
	my %h = ('::FileVersion' => 1);
	foreach my $f (@$files) {
		my $lines = $ROBJ->fread_lines("${dir}Tag_$f.pm");
		my $in_info;
		foreach(@$lines) {
			$_ =~ s/^\s*//;
			$_ =~ s/[\r\n]*$//;
			if (!$in_info) {
				if ($_ eq $INFO_BEGIN_MARK) { $in_info=1; }
				next;
			}
			if ($_ eq $INFO_END_MARK) { last; }
			#
			# プラグイン情報のパース
			#	$tags->{asin}
			if ($_ !~ /^\$tags->\{("|'|)?([^\}\"\']+)\1\}/) { next; }
			$h{$2} = $f;
			$self->{tags}->{$2} = { plugin => $f };
		}
	}
	# キャッシュに保存
	$ROBJ->fwrite_hash($cfile, \%h);
}


#-------------------------------------------------------------------------------
# ●タグ定義のロード
#-------------------------------------------------------------------------------
# タグデータ構造
# $tag = $tags{tag_name};
#	$tag{data}   = tag data
#	$tag{argc}   = argments for url data
#	$tag{option} = tag option
# (search only)
#	$tag{name}   = tag name
#	$tag{title}  = title
#	$tag{class}  = html style sheet class
# (alias or html tag)
#	$tag{alias}  = alias to
#	$tag{html}   = html tag
sub load_tagdata {
	my ($self, $data, $allow_load) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file;
	if (!ref($data)) {
		$file = $data;
		if (!-r $file) { return; }
		$data = $ROBJ->fread_lines_cached( $file, {DelCR => 1} );
	}

	# 現在の設定ロード
	my $basepath = $ROBJ->{Basepath};
	my $tags   = $self->{tags};
	my $macros = $self->{macros};
	my @load_files;
	while(@$data) {
		my $line = shift(@$data);
		chomp($line);
		if (ord($line) == 0x23) { next; }		# 先頭'#'はコメント
		#---------------------------------------------------------------
		# プラグインロード？
		#---------------------------------------------------------------
		if ($line =~ /^plugin\s+(\w+)/i) {
			$self->eval_load_plugin($1);
			next;
		}
		#---------------------------------------------------------------
		# 他のファイルをロード
		#---------------------------------------------------------------
		if ($line =~ /^load\s+([\w\/\.]+)/i) {
			if ($allow_load) { push(@load_files, $ROBJ->get_relative_path($file, $1)); }
			next;
		}
		#---------------------------------------------------------------
		# マクロ定義
		#---------------------------------------------------------------
		if ($line =~ /^\*(.+?)\s*$/) {
			my $tag = $1;
			my @ary;
			while (@$data) {
				my $x = shift(@$data);
				if (ord($x) == 0x23) { next; }	# 先頭 # コメント
				chomp($x);
				if ($x =~ /^\s*$/) { last; }
				unshift(@ary,$x);
			}
			$macros->{$tag} = \@ary;
			next;
		}
		#---------------------------------------------------------------
		# タグ定義
		#---------------------------------------------------------------
		if ($line !~ /^([\w\-\+#:]+)\s*=\s*(.*?)\s*$/s) { next; }	# '=' のない行は無視
		my $tag   = $1;
		my $value = $2;
		$tag =~ s/[\"\']//g;
		my @ary = split(':', $tag);
		if ($#ary > 1) {	# : が２つ以上ある
			my $cmd = shift(@ary); pop(@ary);
			while (@ary) {
				$cmd .= ':' . shift(@ary);
				$tags->{$cmd} ||= {};
			}
		}

		# タグ定義処理
		my $tag_hash = $tags->{$tag} ||= {};

		if (substr($value,0,1) eq '>') {	# alias
			$tag_hash->{alias} = substr($value, 1);

		} elsif (substr($value,0,5) eq 'html:') { # HTMLタグ置換
			my $tag = substr($value, 5);
			$tag =~ s/>/&gt;/g;
			$tag =~ s/</&lt;/g;
			($tag_hash->{html}, $tag_hash->{attribute}) = split(/\s+/, $tag, 2);
			if ($tag_hash->{attribute} ne '') {
				$tag_hash->{attribute} = ' ' . $tag_hash->{attribute};
			}
		} elsif (substr($value,0,5) eq 'text:') { # text置換
			my $text = substr($value, 5);
			$text =~ s/^\s*(.*?)\s*$/$1/g;
			$tag_hash->{data} = $text;
			$tag_hash->{argc} = 9;
			$tag_hash->{replace_html} = 1;

		} elsif (substr($value,0,7) eq 'plugin:') { # プラグイン設定
			my $plg = substr($value, 7);
			if ($plg =~ /[^\w]/) { next; }
			$tag_hash->{plugin} = $plg;
		} else {
			if (substr($value,0,1) eq '<') {	# HTML置換
				$value = "$tag,ASCII,9," . $value;
			}
			# タグの（リンク）クラス
			my $class =$tag;
			$class =~ s/#.*//;
			$tag_hash->{name} = $class;
			$class =~ s/[^A-Za-z0-9 ]/-/g;
			$tag_hash->{class} = "$CSS_CLASS_PREFIX$class";
			# タイトルなど
			my ($title, $option, $url) = split(/\s*,\s*/, $value, 3);
			$self->tag_escape( $title, $option );
			if ($url =~ /^(\d+)\s*,\s*(.*)$/) {	# 受け取り引数指定
				$tag_hash->{argc} = $1;
				$url = $2;
			} else {
				$tag_hash->{argc} = 1;
				$url .= '$1';
			}
			$url =~ s/\"/&quot;/g;
			if ($title  ne '') { $tag_hash->{title}  = $title;  }
			if ($option ne '') { $tag_hash->{option} = $option; }
			if ($url eq 'block:') {	# block要素ならば、空行が出るまで読み込み
				$url = '';
				while(@$data) {
					my $add = shift(@$data);
					chomp($add);
					# $add =~ s/^\s*(.*?)\s*\n?$/$1/;	# 前後の空白除去
					if ($add eq '') { last; }
					$url .= $add;
				}
			}
			if ($url ne '') {
				if (substr($url,0,1) eq '<') {	# HTML置換
					$tag_hash->{replace_html}=1;
				}
				if ($url =~ /^html:(.*)/) {	# HTML置換
					$tag_hash->{replace_html}=1;
					$url = $1;
				}
				$tag_hash->{data} = $url;
			}
		}
	}
	# 他のファイルロード（エラーなし）
	foreach(@load_files) {
		$self->load_tagdata( $_ );
	}
}

#-------------------------------------------------------------------------------
# ●プラグインのロード
#-------------------------------------------------------------------------------
sub eval_load_plugin {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = shift;
	$file =~ s/[^\w]//g;
	# $ROBJ->debug("load tag plugin '$file'");
	eval{ $ROBJ->loadpm("${TAG_PLUGIN_CLASS}$file", $self->{tags}); };
	if ($@) { $ROBJ->error('[plugin load failed] %s', $@); }
}

################################################################################
# ■内部サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●タグエスケープ
#-------------------------------------------------------------------------------
sub tag_escape {
	my $self=shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->tag_escape(@_);
}

#-------------------------------------------------------------------------------
# ●タグ/記法記号のエスケープ（エンコード）
#-------------------------------------------------------------------------------
# 【注意】ここを修正したら、ブロック記法中のエスケープ部も修正すること！
sub tag_syntax_escape {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/"/&quot;/g;		# _~^* は table 記法用
		$_ =~ s/([\[\]\{\}\(\)\|:_~^*])/'&#' . ord($1) . ';'/eg;
	}
}

#-------------------------------------------------------------------------------
# ●タグの除去
#-------------------------------------------------------------------------------
sub tag_delete {
	my $self=shift;
	foreach(@_) {
		$_ =~ s/<\/.*?>//sg;
		$_ =~ s/<\w([^>"']|[=\s]".*?"|[=\s]'.*?')*?>//sg;
	}
}

#-------------------------------------------------------------------------------
# ●エスケープした文字の復元
#-------------------------------------------------------------------------------
sub un_escape {
	my $self=shift;
	foreach(@_) {	# ( ) [ ] { } | * ^ ~: = + - を復元
		$_ =~ s/&#(36|40|41|91|93|123|125|124|58|42|94|126|61|43|45);/chr($1)/eg;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●class/id表記の分離と解析
#-------------------------------------------------------------------------------
sub parse_class_id {
	my $self=shift;
	my $str=shift;
	my $id;
	$str =~ s/(?:^|\s)[Ii][Dd]=("?)([\w\-]+)\1/$id=$2,""/e;
	$str =~ s/^\s*(.*?)\s*$/$1/;
	$str =~ s/[^\w\-: ]//g;
	$str =~ s/\s+/ /g;
	
	my $r;
	$r  = ($str ne '' ? " class=\"$str\"" : '');
	$r .= ($id  ne '' ? " id=\"$id\"" : '');
	return $r;
}

#-------------------------------------------------------------------------------
# ●classの結合処理
#-------------------------------------------------------------------------------
sub make_class_attr {
	my $self  = shift;
	my $class = $self->chain_class(@_);
	if ($class eq '') { return; }
	return " class=\"$class\"";
}
sub chain_class {
	my $self = shift;
	my $class='';
	foreach(@_) {
		if ($_ eq '') { next; }
		$class .= $_ . ' ';
	}
	chop($class);
	return $class;
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
#-------------------------------------------------------------------------------
# ●class名の正規化
#-------------------------------------------------------------------------------
sub normalize_class_string {
	my $self  = shift;
	my $class = shift;
	$class =~ tr/A-Z/a-z/;
	$class =~ s/[^a-z0-9 ]+/-/g;
	$class =~ s/  +/ /g;
	$class =~ s/(^| )[\-\d]+/$1/g;
	return $class;
}

#-------------------------------------------------------------------------------
# ●URIエンコード
#-------------------------------------------------------------------------------
sub encode_uri {
	my $self=shift;
	return $self->{ROBJ}->encode_uri(@_);
}
sub encode_uricom {
	my $self=shift;
	return $self->{ROBJ}->encode_uricom(@_);
}

#-------------------------------------------------------------------------------
# ●class/titleの設定
#-------------------------------------------------------------------------------
sub make_attr {
	my $self = shift;
	my ($ary, $tag, $type) = @_;

	# target/class/rel 設定, type未定義のとき初期値なし(mailto:等)
	my $class;
	my $title = $tag->{title} || $tag->{name};
	my $target='';
	while(1) {
		my $x = $ary->[0];
		if ($x =~ /^title=\s*(.*?)\s*$/)  { shift(@$ary); $title = $1; next; }
		if ($x =~ /^class=\s*(.*?)\s*$/)  { shift(@$ary); $class = $1; next; }
		if ($x =~ /^target=\s*(.*?)\s*$/) { shift(@$ary); $target= $1; next; }
		last;
	}
	$class =~ s/[^\w\s:\-]//g;
	$self->tag_escape($title);
	$target =~ s/[^\w\-]//g;

	my $attr='';
	if ($class ne '' || $tag->{class} ne '') {
		my $sp = ($class ne '' && $tag->{class} ne '') ? ' ' : '';
		$attr  =" class=\"$tag->{class}$sp$class\"";
	}
	if ($title  ne '') { $attr .= " title=\"$title\""; }
	if ($target ne '') { $attr .=" target=\"$target\""; }
	if ($type eq 'image' && $self->{image_attr} ne '') {
		my $at = $self->{image_attr};
		$at =~ s/%k/$self->{thispkey}/g;
		$attr .= ' ' . $at;
	}

	# 属性文字列を返す
	return $attr;
}
#--------------------------------------
# name の設定
#--------------------------------------
sub make_name {
	my $self=shift;
	my ($ary, $name) = @_;
	my $x = join(':', @$ary);
	return ($x eq '' ?  $name : $x);
}

1;
