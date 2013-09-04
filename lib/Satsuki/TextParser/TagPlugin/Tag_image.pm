use strict;
#------------------------------------------------------------------------------
# 画像記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_image;
###############################################################################
# ■基本処理
###############################################################################
# ●使い方
#   通常の記法プラグインと違い、オプション部（文字コード部）に image と
# 指定することで使用する。
# 
#（設定例）
#	img       = 画像, image, 1, http://image.xxx.jp/image/$1_small.jpg
#	img#large = 画像, image, 1, http://image.xxx.jp/image/$1_large.jpg
#	img#link  = 画像, image, 1, http://image.xxx.jp/image/$1.jpg
#　large などのサイズ違いを指定する際は、引数の数を同一にすること。
#  $11 引数から、最初に出てくる "." の手前までに置換。
#
# としたとき
# [img:test]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img">
#	<img alt="test" title="test" src="http://image.xxx.jp/image/test_large.jpg"></a>
#
# [img:test:small]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img small">
#	<img alt="test" title="test" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
# [img:test:てすと]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img">
#	<img alt="てすと" title="てすと" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'&image'} = \&image;
	#---end

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●image記法
#------------------------------------------------------------------------------
sub image {
	my ($parser_obj, $tag, $cmd, $ary) = @_;
	my $tags = $parser_obj->{tags};
	my $ROBJ = $parser_obj->{ROBJ};
	my $replace_data = $parser_obj->{replace_data};

	# mode チェック
	my $tag_name = $tag->{name};
	my $argc     = $tag->{argc};
	my $mode     = $ary->[ ($argc || 1) ];
	if (exists $tags->{"$tag_name#$mode"}) {
		$tag  = $tags->{"$tag_name#$mode"};
		$mode = undef;
	}

	#  構成
	my $url  = $tag->{data};
	my $link = $url;
	if (exists $tags->{"$tag_name#link"}) { $link = $tags->{"$tag_name#link"}->{data}; }
	# URL生成
	if (! $argc) {	#引数個数指定なし
		if (index($url,'$$')>=0) {
			$argc = 9999;
		} else {
			$argc = 1;
			$url .= '$1';
		}
	}
	my @argv = splice(@$ary, 0, $argc);
	unshift(@argv, $ROBJ->{Basepath});
	$url  =~ s/\$(\d)/$argv[$1]/g;			# 文字コード変換後
	$link =~ s/\$(\d)/$argv[$1]/g;
	$url  =~ s/\$\{(\w+)\}/$replace_data->{$1}/g;	# 任意データ置換
	$link =~ s/\$\{(\w+)\}/$replace_data->{$1}/g;
	if ($url =~ /\$\$/) {	# 全引数置換
		shift(@argv);
		my $str = join(':', @argv);
		$url  =~ s/\$\$/$str/g;
		$link =~ s/\$\$/$str/g;
	}
	# 名前
	my $name = $argv[$#argv];
	$ROBJ->tag_escape($name);

	# 画像サイズ
	my $size;
	if    ($mode =~ /^w(\d+%?)$/) { $size=" width=\"$1\"";  shift(@$ary); }
	elsif ($mode =~ /^h(\d+%?)$/) { $size=" height=\"$1\""; shift(@$ary); }
	elsif (!defined $mode) { shift(@$ary); }	# モード指定読み捨て

	# 属性値
	my %tag2 = %$tag; 
	$tag2{title}='';	# altタグと同一にする
	my $attr = $parser_obj->make_attr($ary, \%tag2, 'image');
	   $name = $parser_obj->make_name($ary, $name);

	# リンク構成
	if ($link eq '') {	# リンクなし
		return "<img title=\"$name\" alt=\"$name\"$size src=\"$url\" class=\"$tag->{class}\">";
	}
	return "<a href=\"$link\"$attr><img alt=\"$name\"$size src=\"$url\"></a>";
}



1;
