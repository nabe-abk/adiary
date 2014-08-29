use strict;
#------------------------------------------------------------------------------
# URLフィルター
#                                                (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_url_filter;
###############################################################################
# ■基本処理
###############################################################################
# TagEscapeのモジュール機構と連携して動作するURLフィルターです。
#
#（例）
# [&http://www.youtube.com/watch?v=njLDgvQDKdE]
#　　↓
# [filter:http://www.youtube.com/watch?v=njLDgvQDKdE]	by Satsuki.pm
#　　↓
# <module name="youtube" vid="$1">			by this plugin
#　　↓
# <iframe>-----</iframe>				by TagEscape.pm
#
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'filter'}->{data} = \&filter;
	#---end

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●filter記法
#------------------------------------------------------------------------------
sub filter {
	my $self = $_[0];
	my $r = &_filter(@_);
#	$self->{ROBJ}->debug($r);
	return $r;
}

sub _filter {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};
	my $tags = $pobj->{tags};

	my $urlf = join(':',@$ary);
	my $url  = shift(@$ary);
	if ($url =~ m|^https?$| && $ary->[0] =~ m|^//|) { $url .= ':' . shift(@$ary); }
	#------------------------------------------------------------
	# youtube
	#------------------------------------------------------------
	if ($url =~ m|^https?://www\.youtube\.com/watch\?v=(\w+)$|) {
		my $w = 480;
		my $h = 270;
		if ($ary->[0] eq 'small') { $w=320; $h=180; }
		if ($ary->[0] eq 'large') { $w=640; $h=360; }
		return "<module name=\"youtube\" vid=\"$1\" width=\"$w\" height=\"$h\">";
	}

	#------------------------------------------------------------
	# twitter
	#------------------------------------------------------------
	if ($url =~ m|^https://twitter\.com/(\w+)/status/(\d+)$|) {
		return "<module name=\"tweet\" uid=\"$1\" status-id=\"$2\">";
	}

	#------------------------------------------------------------
	# ニコニコ動画
	#------------------------------------------------------------
	if ($url =~ m|^http://www\.nicovideo\.jp/watch/(\w+)$|) {
		return "<module name=\"nico\" vid=\"$1\">";
	}
	if ($url =~ m|^http://www.nicovideo.jp/mylist/(\w+)$|) {
		return "<module name=\"nico:mylist\" mid=\"$1\">";
	}
	if ($url =~ m|^http://www.nicovideo.jp/user/(\w+)$|) {
		return "<module name=\"nico:user\" uid=\"$1\">";
	}
	if ($url =~ m|^http://com\.nicovideo\.jp/community/(\w+)$|) {
		return "<module name=\"nico:commu\" cid=\"$1\">";
	}

	#------------------------------------------------------------
	# Amazon
	#------------------------------------------------------------
	if ($url =~ m!^https?://www\.amazon\.co\.jp/(?:([^/]+)/)?(?:dp|gp/product)/(\w+)!) {
		my $title = $1;
		my $asin  = $2;
		my $tag   = $pobj->load_tag('asin');
		$title =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
		$title =~ s/[\x00-\x1F\"]//g;
		if (!exists($tags->{asin}) || ref($tag) ne 'HASH' || ref($tag->{data}) ne 'CODE') { 
			my $name = join(':', @$ary) || $title || $asin;
			return "<a href=\"http://www.amazon.co.jp/dp/$asin\">$name</a>";
		}
		if ($title ne '') { unshift(@$ary, $title); }
		unshift(@$ary, $asin);
		return &{$tag->{data}}($pobj, $tag, 'asin', $ary);
	}

	#------------------------------------------------------------
	# github/gist
	#------------------------------------------------------------
	if ($url =~ m|^https://gist\.github\.com(/[\w\-/\.]*)|) {
		return "<module name=\"gist\" path=\"$1\">";
	}
	if ($url =~ m|^https://github\.com(/[\w\-/\.]*)|) {
		return "<module name=\"gist-it\" path=\"$1\">";
	}

	#------------------------------------------------------------
	# slideshare
	#------------------------------------------------------------
	if ($url =~ m|^https?://www\.slideshare\.net/\w+/(?:[\w\-]+-)?(\w+)|) {
		my $sid = $1;
		$url =~ s/\?.*//;

		# 一応getして確認する
		while($sid =~ /[^\d]/) {
			my $http = $ROBJ->loadpm('Base::HTTP');
			my $res = $http->get($url);
			if (!ref($res)) { last; }
			foreach(@$res) {
				if ($_ !~ m|http://www\.slideshare\.net/slideshow/embed_code/(\d+)|) { next; }
				$sid=$1;
				last;
			}
			last;
		}
		my $w = 429;
		my $h = 357;
		if ($ary->[0] eq 'small') { $w=344; $h=292; }
		if ($ary->[0] eq 'large') { $w=599; $h=487; }
		return "<module name=\"slideshare\" sid=\"$sid\" width=\"$w\" height=\"$h\">";
	}

	#------------------------------------------------------------
	# http://slide.rabbit-shocker.org/
	#------------------------------------------------------------
	if ($url =~ m|http://slide\.rabbit-shocker\.org(/authors/\w+/[\w\-]+/)|) {
		my $path = $1;
		return "<module name=\"rabbit-shocker:slide\" path=\"$path\">";
	}

	#------------------------------------------------------------
	# audio/video
	#------------------------------------------------------------
	if ($url =~ m{\.(?:wave?|ogg|mp3|aac|m4a)}i) {
		return $pobj->parse_tag("[audio:$urlf]");
	}

	if ($url =~ m{\.(?:webm|mp4|m4v)}i) {
		return $pobj->parse_tag("[video:$urlf]");
	}

	#------------------------------------------------------------
	# Google map
	#------------------------------------------------------------
	{
		my $url2 = substr($ary->[0],0,2) eq '0x' ? "$url:" . shift(@$ary) : $url;
		if ($url2 =~ m!^https?://maps\.google\.(?:co\.jp|com)/maps\?(.+)$!
		 || $url2 =~ m!^<iframe .*?src="https?://maps\.google\.(?:co\.jp|com)/maps\?([^"]+)"!) {
			my $query = $1;
			$query =~ s/&(?:amp)?(?:output|source)=embed//;
			my $w = 425;
			my $h = 350;
			if ($ary->[$#$ary] eq 'small') { $w=300; $h=300; }
			if ($ary->[$#$ary] eq 'large') { $w=640; $h=480; }
			return "<module name=\"google:map\" query=\"$query\" width=\"$w\" height=\"$h\">";
		}
	}

	#------------------------------------------------------------
	# その他（URLからタイトルを取得してリンク）
	#------------------------------------------------------------
	if ($urlf =~ m|^https?://[\w\./\@\?\&\~\=\+\-%\[\]:;,\!*]+|) {
		my $http = $ROBJ->loadpm('Base::HTTP');
		my ($status, $header, $res) = $http->get($urlf);
		while(1) {
			if (!ref($res)) { last; }
			my $title='';
			my $charset;
			foreach(@$header, @$res) {
				if ( $_ =~ /charset=([\w\-]+)/) { $charset=$1; }
				if (!$charset && $_ =~ /charset=([\w\-]+)/) { $charset=$1; }
				if ($_ !~ m!<title(?:>| [^>]*>)([^<]+)</title>!i) { next; }
				$title = $1;
				last;
			}
			if ($title eq '') { last; }
			my $jcode = $ROBJ->load_codepm_if_needs($title);
			$jcode && $jcode->from_to( \$title, $charset, $ROBJ->{System_coding} );
			my $class = $pobj->make_attr([], {}, 'http');
			return "<a href=\"$urlf\"$class>$title</a>";
		}
		return "[(access failed) $urlf]";
	}

	return "[(filter unkown) $urlf]";
}

1;
1
