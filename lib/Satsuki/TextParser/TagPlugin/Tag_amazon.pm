use strict;
#-------------------------------------------------------------------------------
# Amazon記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_amazon;
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て

	my $tags = shift;
	#---begin_plugin_info
	$tags->{amazon}->{data} = \&amazon_search;
	$tags->{asin}  ->{data} = \&amazon_asin;
	#---end

	return ;
}

################################################################################
# ■タグ処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●Amazon記法(Amazon search)
#-------------------------------------------------------------------------------
sub amazon_search {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $keyword = shift(@$ary);
	my $name    = $keyword;
	# 文字コード変換
	my $ROBJ = $pobj->{ROBJ};
	my $system_coding = $ROBJ->{SystemCode};
	if ($system_coding ne 'UTF-8') {
		my $jcode = $pobj->{jcode} ||= $ROBJ->load_codepm();
		$jcode->from_to(\$keyword, $system_coding, 'UTF-8');
	}
	# URIエンコード
	$pobj->encode_uricom($keyword);
	my $nihongo = "%E6%97%A5%E6%9C%AC%E8%AA%9E";	# '日本語' by UTF-8

	# アソシエイトID &tag=user-id
	my $asid = $pobj->{vars}->{asid};
	$asid =~ s/[^\w\-\.]//g;	# 不要文字除去
	if ($asid ne '') { $asid="&tag=$asid"; }

	# 属性/リンク名
	my $attr = $pobj->make_attr($ary, $tag);
	   $name = $pobj->make_name($ary, $name);

	return "<a href=\"https://www.amazon.co.jp/s?mode=blended$asid&encoding-string-jp=$nihongo&keyword=$keyword\"$attr>$name</a>";
}

#-------------------------------------------------------------------------------
# ●asin/isbn記法(amazon)
#-------------------------------------------------------------------------------
sub amazon_asin {
	my ($pobj, $tag, $cmd, $ary) = @_;

	# アソシエイトID &tag=user-id
	my $asid = $pobj->{vars}->{asid};
	$asid =~ s/[^\w\-\.]//g;	# 不要文字除去

	# ASIN/ISBNロード
	my $asin = shift(@$ary);
	$asin =~ s/[^\w\.]//g;	# 不要文字除去

	# 画像モード？
	if ($ary->[0] eq 'img' || $ary->[0] eq 'image' || $ary->[0] eq 'detail') {
		shift(@$ary);
		return &amazon_asin_image($pobj, $tag, $cmd, $ary, $asin, $asid);
	}

	# 属性/リンク名
	# $cmd =~ tr/a-z/A-Z/;
	unshift(@$ary, 'class=js-popup-img');
	my $attr = $pobj->make_attr($ary, $tag);
	my $name = $pobj->make_name($ary, "$cmd:$asin");

	my $link   = &link_url ($asin, $asid);
	my $imgurl = &image_url($asin);
	return "<a href=\"$link\" data-img-url=\"$imgurl\"$attr>$name</a>";
}

#-------------------------------------------------------------------------------
# ●asin/isbn - image記法(amazon)
#-------------------------------------------------------------------------------
sub amazon_asin_image {
	my ($pobj, $tag, $cmd, $ary, $asin, $asid) = @_;

	# サイズ認識
	my $size = $ary->[$#$ary];
	if ($size eq 'large' || $size eq 'small') {
		pop(@$ary);
	}

	my $size_tag;
	if    ($ary->[0] =~ /^w(\d+%?)$/) { $size_tag=" width=\"$1\"";  shift(@$ary); }
	elsif ($ary->[0] =~ /^h(\d+%?)$/) { $size_tag=" height=\"$1\""; shift(@$ary); }

	# タイトル
	# $cmd =~ tr/a-z/A-Z/;
	my $attr = $pobj->make_attr($ary, $tag);
	my $name = $pobj->make_name($ary, "$cmd:$asin");
	$name =~ s/"/&quot;/g;

	my $link   = &link_url ($asin, $asid);
	my $imgurl = &image_url($asin, $size);
	return "<a href=\"$link\"$attr><img src=\"$imgurl\" alt=\"$name\" class=\"asin\"$size_tag></a>";
}

#-------------------------------------------------------------------------------
# link/image_url
#-------------------------------------------------------------------------------
# https://www.amazon.co.jp/exec/obidos/ASIN/$asin/$asid
# https://www.amazon.co.jp/gp/product/$asin/?tag=$asid
#
sub link_url {
	my $asin = shift;
	my $asid = shift;
	return "https://www.amazon.co.jp/gp/product/$asin/?tag=$asid";
}

sub image_url {
	my $asin = shift;
	my $size = shift;

	my $format = '_SL160_';
	if ($size eq 'large') { $format = '_SL250_'; }
	if ($size eq 'small') { $format = '_SL110_'; }
	
	return "//ws-fe.amazon-adsystem.com/widgets/q?_encoding=UTF8&amp;MarketPlace=JP&amp;ASIN=$asin&amp;ServiceVersion=20070822&amp;ID=AsinImage&amp;WS=1&amp;Format=$format";
}

1;
