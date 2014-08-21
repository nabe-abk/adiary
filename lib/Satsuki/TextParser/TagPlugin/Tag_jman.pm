use strict;
#------------------------------------------------------------------------------
# Linux jman/FreeBSD jman 記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_jman;
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
	$tags->{"linux:jman"}  ->{data} = \&linux_jman;
	$tags->{"freebsd:jman"}->{data} = \&freebsd_jman;
	#---end
	$tags->{"freebsd:jman"}->{option} ||= '10.0';

	return ;
}

###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●Linux man記法
#------------------------------------------------------------------------------
sub linux_jman {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $section;
	my $search = shift(@$ary);
	if ($search =~ /^\d$/) {	# section 番号指定
		$section = "&Sec$search=on";
		$search  = shift(@$ary);
	} else {
		$section = "&Sec1=on&Sec2=on&Sec3=on&Sec4=on&Sec5=on&Sec6=on&Sec7=on&Sec8=on";
	}
	# 英字以外除去
	$search =~ /[^\w\-\.]/g;
	# 属性/リンク名
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	my $name = $pobj->make_name($ary, $search);

	return "<a href=\"http://search.linux.or.jp/cgi-bin/JM/man.cgi?Pagename=$search$section\"$attr>$name</a>";
}

#------------------------------------------------------------------------------
# ●FreeBSD man記法
#------------------------------------------------------------------------------
sub freebsd_jman {
	my ($pobj, $tag, $cmd, $ary) = @_;

	my $release_ver = $tag->{option};
	my $section;
	my $search = shift(@$ary);
	if ($search =~ /^\d\.\d\.\d$/) {	# RELEASE Version指定
		$release_ver = $search;
		$search      = shift(@$ary);
	}
	if ($search =~ /^\d$/) {	# section 番号指定
		$section = "&amp;sect=$search";
		$search  = shift(@$ary);
	}
	# 英字以外除去
	$search =~ /[^\w\-\.]/g;
	# 属性/リンク名
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	my $name = $pobj->make_name($ary, $search);

	return "<a href=\"http://www.jp.freebsd.org/cgi/mroff.cgi?subdir=man&lc=1&dir=jpman-$release_ver%2Fman&man=$search$section#toc\"$attr>$name</a>";
}


1;
