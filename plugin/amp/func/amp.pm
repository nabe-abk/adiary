#-------------------------------------------------------------------------------
# AMPモジュール
#-------------------------------------------------------------------------------
sub {
	use strict;
#-------------------------------------------------------------------------------
# ●コンストラクタ（無名クラスを生成する）
#-------------------------------------------------------------------------------
my $mop;
my $name;
{
	my $aobj = shift;
	$name = shift;
	my $ROBJ = $aobj->{ROBJ};
	my $self = $ROBJ->loadpm('MOP', $aobj->{call_file});	# 無名クラス生成用obj
	$self->{aobj} = $aobj;
	$self->{this_tm} = $ROBJ->get_lastmodified($aobj->{call_file});

	$self->{trans_png} = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $aobj->{pubdist_dir} . 'trans.png';
	$mop = $self;
}

#-------------------------------------------------------------------------------
# ●ロゴ情報の取得
#-------------------------------------------------------------------------------
$mop->{get_logo} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};
	my $blog = $aobj->{blog};

	my $file = $blog->{blog_image} || $aobj->{pubdist_dir} . 'default-logo.png';
	my $url  = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $file;

	my $tm = $ROBJ->get_lastmodified( $file );
	if ($tm == $aobj->load_plgset('amp', 'logo_tm')) {
		return $url;
	}

	my $img = $aobj->load_image_magick();
	if (!$img) { return; }

	$img->Read( $file );
	my ($x, $y) = $img->Get('width', 'height');

	$aobj->update_plgset('amp', 'logo_tm',    $tm);
	$aobj->update_plgset('amp', 'logo_width',  $x);
	$aobj->update_plgset('amp', 'logo_height', $y);
	return $url;
};

#-------------------------------------------------------------------------------
# ●メイン画像の取得
#-------------------------------------------------------------------------------
$mop->{get_main_image} = sub {
	my $self = shift;
	my $art  = shift;

	if ($art->{main_image}) { return ; }

	my $txt = $art->{amp_txt};
};

#-------------------------------------------------------------------------------
# ●AMP用のCSSで不要なセレクタリスト
#-------------------------------------------------------------------------------
	my @ignore_selector = qw(
.ddmenu
button form input select option textarea #edit
.checkbox .button .colorbox .color-picker .colorpicker
#sidebar .hatena-module #com
article.setting	.help .highlight .search .ui-icon- .social-button
#album ul.dynatree #file #iframe #selected
.design .module-edit .ui-dialog .ui-progressbar
.system table.calendar ul.hatena-section
#popup resize-parts #ui-icon-autoload
.lb-
);

