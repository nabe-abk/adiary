use strict;
#------------------------------------------------------------------------------
# 記法システム - シンプルパーサー
#                                                   (C)2013-2015 nabe@abk
#------------------------------------------------------------------------------
package Satsuki::TextParser::Simple;
our $VERSION = '1.30';
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
	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●記事本文の整形
#------------------------------------------------------------------------------
sub text_parser {
	my ($self, $text) = @_;

	# コメントの退避
	my @comment;
	$text =~ s/\x00//g;
	$text =~ s/((?:<!(?:--.*?--\s*)+>)\n?)/push(@comment, $1),"\x00" . $#comment . "\x00"/esg;

	# 行に分解
	my $lines = [ split(/\n/, $text) ];
	undef $text;

	# simpleパーサー
	my ($all, $short) = $self->simple_parser($lines);

	# section付加
	if ($self->{section}) {
		unshift(@$all,   "<section>\n");
		push   (@$all,   "</section>\n");
		if (@$short) {
			unshift(@$short, "<section>\n");
			push   (@$short, "</section>\n");
		}
	}

	$all   = join('', @$all);
	$short = join('', @$short);

	# コメントの復元
	foreach(@comment) {
		# コメント中の %SeeMore% 除去
		$_ =~ s/<\!--%SeeMore%-->/<\!--%SeeMore% -->/;
	}
	$all   =~ s/\x00(\d+)\x00/$comment[$1]/g;
	$short =~ s/\x00(\d+)\x00/$comment[$1]/g;

	return wantarray ? ($all, $short) : $all;
}

###############################################################################
# ■ シンプルパーサー（特殊タグなし）
###############################################################################
sub simple_parser {
	my ($self, $lines) = @_;
	# 初期設定
	my $br_mode = $self->{br_mode};
	my $p_mode  = $self->{paragraph_mode};
	my $p_class = $self->{paragraph_class};
	my $tagline = $self->{skip_tag_line};	# タグのみの行は段落処理しない
	my $indent  = $self->{indent};
	# p class処理
	$p_class =~ s/[^\w\-]//g;
	if ($p_class ne '') { $p_class = " class=\"$p_class\""; }

	# フラグ初期化
	my $in_paragraph = 0;
	my $see_more     = 0;

	my @ary;
	my @short;
	my ($prev_f, $this, $this_f, $next, $next_f);
	push(@$lines, '');
	foreach(@$lines) {
		$prev_f = $this_f;
		$this = $next; $this_f = $next_f;
		$next = $_;    $next_f = 0;
		if ($next eq '') { $next_f=1; }
		if (!defined $this) { next; }
		#----------------------------------------------------
		# 続きを読む記法
		#----------------------------------------------------
		if (! $see_more && ($next eq '====' || $next eq '=====')) { $next_f=-1; }
		if ($this_f == -1) {
			@short = @ary;	# 短いテキストのコピー
			$see_more=1;
			push(@ary,"<!--%SeeMore%-->");	# SeeMore Marking
			next;
		}
		# ==== のエスケープ表記
		$this =~ s/^ =/=/;

		#----------------------------------------------------
		# タグのみの行は段落処理しない
		#----------------------------------------------------
		if ($tagline && $this =~ m!^\s*(?:</?\w+(?:"[^"]*"|'[^']*'|[^>])*>)+\s*$!) {
			push(@ary, "$indent$this\n");
			next;
		}
		#----------------------------------------------------
		# 段落の始まり？
		#----------------------------------------------------
		# １行＝１段落
		if ($p_mode==1) {
			if ($this_f) {
				if ($br_mode) { push(@ary, "$indent<br>\n"); }
				next;
			}
			push(@ary, "$indent<p$p_class>$this</p>\n");
			next;
		}
		# 段落処理なし
		if (! $p_mode)  {
			if ($br_mode) { push(@ary, "$indent$this<br>\n"); }    # 改行処理
				else  { push(@ary, "$indent$this\n");     }
			next;
		}

		#-----------------------------------------------------------
		# 空行で段落処理 (p_mode = 2)
		#-----------------------------------------------------------
		if ($p_mode!=2 && $p_mode!=3) { next; }
		if ($this_f && $prev_f) {	# 2行以上続く空行
			if ($p_mode == 3) { push(@ary, "$indent<br>\n"); }
			next;
		}
		if ($this_f) { next; }

		# 段落の始まり？
		my $head = '';
		my $foot = '';
		if (! $in_paragraph) { $head = "<p$p_class>"; $in_paragraph=1; }

		# ここで段落の終わり
		if ($next_f) {
			$in_paragraph=0;
			$foot="</p>\n\n";

		# 途中改行を処理
		} elsif ($br_mode) {
			$foot='<br />';
		
		# 日本語の文章のとき、行末改行を取り除く
		} elsif (ord(substr($this,-1))<0x80 && ord(substr($next,0,1))<0x80) {
			$foot="\n";
		}

		# 出力
		push(@ary, "$indent$head$this$foot");
	}
	if (@short) {
		push(@short, <<TEXT);
<p class="seemore"><a class="seemore" href="$self->{thisurl}">$self->{seemore_msg}</a></p>
TEXT
	}

	return (\@ary, \@short);
}


###############################################################################
###############################################################################


1;
