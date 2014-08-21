use strict;
#------------------------------------------------------------------------------
# 麻雀記法プラグイン
#                                                (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_mahjong;
###############################################################################
# ■基本処理
###############################################################################
# ●使い方
# [mj:1m2m3m 4p5rp6p 7s8s9s ton ton sp haku haku hakuy]
#
# のように書きます。スペースは区切りになりますが入れなくても構いません。
# 1m?9m 萬子（マンズ）
# 1p?9p 筒子（ピンズ）
# 1s?9s 索子（ソウズ）
# 5rm, 5rp, 5rs = 赤ドラ
# ton nan sha pei = 東南西北
# haku hatu chun  = 白ハツ中
# ura = 裏面
# sp  = 1牌分のスペース
# 最後に'y'をつけると横向き牌になります。
#
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;	# 読み捨て
	my $ROBJ  = shift;	# 読み捨て

	my $tags  = shift;

	#---begin_plugin_info
	$tags->{'mj'}->{data} = \&mahjong;
	#---end
	$tags->{'mj:img'}->{data} ||= '${pubdist}mahjong/';

	return ;
}
###############################################################################
# ■タグ処理ルーチン
###############################################################################
my %jihai=(
# 字牌
'ton'=>1,'nan'=>1,'sha'=>1,'pei'=>1,'haku'=>1,'hatu'=>1,'tyun'=>1,
# 裏、スペース
'ura'=>1,'sp'=>1,
# alias
'hatsu'=>'hatu','chun'=>'tyun');
my %suji=('m'=>'man', 'p'=>'pin', 's'=>'sou');

#------------------------------------------------------------------------------
# ●mj記法
#------------------------------------------------------------------------------
sub mahjong {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $tags = $pobj->{tags};
	my $ROBJ = $pobj->{ROBJ};

	# mode チェック
	my $tag_name = $tag->{name};
	my $argc     = $tag->{argc};
	my $mode     = $ary->[ ($argc || 1) ];
	if (exists $tags->{"$tag_name#$mode"}) {
		$tag  = $tags->{"$tag_name#$mode"};
		$mode = undef;
	}

	# decode
	my @pi;
	my $line=shift(@$ary);
	my $jihai='';
	my $s=0;
	while($s<length($line)) {
		my $x = substr($line, $s++, 1);
		if (0x30 <= ord($x) && ord($x) < 0x3a) {
			my $r='';
			my $yoko='';
			my $y = substr($line, $s++, 1);
			if ($y eq 'r') {	# 赤ドラ
				$r='r'; $y=substr($line, $s++, 1);
			}
			if ($suji{$y}) {
				if (substr($line, $s, 1) eq 'y') {	# 横
					$yoko='y'; $s++;
				}
				push(@pi, "$yoko$x$r$suji{$y}");
			}
			$jihai='';
			next;
		}
		# spaceが出たら区切りと見なす
		if ($x eq ' ') { $jihai=''; next; }
		$jihai .= $x;
		if (!$jihai{$jihai}) { next; }

		# 字牌
		my $yoko='';
		if (substr($line, $s, 1) eq 'y') {	# 横
			$yoko='y'; $s++;
		}
		if ($jihai{$jihai} != 1) { $jihai=$jihai{$jihai}; }
		push(@pi, "$yoko$jihai");
		$jihai='';
	}

	# タグ構成
	my $dir  = $pobj->replace_data( $tags->{'mj:img'}->{data} );
	my $name = $pobj->make_name($ary, 'mahjong');

	my $img = join('', map {"<img class=\"mahjong\" alt=\"$_\" src=\"$dir$_.gif\">"} @pi);
	return "<div class=\"mahjong\">$img</div>";
}

1;
