use strict;
#-------------------------------------------------------------------------------
# 画像記法プラグイン
#                                                   (C)2015 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_image;
################################################################################
# ■基本処理
################################################################################
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
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img" title="test">
#	<img alt="test" src="http://image.xxx.jp/image/test_large.jpg"></a>
#
# [img:test:small]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img small" title="test">
#	<img alt="test" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
# [img:test:てすと]
#  → <a href="http://image.xxx.jp/image/test.jpg" class="img" title="てすと">
#	<img alt="てすと" src="http://image.xxx.jp/image/test_small.jpg"></a>
#
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'&image'} = \&image;
	#---end

	return ;
}
################################################################################
# ■タグ処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●image記法
#-------------------------------------------------------------------------------
sub image {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tags = $pobj->{tags};
	my $ROBJ = $pobj->{ROBJ};

	# mode チェック
	my $tag_name = $tag->{name};
	my $argc     = $tag->{argc};
	my $mode     = $ary->[ ($argc || 1) ];
	if (exists $tags->{"$tag_name#$mode"}) {	# [tag:～:large] 等の指定がある
		$tag  = $tags->{"$tag_name#$mode"};
		$mode = undef;
		splice(@$ary, $argc || 1, 1);	# モード指定部を削除
	}

	#  構成
	my $url  = $tag->{data};
	my $link = (exists $tags->{"$tag_name#link"}) ? $tags->{"$tag_name#link"}->{data} : $url;

	# http/httpsの特殊処理
	if ($ary->[0] =~ /^https?$/i && $ary->[1] =~ m|^//|) {
		my $p = shift(@$ary);
		$ary->[0] = $p . ':' . $ary->[0];
	}

	# URL生成
	{
		my @ary2 = @$ary;
		$url  = $pobj->replace_link($url,   $ary,  $argc);
		$link = $pobj->replace_link($link, \@ary2, $argc);
	}

	# 画像サイズ
	my $size;
	{
		my @ary2;
		my ($w,$h);
		foreach(@$ary) {
			if ($_ =~ /^\s*w(\d+)\s*$/) { $w=" width=\"$1\"";  next; }
			if ($_ =~ /^\s*h(\d+)\s*$/) { $h=" height=\"$1\""; next; }
			push(@ary2, $_);
		}
		$size=$w . $h;
		$ary = \@ary2;
	}

	# Captionあり？
	my $caption;
	for(my $i=0; $i<=$#$ary; $i++) {
		if ($ary->[$i] =~ /\#/) {
			$caption = $i;
			last;
		}
	}
	if ($caption) {
		my $cap = substr(join(':', splice(@$ary,$caption)),1);
		$caption = "<figcaption>$cap</figcaption>";
	}

	# 属性値
	my $name = $ary->[$#$ary];
	$ROBJ->tag_escape($name);
	my %tag2 = %$tag;
	$tag2{title} = $name;
	my $attr = $pobj->make_attr($ary, \%tag2, exists($tags->{"$tag_name#ext"}) ? '' : 'image');
	   $name = $pobj->make_name($ary, $name);

	my $tag = "<a href=\"$link\"$attr><img alt=\"$name\"$size src=\"$url\"></a>";
	## if (!$caption) { return $tag; }

	return "<figure>$tag$caption</figure>";
}

1;
