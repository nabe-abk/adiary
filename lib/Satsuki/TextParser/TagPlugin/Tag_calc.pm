use strict;
#------------------------------------------------------------------------------
# 電卓記法プラグイン
#                                                   (C)2013 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::TextParser::TagPlugin::Tag_calc;
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
	$tags->{"calc"}  ->{data} = \&calc;
	$tags->{"calcx"} ->{data} = sub { &calc(@_); return ''; };
	$tags->{"poland"}->{data} = \&calc;
	#---end

	return ;
}

###############################################################################
# ■タグ処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●calc記法
#------------------------------------------------------------------------------
sub calc {
	my ($pobj, $tag, $cmd, $ary) = @_;
	my $ROBJ = $pobj->{ROBJ};

	my $exp = shift(@$ary);
	# 式の解析
	my @str_buf;
	my $r = &convert_reversed_poland( $ROBJ, \@str_buf, $exp );
	if (! ref($r)) { return $r; }
	if ($cmd eq 'poland') {
		my @a = grep { $_ ne '%a' } @$r;
		return join(' ', @a);
	}
	# 式の評価
	my $r = &evaluate_poland( $ROBJ, $pobj->{vars}, \@str_buf, $r );
	$exp =~ s/\"//g;
	$exp =~ s/\(/&#40;/g;
	return "<span class=\"calc\" title=\"$exp\">$r</span>";
}

###############################################################################
# ■定義部
###############################################################################
#------------------------------------------------------------------------------
# ●演算子情報
#------------------------------------------------------------------------------
my %operators;	# 優先度配列
my %operation;	# 実行処理
# bit 0 - 右から左
# bit 1 - 単項演算子
# bit 2 - 左辺はオブジェクトで
# bit 3 - 後置単項演算子
# bit 4?12 - 演算子優先度
$operators{'('}  =  0x00;
$operators{')'}  =  0x00;
$operators{'%a'} =  0x00;	# 例外処理
$operators{'%r'} =  0x00;	# 例外処理
$operators{';'}  =  0x00;	# 例外処理
$operators{','}  =  0x10;	# 例外処理
$operators{'='}  =  0x25; $operation{'='}  = sub { $_[0]->{$_[1]}   = $_[2]; }; 
$operators{'+='} =  0x25; $operation{'+='} = sub { $_[0]->{$_[1]}  += $_[2]; };
$operators{'-='} =  0x25; $operation{'-='} = sub { $_[0]->{$_[1]}  -= $_[2]; };
$operators{'*='} =  0x25; $operation{'*='} = sub { $_[0]->{$_[1]}  *= $_[2]; };
$operators{'/='} =  0x25; $operation{'/='} = sub { $_[0]->{$_[1]}  /= $_[2]; };
$operators{'%='} =  0x25; $operation{'%='} = sub { $_[0]->{$_[1]}  %= $_[2]; };
$operators{'%.='}=  0x25; $operation{'%.='}= sub { $_[0]->{$_[1]}  .= $_[2]; };
$operators{'**='}=  0x25; $operation{'**='}= sub { $_[0]->{$_[1]} **= $_[2]; };
$operators{'^='} =  0x25; $operation{'^='} = sub { $_[0]->{$_[1]} **= $_[2]; };
$operators{'<<='}=  0x25; $operation{'<<='}= sub { $_[0]->{$_[1]} <<= $_[2]; };
$operators{'>>='}=  0x25; $operation{'>>='}= sub { $_[0]->{$_[1]} >>= $_[2]; };
$operators{'&='} =  0x25; $operation{'&='} = sub { $_[0]->{$_[1]}  &= $_[2]; };
$operators{'|='} =  0x25; $operation{'|='} = sub { $_[0]->{$_[1]}  |= $_[2]; };
$operators{'&&='}=  0x25; $operation{'&&='}= sub { $_[0]->{$_[1]} &&= $_[2]; };
$operators{'||='}=  0x25; $operation{'||='}= sub { $_[0]->{$_[1]} ||= $_[2]; };
$operators{'||'} =  0x30; $operation{'||'} = sub { $_[0] || $_[1]; };
$operators{'&&'} =  0x40; $operation{'&&'} = sub { $_[0] && $_[1]; };
$operators{'|'}  =  0x50; $operation{'|'}  = sub { $_[0] |  $_[1]; };
#$operators{'^'}  =  0x60; $operation{'^'}  = sub { $_[0] ^  $_[1]; };
$operators{'&'}  =  0x70; $operation{'&'}  = sub { $_[0] &  $_[1]; };
$operators{'=='} =  0x80; $operation{'=='} = sub { $_[0] == $_[1]; };
$operators{'!='} =  0x80; $operation{'!='} = sub { $_[0] != $_[1]; };
$operators{'<=>'}=  0x80; $operation{'<=>'}= sub { $_[0] <=> $_[1]; };
$operators{'%e'} =  0x80; $operation{'%e'} = sub { $_[0] eq $_[1]; };
$operators{'%n'} =  0x80; $operation{'%n'} = sub { $_[0] ne $_[1]; };
$operators{'<'}  =  0x90; $operation{'<'}  = sub { $_[0] <  $_[1]; };
$operators{'>'}  =  0x90; $operation{'>'}  = sub { $_[0] >  $_[1]; };
$operators{'<='} =  0x90; $operation{'<='} = sub { $_[0] <= $_[1]; };
$operators{'>='} =  0x90; $operation{'>='} = sub { $_[0] >= $_[1]; };
$operators{'%d'} =  0xa2; $operation{'%d'} = sub { defined $_[0]; };
$operators{'>>'} =  0xb0; $operation{'>>'} = sub { $_[0] >> $_[1]; };
$operators{'<<'} =  0xb0; $operation{'<<'} = sub { $_[0] << $_[1]; };
$operators{'+'}  =  0xc0; $operation{'+'}  = sub { $_[0] +  $_[1]; };
$operators{'-'}  =  0xc0; $operation{'-'}  = sub { $_[0] -  $_[1]; };
$operators{'%.'} =  0xc0; $operation{'%.'} = sub { $_[0] .  $_[1]; };
$operators{'*'}  =  0xd0; $operation{'*'}  = sub { $_[0] *  $_[1]; };
$operators{'/'}  =  0xd0; $operation{'/'}  = sub { $_[0] /  $_[1]; };
$operators{'%'}  =  0xd0; $operation{'%'}  = sub { $_[0] %  $_[1]; };
$operators{'%x'} =  0xd0; $operation{'%x'} = sub { $_[0] x  $_[1]; };
$operators{'%+'} =  0xee; $operation{'%+'} = sub { ($_[0]->{$_[1]})++; };
$operators{'%-'} =  0xee; $operation{'%-'} = sub { ($_[0]->{$_[1]})--; };
$operators{'%++'}=  0xe6; $operation{'%++'}= sub { ++($_[0]->{$_[1]}); };
$operators{'%--'}=  0xe6; $operation{'%--'}= sub { --($_[0]->{$_[1]}); };
$operators{'!'}  =  0xf2; $operation{'!'}  = sub { ! $_[0]; };
$operators{'~'}  =  0xf2; $operation{'~'}  = sub { ~ $_[0]; };
$operators{'^'}  = 0x100; $operation{'^'}  = sub { $_[0] ** $_[1]; };
$operators{'**'} = 0x100; $operation{'**'} = sub { $_[0] ** $_[1]; };
$operators{'#'}  = 0x200; $operation{'#'}  = sub { $_[0]->[ $_[1] ]; };	# 逆かも？
$operators{'%m'} = 0x202; $operation{'%m'} = sub { - $_[0]; };

#------------------------------------------------------------------------------
# ●関数情報
#------------------------------------------------------------------------------
my %functions;
$functions{'sin'}  = sub { sin($_[0]) };
$functions{'cos'}  = sub { cos($_[0]) };
$functions{'tan'}  = sub { sin($_[0])/cos($_[0]) };
$functions{'asin'} = sub { atan2($_[0] / sqrt(1 - $_[0] * $_[0]), 1) };
$functions{'acos'} = sub { atan2(sqrt(1 - $_[0] * $_[0]) / $_[0], 1) };
$functions{'atan'} = sub { atan2($_[0], 1) };
$functions{'atan2'}= sub { atan2($_[0], $_[1]) };
$functions{'rand'} = sub { rand($_[0]) };
$functions{'oct'}  = sub { oct($_[0]) };
$functions{'hex'}  = sub { hex($_[0]) };
$functions{'abs'}  = sub { ($_[0] < 0) ? -$_[0] : $_[0] };
$functions{'ln'}   = sub { log($_[0]) };		# 自然対数
$functions{'log'}  = sub { log($_[0])/log(10) };	# 常用対数
$functions{'exp'}  = sub { exp($_[0]) };
$functions{'sqrt'} = sub { sqrt($_[0]) };
$functions{'pow'}  = sub { $_[0] ** $_[1] };
$functions{'sqr'}  = $functions{'sqrt'};
$functions{'root'} = $functions{'sqrt'};

$functions{'floor'} = sub { int($_[0]) };
$functions{'round'} = sub { int($_[0]+0.5) };
$functions{'ceil'}  = sub { (int($_[0]) != $_[0]) ? ($_[0]+1) : $_[0] };
$functions{'int'}   = $functions{'floor'};
$functions{'rint'}  = $functions{'round'};
$functions{'cint'}  = $functions{'round'};
$functions{'ceiling'}=$functions{'ceil'};

$functions{'max'} = sub { my $x=shift(@_); ($x<$_) && ($x=$_) foreach(@_); $x; };
$functions{'min'} = sub { my $x=shift(@_); ($x>$_) && ($x=$_) foreach(@_); $x; };

$functions{'pow10'}  = sub { 10 ** $_[0] };
$functions{'log10'}  = $functions{'log'};
$functions{'log2'}   = sub { log($_[0])/log(2) };
$functions{'hypot'}  = sub { sqrt($_[0] * $_[0] + $_[1] * $_[1]) };
$functions{'fabs'}   = $functions{'abs'};
$functions{'fma'}    = sub { $_[0] * $_[1] + $_[2] };
$functions{'remainder'} = sub { $_[0] - int(&{$functions{'round'}}($_[0] / $_[1])) * $_[1] };
$functions{'ldexp'}  = sub { $_[0] * (2 ** $_[1]) };
$functions{'scalb'}  = sub { $_[0] * ($_[1] ** $_[2]) };

$functions{'rad2deg'}= sub { $_[0] * 180 / 3.14159265358979323846 };
$functions{'def2rag'}= sub { $_[0] * 3.14159265358979323846 / 180 };


#--- 時計関数 --------------------------
$functions{'time'}      = sub { time() };
$functions{'localtime'} = sub {
	my %h;
	$h{tm} = $_[0];
	( $h{sec},  $h{min},  $h{hour},
	  $h{_day}, $h{_mon}, $h{year},
	  $h{wday}, $h{yday}, $h{isdst}) = localtime($_[0]);
	$h{year} +=1900;
	$h{_mon} ++;
	return \%h;
};

#--- 文字列関数 ------------------------
$functions{'substr'} = sub { substr($_[0], $_[1], $_[2]) };
$functions{'ord'}    = sub { ord(@_) };
$functions{'length'} = sub { length(@_) };
$functions{'index'}  = sub { index ($_[0], $_[1], $_[2]) };
$functions{'rindex'} = sub { rindex($_[0], $_[1], $_[2]) };
$functions{'chop'}   = sub { chop (@_) };
$functions{'chomp'}  = sub { chomp(@_) };
$functions{'regexp'}  = sub { $_[0] =~ /$_[1]/; };
$functions{'replace'} = sub { $_[0] =~ s/$_[1]/$_[2]/g };
$functions{'split'} = sub { my $x=shift; [ split(/$x/, @_) ] };
$functions{'join'}  = sub {
	my $x = shift; my $y = $_[0];
	if (ref($y) eq 'ARRAY') { return join($x, @$y) }
	join($x, @_);
};
$functions{'crypt'}  = sub { crypt($_[0], $_[1]) };

#--- 配列関数 --------------------------
$functions{'push'} = sub { my $ary=shift; push(@$ary, @_) };
$functions{'pop'}  = sub { pop(@{ $_[0] }) };
$functions{'unshift'} = sub { my $ary=shift; unshift(@$ary, @_) };
$functions{'shift'}   = sub { shift(@{ $_[0] }) };
$functions{'sort'}    = sub {[ sort {$a <=> $b} (ref($_[0]) ? @{ $_[0] } : @_) ]};
$functions{'strsort'} = sub {[ sort {$a cmp $b} (ref($_[0]) ? @{ $_[0] } : @_) ]};
$functions{'reverse'} = sub {[ reverse (ref($_[0]) ? @{ $_[0] } : @_) ]};

#--- 条件分岐 --------------------------
$functions{'if'} = sub { $_[0] ? $_[1] : $_[2] };




###############################################################################
# ■解析部
###############################################################################
#------------------------------------------------------------------------------
# ●逆ポーランド記法に変換
#------------------------------------------------------------------------------
sub convert_reversed_poland {
	my ($ROBJ, $str, $cmd) = @_;
	# 文字列の避難措置
	$cmd =~ s/\x00-\x03//g;
	$cmd =~ s/\"((?:\\.|[^\"])*)\"/push(@$str, $1), "\x01$#$str\x01"/eg;
	foreach(@$str) {
		$_ =~ s/\$([\w\.]+)/\x02$1\x02/g;	# 変数置換評価
		$_ =~ s/\$\[([\w\.]+)\]/\x02$1\x02/g;	# 変数置換評価
		$_ =~ s/\\(.)/$1/g;			# \ エスケープ
	}
	$cmd =~ s/\'([^\']*)\'/push(@$str, $1), "\x01$#$str\x01"/eg;

	# 変換のための置換処理
	$cmd =~ s/(\W)\.([^\w=])/$1%.$2/g;	# 文字連結
	$cmd =~ s/\.=/%.=/g;			# 代入＋文字連結
	$cmd =~ s/(\W)eq(\W)/$1%e$2/g;		# 文字比較
	$cmd =~ s/(\W)ne(\W)/$1%n$2/g;		# 文字比較
	$cmd =~ s/(\W)defined(\W)/$1%d$2/g;	# 定義済
	# $cmd =~ s/(\W)x(\W)/$1%x$2/g;		# 文字列 x n
	$cmd =~ s/\+\+/%+/g;			# ++
	$cmd =~ s/\-\-/%-/g;			# --
	$cmd =~ s/\s//g;			# 空白削除
	$cmd =~ s/\(\)/(undef)/g;		# func() の処理

	# 構文解析
	# my $z = $cmd; $z =~ s/\e/|/g; print "\n*** $z\n";	# debug
	my @op  = ('(');	# 演算子スタック
	my @opl = ( 0 );	# スタックの演算子優先度 保存用
	my @poland;		# 逆ポーランド記法記録用
	my $x = $cmd . ')';
	my $right_arc = 0;
	while ($x =~ /(.*?)([=,\(\)\+\-<>\^\*\/&|%!;\#\@])(.*)/s) {
		if ($1 ne '') { push(@poland,  $1); }	# 　演算子の手前を出力
		my $op  = $2;
		if (length($3) >1 && $operators{$op . substr($3, 0, 2)}) {	# 3文字の演算子？
			$op .= substr($3, 0, 2);
			$x   = substr($3, 2);	# 残り
		} elsif ($3 ne '' && $operators{$op . substr($3, 0, 1)}) {	# 2文字の演算子？
			$op .= substr($3, 0, 1);
			$x   = substr($3, 1);	# 残り
		} else {
			$x = $3;		# 残り
		}
		if (!$right_arc && $1 eq '') {	# 演算子の直前が ) でなく、空でもない
			if ($op eq '-') { $op = '%m'; }	# 数値の負数表現判別
			elsif ($op eq '%+' || $op eq '%-') {	# ++/--
				$op .= substr($op, 1, 1);	# %+/%-(後置) → %++/%--（前置）
			}
		}
		# 演算子優先度を取り出す（bit 0 は右優先判別のときに使用）
		my $opl = $operators{$op};
		#
		# $op  読み込んだ演算子
		# $opl 演算子優先度
		# $1   演算子の前
		#
		if ($op eq '(') {
			push(@op, '('); push(@opl, 0);
			if ($1 eq '') {		# 裸のかっこは配列化
				push(@op, '%a');
				push(@opl, 0);
			} else {		# xxxxxx() の関数実行
				push(@op, '%r');
				push(@opl, 0);
			}
		} else {
			my $z = $opl & 1;	# 右から優先の場合 $z = 1
			if ($opl & 8) {	# 後置単項演算子なら出力
				push(@poland, $op);
				$right_arc = -1;	# 括弧扱い
				next;
			} elsif ($opl[$#opl] & $opl & 2) {	# スタックトップと現演算子が同時に単項演算子
				# 優先度に関係なく演算子を取り出さない
			} else {
				while ($#opl>=0 && $opl[$#opl] >= $opl + $z) {
					my $op0   = pop(@op);
					my $level = pop(@opl);
					if ($op0 eq '(') { last; }	# '(' の場合、処理を強制終了
					# 現演算子より優先度の低い演算子を出力
					push(@poland, $op0);	# 逆ポーランド記法
				}
			}
			# 新しい演算子を積む
			if ($op eq ')') {
				$right_arc = 1;
			} else {
				$right_arc = 0;
				push(@op,  $op);
				push(@opl, $opl);
			}
		}
		# print "poland exp.   : ", join(' ', @poland), "\n";
		# print "op stack dump : ", join(' ', @op), "\n";
	}
	#
	# 変換完了
	#
	if ($x ne '' || $#op >= 0) {	# 残った文字列 or 演算子スタックを確認
		return  "expression error";	# エラー
	}
	return \@poland;
}

#------------------------------------------------------------------------------
# ●逆ポーランド記法を eval 形式に変換
#------------------------------------------------------------------------------
sub evaluate_poland {
	my ($ROBJ, $vars, $str, $pol) = @_;

	# 処理準備
	$vars->{PI} ||= 3.14159265358979323846;
	$vars->{e}  ||= 2.71828182845905;
	my @types = map { &get_element_type($_) } @$pol;

	# 単一置換式 <@t.var> 等
	if ($#$pol == 0 && $types[0] eq 'obj') { return &get_object($vars, $pol->[0]); }
	# 単一置換式（定数）
	if ($#$pol == 0 && $types[0] eq 'const') { return $pol->[0]; }

	# 複式
	my @stack;
	my @stack_type;
	my $i = 0;
	foreach my $p (@$pol) {
		## print "  dump stack : ", join(' ', @stack), "\n";
		## print "  type stack : ", join(' ', @stack_type), "\n";
		my $type = $types[$i++];		# 型をロード
		if ($type eq 'op') {			# 演算子
			my $op  = $p;
			my $opl = $operators{$p};
			my $opf = $operation{$p};	# 関数
			## printf("\top = $op [%x]\n", $opl);

			my $x  = pop(@stack);
			my $xt = pop(@stack_type);
			if (!defined $x) { last; }	# エラー
			if ($xt eq 'obj' && ($opl & 6)!=6) { $x = &get_object($vars, $x); }
			if (ref($x) eq 'ARRAY') { $x = pop(@$x); }
			if ($opf) {
				if ((~$opl) & 2) {	# ２項演算子
					# $y (op) $x
					my $y  = pop(@stack);
					my $yt = pop(@stack_type);
					if (!defined $y) { last; }	# エラー
					if (ref($y) eq 'ARRAY') { $y = pop(@$y); }
					if ($opl & 4) {		# 左辺オブジェクト渡し
						if ($yt ne 'obj') { push(@stack, $yt); last; }	#エラー
						my ($obj, $name) = &get_object_sep($vars, $y);
						eval { $x = &$opf($obj, $name, $x); };
						if ($@) { return $@; }
					} else {
						if ($yt eq 'obj') { $y = &get_object($vars, $y); }
						eval { $x = &$opf($y, $x); };
						if ($@) { return $@; }
					}
				} elsif ($opl & 4) {	# 単項演算子, 左辺オブジェクト渡し
					if ($xt ne 'obj') { push(@stack,$xt); last; }	#エラー
					my ($obj, $name) = &get_object_sep($vars, $x);
					eval { $x = &$opf($obj, $name); };
					if ($@) { return $@; }
				} else {	# 単項演算子
					$x  = &$opf($x);
				}
				push(@stack, $x);
				push(@stack_type, 'const');
				next;
			}
			#
			# セミコロン処理
			#
			if ($op eq ';')  {
				if (@stack) {	# 左辺値読み捨て
					pop(@stack);
					pop(@stack_type);
				}
				push(@stack,      $x);
				push(@stack_type, $xt);
				next;
			}
			#
			# カンマ処理
			#
			if ($op eq '%a') {	# %a(a, b, c, ...);
				my @x2 = split("\x03,", $x);
				if ($#x2 > 0) { $x = \@x2; $xt='array'; }
				push(@stack,      $x);		# 配列化
				push(@stack_type, $xt);
				next;
			}
			if ($op ne ',' && $op ne '%r') { next; }
			my $y  = pop(@stack);
			my $yt = pop(@stack_type);
			if ($op eq ',')  {
				if ($yt eq 'obj') { $y = &get_object($vars, $y); }
				push(@stack,      "$y\x03,$x");
				push(@stack_type, 'array');
				next;
			}
			#
			# 関数実行
			#
			if ($y eq 'array') {	# array(a, b, c, ...);
				$x = [ split("\x03,", $x) ];
				push(@stack,     $x);		# 配列化
				push(@stack_type, 'array');
				next;
			} elsif ($yt eq 'obj') {
				if ($y eq 'clear') {		# 初期化関数
					$_[0] = $vars = {};
					push(@stack,      undef);
					push(@stack_type, 'const');
					next;
				}
				my $func = $functions{$y};
				if (! ref($func)) {	# エラー
					return "Unknown function '$y'";
				}
				if ($xt eq 'array') {	# 配列化
					$x = [ split("\x03,", $x) ];
				} else {
					$x = [$x];
				}
				eval { $x = &$func(@$x); };
				if ($@) { $x="Error [$@]"; }
				push(@stack,      $x);
				push(@stack_type, '*');
			} else {	# エラー
				push(@stack,      $y);
				push(@stack_type, $yt);
				last;
			}
			next;

		} elsif ($type eq 'error') {	# エラー
			push(@stack,      $p);
			push(@stack_type, $type);
			last;

		} elsif ($type eq 'string') {	# 文字列
			$p =~ s/\x01(\d+)\x01/$str->[$1]/;
			$p =~ s/\x02([\w\.]+)\x02/ &get_object($vars, $1) /eg;
			push(@stack,      $p);
			push(@stack_type, 'const');
		} else {	# オブジェクト指定や定数など
			push(@stack,      $p);
			push(@stack_type, $type);
		}
	}

	if ($#stack != 0) {
		return "expression error($#stack) $stack[0] $stack[1] $stack[2] $stack[3]";	# エラー行を置換
	}
	my $exp  = pop(@stack);
	my $type = pop(@stack_type);
	if ($type eq 'obj') { return &get_object($vars, $exp); }	# オブジェクの場合は評価
	$exp =~ s/^.*\x03,([^\x03]*?)$/$1/;				# , の場合最後を戻り値とする
	return $exp;
}

#------------------------------------------------------------------------------
# ●要素の種類を取得
#------------------------------------------------------------------------------
sub get_element_type {
	my $p = $_[0];
	if (exists $operators{$p}) { return 'op'; }		# 演算子
	if ($p =~ /^\x01\d+\x01$/)   { return 'string'; }	# 文字列（加工しない）
	if ($p =~ /[^\w\.]/)         { return 'error'; }	# 不正な文字列／エラー
	if ($p =~ /^[\d\.]+$/ || $p =~ /^0x[\dA-Fa-f]+$/) { return 'const'; }	# 数値（加工しない）
	if ($p =~ /^(\d+)\.\w+$/) {		# 説明付きの数値  10.is_cache_on など
		$_[0] = $1; return 'const';
	}
	if ($p =~ /^yes$/i || $p =~ /^true$/i) {
		$_[0] = 1; return 'const';
	}
	if ($p =~ /^no$/i || $p =~ /^false$/i) {
		$_[0] = 0; return 'const';
	}
	if ($p =~ /^new(|\..*)$/) {
		if ($1 eq '' || $1 eq '.hash') { $_[0] = '{}'; return 'hash';  }
		if ($1 eq '.array')            { $_[0] = '[]'; return 'array'; }
		$_[0] = ''; return 'error';
	}
	if ($p eq 'undef') { $_[0]=undef; return 'const'; }

	return 'obj';
}

#------------------------------------------------------------------------------
# ●名前からオブジェクトの取得
#------------------------------------------------------------------------------
sub get_object {
	my ($obj, $name) = &get_object_sep(@_);
	return ($name ne '') ? $obj->{$name} : $name;
}
sub get_object_sep {
	my ($obj, $name) = @_;
	$name =~ s/[^\w\.]//g;		# 半角英数と _ . 以外の文字を除去
	if ($name eq '') { return 'undef'; }	# エラー時未定義を示すオブジェクトを返す

	my @ary = split(/\./, $name);
	my $last = pop(@ary);
	foreach $name (@ary) {
		$obj = $obj->{$name};
	}
	return ($obj, $last);
}

1;
