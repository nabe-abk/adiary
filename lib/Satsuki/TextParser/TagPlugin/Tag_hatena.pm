use strict;
#------------------------------------------------------------------------------
# はてな記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_hatena;
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
	$tags->{'jan'}     ->{data} = \&hatena_jan;
	$tags->{'hatena:f'}->{data} = \&hatena_fotolife;
	$tags->{'graph:id'}->{data} = \&hatena_graph;
	#---end

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●はてなjan/ean記法
#------------------------------------------------------------------------------
sub hatena_jan {
	my ($pobj, $tag, $cmd, $ary) = @_;

	# janコード
	my $jan = shift(@$ary);
	$jan =~ s/[^\d]//g;	# 不要文字除去

	# 画像モードは標準サイズのみ対応 (png/gif/jpg 判別不能のため)
	my $name = "$cmd:$jan";
	if ($ary->[0] ne '' && $ary->[0] ne 'title') { $name=join(':', @$ary); }
	if ($name eq 'image') {
		$name = "<img src=\"http://d.hatena.ne.jp/images/ean/${jan}_m.gif\" alt=\"$jan\" class=\"ean\">";
	} elsif ($name eq 'barcode') {
		$name = "<img src=\"http://d.hatena.ne.jp/barcode?ean=$jan\" alt=\"$jan\" class=\"barcode\">";
	}
	my $attr = $pobj->make_attr($ary, $tag);
	   $name = $pobj->make_name($ary, $name);

	return "<a href=\"http://d.hatena.ne.jp/ean/$jan\"$attr>$name</a>";
}

#------------------------------------------------------------------------------
# ●はてなfotolife記法
#------------------------------------------------------------------------------
sub hatena_fotolife {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $name = "$cmd:" . join(':', @$ary);
	# f:id:hatenadiary:20041007101545j:image
	# f:id:hatenadiary:20041007101545j:image:small
	# f:id:hatenadiary:20041007101545j:image:w50
	my $id = shift(@$ary);
	$id =~ s/\W//g;
	my $id_key = substr($id, 0, 1);
	my $code = shift(@$ary);
	$code =~ s/[^\d]//g;
	my $yyyymmdd = substr($code, 0, 8);
	my $img_url = "http://f.hatena.ne.jp/images/fotolife/$id_key/$id/$yyyymmdd/$code";
	my $url     = "http://f.hatena.ne.jp/$id/$code";

	# 画像モード判別
	my $image = shift(@$ary);
	my $size  = shift(@$ary);
	if ($size eq 'small') { $img_url .= '_m.gif'; } else { $img_url .= '.jpg'; }
	if    ($size =~ /^w(\d+%?)$/) { $size=" width=\"$1\"";  }
	elsif ($size =~ /^h(\d+%?)$/) { $size=" height=\"$1\""; }
	else { $size=''; }

	# 属性
	my $attr = $pobj->make_attr($ary, $tag, 'image');

	return "<a href=\"$url\"$attr><img src=\"$img_url\" alt=\"$name\" class=\"hatena-fotolife\"$size></a>";
}

#------------------------------------------------------------------------------
# ●はてなgraph記法
#------------------------------------------------------------------------------
# regist = graph:id
sub hatena_graph {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};

	my $name = "$cmd:" . join(':', @$ary);
	# graph:id:sample
	# graph:id:sample:しなもんの体重
	# graph:id:sample:しなもんの体重:image
	my $id  = shift(@$ary);
	$id =~ s/\W//g;
	my $url = "http://graph.hatena.ne.jp/$id/";
	#
	my $graph;
	if ($ary->[0] ne '') {
		$name = $graph = shift(@$ary);
		my $jcode = $pobj->{jcode} ||= $ROBJ->load_codepm();
		$jcode->from_to(\$graph, $ROBJ->{System_coding}, 'UTF-8');
		$pobj->encode_uricom($graph);
		$url .= $graph . '/';
	}
	# 画像モード
	if ($graph ne '' && $ary->[0] eq 'image') {
		my $attr = $pobj->make_attr($ary, $tag, 'image');
		   $name = $pobj->make_name($ary, $name);
		return "<a href=\"$url\"$attr><img src=\"http://graph.hatena.ne.jp/$id/graph?graphname=$graph\" class=\"hatena-graph-image graph\" alt=\"$name\"></a>";
	}
	# 属性/リンク名
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	   $name = $pobj->make_name($ary, $name);

	# リンク構成
	return "<a href=\"$url\"$attr\">$name</a>";
}

1;
