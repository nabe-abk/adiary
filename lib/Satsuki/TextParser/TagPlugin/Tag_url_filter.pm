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
	my $vars = $pobj->{vars};

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
	if ($url =~ m|^http://www\.nicovideo\.jp/watch/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico\" vid=\"$1\">";
	}
	if ($url =~ m|^http://www.nicovideo.jp/mylist/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico:mylist\" mid=\"$1\">";
	}
	if ($url =~ m|^http://www.nicovideo.jp/user/(\w+)(?:\?.*)?$|) {
		return "<module name=\"nico:user\" uid=\"$1\">";
	}
	if ($url =~ m|^http://com\.nicovideo\.jp/community/(\w+)(?:\?.*)?$|) {
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
	if ($url =~ m|^https?://www\.slideshare\.net/[\w-]+/(?:[\w\-]+-)?(\w+)|) {
		my $sid = $1;
		$url =~ s/\?.*//;

		# 一応getして確認する
		while($sid =~ /[^\d]/) {
			my $http = $ROBJ->loadpm('Base::HTTP');
			my $res = $http->get($url);
			if (!ref($res)) { last; }
			foreach(@$res) {
				# https://www.slideshare.net/slideshow/embed_code/key/sqUybEjkhm2G5P
				if ($_ !~ m|https?://www\.slideshare\.net/slideshow/embed_code/key/(\w+)|) { next; }
				$sid=$1;
				last;
			}
			last;
		}
		my $w = 425;
		my $h = 355;
		if ($ary->[0] eq 'small') { $w=340; $h=290; }
		if ($ary->[0] eq 'large') { $w=595; $h=485; }
		return "<module name=\"slideshare\" sid=\"$sid\" width=\"$w\" height=\"$h\">";
	}

	#------------------------------------------------------------
	# Speaker Deck
	#------------------------------------------------------------
	if ($url =~ m|^https?://speakerdeck\.com/|) {
		my $sid = $1;
		$url =~ s/\?.*//;

		# getして確認する
		my $http = $ROBJ->loadpm('Base::HTTP');
		my $res = $http->get($url);
		my $id;
		my $raito;
		foreach(@$res) {
			# <div class="speakerdeck-embed" data-id="cc--90f" data-ratio="1.77777777777778"></div>
			if ($_ =~ m|class\s*=\s*"speakerdeck-embed"|) {
				if ($_ =~ m|data-id\s*=\s*"(\w+)"|)    { $id = $1; }
				if ($_ =~ m|data-ratio\s*=\s*"([\d\.]+)"|) { $raito = $1; }
				last;
			}
		}
		if (!$id) { return "[(not found)$url]"; }

		return "<module name=\"speakerdeck\" sid=\"$id\" raito=\"$raito\">";
	}

	#------------------------------------------------------------
	# http://slide.rabbit-shocker.org/
	#------------------------------------------------------------
	if ($url =~ m|http://slide\.rabbit-shocker\.org(/authors/\w+/[\w\-]+/)|) {
		my $path = $1;
		return "<module name=\"rabbit-shocker:slide\" path=\"$path\">";
	}


	#------------------------------------------------------------
	# Google map
	#------------------------------------------------------------
	# API infomation : https://developers.google.com/maps/documentation/embed/guide
	while ($vars->{gmap_key} && $url =~ m!^https://www\.google\.(?:co\.jp|com)/maps/(place/|dir/|)(.+)$!) {
		my $q = $2;
		my $type;
		my $opt;
		if ($1 eq 'dir/') {
			$type = 'directions';
			my ($org, $des) = split('/', $q);
			$opt = "origin=\"$org\" destination=\"$des\"";
		} elsif ($1 eq 'place/') {
			$type = 'search';
			$q =~ s|/.*||g;
			$opt = "q=\"$q\"";	# 検索語
		} elsif ($q =~ /^@(\d+\.\d+,\d+\.\d+)(?:,(\d+)z)?/) {
			$type = 'view';
			$opt  = "center=\"$1\" zoom=\"$2\"";
		} else {
			last;	# unknown url type
		}
		my $w = 425;
		my $h = 350;
		if ($ary->[$#$ary] eq 'small') { $w=300; $h=300; }
		if ($ary->[$#$ary] eq 'large') { $w='100%'; $h=480; }
		return "<module name=\"google:map:$type\" key=\"$vars->{gmap_key}\" $opt width=\"$w\" height=\"$h\">";
	}

	#------------------------------------------------------------
	# その他（audio/video）
	#------------------------------------------------------------
	if ($url =~ m{\.(?:wave?|ogg|oga|mp3|aac|m4a)}i) {
		return $pobj->parse_tag("[audio:$urlf]");
	}

	if ($url =~ m{\.(?:webm|ogv|mp4|m4v)}i) {
		return $pobj->parse_tag("[video:$urlf]");
	}

	#------------------------------------------------------------
	# その他（画像）
	#------------------------------------------------------------
	if ($url =~ m{\.(?:jpg|jpeg|png|gif|bmp)}i) {
		my $opt = (@$ary ? ':' : '') . join(':',@$ary);
		return $pobj->parse_tag("[img:$url$opt]");
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
