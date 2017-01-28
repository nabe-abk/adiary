use strict;
#------------------------------------------------------------------------------
# aidio/videoタグ
#                                                (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_audio;
###############################################################################
# ■MIMEタイプ定義
###############################################################################
my %audio_mime = (
'wav'  => 'wave',
'wave' => 'wave',
'ogg'  => 'ogg',
'oga'  => 'ogg',
'mp3'  => 'mpeg',
'aac'  => 'aac',
'mp4'  => 'aac',
'm4a'  => 'aac'
);
my %video_mime = (
'ogg'  => 'ogg',
'ogv'  => 'ogg',
'webm' => 'webm',
'mp4'  => 'mp4',
'm4v'  => 'mp4'
);

###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て
	my $tags  = shift;

	#---begin_plugin_info
	$tags->{audio}->{data} = \&audio_video;
	$tags->{video}->{data} = \&audio_video;
	#---end
	
	$tags->{audio}->{name} = 'audio';
	$tags->{audio}->{mime} = \%audio_mime;
	$tags->{video}->{name} = 'video';
	$tags->{video}->{mime} = \%video_mime;

	return ;
}

###############################################################################
# ■タグ処理ルーチン
###############################################################################
sub audio_video {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tname = $tag->{name};
	my $width;
	my $height;

	my $ftag = $pobj->{tags}->{file};
	if ($ftag && $cmd =~ /^file:(\w+)/) {
		# [file:xxx] タグからのaliasの時
		unshift(@$ary, $1);
		my $url = $pobj->replace_link($ftag->{data}, $ary, $ftag->{argc});
		foreach(@$ary) {
			if ($_ =~ /^w(\d+)$/) { $width =$1; }
			if ($_ =~ /^h(\d+)$/) { $height=$1; }
		}
		$ary = [ $url ];
	}

	my $url0;
	my $src='';
	while(@$ary) {
		my $url = shift(@$ary);
		if ($url eq 'http' || $url eq 'https') {
			$url .= ':' . shift(@$ary);
		}
		$url0 ||= $url;
		if ($url =~ /^w(\d+)$/) { $width =$1; }
		if ($url =~ /^h(\d+)$/) { $height=$1; }

		my $mime='';
		my $url2 = $url;
		$url2 =~ tr/A-Z/a-z/;
		if ($url =~ /\.(\w+)$/ && $tag->{mime}->{$1}) {
			$mime = ' type="' . $tname . '/' . $tag->{mime}->{$1} . '"'
		}

		$src .= "<source src=\"$url\"$mime>";
	}
	if (!$src) { return''; }

	$width  = $width  ?  " width=\"$width\""  : '';
	$height = $height ? " height=\"$height\"" : '';

	return "<$tname$width$height controls>$src(Browser not support $tname tag) <a class=\"$tname\" href=\"$url0\">$url0</a></$tname>";
}

1;
