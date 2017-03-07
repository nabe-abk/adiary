use strict;
#------------------------------------------------------------------------------
# adiary固有記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_adiary;
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
	$tags->{"adiary:this"}->{data} = \&adiary_key;
	$tags->{"adiary:key"} ->{data} = \&adiary_key;
	$tags->{"adiary:id"}  ->{data} = \&adiary_key;
	$tags->{"adiary:day"} ->{data} = \&adiary_day;
	$tags->{"adiary:tag"} ->{data} = \&adiary_tag;
	#---end

	$tags->{"adiary:this"}->{_this} = 1;
	$tags->{"adiary:key"} ->{_key}  = 1;
	$tags->{"adiary:id"}  ->{_id}   = 1;

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●adiary this/key/id 記法
#------------------------------------------------------------------------------
sub adiary_key {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $aobj    = $pobj->{aobj};
	my $replace = $pobj->{vars};

	# ID記法
	my $url;
	my $name;
	my $blogid = $aobj->{blogid};
	if ($tag->{_id}) {
		$blogid = shift(@$ary);
		$url    = $aobj->get_blog_path($blogid);
		$name   = $blogid;
	} elsif ($tag->{_this}) {
		$url = $pobj->{thisurl};
	} else {
		$url = $replace->{myself2};
	}

	my $title;
	if ($tag->{_key} || $tag->{_id}) {
		# 記事 pkey/link_key 指定
		my $link_key = shift(@$ary);
		if ($link_key ne '') {
			$name .= (($name ne '')?':':'') . $link_key;
			if ($link_key =~ /^[\d]+$/) {
				if ($link_key < 10000000) { $link_key = "0" . int($link_key); }
				$url .= $link_key;
			} elsif (substr($link_key,0,1) eq '/' || $link_key =~ /\"\'/) {
				return "(key error)";	# error
			} else {
				my $ekey = $link_key;
				$aobj->link_key_encode($ekey);
				$url .= $ekey;
			}
			#---------------------------
			# 記事タイトルの自動抽出
			#---------------------------
			# セキュリティの関係で同一ブログ内のみ参照可
			if ($blogid eq $aobj->{blogid}) {
				my $DB = $aobj->{DB};
				my $h = $DB->select_match_limit1("${blogid}_art", 'link_key', $link_key, '*cols', ['title']);
				if ($h) {
					$name = $title = $h->{title};
				}
			}
		}
	}
	return &adiary_link_base($pobj, $tag, $url, $name, $ary, $title);
}

#------------------------------------------------------------------------------
# ●adiary day 記法
#------------------------------------------------------------------------------
sub adiary_day {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $aobj = $pobj->{aobj};
	my $replace = $pobj->{vars};

	# 記事の日付指定
	my $url = $replace->{myself2};
	my $opt = shift(@$ary);
	my $name;
	if ($opt =~ m|^(\d\d\d\d)(\d\d)(\d\d)?$|
	 || $opt =~ m|^(\d\d\d\d)[-/](\d\d?)[-/](\d\d?)?$|) {	# YYYYMM YYYYMMDD
		$name = $opt;
		$url .= sprintf("$1%02d%02d", $2, $3);
	} elsif ($opt =~ m|^(\d\d\d\d)[-/]?(\d\d)$|) {
		$name = $opt;
		$url .= sprintf("$1%02d", $2);
	} elsif ($opt =~ m|^(\d\d\d\d)$|) {
		$name = $opt;
		$url .= $opt;
	} else {
		return '[date:(format error)]';
	}

	return &adiary_link_base($pobj, $tag, $url, $name, $ary);
}

#------------------------------------------------------------------------------
# ●adiary tag 記法
#------------------------------------------------------------------------------
# [tag:import,tag::tag2,tag\:tag:リンク名]
sub adiary_tag {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $aobj = $pobj->{aobj};
	my $replace = $pobj->{vars};

	my $x = shift(@$ary);
	while(@$ary) {
		if (!($ary->[0] eq '' && $ary->[1] ne '')) {
			last;
		}
		shift(@$ary);
		$x .= '::' . shift(@$ary);
	}
	# $x = "import,tag::tag2,tag:tag"
	my @tags = split(',', $x);
	my $url = $replace->{myself} . '?&';
	foreach(@tags) {
		$pobj->encode_uricom($_);
		$url .= "t=$_&";
	}
	chop($url);

	# 属性
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	my $name = $pobj->make_name($ary, $x);

	return "<a href=\"$url\"$attr>$name</a>";
}

#------------------------------------------------------------------------------
# ○adiary  記法のベース
#------------------------------------------------------------------------------
sub adiary_link_base {
	my ($pobj, $tag, $url, $name, $ary, $title) = @_;

	# アンカー指定
	if ($ary->[0] =~ /^\#[\w\.\-]*$/) {
		$name .= $ary->[0];
		$url  .= shift(@$ary);
	}
	# title
	if ($title ne '') {
		unshift(@$ary, "title=$title");
	}
	# 属性
	my $attr = $pobj->make_attr($ary, $tag, 'http');
	# リンク名
	if ($ary->[0] ne '') { $name=join(':', @$ary); }
	return "<a href=\"$url\"$attr>$name</a>";
}

1;