#-------------------------------------------------------------------------------
# ●AMP用のCSS生成
#-------------------------------------------------------------------------------
$mop->{amp_css} = sub {
	my $self = shift;
	my $files= shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my $amp_css_file = $aobj->{blogpub_dir} . 'amp.css';
	my $uiicon_file  = $aobj->{pubdist_dir} . 'ui-icon/ui-icon.png';

	# ファイル更新チェック
	my $amp_css = $self->{this_tm} . "\n";
	foreach(@$files) {
		my $tm = $_ ? $ROBJ->get_lastmodified($_) : 0;
		$amp_css .= "$_?$tm\n";
	}
	chomp($amp_css);
	if ($aobj->load_plgset('amp', 'css_info') eq $amp_css) {
		return join('', @{ $ROBJ->fread_lines_cached($amp_css_file) });
	}

	#-------------------------------------------------------------
	# regenerate amp css
	#-------------------------------------------------------------
	my $css;
	foreach(@$files) {
		if (!$_) { next; }
		local ($/) = "\0";
		my $lines = $ROBJ->fread_lines($_);
		my $dir = ($_ =~ m|^(.*/)[^/]+$|) ? $ROBJ->{Basepath} . $1 : '';
		foreach(@$lines) {
			# オプション内に画像ファイルを含む
			$_ =~ s!url\s*\(\s*(['"])([^'"]+)\1\s*\)!
				my $q = $1;
				my $file = $2;
				if ($file =~ m|^(?:\./)*[\w-]+(?:\.[\w-]+)*$|) {
					$file = $dir . $file;
				}
				"url($q$file$q)";
			!ieg;
			$css .= $_;
		}
	}
	my @str;
	$css =~ s!/\*.*?\*/|("[^"]*")!
		$1 && push(@str, $1) && "\x00$#str";
	!esg;
	$css =~ s|\@charset[^;]*;||ig;

	my @out;
	my $uiicon;
	$css =~ s!\s*(\@media[^\{]*{)?([^\{]*)(\{[^\}]*\})!
		my $media = $1;
		my $sels  = $2;
		my $attr  = $3;
		if ($media) {
			$media =~ s/\s+/ /g;
			$media =~ s/\s*([\{\};:,])\s*/$1/g;
			push(@out, $media);
		}
		if ($sels =~ /\}(.*)/s) {
			$out[$#out] .= '}';
			$sels = $1;
		}

		if ($sels =~ /#ui-icon-autoload/ && $attr =~ /background-color\s*:\s*#([0-9A-Fa-f]+);/) {
			$uiicon = $1;
		}

		my @ary;
		foreach my $sel (split(/,/,$sels)) {
			$sel =~ s/^\s*(.*?)\s*$/$1/;
			$sel =~ s/\s*>\s*/>/g;
			if ($sel =~ /^\.w\d+$/) { next; }	# .w20 .w400
			my $f;
			foreach(@ignore_selector) {
				if (index($sel, $_) < 0) { next; }
				$f=1;
				last;
			}
			if ($f) { next; }
			push(@ary, $sel);	# 残すセレクタ
		}
		$attr =~ s/\s+/ /g;
		$attr =~ s/\s*([\{\};:,])\s*/$1/g;
		$attr =~ s/\x00(\d+)/$str[$1]/g;	# 文字列復元
		@ary && push(@out, join(',',@ary) . $attr);
		'';
	!seg;
	if ($uiicon) {
		push(@out, $self->load_uiicon_css($uiicon, $uiicon_file));
	}
	$css = join("\n", @out);

	#-------------------------------------------------------------
	# save amp css
	#-------------------------------------------------------------
	$ROBJ->fwrite_lines($amp_css_file, $css);
	$aobj->update_plgset('amp', 'css_info', $amp_css);

	return $css;
};

#-------------------------------------------------------------------------------
# ●ui-iconロード用cssの生成
#-------------------------------------------------------------------------------
$mop->{load_uiicon_css} = sub {
	my $self = shift;
	my $col  = shift;
	my $file = shift;

	my $png;
	{
		require Fcntl;
		sysopen(my $fh, $file, &Fcntl::O_RDONLY);
		binmode($fh);
		sysread($fh, $png, 0x1000);	# Max 16KB
		close($fh);
	}
	my $PLTE_OFFSET  = 0x25;
	my $COLOR_OFFSET = 0x29;
	if (substr($png, $PLTE_OFFSET, 4) ne 'PLTE') { return ''; }

	# replace color
	substr($png, $COLOR_OFFSET, 3) = chr(hex(substr($col,0,2))) . chr(hex(substr($col,2,2))) . chr(hex(substr($col,4,2)));

	# calc CRC32 for PNG
	my $GEN  = 0xEDB88320;
	my $len  = unpack('N', substr($png, $PLTE_OFFSET-4, 4)) + 4;
	my $data = substr($png, $PLTE_OFFSET, $len);
	my $crc  = 0xffffffff;
	{
		my $d;
		my $bits = $len<<3;
		my $j=0;
		for(my $i=0; $i<$bits; $i++) {
			if (($i & 7)==0) {
				$d = ord(substr($data,$j++,1));
			}
			$crc ^= ($d & 1);
			my $x = $crc & 1;
			$crc>>=1;
			$d  >>=1;
			if ($x) {
				$crc ^= $GEN;
			}
		}
		$crc = ~$crc;
		$crc = pack('C4', ($crc>>24) & 0xff, ($crc>>16) & 0xff, ($crc>>8) & 0xff, $crc & 0xff);

		my $p = $PLTE_OFFSET + $len;
		substr($png,$p,4) = $crc;
	}
	return '.ui-icon, .art-nav a:before, .art-nav a:after {'
			. 'background-image: '
			. 	'url("data:image/png;base64,' . $self->base64encode($png) . '")'
			. '}';
};

#-------------------------------------------------------------------------------
# ●AMP用のHTML生成
#-------------------------------------------------------------------------------
$mop->{amp_txt} = sub {
	my $self = shift;
	my $art  = shift;
	my $aobj = $self->{aobj};
	my $ROBJ = $self->{ROBJ};
	my $DB   = $aobj->{DB};

	if ($art->{update_tm} < $art->{amp_tm}
	 && $self->{this_tm}  < $art->{amp_tm}) {
		return $art->{amp_txt};
	}

	# AMP用HTMLの生成
	my %header;
	my $escaper = $aobj->_load_tag_escaper( $aobj->plugin_name_dir($name) . 'allow_tags.txt' );
	my $text = $escaper->escape( $art->{text}, {
		filter => sub {
			my $html = shift;
			return $self->html_filter($html, \%header);
		}
	} );
	$ROBJ->trim( $text );

	# 記録
	my $blogid = $aobj->{blogid};
	$DB->update_match("${blogid}_art", {
		amp_txt  => $text,
		amp_head => join("\n", keys(%header)),
		amp_tm   => $ROBJ->{TM}
	}, 'pkey', $art->{pkey});
	
	$art->{amp_tm} = $ROBJ->{TM};
	return ($art->{amp_txt} = $text);
};

#-------------------------------------------------------------------------------
# ●AMP用のHTML書き換えルーチン
#-------------------------------------------------------------------------------
# https://www.ampproject.org/docs/reference/components
#
my %amp_scripts = (
'amp-ad'	=> '<script async custom-element="amp-ad" src="https://cdn.ampproject.org/v0/amp-ad-0.1.js"></script>',
'amp-audio'	=> '<script async custom-element="amp-audio" src="https://cdn.ampproject.org/v0/amp-audio-0.1.js"></script>',
'amp-video'	=> '<script async custom-element="amp-video" src="https://cdn.ampproject.org/v0/amp-video-0.1.js"></script>',
'amp-iframe'	=> '<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>',
'amp-youtube'	=> '<script async custom-element="amp-youtube" src="https://cdn.ampproject.org/v0/amp-youtube-0.1.js"></script>',
'amp-twitter'	=> '<script async custom-element="amp-twitter" src="https://cdn.ampproject.org/v0/amp-twitter-0.1.js"></script>'
);
$mop->{html_filter} = sub {
	my $self = shift;
	my $html = shift;
	my $header = shift;
	my $ROBJ = $self->{ROBJ};

	foreach($html->getAll) {
		if ($_->type ne 'tag') { next; }
		my $name = "filter_" . $_->tag;
		if (! $self->{$name}) { next; }

		$self->$name($_);

		# ヘッダの追加が必要なタグ？ ex)amp-img, amp-video
		my $sc = $amp_scripts{ $_->tag };
		if ($sc) { $header->{$sc} = 1; }
	}
};

#-----------------------------------------------------------
# img
#-----------------------------------------------------------
$mop->{filter_img} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;

	if ($at->{width}  =~ /[^\d]/) { $at->{width} =0; }
	if ($at->{height} =~ /[^\d]/) { $at->{height}=0; }

	if (!$at->{width} || !$at->{height}) {
		$self->load_image_size($at);
	}
	$at->{layout}="intrinsic";

	$self->set_lastmodified($at);
	$p->setTag('amp-img');
	$p->after('html', '</amp-img>');
};

#-----------------------------------------------------------
# Google AdSense
#-----------------------------------------------------------
$mop->{filter_ins} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;

	if ($at->{class} ne 'adsbygoogle') { return; }

	foreach(keys(%$at)) {
		if (substr($_,0,5) eq 'data-') { next; }
		delete $at->{$_};
	}
	$at->{type}   = "adsense";
	$at->{layout} = "responsive";
	$at->{width}  = 300;
	$at->{height} = 250;

	$p->setTag('amp-ad');
};

#-----------------------------------------------------------
# audio
#-----------------------------------------------------------
$mop->{filter_audio} = sub {
	my $self = shift;
	my $p  = shift;
	$p->setTag('amp-audio');
};

#-----------------------------------------------------------
# video
#-----------------------------------------------------------
$mop->{filter_video} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;

	$p->setTag('amp-video');
	if ($p->isClose) { return; }

	$at->{poster} ||= $self->{trans_png};
	$self->layout($at, 180);
};

#-----------------------------------------------------------
# iframe
#-----------------------------------------------------------
$mop->{filter_iframe} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;

	my $url = $at->{src};
	#-------------------------------------------------------------
	# YouTube
	#-------------------------------------------------------------
	if ($url =~ m!^https?://(?:www\.youtube\.com|youtu\.be)/!) {
		delete $at->{src};
		$url =~ m/([\w]*)$/;
		$at->{"data-videoid"} = $1;

		$self->layout($at);
		$p->setTag('amp-youtube');
		my $c = $p->afterSearch('/iframe');
		$c && $c->setTag('amp-youtube');
		return;
	}

	#-------------------------------------------------------------
	# iframe
	#-------------------------------------------------------------
	$p->setTag('amp-iframe');
	if ($p->isClose) { return; }

	$self->layout($at);
	$p->after('html', "<amp-img layout=\"fill\" src=\"$self->{trans_png}\" placeholder></amp-img>");
};

#-----------------------------------------------------------
# source
#-----------------------------------------------------------
$mop->{filter_source} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;
	my $ROBJ = $self->{ROBJ};

	my $url = $at->{src};
	if ($url !~ m|^//|i) {
		$url =~ s|^https?:||i;
		if (substr($url,0,2) ne '//') {
			$url = $ROBJ->{ServerURL} . $url;
			$url =~ s|^https?:||i;
		}
		$at->{src} = $url;
	}
};

