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
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tags = $pobj->{tags};
	my $ROBJ = $pobj->{ROBJ};

	# mode チェック
	my $tag_name = $tag->{name};
	my $argc     = $tag->{argc};
	my $mode     = $ary->[ ($argc || 1) ];
	if (exists $tags->{"$tag_name#$mode"}) {
		$tag  = $tags->{"$tag_name#$mode"};
		$mode = undef;
	}

	#  構成
	my $name = $ary->[$#$ary];
	my $url  = $tag->{data};
	my $link = $url;
	if (exists $tags->{"$tag_name#link"}) { $link = $tags->{"$tag_name#link"}->{data}; }
	# URL生成
	$url  = $pobj->replace_link($url,  $ary, $argc);
	$link = $pobj->replace_link($link, $ary, $argc);
	# 使った要素の削除
	splice(@$ary, 0, $argc);
	$ROBJ->tag_escape($name);

	# 画像サイズ
	my $size;
	if    ($mode =~ /^w(\d+%?)$/) { $size=" width=\"$1\"";  shift(@$ary); }
	elsif ($mode =~ /^h(\d+%?)$/) { $size=" height=\"$1\""; shift(@$ary); }
	elsif (!defined $mode) { shift(@$ary); }	# モード指定読み捨て

	# 属性値
	my %tag2 = %$tag; 
	$tag2{title} = $name;
	my $attr = $pobj->make_attr($ary, \%tag2, 'image');
	   $name = $pobj->make_name($ary, $name);

	# リンク構成
	if ($link eq '') {	# リンクなし
		return "<img title=\"$name\" alt=\"$name\"$size src=\"$url\" class=\"$tag->{class}\">";
	}
	return "<a href=\"$link\"$attr><img alt=\"$name\"$size src=\"$url\"></a>";
}



1;
