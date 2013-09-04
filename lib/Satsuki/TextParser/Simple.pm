use strict;
#------------------------------------------------------------------------------
# 記法システム - シンプルパーサー
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::Simple;
our $VERSION = '1.20';
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
	my $ls_mode = $self->{ls_mode};		# 行間処理モード
	my $indent  = $self->{indent};
	# p class処理
	$p_class =~ s/[^\w\-]//g;
	if ($p_class ne '') { $p_class = " class=\"$p_class\""; }

	# フラグ初期化
	my $in_paragraph = 0;
	my $see_more     = 0;
	my $ls_count     = 0;	# 空行カウンタ

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
			$ls_count=0;
			push(@ary,"<!--%SeeMore%-->");	# SeeMore Marking
			next;
		}
		# ==== のエスケープ表記
		$this =~ s/^ =/=/;

		#----------------------------------------------------
		# 空行処理
		#----------------------------------------------------
		if ($this eq '') {
			if (! $ls_mode) { next; }
			# 空行処理モード
			$ls_count++;
			if ($ls_count>1) { push(@ary, "$indent<br />\n"); }
			next;
		}
		$ls_count = 0;	# 空行カウンタ初期化
		#----------------------------------------------------
		# 段落の始まり？
		#----------------------------------------------------
		# １行＝１段落
		if ($p_mode==1) {
			push(@ary, "$indent<p$p_class>$this</p>\n");
			next;
		}
		# 段落処理なし
		if (! $p_mode)  {
			if ($br_mode) { push(@ary, "$indent$this<br>\n"); }    # 改行処理
				else  { push(@ary, "$indent$this\n");     }
			next;
		}
		# 不明な指定
		if ($p_mode!=2) { next; }

		# 空行で段落処理
		my $head = '';
		my $foot = '';
		# 段落の始まり
		if (! $in_paragraph) { $head = "<p$p_class>"; $in_paragraph=1; }
		# ここで段落の終わり
		if ($next_f) {
			$in_paragraph=0;
			$foot='</p>';
		# 途中改行を処理
		} elsif ($br_mode) {
			$foot='<br />';
		}
		# 出力
		push(@ary, "$indent$head$this$foot\n");
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