#-----------------------------------------------------------
# Twitter
#-----------------------------------------------------------
$mop->{filter_blockquote} = sub {
	my $self = shift;
	my $p  = shift;
	my $at = $p->attr;

	if ($at->{class} ne 'twitter-tweet') { return; }
	my $a = $p->afterSearch('a');
	if (!$a) { return; }

	my $url = $a->attr->{href};
	if ($url =~ m|https://twitter\.com/[^/]*/status(?:es)?/(\d+)|) {
		$p->setTag('amp-twitter');

		my $at2 = { 'data-tweetid' => $1 };
		$self->layout($at2);
		$p->setAttr($at2);

		my $ac = $a->next;
		if ($ac->tag eq 'a' && $ac->isClose) { $ac->remove(); }
		$a->remove();

		my $bq = $p->afterSearch('/blockquote');
		$bq && $bq->setTag('amp-twitter');
	}
};

#-----------------------------------------------------------
# layoutの処理
#-----------------------------------------------------------
$mop->{layout} = sub {
	my $self = shift;
	my $at   = shift;
	my $default = shift;

	if ($at->{style} =~  /(?:^|\s)width\s*:\s*(\d+)(?:px)?/i) { $at->{width} = $1; }
	if ($at->{style} =~ /(?:^|\s)height\s*:\s*(\d+)(?:px)?/i) { $at->{height}= $1; }

	if ($at->{width} && $at->{height}) {
		$at->{layout} = 'intrinsic';
	} else {
		$at->{layout} = 'fixed-height';
		$at->{height} ||= $default || 240;
		delete $at->{width};
	}
};

