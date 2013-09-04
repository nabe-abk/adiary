use strict;
#------------------------------------------------------------------------------
# Amazon記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_amazon;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
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

###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●Amazon記法(Amazon search)
#------------------------------------------------------------------------------
sub amazon_search {
	my ($parser_obj, $tag, $cmd, $ary) = @_;

	my $keyword = shift(@$ary);
	my $name    = $keyword;
	# 文字コード変換
	my $ROBJ = $parser_obj->{ROBJ};
	my $system_coding = $ROBJ->{System_coding};
	if ($system_coding ne 'UTF-8') {
		my $jcode = $parser_obj->{jcode} ||= $ROBJ->load_codepm();
		$jcode->from_to(\$keyword, $system_coding, 'UTF-8');
	}
	# URIエンコード
	$parser_obj->encode_uricom($keyword);
	my $nihongo = "%E6%97%A5%E6%9C%AC%E8%AA%9E";	# '日本語' by UTF-8

	# アソシエイトID &tag=user-id
	my $asid = $parser_obj->{asid};
	$asid =~ s/[^\w\-\.]//g;	# 不要文字除去
	if ($asid ne '') { $asid="&tag=$asid"; }

	# 属性/リンク名
	my $attr = $parser_obj->make_attr($ary, $tag);
	   $name = $parser_obj->make_name($ary, $name);

	return "<a href=\"http://www.amazon.co.jp/exec/obidos/external-search?mode=blended$asid&encoding-string-jp=$nihongo&keyword=$keyword\"$attr>$name</a>";
}

#------------------------------------------------------------------------------
# ●asin/isbn記法(amazon)
#------------------------------------------------------------------------------
sub amazon_asin {
	my ($parser_obj, $tag, $cmd, $ary) = @_;

	# アソシエイトID &tag=user-id
	my $asid = $parser_obj->{asid};
	$asid =~ s/[^\w\-\.]//g;	# 不要文字除去
	# if ($asid ne '') { $asid .= '/ref=nosim'; }

	# ASIN/ISBNロード
	my $isbn = shift(@$ary);
	my $asin = $isbn;
	$asin =~ s/[^\w\.]//g;	# 不要文字除去

	# 画像モード？
	if ($ary->[0] eq 'img' || $ary->[0] eq 'image' || $ary->[0] eq 'detail') {
		shift(@$ary);
		return &amazon_asin_image($parser_obj, $tag, $cmd, $ary, $isbn, $asin, $asid);
	}

	# 属性/リンク名
	# $cmd =~ tr/a-z/A-Z/;
	unshift(@$ary, 'class=js-popup-img');
	my $attr = $parser_obj->make_attr($ary, $tag);
	my $name = $parser_obj->make_name($ary, "$cmd:$isbn");

	return "<a href=\"http://www.amazon.co.jp/exec/obidos/ASIN/$asin/$asid\" data-img-url=\"http://images-jp.amazon.com/images/P/$asin.09.MZZZZZZZ.jpg\"$attr>$name</a>";
}

#------------------------------------------------------------------------------
# ●asin/isbn - image記法(amazon)
#------------------------------------------------------------------------------
sub amazon_asin_image {
	my ($parser_obj, $tag, $cmd, $ary, $isbn, $asin, $asid) = @_;

	# サイズ認識
	my $size = '.09.MZZZZZZZ.jpg';	# midium
	if ($ary->[0] eq 'large') {
		shift(@$ary);
		$size = '.09.LZZZZZZZ.jpg';
	} elsif ($ary->[0] eq 'small') {
		shift(@$ary);
		$size = '.09.THUMBZZZ.jpg';
	}
	my $size_tag;
	if    ($ary->[0] =~ /^w(\d+%?)$/) { $size_tag=" width=\"$1\"";  shift(@$ary); }
	elsif ($ary->[0] =~ /^h(\d+%?)$/) { $size_tag=" height=\"$1\""; shift(@$ary); }

	# タイトル
	# $cmd =~ tr/a-z/A-Z/;
	my $attr = $parser_obj->make_attr($ary, $tag, 'image');
	my $name = $parser_obj->make_name($ary, "$cmd:$isbn");
	$name =~ s/"/&quot;/g;

	return "<a href=\"http://www.amazon.co.jp/exec/obidos/ASIN/$asin/$asid\"$attr><img src=\"http://images-jp.amazon.com/images/P/$asin$size\" alt=\"$name\" class=\"asin\"$size_tag></a>";
}


1;
