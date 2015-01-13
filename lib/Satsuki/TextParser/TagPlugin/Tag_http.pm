use strict;
#------------------------------------------------------------------------------
# http, ftp, mailto 記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_http;
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
	$tags->{http}  ->{data} = \&http;
	$tags->{https} ->{data} = \&http;
	$tags->{ftp}   ->{data} = \&http;
	$tags->{mailto}->{data} = \&mailto;
	#---end

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●http記法
#------------------------------------------------------------------------------
sub http {
	my ($pobj, $tag, $cmd, $ary) = @_;

	# URL取り出し
	my $url2 = shift(@$ary);
	if ($ary->[0] =~ /^#/) {
		$url2 .= shift(@$ary);
	}
	# URIエンコード
	$pobj->encode_uri($url2);
	$cmd =~ s/\W//g;
	my $url = $url2;
	if (substr($url2,0,2) eq '//') { $url = $cmd . ':' . $url2; }
	# サムネイル表示？ (image プラグインあり）
	my $tags = $pobj->{tags};
	if ($ary->[0] eq 'image' && $tags->{"$cmd:image"} && $tags->{'&image'}) {
		# 第１引数にURLを納める
		$ary->[0] = substr($url2, 2);	# //xxx.dom.jp → xxx.dom.jp
		$cmd .= ':image';
		$tag  = $tags->{$cmd};
		my $image = $pobj->load_tag('&image');
		return &$image($pobj, $tag, $cmd, $ary, 'http');
	}
	# 属性/リンク名
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	my $bookmark='';
	if ($ary->[0] eq 'bookmark') {
		shift(@$ary);
		my $url2 = $url;
		$url2 =~ s|^\w+://||;
		$bookmark = "<a href=\"http://b.hatena.ne.jp/entry/$url2\"><img src=\"http://b.hatena.ne.jp/entry/image/$url\" class=\"http-bookmark\"></a>";
	}
	my $name = $pobj->make_name($ary, $url);

	return "<a href=\"$url\"$attr>$name$bookmark</a>";
}
#--------------------------------------------------------------------
# ●mailto記法
#--------------------------------------------------------------------
sub mailto {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $mail = shift(@$ary);
	$mail =~ s/\"\'/'%' . unpack('H2',$1)/eg;
	$mail = 'mailto:' . $mail;
	my $attr = $pobj->make_attr($ary, $tag);
	my $name = $pobj->make_name($ary, $mail);

	return "<a href=\"$mail\"$attr>$name</a>";
}


1;