#-------------------------------------------------------------------------------
# ●更新日時の追加
#-------------------------------------------------------------------------------
$mop->{set_lastmodified} = sub {
	my $self = shift;
	my $at   = shift;
	my $ROBJ = $self->{ROBJ};
	my $url  = $at->{src};

	if (index($url, '?') >= 0) { return; }

	my $basepath = $ROBJ->{Basepath};
	my $base_len = length($basepath);
	if (substr($url, 0, $base_len) eq $basepath) {
		my $file = substr($url, $base_len);
		$ROBJ->tag_unescape($file);
		$file =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;

		my $tm = $ROBJ->get_lastmodified($file);
		$url .= "?$tm";
		$at->{src} = $url;
	}
};

#-------------------------------------------------------------------------------
# ●画像のサイズ取得
#-------------------------------------------------------------------------------
$mop->{load_image_size} = sub {
	my $self = shift;
	my $at   = shift;	# tag attributes hash
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my ($x, $y) = $self->get_image_size($at->{src});
	if (!$x) { return; }

	if (!$at->{width})  { $at->{width} =$x; }
	if (!$at->{height}) { $at->{height}=$y; }
	return;
};

#-------------------------------------------------------------------------------
# ●指定URLから画像サイズ取得
#-------------------------------------------------------------------------------
$mop->{get_image_size} = sub {
	my $self = shift;
	my $url  = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my $img = $aobj->load_image_magick();
	if (!$img) {
		$ROBJ->error('Image::Magick Load Error');
		return;
	}

	my $basepath = $ROBJ->{Basepath};
	my $base_len = length($basepath);

	my $file = substr($url, $base_len);
	if (substr($url, 0, $base_len) ne $basepath) {
		if (substr($url,0,2) eq '//') { $url = 'http:' . $url; }
		if (substr($url,0,1) eq '/')  { $url = $ROBJ->{ServerURL} . $url; }

		if ($url !~ m|^https?://|i) { return; }

		# 指定のURLから情報取得
		my $http = $ROBJ->loadpm('Base::HTTP');
		my ($status, $header, $data) = $http->get($url);
		if ($status != 200) { return; }

		$data = join('', @$data);
		my ($fh, $file) = $ROBJ->open_tmpfile();
		syswrite($fh, $data, length($data));
		seek($fh, 0, 0);
		$img->Read( file => $fh );
		close($fh);
		$ROBJ->file_delete($file);
	} else {
		$ROBJ->tag_unescape($file);
		$file =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
		$file =~ s|^/+||g;
		$file =~ s|\.+/||g;
		$img->Read( $file );
	}

	my ($x, $y) = $img->Get('width', 'height');
	return ($x, $y);
};

#-------------------------------------------------------------------------------
# ●指定URLから画像サイズ取得
#-------------------------------------------------------------------------------
my $base64table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
$mop->{base64encode} = sub {
	my $self = shift;
	my $str  = shift;
	my $ret;

	# 2 : 0000_0000 1111_1100
	# 4 : 0000_0011 1111_0000
	# 6 : 0000_1111 1100_0000
	my ($i, $j, $x);
	for($i=$x=0, $j=2; $i<length($str); $i++) {
		$x    = ($x<<8) + ord(substr($str,$i,1));
		$ret .= substr($base64table, ($x>>$j) & 0x3f, 1);

		if ($j != 6) { $j+=2; next; }
		# j==6
		$ret .= substr($base64table, $x & 0x3f, 1);
		$j    = 2;
	}
	if ($j != 2)    { $ret .= substr($base64table, ($x<<(8-$j)) & 0x3f, 1); }
	if ($j == 4)    { $ret .= '=='; }
	elsif ($j == 6) { $ret .= '=';  }

	return $ret;
};

################################################################################
################################################################################
	return $mop;
}

