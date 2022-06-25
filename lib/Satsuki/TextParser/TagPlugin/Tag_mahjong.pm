use strict;
#-------------------------------------------------------------------------------
# 麻雀記法プラグイン
#                                                (C)2013 nabe / nabe@abk.nu
#-------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_mahjong;
################################################################################
# ■基本処理
################################################################################
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
#-------------------------------------------------------------------------------
# ●コンストラクタ
#-------------------------------------------------------------------------------
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
################################################################################
# ■タグ処理ルーチン
################################################################################
my %jihai=(
# 字牌
'ton'=>1,'nan'=>1,'sha'=>1,'pei'=>1,'haku'=>1,'hatu'=>1,'chun'=>1,
# 裏、スペース
'ura'=>1,'sp'=>1,
# alias
'hatsu'=>'hatu','tyun'=>'chun');
my %suhai=('m'=>'man', 'p'=>'pin', 's'=>'sou');

#-------------------------------------------------------------------------------
# ●mj記法
#-------------------------------------------------------------------------------
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

	# 5r --> r
	my $line=shift(@$ary);
	$line =~ s/5r/r/g;
	$line .= ' ';

	my @pi;
	my $err;
	while($line ne '') {
		if ($line =~ /^ +(.*)/) {	# space
			$line = $^N;
			next;
		}
		if ($line =~ /^((?:[0-9r]y?)+)([spm])(y?)(.*)/) {	# 数牌
			$line = $^N;
			my $num = $1;
			my $s  = $suhai{$2};
			my $yy = $3;
			$num =~ s/([0-9r])(y?)/
				my $y = $2 || $yy;
				push(@pi, "$y$s$1");
			/eg;
			next;
		}

		# 字牌
		if ($line =~ /^(\w+?)(y?) (.*)/ && $jihai{$1}) {	# 字牌
			$line = $^N;
			push(@pi, "$2$1");
			next;
		}

		# error
		$line =~ s/ +$//;
		$err = "\"$line\"";
		last;
	}

	# タグ構成
	my $dir  = $pobj->replace_vars( $tags->{'mj:img'}->{data} );
	my $name = $pobj->make_name($ary, 'mahjong');

	if ($err) {
		return "<div class=\"mahjong\">syntax error!! : $err</div>";
	}

	my $img = join('', map {"<img class=\"mahjong\" alt=\"$_\" src=\"$dir$_.png\">"} @pi);
	return "<div class=\"mahjong\">$img</div>";
}

1;
