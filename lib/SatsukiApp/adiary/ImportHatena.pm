use strict;
#------------------------------------------------------------------------------
# データインポート for はてな形式(xml)/adiary形式
#                                                   (C)2006 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package SatsukiApp::adiary::ImportHatena;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift}, $class);
}

###############################################################################
# ■データインポータ
###############################################################################
#------------------------------------------------------------------------------
# ●はてな/adiary形式のデータインポート
#------------------------------------------------------------------------------
sub import_arts {
	my ($self, $aobj, $form, $session) = @_;
	my $ROBJ = $self->{ROBJ};

	# データチェック
	my $data = $form->{file}->{data};
	delete $form->{file};
	{
		my $check_data = substr($data, 0, 1024);
		if ($check_data !~ /<\?xml .*? encoding="([\w\-]*)".*?\?>.*<diary>/s) {
			$session->msg('Data format error (%s)', 'adiary/hatena');
			return 1;
		}
		my $file_coding = $1;
		$file_coding =~ tr/a-z/A-Z/;

		# 文字コード変換
		my $system_coding = $ROBJ->{System_coding};
		if ($system_coding ne $file_coding) {
			my $jcode = $ROBJ->load_codepm();
			$jcode->from_to(\$data, $file_coding, $system_coding);
		}
		# 改行コード変換
		$data =~ s/\r\n|\r/\n/g;
	}

	my @days;
	$data =~ s|(<day.*?</day>)|push(@days, $1),''|seg;
	undef $data;

	#---------------------------------------------------------------------
	# ログの解析と保存
	#---------------------------------------------------------------------
	foreach my $log (@days) {
		#-------------------------------------------------------------
		# <day date="2004-02-29" title="xxx"> の解析
		#-------------------------------------------------------------
		$log =~ /<day\b(.*?)>/s;
		my $day_tag = $1;
		my %art;
		$day_tag =~ s/\s*(\w+)\s*?=\s*?([\"\'])(.*?)\2/$art{$1}=$3,''/seg;
		#-------------------------------------------------------------
		# <attributes xxx="yyy" ...> の解析（adiary拡張）
		#-------------------------------------------------------------
		if ($log =~ /<attributes\b(.*?)>/s) {
			my $attributes = $1;
			$attributes =~ s/\s*(\w+)\s*?=\s*?([\"\'])(.*?)\2/$art{$1}=$3,''/seg;
		}

		#-------------------------------------------------------------
		# 本文抽出
		#-------------------------------------------------------------
		if ($log =~ /<body>(.*?)<\/body>/s) { $art{text}=$1; }

		#-------------------------------------------------------------
		# XML デコード
		#-------------------------------------------------------------
		$self->tag_dencode_for_xml($art{title}, $art{category}, $art{tags}, $art{name}, $art{agent}, $art{text});

		#-------------------------------------------------------------
		# コメントの解析
		#-------------------------------------------------------------
		my $comments='';
		if ($log =~ /<comments>(.*?)<\/comments>/s) { $comments=$1; }
		my @comments;
		if ($comments ne '') {
			my @ary;
			$comments =~ s/<comment>(.*?)<\/comment>/push(@ary, $1),''/seg;
			foreach(@ary) {
				my %h;
				$_ =~ s|<(\w+)>(.*?)</\1>|$h{$1}=$2,''|seg;
				$h{tm}   = $h{timestamp};
				$h{name} = $h{username};
				$h{text} = $h{body};
				delete $h{timestamp};
				delete $h{username};
				delete $h{body};

				# XML復元
				$self->tag_dencode_for_xml($h{name}, $h{url}, $h{text});
				if ($art{adiary}>=3) {	# Ver3以降
					$self->tag_dencode_for_xml($h{host}, $h{agent});
				}
				$h{text} =~ s/<br>/\n/ig;	# <br>→\n に変換
				push(@comments, \%h);
			}
		}

		#-------------------------------------------------------------
		# トラックバックの解析
		#-------------------------------------------------------------
		my $trackbacks='';
		if ($log =~ /<trackbacks>(.*?)<\/trackbacks>/s) { $trackbacks=$1; }
		my @trackbacks;
		if ($trackbacks ne '') {
			my @ary;
			$trackbacks =~ s/<trackback>(.*?)<\/trackback>/push(@ary, $1),''/seg;
			foreach(@ary) {
				my %h;
				$_ =~ s|<(\w+)>(.*?)</\1>|$h{$1}=$2,''|seg;
				$h{tm}      = $h{timestamp};
				$h{excerpt} = $h{excerpt};
				delete $h{timestamp};
				delete $h{body};
				$self->tag_dencode_for_xml($h{title}, $h{excerpt}, $h{blog_name}, $h{author});

				push(@trackbacks, \%h);
			}
		}

		#-------------------------------------------------------------
		# はてなスタイルのデータをadiaryスタイルに整形（本文の記法変換）
		#-------------------------------------------------------------
		# adiaryデータではない → はてな形式のデータ
		if (! $art{adiary}) { $self->convert_hatena_to_adiary( \%art, $form, $session ); }

		#-------------------------------------------------------------
		# 日付加工
		#-------------------------------------------------------------
		my $date = $art{date};	# 2005-11-22
		$date =~ /(\d+)\-(\d+)\-(\d+)/;
		$art{year} = $1;
		$art{mon}  = $2;
		$art{day}  = $3;

		#-------------------------------------------------------------
		# カテゴリ
		#-------------------------------------------------------------
		if (!exists $art{tags} && $art{category} ne '') {
			$art{tags} = $art{category};
		}

		#-------------------------------------------------------------
		# データを保存
		#-------------------------------------------------------------
		$art{save_pkey} = $art{adiary} && $form->{save_pkey};

		$aobj->save_article(\%art, \@comments, \@trackbacks, $form, $session);
	}
	return 0;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●XML tagデコーダ
#------------------------------------------------------------------------------
sub tag_dencode_for_xml {
	foreach(@_) {
		$_ =~ s/&lt;/</g;
		$_ =~ s/&gt;/>/g;
		$_ =~ s/&quot;/"/g;
		$_ =~ s/&amp;/&/g;
		$_ =~ s/&#39;|&apos;/'/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●はてな形式コンバータ
#------------------------------------------------------------------------------
sub convert_hatena_to_adiary {
	my ($self, $art, $option, $session) = @_;

	# はてな向けの設定
	my $style_conv = $option->{style_conv};
	my $link_stop  = $option->{link_stop};
	my $autolink   = $option->{autolink};
	my $p_stop     = $option->{p_stop};
	my $pre_end    = $option->{pre_end};
	my $f_delete   = $option->{f_delete};
	my $sec2title  = $option->{section2title};
	my $up_section = $option->{up_section};

	$art->{parser} = $option->{parser} || 'default_p1';	# 1行=1段落

	#-------------------------------------
	# superプレ記法を退避
	#-------------------------------------
	my @spbuf;
	my $text = $art->{text};
	$text =~ s/[\x00-\x03\e]//g;
	$text =~ s/(^|\n)(>\|(?:\?|\w*)\|\s*\n.*?\n\|\|<)\n/
		push(@spbuf, $2);
		"$1\x01" . $#spbuf . "\x02\n"/seg;

	my @newary;
	my @ary = split("\n", $text);
	my $first_sec = 1;
	my $do_up_section;
	while( @ary ) {
		my $x = shift(@ary);
		if (substr($x,-1) eq "\x02") {	# super pre buffer
			push(@newary, $x);
			next;
		}
		#-------------------------------------
		#  <p>タグ停止記法
		#-------------------------------------
		if ($p_stop) {	#
			if ($x =~ /^></) {	# p stop div block
				$x = ">>>|\n" . substr($x, 1);
			} elsif ($x =~ /><$/) {	# block end
				chop($x);
				$x .= "\n|<<<";
			}
		}
		#-------------------------------------
		# タグを保存しておく
		#-------------------------------------
		my @tags;
		$x =~ s/(<\w([^>"']|[=\s\n]".*?"|[=\s\n]'.*?')*?>)/push(@tags, $1), "<\e$#tags>"/esg;
		#-------------------------------------
		# 行末 |< による pre ブロックの終わりを変換する
		#-------------------------------------
		if ($x ne '|<' && $x ne '||<' && substr($x, -2) eq '|<' && substr($x, -3) ne '||<') {
			chop($x); chop($x);
			$x = $x . "\n|<";
		}

		# 自動リンク停止記法を除去
		if ($link_stop) {
			$x =~ s/\[\](.+?)\[\]/$1/g;
		}
		# 拡張引用記法の書き換え
		$x =~ s|^>(https?://.*?)>|>>[$1]|;
		# 行末 \ のエスケープ
		if (substr($x, -1) eq "\\") { $x .= " "; }

		#-------------------------------------
		# 最初のサブタイトル抽出
		#-------------------------------------
		my $is_section;
		if ($x =~ /^\*[^\*]/) {		# 「*見出し」
			$is_section=1;
			$do_up_section=0;	# 見出し書き換えは最初のみ
		}
		if ($first_sec && $is_section) {		# 最初のsection
			$first_sec = 0;
			if ($x =~ /\*(?:(\w*)\*)?((?:\[.*?\])*)(.*)/) {
				if ($sec2title) {
					$do_up_section = $up_section;
					$art->{title} = $art->{title} || $3;
				}
				my $tm = int($1);
				if ($tm) { $art->{tm} = $tm; }
				my $tags = $2;
				$tags =~ s/\]\[/,/g;
				$tags =~ s/[\[\]]//g;
				$art->{tags} = $tags;
			}
		}
		if ($do_up_section) {	# *見出し→タイトル、**小見出し→*見出し
			if ($is_section) {
				if ($ary[0] eq '') {
					# 次が空行なら読み捨てる
					shift(@ary);
				}
				next;
			} else {
				$x =~ s/^\*\*/*/;
			}
		}

		#-------------------------------------
		# 記法変換
		#-------------------------------------
		if ($x =~ m!\w:(?:\w|//)!) {
			# 写真へのリンクをコメントアウト
			if ($f_delete) {
				$x =~ s/(\[?f:id:[\w:]+\]?)/<!-- $1 -->/g;
			}
			# はてな記法を置き換える
			if ($style_conv) {
				# 正規表現用の調整
				$x = " $x";
				$x =~ s/([^\w:\[])((isbn|asin|jan|ean|question|idea|graph|map):[\w:]+)/$1\[$2\]/ig;
				# x:id:? → [hatena:x:id:?]
				$x =~ s/([^\w:\[])(\w:)(id|t|keyword):([\w:]+)/$1\[hatena:$2$3:$4\]/g;
				$x =~ s/\[(\w:)(id|t|keyword):(.+?)\]/[hatena:$1$2:$3]/g;
				# g:? → [hatena:g:?]
				$x =~ s/([^\w:\[])g:([\w:]+)/$1\[hatena:g:$2\]/g;
				$x =~ s/\[g:(.+?)\]/[hatena:g:$1]/g;
				# id:? → [hatena:id:?]
				$x =~ s/([^\w:\[])id:([\w:\#]+)/$1\[hatena:id:$2\]/g;
				$x =~ s/\[id:(.+?)\]/[hatena:id:$1]/g;
				# [tex:?] → [[tex:?]]
				$x =~ s/\[tex:(.*?)\]/[[tex:$1\]\]/g;
				# 元に戻す
				$x = substr($x, 1);
			}
			# 自動リンクを生成
			if ($autolink) {
				$x =~ s!(^|[^\w\[:])(https?):(//[\w\./\#\@\?\&\~\=\+\-%\[\]:;,\!*]+)!
					my $x="$1\[$2:"; my $y=$3;
					$y =~ s/([\[\]:])/"&#" . ord($1) . ';'/eg;
					"$x$y]";
				       !eg;
				$x =~ s|(mailto:[\w\-\.]+\@[\w\.\-]+)|\[$1\]|g;
			}
		}

		# タグを書き戻す
		$x =~ s/<\e(\d+)>/$tags[$1]/g;
		push(@newary, $x);
	}
	$art->{text} = join("\n", @newary);
	# super preを戻す
	$art->{text} =~ s/\x01(\d+)\x02/$spbuf[$1]/g;
	return ;
}

1;
