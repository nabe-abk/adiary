use strict;
#------------------------------------------------------------------------------
# skeleton parser / 構文解析コンパイラ
#						(C)2006-2016 nabe@abk
#------------------------------------------------------------------------------
package Satsuki::Base::Compiler;
our $VERSION = '1.73';
#(簡易履歴)
# 2016/01 Ver1.73  load_from_aryのバグ修正
# 2015/11 Ver1.72  関数展開時の出力書式を綺麗に（実行結果に変化なし）
# 2015/05 Ver1.71  <@ifcall(cond,f)>バグ修正。begin_array等で最後の空白行を除去。
# 2014/09 Ver1.70  begin_hash/array/string中にコマンドを書けるように。
# 2014/08 Ver1.63  begin_hashの順序保存を標準でoffに。
# 2013/08 Ver1.62  サブルーチン展開関連bugfix。<$break>の警告。pragma行処理bugfix
# 2013/08 Ver1.61  サブルーチンの展開位置を宣言場所に変更（クロージャ対応）
# 2013/07 Ver1.60  サブルーチンをメイン関数内記述に変更
# 2011/08 Ver1.51  breakチェックをブラックリスト式に
# 2010/xx Ver1.50  Ver2システム(adiary V3)準拠
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{__CACHE_PM} = 1;

	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●コンパイル処理
#------------------------------------------------------------------------------
# compile( \@source_lines );
#
sub compile {
	my ($self, $lines, $src_file, $debugfile) = @_;
	# エラー保存領域初期化
	$self->{errors}    = 0;
	$self->{warnings}  = 0;
	$self->{error_msg} = [];
	# エラー表示用
	$self->{src_file} = $src_file;
	# 組み込み関数使用状況の初期化
	$self->{use_builtin_ary}  = [];
	$self->{use_builtin_hash} = {};

	# 入力データチェック
	if (ref $lines ne 'ARRAY') {
		$self->error(undef, 'To complile array only');
		return (-1);	# 致命的エラー
	}

	# プリプロセッサ
	my ($buf, $lnum, $strbuf) = $self->preprocessor($lines);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_01.log", $buf, $lnum, $strbuf); }

	# 逆ポーランド記法に変換
	$self->convert_reversed_poland($buf, $lnum);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_02.log", $buf, $lnum, $strbuf); }

	# eval 実行式に変換（from 逆ポーランド記法）, 文字列の評価
	$self->poland_to_eval($buf, $lnum, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_03.log", $buf, $lnum, $strbuf); }

	# 文字列を元に戻し、beginブロックを処理
	my $arybuf = $self->split_begin_block($buf, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_04.log", $buf, undef, $strbuf, $arybuf); }

	# 最適化処理
	$arybuf = $self->optimize($arybuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_05.log", undef, undef, $strbuf, $arybuf); }

	# ブロックをサブルーチンに変換
	$arybuf = $self->array2sub($arybuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_06.log", undef, undef, $strbuf, $arybuf); }

	# 最終処理（文字列を元に戻す）
	$arybuf = $self->recover_string($arybuf, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_07.log", undef, undef, [], $arybuf); }

	return ($self->{errors}, $self->{warnings}, $arybuf);
}
###############################################################################
# ■演算子データ部
###############################################################################
#------------------------------------------------------------------------------
# ●プラグマ定数
#------------------------------------------------------------------------------
my $p_ctab2blank     = 0x0001;	# コマンド手前がタブのみの場合、それを除去する
my $p_cspace2blank   = 0x0002;	# コマンドのみの行の行頭空白や文末改行を自動除去する
my $p_dellf_aftercmd = 0x0004;	# コマンド行に続く空行を除去する
my $p_nocr           = 0x0010;	# 改行を除去する
my $p_cmd_only       = 0x0020;	# コマンド以外を無視
my $p_is_function    = 0x0040;	# 関数として処理

#------------------------------------------------------------------------------
# ●演算子情報
#------------------------------------------------------------------------------
my %operators;		# 優先度配列
my %op_formalname;	# 演算子正式名（存在するもののみ）
# bit 0 - 右から左
# bit 1 - 単項演算子
# bit 2 - reserved
# bit 3 - 連結時にspaceが必要
# bit 4?12 - 演算子優先度（大きいほうが優先）
$operators{'('}   =  0x00;
$operators{')'}   =  0x00;
$operators{';'}   =  0x00;
$operators{','}   =  0x10;	# 例外処理
$operators{'='}   =  0x21;
$operators{'+='}  =  0x21;
$operators{'-='}  =  0x21;
$operators{'*='}  =  0x21;
$operators{'/='}  =  0x21;
$operators{'%='}  =  0x21;
$operators{'&='}  =  0x21;
$operators{'|='}  =  0x21;
$operators{'%.='} =  0x21; $op_formalname{'%.='} = '.=';
$operators{'**='} =  0x21;
$operators{'<<='} =  0x21;
$operators{'>>='} =  0x21;
$operators{'&&='} =  0x21;
$operators{'||='} =  0x21;
$operators{'..'}  =  0x30;	# 本当は || より優先度は低い
$operators{'||'}  =  0x30;
$operators{'&&'}  =  0x40;
$operators{'|'}   =  0x50;
$operators{'^'}   =  0x60;
$operators{'&'}   =  0x70;
$operators{'=='}  =  0x80;
$operators{'!='}  =  0x80;
$operators{'<=>'} =  0x80;
$operators{'%e'}  =  0x88; $op_formalname{'%e'} = 'eq';
$operators{'%n'}  =  0x88; $op_formalname{'%n'} = 'ne';
$operators{'<'}   =  0x90;
$operators{'>'}   =  0x90;
$operators{'<='}  =  0x90;
$operators{'>='}  =  0x90;
$operators{'%d'}  =  0xa2; $op_formalname{'%d'} = 'defined';
$operators{'>>'}  =  0xb0;
$operators{'<<'}  =  0xb0;
$operators{'+'}   =  0xc0;
$operators{'-'}   =  0xc0;
$operators{'%.'}  =  0xc0; $op_formalname{'%.'} = '.';
$operators{'*'}   =  0xd0;
$operators{'/'}   =  0xd0;
$operators{'%'}   =  0xd0;
$operators{'%x'}  =  0xd8; $op_formalname{'%x'} = 'x';
#$operators{'++'} =  0xe2;
#$operators{'--'} =  0xe2;
$operators{'!'}   =  0xf2;	# boolean not
$operators{'~'}   =  0xf2;	# bit invert
$operators{'**'}  = 0x100;
$operators{'%r'}  = 0x200;	# 例外処理
$operators{' '}   = 0x200;	# 例外処理
$operators{'#'}   = 0x200;				# 配列参照（例外処理）
$operators{'->'}  = 0x200;				# ハッシュ参照／変数（例外処理）
$operators{'%h'}  = 0x200;				# ハッシュ参照／メソッドcall（例外処理）
$operators{'@'}   = 0x202;				# 配列デリファレンス（例外処理）
$operators{'##'}  = 0x202;				# 配列の要素数-1（例外処理）
$operators{'%m'}  = 0x202; $op_formalname{'%m'} = '-';	# 負の数値

#------------------------------------------------------------------------------
# ●呼び出しを許可する perl の core 関数
#------------------------------------------------------------------------------
#		  0 : 許可（そのまま）
#	bit 0 =   1 : 戻り値が array
#	bit 1 =   2 : 第１引数が array
#	bit 2 =   4 : 第２引数が array
#	bit 3 =   8 : 第３引数が array
#	bit 8 = 256 : 第１引数が hash
#	bit 9 = 512 : 第２引数が hash
#	bit10 =1024 : 第３引数が hash
#	-1 : 関数ではなく裸制御文

my %core_functions = (undef => 0, length => 0, sprintf => 0, join => 4, split => 1,
index => 0, rindex => 0, shift => 2, unshift => 2, pop => 2, push => 2,
int => 0, undef => 0, substr => 0, chop => 0, chomp => 0, chr => 0, ord => 0,
uc => 0, lc => 0, keys => 0x101, ref => 0, delete => 0, splice => 1, rand => 0,
next=>-1, last=>-1, exists=>0, reverse => 15, return => 0, umask => 0, sleep => 0);

#------------------------------------------------------------------------------
# ●breakフラグをチェックする関数
#------------------------------------------------------------------------------
# 関数名の部分一致
my @break_functions = (
'break',
'jump',
'continue',
'call',
'exit',
'exec');

#------------------------------------------------------------------------------
# ●入れ子を許可しない関数
#------------------------------------------------------------------------------
# <$x = ifexec(...)> 等を許可しない。
# <$ifexec(...)> のみ許可する。
my %only_lastop_functions = ( forexec=>1, ifexec=>1, local=>1);

#------------------------------------------------------------------------------
# ●if関連の inline 展開
#------------------------------------------------------------------------------
# ifexec を inline 展開する
# forexec を inline 展開する
my $ifexec_inline_on  = 1;
my $forexec_inline_on = 1;
# ==> 全パスを実行しないと、きちんとした結果が得られなくなります

# ifjump や ifmessage を展開する
my %inline_if = (if=>-1, ifdef=>-1,
	ifcontinue=>1,
	ifbreak=>1, ifbreak_clear=>1, ifsuperbreak=>1, ifsuperbreak_clear=>1,
	ifjump=>1, ifjump_clear=>1, ifsuperjump=>1, ifsuperjump_clear=>1,
	ifcall=>1, ifredirect=>1, ifform_error=>1, ifform_clear=>1,
	ifmessage=>2, ifmessage_top=>2, ifnotice=>2,
	ifset_cookie=>1, ifclear_cookie=>1,
	ifset=>-1, ifnext=>-1, iflast=>-1, ifset_status=>1,
	ifpush=>4, ifpop=>4, ifshift=>4, ifunshift=>4,
	ifreturn=>3, ifumask=>3, ifprint=>3);
#  1 : ifxxx(exp, a1, a2, ... ) → if(exp) { xxx(a1, a2, ...); }
#  2 : ifxxx(exp, A, B)         → if(exp) { xxx(A); } else { xxx(B); }
#  3 : 1の型で、expがperl命令かつ引数そのまま
#  4 : 1の型で、expがperl命令かつ、第一引数が配列
# -1 : 特殊処理（コード参照）

#------------------------------------------------------------------------------
# ●行情報フラグ
#------------------------------------------------------------------------------
my $l_replace        = 0x0001;	# 置換処理
my $l_line_number    = 0x0002;	# 行情報が必要
my $l_break_check    = 0x0004;	# breakチェックが必要
my $l_no_change      = 0x0008;	# 変更禁止フラグ
my $l_v_load         = 0x0010;	# $v の値を取り出し
my $l_single         = 0x0020;	# 単一式である
my $l_indent         = 0x0100;	# indent 情報用のゲタ
my $l_indent_bits    = 8;	# ↑が何ビットシフトか

#------------------------------------------------------------------------------
# ●その他情報
#------------------------------------------------------------------------------
# 単位情報
my %unit2num = (K => 1024, M => 1024*1024, G => 1024*1024*1024, T => 1024*1024*1024*1024,
		week => 3600*24*7, day => 3600*24, hour => 3600, min => 60, sec => 1);

# 定義済ローカル変数（内部使用）
my %special_vars = (v=>1);

# 行番号の桁数
my $line_num_length = 4;
my $line_num_zero   = '0' x $line_num_length;
# \d\d\d\d\d の正規表現も修正すること！

###############################################################################
# ■インライン関数
###############################################################################
# #0?#9までの引数が取れる
# 複雑な処理の場合は組み込み関数にすること
# 展開時に外側に「( )」自動で付く。
my %inline_functions = (
'is_int'   => '#0 =~ /^-?\d+$/',
'is_array' => "ref(#0) eq 'ARRAY'",
'is_hash'  => "ref(#0) eq 'HASH'"
);

###############################################################################
# ■組み込み関数
###############################################################################
# 追加関数としてコンパイル済スケルトンの後ろに関数を付加する。
# 呼び出し側では、その関数のリファレンスを呼び出す。
#
my %Builtin_func;
#--------------------------------------------------------------------
# ●ifexecの処理（通常はインライン展開される）
#--------------------------------------------------------------------
$Builtin_func{ifexec} = <<'FUNC';
sub {
	my $self = shift;
	my ($exp, $obj1, $obj2) = @_;
	if (defined $obj1 && $exp) { return $self->execute( $obj1 ); }
	if (defined $obj2)         { return $self->execute( $obj2 ); }
	return ;
}
FUNC
#--------------------------------------------------------------------
# ●文字列を各文字の文字コードに分解
#--------------------------------------------------------------------
$Builtin_func{string2ordary} = <<'FUNC';
sub {
	my $txt = shift;
	return [ map { ord($_) } split('', $txt) ];
}
FUNC
#--------------------------------------------------------------------
# ●文字列マッチ
#--------------------------------------------------------------------
$Builtin_func{match} = <<'FUNC';
sub {
	my ($data, $reg) = @_;
	if ($data =~ /$reg/) {
		return [$1,$2,$3,$4,$5,$6,$7,$8,$9];
	}
	return ;
}
FUNC
#--------------------------------------------------------------------
# ●文字列置換
#--------------------------------------------------------------------
$Builtin_func{replace} = <<'FUNC';
sub {
	my ($data, $x, $y) = @_;
	if (ref $data ne 'ARRAY') {
		$_[0] =~ s/$x/$y/sg;
		return $_[0];
	}
	foreach(@$data) {
		$_ =~ s/$x/$y/sg;
	}
	return $data;
}
FUNC
$Builtin_func{replace_one} = <<'FUNC';
sub {
	my ($data, $x, $y) = @_;
	if (ref $data ne 'ARRAY') {
		$_[0] =~ s/$x/$y/;
		return $_[0];
	}
	foreach(@$data) {
		$_ =~ s/$x/$y/;
	}
	return $data;
}
FUNC
#--------------------------------------------------------------------
# ●文字列検索
#--------------------------------------------------------------------
$Builtin_func{grep} = <<'FUNC';
sub {
	my ($data, $x) = @_;
	if (ref $data ne 'ARRAY') {
		return ($data =~ /$x/) ? 1 : 0;
	}
	my @ary;
	foreach(@$data) {
		if ($_ =~ /$x/) { push(@ary, $_); }
	}
	return \@ary;
}
FUNC
#--------------------------------------------------------------------
# ●ハッシュ関係
#--------------------------------------------------------------------
$Builtin_func{copy} = <<'FUNC';
sub {
	my %h = %{ $_[0] };
	return \%h;
}
FUNC

$Builtin_func{array2hash} = <<'FUNC';
sub {
	my $ary = shift;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_ => 1} @$ary;
	return \%h;
}
FUNC

$Builtin_func{arrayhash2hash} = <<'FUNC';
sub {
	my ($ary, $key) = @_;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_->{$key} => 1} @$ary;
	return \%h;
}
FUNC
#--------------------------------------------------------------------
# ●指定したハッシュキーが存在したときのみコピーを生成する
#--------------------------------------------------------------------
$Builtin_func{copy_with_key} = <<'FUNC';
sub {
	my ($out, $in, $ary) = @_;
	foreach(@$ary) {
		if (!exists $in->{$_}) { next; }
		$out->{$_} = $in->{$_};
	}
	return $out;
}
FUNC
#--------------------------------------------------------------------
# ●ハッシュや配列をソートする
#--------------------------------------------------------------------
$Builtin_func{sort_num} = <<'FUNC';
sub {
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a<=>$b} @$ary ]; }
	return [ sort {$a->{$key} <=> $b->{$key}} @$ary ];
}
FUNC

$Builtin_func{sort_str} = <<'FUNC';
sub {
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a cmp $b} @$ary ]; }
	return [ sort {$a->{$key} cmp $b->{$key}} @$ary ];
}
FUNC

#--------------------------------------------------------------------
# ●print
#--------------------------------------------------------------------
# 特別な状況以外では使用しないこと
$Builtin_func{print} = <<'FUNC';
sub {
	print @_;
}
FUNC
#--------------------------------------------------------------------
# ●ファイル存在確認
#--------------------------------------------------------------------
$Builtin_func{'file_exists.arg'} = '$R,';
$Builtin_func{file_exists} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-e $self->get_filepath($file)) { return 1; }
	return 0;
}
FUNC

$Builtin_func{'file_readable.arg'} = '$R,';
$Builtin_func{file_readable} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-r $self->get_filepath($file)) { return 1; }
	return 0;
}
FUNC

$Builtin_func{'file_writable.arg'} = '$R,';
$Builtin_func{file_writable} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-w $self->get_filepath($file)) { return 1; }
	return 0;
}
FUNC

$Builtin_func{'file_size.arg'} = '$R,';
$Builtin_func{file_size} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-s $self->get_filepath($file)) { return 1; }
	return 0;
}
FUNC

#--------------------------------------------------------------------
# ●更新日時を付加
#--------------------------------------------------------------------
$Builtin_func{'add_lastmodified.arg'} = '$R,';
$Builtin_func{add_lastmodified} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	return $file . '?' . $self->get_lastmodified( $file );
}
FUNC


#--------------------------------------------------------------------
# ●配列から指定した数をランダムにロードする
#--------------------------------------------------------------------
$Builtin_func{load_from_ary} = <<'FUNC';
sub {
	my ($ary,$num) = @_;
	my $max = @$ary;
	if ($max <= $num) { return $ary; }
	my @a = @$ary;
	for(my $i=0; $i<$max; $i++) {
		my $r = int(rand($max));
		my $x = $a[$i];
		$a[$i] = $a[$r];
		$a[$r] = $x;
	}
	return [ splice(@a, 0, $num) ];
}
FUNC

###############################################################################
# ■コンパイラ本体
###############################################################################
#------------------------------------------------------------------------------
# ●[01] プリプロセッサ
#------------------------------------------------------------------------------
# ・コマンドは１つだけで配列の１要素（１行）になるよう加工する（コマンド登場前後は、行分け）
# ・文字列を配列に格納し、記号コードに置き換える
# ・入力文字列から文字コード 00h-03h を除去する（内部的に使用するため）
sub preprocessor {
	my ($self, $lines) = @_;

	my @strbuf;
	my @buf;
	my @line_no = ( 0 );
	#------------------------------------------------------------
	# ○プリプロセッサ
	#------------------------------------------------------------
	my $pragma = 0;
	my $line = 0;
	my $prev_cmd_only = 0;
	my $sharp_comment = 0;
	my $chain_line_flag = 0;
	foreach(@$lines) {
		$line++;	# 行カウンタ
		my $l2 = $line;	# $l2 は行連結に利用
		if (ref $_) {
			$self->error($line, "Source line allowed scalar only (contain reference)" );
			my $ref = ref $_;
			push(@buf, "<!-- compiler : this line is reference '$ref' -->\n");
			push(@line_no, $line);	# 元の行を記憶
			next;
		}
		# 行頭 # によるコメント on / off
		if ($_ =~ /^<\@\#>/)   { $sharp_comment = 1; next; }	# on
		if ($_ =~ /^<\@\-\#>/) { $sharp_comment = 0; next; }	# off
		# 行頭 # を無視する
		if ($sharp_comment && $_ =~ /^\s*\#/) { next; }

		# 手前の行と連結
		my $x =  $_;
		if ($chain_line_flag) {
			$x =~ s/^\s*//;
			$chain_line_flag = 0;
		}
		# 行末 <@\> のとき行連結し、手前と改行後のスペースを除去する
		if ($x =~ /^(.*?)\s*<\@\\>\r?\n$/) {
			$x = $1;
			$chain_line_flag = 1;
		}

		# 手前の行がコマンドのみの行ならば、続く空行を除去
		if (($pragma & $p_dellf_aftercmd) && $prev_cmd_only && $x =~ /^\s*\n$/) { next; }
		$prev_cmd_only = 0;
		# $end で終わる行は行末改行除去
		$x =~ s/(<[\$\@]end(?:\.\w+)?>)\r?\n$/$1/;

		# プラグマの処理
		if ($x =~ /^<\@([+-])?(\d+)(?:\.\w+)?>/) {
			my $n = oct("0x$2");
			if    ($1 eq '+') { $pragma |=  $n; }
			elsif ($1 eq '-') { $pragma &= ~$n; }
			else              { $pragma  =  $n; }
			if ($pragma & $p_is_function) {		# 関数処理なら
				$pragma |= $p_cmd_only;		# コマンド以外を無視
			}
			# push(@buf, sprintf("pragma = %x", $pragma));
			# push(@line_no, $line);
			next;
		}
		# コマンドの解析処理
		if ($x =~ /^(.*?)<\@>/) {	# コメント処理
			$x=$1;
			if ($x =~ /^\s*$/) { next; }
		}
		if ($pragma & $p_nocr) { $x =~ s/\n//g;}
		$x =~ s/[\x00-\x04]//g;		# 文字 00h-04h を除去
		$x =~ s|</\$>|<\$\$>|g;		# </$> → <$$>

		# コマンド以外の文字列があるか、判別フラグ
		my $line_is_cmd_only = 1;
		# コマンドの認識
		my $commands = 0;
		my $line_1st_data;
		while ($x =~ /^(.*?)<([\$\@\#])(.*)/s) {	# コマンド
			$commands++;
			my $t = $1;		# 手前
			my $z = '<' . $2;	# 先頭部 - 確定
			my $y = $3;		# コマンド？
			my $end_mark = '>';
			if ($commands==1) {	# 行の最初のコマンドのみ
				if (($pragma & $p_ctab2blank) && $t =~ /^\t+$/) { $t = ''; }
			}
			if ($t ne '') {		# コマンドより前部分
				if ($t !~ /^\s+$/) {
					$line_is_cmd_only = 0;
				}
				push(@buf, $t);
				push(@line_no, $line);	# 元の行を記憶
				$line_1st_data = $#buf;
			}
			# <@@xxx> のとき行末改行を除去しない
			if ($2 eq '@' && ord($y) == 0x40) {
				$y = substr($y,1);
				$line_is_cmd_only = 0;
			}
			while ($y =~ /(.*?)([>\"\'])(.*)/s) {
				if ($2 eq '>') {
					$z .= $1 . '>';
					$x  = $3;	# 残り
					if (index($z,'{')<0 || substr($z, -2) ne '=>') {	# {hash => xxx} ではない 
						# 確定部分の ( ) の対応が合っていれば
						my $tmp=$z;
						while($tmp =~ /^(.*?)\([^\(]*?\)(.*)/) { $tmp="$1$2"; }
						if (index($tmp, '(') <0) { last; }
					}
					$y  = $x;	# 引き続き処理
					next;
				}
				if ($2 ne '"' && $2 ne "'") {
					$z .= $1 . $2;
					$y  = $3;	# 残り
					next;
				}
				$z .= $1;		# コマンドの手前を出力
				my $quot = $2;		# " or '
				my $str = $3;
				if ($quot eq "'" && $str !~ /^((?:\\.|[^\\'])*)\'(.*)/s 
				 || $quot eq '"' && $str !~ /^((?:\\.|[^\\"])*)\"(.*)/s) {
					$self->error($line, 'String error');
					$z = "<!-- compiler : string error -->\n";
					$x =''; last;
				}
				$str = $1;	# 文字列の中身
				$y   = $2;	# 残り

				if ($quot eq "'" && substr($z,-1) eq '#') {	# シングルクォート
					chop($z);
					$quot = '"';	# #'string' を評価文字列 "string" として扱う
				}
				if ($quot eq '"') {	# ダブルクォーテーションの場合
					$str =~ s/\\([\"\\\$\@])/"\\x" . unpack('H2', $1)/eg;	# \$ などのエスケープ文字
					$str =~ s/<@([\w\.]+?(\#\d+)?)>/\x01<$1>/g;		# 評価する文字列（変数）
					$str =~ s/"/\\"/g;					# " をエスケープ
					$str =~ s/([\$\@])/"\\x" . unpack('H2', $1)/eg;		# $ @ をエスケープ
					push(@strbuf, "\"$str\"");	# 文字列保存
					$z .= "\x01[\x01$#strbuf]";
				} else {		# シングルクォーテーションの場合
					push(@strbuf, "'$str'");	# 文字列保存
					$z .= "\x01[\x01$#strbuf]";
				}
			}
			if (substr($z,-1) ne '>' || substr($z,-2) eq '=>') {
				if ($y =~ /(.*)\\\r?\n?$/) {		# コマンド続き
					$x = $z . $1 . $lines->[$l2];	# 次行の連結
					$lines->[$l2++]='';
					next;
				}
				$self->error($line, 'Command not ended (must write in one line)');
				$z = "<!-- compiler : command not ended? -->\n";
				$x = '';
			}
			push(@buf, $z);			# コマンド部分
			push(@line_no, $line);		# 元の行を記憶
			# 単純置換コマンドがあればコマンド行とみなさない
			# if ($z =~ /^<\@\w[\w+\.]*(?:\#\d+)?>$/) {
			# 	$line_is_cmd_only = 0;
			# }
		}
		# コマンドしかない行ならば
		if (($pragma & $p_cspace2blank) && $commands && $line_is_cmd_only) {
			# 行末改行を除去する
			if ($x eq "\n" || $x eq "\r\n") { $prev_cmd_only=1; $x=''; }
			# 行頭空白を除去する
			if (defined $line_1st_data) { $buf[$line_1st_data] = ''; }
		}
		#begin などの処理ができなくなるので禁止
		if ($x ne '') {		# 残りを push
			push(@buf, $x);
			push(@line_no, $line);	# 元の行を記憶
		}
	}
	$self->{pragma} = $pragma;	# プラグマを保存

	return (\@buf, \@line_no, \@strbuf);
}

#------------------------------------------------------------------------------
# ●[02] 逆ポーランド記法に変換
#------------------------------------------------------------------------------
sub convert_reversed_poland {
	my ($self, $buf, $lnum) = @_;

	my $line = 0;			# 行カウンタ
	my $comment_flag = 0;
	foreach (@$buf) {
		$line++;
		if ($_ eq '<$>')     { $_=''; $comment_flag=1; next; }	# コメントの開始
		if ($_ eq '<$$>')    { $_=''; $comment_flag=0; next; }	# コメントの終了
		if ($comment_flag) { $_=''; next; }
		#-------------------------------------------------------------
		# ローカル変数宣言の場合
		#-------------------------------------------------------------
		if ($_ =~ /^<[\@\$]local\((.*)\)>/) {
			my @vars = split(/\s*,\s*/, $1);
			my %v;
			foreach(@vars) {
				if ($special_vars{$_}) { next; }
				if ($_ !~ /^[a-z][a-z0-9]*$/) { next; }
				$v{$_}=1;
			}
			if (%v) {
				my @ary = keys(%v);
				push(@ary, "l");	# local var flag
				$_ = \@ary;
			} else { $_=undef; }
			next;
		}
		#-------------------------------------------------------------
		# コメントアウトの場合、除去
		#-------------------------------------------------------------
		if ($_ =~ /^<\#(.*)>$/) {
			undef $_; next;
		}
		#-------------------------------------------------------------
		# コマンドでない場合はそのまま
		#-------------------------------------------------------------
		if ($_ !~ /^<([\$\@])(.*)>$/) {
			next;
		}
		#-------------------------------------------------------------
		# <@\n>, <@\r>, <@\ >, <@\t>, <@\v>, <@\f>, <@\e>処理
		#-------------------------------------------------------------
		if ($_ =~ /^<\@\\([nr tvfe])>$/) {
			my %h = ('n'=>"\n",'r'=>"\r",' '=>" ",'t'=>"\t",'v'=>"\v",'f'=>"\f",'e'=>"\e");
			$_ = $h{$1};
			next;
		}
		#-------------------------------------------------------------
		# コマンド行ならば
		#-------------------------------------------------------------
		my $cmd_flag = $1;	# @ or $
		my $cmd = $2;		# コマンド
		# 変換のための置換処理
		$cmd =~ s/([^\w\)])\.([^\w=])/$1%.$2/g;	# 文字連結
		$cmd =~ s/\.=/%.=/g;			# 代入＋文字連結
		$cmd =~ s/(\W)eq(\W)/$1%e$2/g;		# 文字比較
		$cmd =~ s/(\W)ne(\W)/$1%n$2/g;		# 文字比較
		$cmd =~ s/(\W)defined(\W)/$1%d$2/g;	# 定義済
		# $cmd =~ s/(\W)x(\W)/$1%x$2/g;		# 文字列 x n
		# $cmd =~ s/(\W)-[\d.]+(\W)/$1%m$2$3/g;	# 負の数値
		$cmd =~ s/\.\(/->(/g;			# x.() → x %h () =ハッシュ参照
		$cmd =~ s/\)\./)->/g;			# ().y → x %h () =ハッシュ参照
		$cmd =~ s!->([\w\.]+)!			# ■■注意■■ &get_object の仕様と合わせること！
			my $x=$1;
			$x =~ s/\.(\.*)/')->('$1/g;
			"->('$x')";
		!eg;
		$cmd =~ s!\{([^\{\}]*)\}!		# {aaa=>x, bbb=>y} → hashq(aaa,x,bbb,y)
			my $x=$1;
			$x =~ s/=>/,/g;
			"hashq($x)";
		!eg;
		$cmd =~ s|\[([^\]\x00-\x04]*)\]|array($1)|g;	# [aaa, bbb] → array[aaa,bbb]

		# ■空白削除■「if(exists xxx.yyy）」構文のみ空白を残し、後で' 'を%rと解釈
		# $cmd =~ s/\s*([=,\(\)\+\-<>\^\*\/&|%!;\#\@]+)\s*/$1/g;
		# $cmd =~ s/\s*(%[\w\.]+)\s*/$1/g;
		# ※構文を複雑にするだけなので削除機能はコメントアウト
		$cmd =~ s/\s*//g;

		# flagq(a b c) → flagq(a,b,c)
		$cmd =~ s!(array|arrayq|hash|hashq|hashqq|flag|flagq)\(([^\(\)]*?)\)!
			my $c=$1;
			my $x=$2;
			$x =~ s/\s*,\s*|\s+/,/g;
			"$c($x)";
		!eg;

		$cmd =~ s/shift\(\)/shift(argv)/g;		# shift() → shift(argv)
		$cmd =~ s/\(\)/(__undef__)/g;			# func() の中身に仮に undef を入れる
		$cmd =~ s/->\('([\w\.]+)'\)\(/%h$1%r(/g;	# ('x').func() への対応

		# 構文解析
		# my $z = $cmd; $z =~ s/\e/|/g; print "\n*** $z\n";	# debug
		my @op  = ('(');	# 演算子スタック
		my @opl = ( 0 );	# スタックの演算子優先度 保存用
		my @poland;		# 逆ポーランド記法記録用
		my $x = $cmd . ')';
		my $right_arc = 0;
		my $out_debug_porland;	# debug-safe
		while ($x =~ /(.*?)([=,\(\)\+\-<>\^\*\/&|%!;\#\@ ])(.*)/s) {
			if ($1 ne '') { push(@poland,  $1); }	# 　演算子の手前を出力
			my $op = $2;
			if ($op eq ' ') { $op='%r'; }
			if (length($3) >1 && exists $operators{$op . substr($3, 0, 2)}) {	# 3文字の演算子？
				$op .= substr($3, 0, 2);
				$x   = substr($3, 2);	# 残り
			} elsif ($3 ne '' && exists $operators{$op . substr($3, 0, 1)}) {	# 2文字の演算子？
				$op .= substr($3, 0, 1);
				$x   = substr($3, 1);	# 残り
			} else {
				$x = $3;		# 残り
			}
			if ($op eq '-' && $1 eq '' && !$right_arc) { $op = '%m'; }	# 数値の負数表現判別
			# 演算子優先度を取り出す（bit 0 は右優先判別のときに使用）
			my $opl = $operators{$op};
			#
			# $op  読み込んだ演算子
			# $opl 演算子優先度
			# $1   演算子の前
			#
			if ($op eq '(') {
				push(@op, '('); push(@opl, 0);
				if ($1 ne '') {		# xxxxxx() ならば関数実行
					push(@op, '%r');
					push(@opl, 0);
				}
			} else {
				my $z = $opl & 1;	# 右から優先の場合 $z = 1
				if ($opl[$#opl] & $opl & 2) {	# スタックトップと現演算子が同時に単項演算子
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
			# print "!error \$x=$x op=$#op\n";
			$self->error($lnum->[$line], 'Illigal expression');
			$_ = "<!-- compiler : command error -->";		# エラー行を置換
			next;
		}
		push(@poland, $cmd_flag);	# コマンドフラグを最後に追加
		$_ = \@poland;			# 変換結果に置換
		if ($out_debug_porland) {
			$self->debug(join(' ', @poland));	# debug-safe
		}
	}
	return ;
}

#------------------------------------------------------------------------------
# ●[03] 逆ポーランド記法を eval 形式に変換
#------------------------------------------------------------------------------
sub poland_to_eval {
	my ($self, $buf, $lnum, $strbuf) = @_;
	my $pragma = $self->{pragma};

	my @local_vars_ary = ( {} );		# ローカル変数のバックアップ
	my %constant;				# 定数バッファ
	my $line = 0;				# 行カウンタ
	foreach (@$buf) {
		my $line_info = 0;	# 行情報
		my $local_vars = $local_vars_ary[$#local_vars_ary];
		$line++;
		if (ref $_ ne 'ARRAY') {	# 逆ポーランド式でなければそのまま
			next;
		}
		# 元ソース中の行番号の生成
		my $line_num     = substr($line_num_zero.$lnum->[$line], -$line_num_length);	# 下5文字分
		my $line_num_int = int( $lnum->[$line] );

		my $cmd_flag = pop(@$_);
		# ローカル変数の処理
		if ($cmd_flag eq 'l') {
			my $vars="";
			my $local_vars = $local_vars_ary[$#local_vars_ary];
			foreach my $v (@$_) {
				if (! $local_vars->{$v}) { $local_vars->{$v}=1; }
				$vars .= "\$$v,";
			}
			chop($vars);
			$_ = "\x01$line_num" . "my ($vars)";
			next;
		}
		# 処理準備
		my @types = map { $self->get_element_type(\%constant, \@local_vars_ary, $strbuf, $_) } @$_;

		## print "\npoland expression : ", join(' ', @$_),    "\n";
		## print   "data types        : ", join(' ', @types), "\n";
		if (grep {$_ eq "error"} @types) {
			my $error = 'Illigal expression';
			$self->error($line_num_int, $error);
			$_ = "<!-- compiler : $error -->";	# エラー行を置換
			next;
		}
		# 単一置換式 <@t.var> 等
		if ($#$_ == 0 && $types[0] eq 'obj') {
			my $var_name = pop(@$_);
			# 【警告】breakを変数として参照してる
			if ($var_name eq 'break') {
				$self->warning($line_num, '"break" variable referenced. Do you mean "break()" function?');
			}
			# xxx.yyy のときの xxx を判別
			if ($var_name =~ /^(\w+)/ && $local_vars->{$1}) {
				$_ = "\x03" . $var_name;
			} else {
				$_ = "\x02" . $var_name;
			}
			if ($cmd_flag eq "\$") { undef $_; }
			next;
		}

		# 単一式
		if ($#$_ == 0) {
			# const line info
			$line_info |= $l_single;
		}

		# 複式
		my $i = 0;
		my $error = 0;
		my $last_op;		# 最後の演算子？
		my $arc_last;		# 最後が全体括弧？
		my @stack;
		my @stack_type;
		my $exists_call = 0;
		my $break_check_flag = 0;
		my $need_line_num    = 0;	# 行番号が必要
		my $special_add;		# 命令付加
		foreach my $p (@$_) {
			$arc_last = 0;
			## print "  dump stack : ", join(' ', @stack), "\n";
			## print "  type stack : ", join(' ', @stack_type), "\n";
			my $type = $types[$i++];		# 型をロード
			if ($i > $#$_) { $last_op = 1; }	# 最後の演算子
			if ($type eq 'op') {		# 演算子
				my $op  = $p;
				my $opl = $operators{$p};
				## printf("\top     = $op [%x]\n", $opl);

				# 正式な perl演算子名に変換
				if (exists $op_formalname{$op}) { $op = $op_formalname{$p}; }

				my $x  = pop(@stack);
				my $xt = pop(@stack_type);
				my $x_orig = $x;
				if (!defined $x) { last; }	# エラー
				if (ref $x eq 'ARRAY') {
					$x = join(',', &get_objects_array($x, $xt, $local_vars));
				}
				my ($y, $yt);
				if ((~$opl) & 2) {	# ２項演算子
					$y  = pop(@stack);
					$yt = pop(@stack_type);
					if (!defined $y) { last; }	# エラー
				}
				#
				# 演算式の合成
				#
				# constant（定数宣言）
				if ($op eq '%r' && $y eq 'constant') {
					if ($xt ne 'obj') {
						@stack      = ("$x is not object", '*');
						@stack_type = ('error_msg', '*');
						last;	# エラー exit
					}
					push(@stack,      $x);
					push(@stack_type, 'const_var');
					next;
				}

				if ($xt eq 'obj' || $xt eq 'const_var') { $x = &get_object($x,$local_vars); }	# オブジェクト評価
				if ($op eq '%r') {
					# call のチェック
					if ($y eq 'call' || $y eq '_call' || $y eq 'ifcall') { $exists_call = 1; }

					# _ で始まる関数は呼べない
					if (0 && substr($y,0,1) eq '_') {
						@stack      = ("Not allow call $y() function (skeleton security protect)", '*');
						@stack_type = ('error_msg', '*');
						last;	# エラー exit
					}
					# 入れ子を許可しない関数
					if (!$last_op && $only_lastop_functions{$y}) {
						@stack      = ("Not allow nest $y() function", '*');
						@stack_type = ('error_msg', '*');
						last;	# エラー exit
					}
					#--------------------------------------
					# local変数の確認
					#--------------------------------------
					if ($last_op && $y eq 'local') {	# 演算子 = 一番外側である
					#	@stack      = ("Not use local", '*');
					#	@stack_type = ('error_msg', '*');
					#	last;	# エラー exit
					}
					#--------------------------------------
					# ifexec の展開
					#--------------------------------------
					if ($last_op && $ifexec_inline_on && $y eq 'ifexec') {	# 最後の演算子 = 一番外側である
						my @ary = &get_objects_array($x_orig, $xt, $local_vars);
						if ($#ary == 2 && $ary[2] =~ /^\x01\[(begin.*)\]$/) { $ary[2] = "\x02[$1]"; }
						if ($#ary <= 2 && $ary[1] =~ /^\x01\[(begin.*)\]$/) { $ary[1] = "\x02[$1]"; }
						$ary[0] =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す
						$x = join(",", @ary);
						@stack = ("ifexec($x)");
						@stack_type = ('*');
						last;
					}
					#--------------------------------------
					# forexec の展開
					#--------------------------------------
					if ($last_op && $forexec_inline_on && $y =~ /^forexec/) {
					  my @ary = &get_objects_array($x_orig, $xt, $local_vars);
					  if ($#ary == 2 && $ary[2] =~ /^\x01\[(begin.*)\]$/) {
						my $begin_type = $1;

						if ($y eq 'forexec' && $ary[1] =~ /^\$#\{(.*)\}$/) {
							my $ary1 = $1;		# $#{$var} → $var
							my $cmd = "my \$X=$ary[1]; if (ref($ary1) ne 'ARRAY') { \$X=-1; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] forexec: data is not array'); }; ";
							if ($ary[0] =~ /^\$[a-z][a-z0-9]*$/) {	# ローカル変数
								@stack = ($cmd . "foreach my $ary[0] (0..\$X, \x02[$begin_type])");
							} else {	# 通常変数
								@stack = ($cmd . "foreach(0..\$X, \x02[$begin_type])\x02{ $ary[0]=\$_;}\x02");
							}
							@stack_type = ('*');
							last;

						} elsif ($y eq 'forexec') {
							my $cmd = "my \$X=$ary[1]; if (ref(\$X) ne 'ARRAY') { \$X=[]; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] forexec: data is not array'); }; ";
							if ($ary[0] =~ /^\$[a-z][a-z0-9]*$/) {	# ローカル変数
								@stack = ($cmd . "foreach my $ary[0] (\@{ \$X }, \x02[$begin_type])");
							} else {	# 通常変数
								@stack = ($cmd . "foreach(\@{ \$X }, \x02[$begin_type])\x02{ $ary[0]=\$_;}\x02");
							}
							@stack_type = ('*');
							last;

						} elsif ($y eq 'forexec_hash') {
							my $cmd = "my \$H=$ary[1]; if (ref(\$H) ne 'HASH') { \$H={}; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] forexec_hash: data is not hash'); };"
							. " my \$Keys=\$H->{_order} || [keys(\%\$H)]; if(!ref($ary[0])) {$ary[0]={}};"
							. " foreach(\@\$Keys, \x02[$1])"
							. "\x02{$ary[0]\->{key}=\$_; $ary[0]\->{val}=\$H->{\$_}; }\x02";
							@stack      = ($cmd);
							@stack_type = ('*');
							last;
						
						} elsif ($y eq 'forexec_num') {
							if ($ary[0] =~ /^\$[a-z][a-z0-9]*$/) {	# ローカル変数
								@stack = ("foreach my $ary[0] (1..int($ary[1]), \x02[$begin_type])");
							} else {
								@stack = ("foreach(1..int($ary[1]), \x02[$begin_type])\x02{ $ary[0]=\$_;}\x02");
							}
							@stack_type = ('*');
							last;
						}
					  }
					}

					#--------------------------------------
					# ifxxx の inline 展開
					#--------------------------------------
					if ($inline_if{$y}) {
						$break_check_flag = &check_break_function($y);
						my @ary = &get_objects_array($x_orig, $xt, $local_vars);
						$x = undef;
						if ($y eq 'ifdef') {
							$y = 'if';
							$ary[0] = "defined($ary[0])";
						}
						if ($y eq 'if' && $last_op && $#ary == 1 && $cmd_flag eq '@') {
							$x = undef;
							$line_info |= $l_no_change;
							$x = "($ary[0] && push(\@\$O, $ary[1]));";
							$arc_last = 1;

						} elsif ($y eq 'if' && $ary[1] eq '') {
							$x = undef;	# error
						} elsif ($y eq 'if') {
							if ($ary[2] ne '') {
								$x = "($ary[0] ? $ary[1] : $ary[2])";
							} else {
								$x = "($ary[0] && $ary[1] || undef)";
							}
							$arc_last = 1;
						} elsif ($y eq 'ifset') {
							if ($#ary > 2) {
								$x = "($ary[1]=$ary[0] ? $ary[2]: $ary[3])";
							} elsif ($#ary == 2) {
								$x = "($ary[0] && ($ary[1]=$ary[2]))";
							} else { $x=undef; }
							$arc_last = 1;
						} elsif ($y =~ /^if(next|last)$/) {	# ifnext / iflast
							if ($#ary == 0) {
								$x = "($ary[0] && $1)";
							} else { $x=undef; }
							$arc_last = 1;
						} elsif ($inline_if{$y} == 3 || $inline_if{$y} == 4) {	# ifpush / ifpop
							my $cond = shift(@ary);
							my $func = substr($y, 2);	# iffunc → func
							if ($inline_if{$y}==4) { $ary[0] = '@{' . $ary[0] . '}'; }
							$x = join(',', @ary);
							$x = "($cond && $func($x))";
							$arc_last = 1;
						} elsif (substr($y,0,2) eq 'if') {
							$need_line_num = 1;
							my $func = substr($y, 2);	# iffunc → func
							$x = shift(@ary);
							if ($inline_if{$y} == 2 && $ary[1] ne '') {	# ifxxx(exp, A, B)
								$x = "\$R->$func($x ? $ary[0] : $ary[1])";
							} elsif ($last_op && $cmd_flag eq '@') {
								$line_info |= $l_no_change;
								$x = "($x && push(\@\$O, \$R->$func(" . join(',', @ary) . ")));";
								$arc_last = 1;
							} else {
								$x = "($x && \$R->$func(" . join(',', @ary) . "))";
								$arc_last = 1;
							}
						}
						if (!defined $x) {
							push(@stack,      $x,  $y);
							push(@stack_type, $xt, $yt);
							last;	# エラー exit
						}
						push(@stack, $x);
						push(@stack_type, '*');
						next;

					#--------------------------------------
					# core関数呼び出し
					#--------------------------------------
					} elsif (exists $core_functions{$y}) {
						$need_line_num = 1;
						# perl core 関数の呼び出し
						if ($x eq '' || $x eq 'undef') {	# 引数省略は許可しない
							if ($core_functions{$y}==-1) {	# next/last等の裸制御文
								push(@stack, $y);
								push(@stack_type, '*');
								last;
							}
							push(@stack,      $x,  $y);
							push(@stack_type, $xt, $yt);
							last;	# エラー exit
						}
						# bit 0 =  1 : 戻り値が array
						# bit 1 =  2 : 第１引数が array
						# bit 2 =  4 : 第２引数が array
						# bit 3 =  8 : 第３引数が array
						my $mode = $core_functions{$y};
						if ($mode) {
							my @ary = &get_objects_array($x_orig, $xt, $local_vars);
							if ($mode &    2 && defined $ary[0]) { $ary[0] = '@{' . $ary[0] . '}'; }
							if ($mode &    4 && defined $ary[1]) { $ary[1] = '@{' . $ary[1] . '}'; }
							if ($mode &    8 && defined $ary[2]) { $ary[2] = '@{' . $ary[2] . '}'; }
							if ($mode &  256 && defined $ary[0]) { $ary[0] = '%{' . $ary[0] . '}'; }
							if ($mode &  512 && defined $ary[1]) { $ary[1] = '%{' . $ary[1] . '}'; }
							if ($mode & 1024 && defined $ary[2]) { $ary[2] = '%{' . $ary[2] . '}'; }
							$x = join(',', @ary);
						}
						$x =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す

						if ($core_functions{$y} & 1) {
							push(@stack, "[ $y($x) ]");	# 配列の戻り値をreference化
						} else {
							push(@stack, "$y($x)");
						}
						push(@stack_type, '*');
						next;

					#--------------------------------------
					# inline関数呼び出し
					#--------------------------------------
					} elsif (exists $inline_functions{$y}) {
						my $err;
						my $func = $inline_functions{$y};
						my @ary = &get_objects_array($x_orig, $xt, $local_vars);
						$func =~ s/#(\d)/
							$err |= ($ary[$1] eq '' || $ary[$1] eq 'undef');
							$ary[$1]
						/eg;

						if ($err) {	# 必要な引数がない
							push(@stack,      $x,  $y);
							push(@stack_type, $xt, $yt);
							last;	# エラー exit
						}
						push(@stack, "($func)");
						push(@stack_type, '*');
						next;
					}

					#--------------------------------------
					# その他の関数呼び出し
					#--------------------------------------
					$need_line_num = 1;
					if ($y eq 'array'|| $y eq 'arrayq') {
						# array (a, b, c, ...) to [a, b, c]
						# arrayq(a, b, c, ...) to ['a', 'b', 'c']
						my @ary = ($y eq 'array')
							? &get_objects_array ($x_orig, $xt, $local_vars)
							: &array2quote_string($x_orig, $xt, $local_vars);
						$x = join(',', @ary);
						push(@stack, "[$x]");

					} elsif ($y eq 'hash' || $y eq 'hashq' || $y eq 'hashqq') {
						# hash  (a1, b1, a2, b2, ...) to {a1=>b1, a2=>b2}
						# hashq (a1, b1, a2, b2, ...) to {'a1'=>b1, 'a2'=>b2}
						# hashqq(a1, b1, a2, b2, ...) to {'a1'=>'b1', 'a2'=>'b2'}
						my @ary;
						if ($y eq 'hash' || $y eq 'hashqq') {
						   @ary = ($y eq 'hash')
							? &get_objects_array ($x_orig, $xt, $local_vars)
							: &array2quote_string($x_orig, $xt, $local_vars);
						} else {
							my @a = &array2quote_string($x_orig, $xt, $local_vars);
							my @b = &get_objects_array ($x_orig, $xt, $local_vars);
							foreach(0..$#a) {
								push(@ary, (($_ & 1) ? $b[$_] : $a[$_]));
							}
						}
						my $x='';
						@ary = grep { $_ ne '' } @ary;
						while(@ary) {
							my $a=shift(@ary);
							my $b=shift(@ary) || '';
							$x .= "$a=>$b,";
						}
						chop($x);
						push(@stack, "{$x}");

					} elsif ($y eq 'flag' || $y eq 'flagq') {
						# flag (a, b, c, ...) to {a=>1, b=>1, ...}
						# flagq(a, b, c, ...) to {'a'=>1, 'b'=>1, ...}
						my @ary = ($y eq 'flag')
							? &get_objects_array ($x_orig, $xt, $local_vars)
							: &array2quote_string($x_orig, $xt, $local_vars);
						@ary = grep { $_ ne '' } @ary;
						if (@ary) {
							$x = "{" . join('=>1,', @ary) . "=>1}";
						} else {
							$x='{}';
						}
						push(@stack, $x);

					} elsif ($Builtin_func{$y}) {
						$break_check_flag = &check_break_function($y);
						push(@stack, "\x04$y($x)");
					} elsif ($yt eq 'obj') {
						$break_check_flag = &check_break_function($y);
						my ($class, $func) = &get_object_sep($y,$local_vars);
						push(@stack, "$class\-\>$func($x)");
					} elsif ($yt eq 'function-name') {		# %h 記述参照のこと
						$break_check_flag = &check_break_function($y);
						push(@stack, "$y($x)");
					} else {	# エラー
						push(@stack,      $x,  $y);
						push(@stack_type, $xt, $yt);
						last;
					}
					push(@stack_type, '*');
					next;
				}
				#--------------------------------------
				# constantの処理
				#--------------------------------------
				if ($last_op && $op eq '=' && $yt eq 'const_var' && $xt eq 'const') {
					my $err;
					my $const = $x;
					if ($x =~ /^\x01\[\x01(\d+)\]$/) {
						$const = $strbuf->[$1];
						$const =~ s/^[\"\'](.*)[\"\']$/$1/;
						if ($const !~ /[\x00-\x08\x0a-\x1f\"\'\\]/) {
							$err=0;
						}
					}
					# 定数定義
					if (!$err) {
						@stack      = ($const);
						@stack_type = ('const');

						if ($const eq 'undef') {
							$constant{$y}='';
						} else {
							$constant{$y} = $const;
						}
						last;
					}
				}

				if ($op eq ',')  {
					if (ref($yt) eq 'ARRAY') {
						push(@$y,  $x_orig);
						push(@$yt, $xt);
					} else {
						$y  = [$y,  $x_orig];
						$yt = [$yt, $xt];
					}
					push(@stack,      $y);
					push(@stack_type, $yt);
					next;
				}

				if ($yt eq 'obj' || $yt eq 'const_var') { $y = &get_object($y,$local_vars); }	# オブジェクト評価
				if ($op eq '#')  {	# 配列参照
					$x =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す
					if ($x eq '-1') {
						push(@stack, "$y\-\>[\$#$y]");
					} else {
						push(@stack, "$y\-\>[$x]");
					}
					push(@stack_type, '*');
					$arc_last = 1;
					next;
				}
				if ($op eq '->')  {	# ハッシュ参照（変数）
					if ($yt eq 'string') {
						push(@stack, "\$R->{$y}\-\>{$x}");
						push(@stack_type, '*');
					} else {
						push(@stack, "$y\-\>{$x}");
						push(@stack_type, '*');
					}
					$arc_last = 1;
					next;
				}
				if ($op eq '%h')  {	# ハッシュ参照（メソッドcall）
					push(@stack, "$y\-\>$x_orig");
					push(@stack_type, 'function-name');
					$arc_last = 1;
					next;
				}
				if ($op eq '@')  {
					push(@stack, "\@\{$x\}");
					push(@stack_type, '*');
					next;
				}
				if ($op eq '##')  {
					push(@stack, "\$\#\{$x\}");
					push(@stack_type, '*');
					next;
				}
				# 配列代入 (x,y,z) = func() 等
				if ($op eq '=' && ref($y) eq 'ARRAY')  {
					if (grep { $_ != 'obj'} @$yt) {
						# エラー
						push(@stack,      $y);
						push(@stack_type, $yt);
						last;
					}
					my @ary = &get_objects_array($y, $yt, $local_vars);
					$y = "(". join(',', @ary) . ")";

					# (x,y,z) = (1,2,3) : arrar to array
					if (ref($x_orig) eq 'ARRAY') {
						$x = "(". join(',', @$x_orig) . ")";
					}
				}

				# ローカル変数への代入
				if ($last_op && $op eq '=' && $y =~ /^\$[a-z][a-z0-9]*$/ && $y ne '$v') {
					push(@stack,      "$y=$x");
					push(@stack_type, '*');
					next;
				}
				# 通常の２項演算子
				if ((~$opl) & 2) {
					my $a  = ($opl & 8) ? "($y $op $x)" : "($y$op$x)";
					my $at = '*';
					if ($xt eq 'const' && $yt eq 'const') {
						$a  = eval($a);
						if ($a eq '') { if ($a) { $a=1; } else { $a=0; } }	# true/false
						$at = 'const';
					}
					push(@stack,      $a);
					push(@stack_type, $at);
					$arc_last = 1;
					next;
				}
				# 単項演算子
				my $a  = ($opl & 8) ? "($op $x)" : "($op$x)";
				my $at = '*';
				if ($xt eq 'const') {
					$a  = eval($a);
					if ($a eq '') { if ($a) { $a=1; } else { $a=0; } }	# true/false
					$at = 'const';
				}
				push(@stack,      $a);
				push(@stack_type, $at);
				$arc_last = 1;
				next;

			} elsif ($type eq 'error') {	# エラー
				push(@stack,      $p);
				push(@stack_type, $type);
				last;

			} else {	# オブジェクト指定
				push(@stack,      $p);
				push(@stack_type, $type);
			}
		}

		if ($#stack != 0) {
			my $error = 'Illigal expression (%d)';
			if ($stack_type[0] eq 'error_msg') { $error=$stack[0]; }
			$self->error($line_num_int, $error, $#stack );
			&tag_escape(@stack);
			$_ = "<!-- compiler : command error($#stack) $stack[0] $stack[1] $stack[2] $stack[3]-->";	# エラー行を置換
			next;
		} else {
			my $exp  = pop(@stack);
			my $type = pop(@stack_type);
			if (ref $exp eq 'ARRAY') {
				$exp = join(',', &get_objects_array($exp, $type, $local_vars));
				$type = "*";
			}
			if ($arc_last && $exp =~ /^\((.*)\)(;?)$/) { $exp = "$1$2"; }	# 一番外の (  ) を外す
			if ($type eq 'obj') { $exp = &get_object($exp,$local_vars); }	# オブジェクの場合、参照形式へ
			if ($type eq 'const') {		# 定数
				if ($cmd_flag eq "\$") { undef $_; next; }	# 無視
				# 2/8/16進数なら数値化
				if ($exp =~ /^0[xb]?\d+$/) {
					$exp = oct($exp);
				}
				# 文字列でなければ置き換え
				if ($exp !~ /^\x01\[\x01(\d+)\]$/) {		# 文字列
					$_ = $exp;
					next;
				}
			}
		#	print "  eval string : $exp\n";
			$_ = "\x01$line_num" . $exp;		# 置換

			# 行情報を保存
			if ($cmd_flag eq '@')  { $line_info |= $l_replace;     }	# 結果を置換する
			if ($break_check_flag) { $line_info |= $l_break_check; }	# break をチェックする
			if ($need_line_num)    { $line_info |= $l_line_number; }	# 関数呼び出しあり → 行情報を持つ
			if ($exists_call)      { $line_info |= $l_v_load; }		# $v の再設定
			if ($line_info) {	# 行情報がある
				$_ .= "#$line_info";	# 行情報付加
			}
		}
	}
	return ;

}
#-----------------------------------------------------------
# ○行番号取得
#-----------------------------------------------------------
sub get_line_num {
	return substr($_[0], 1, $line_num_length);
}
sub get_line_num_int {
	return int(substr($_[0], 1, $line_num_length));
}
sub get_line_data {
	return substr($_[0], 1+$line_num_length);
}

#-----------------------------------------------------------
# ○要素の種類を取得
#-----------------------------------------------------------
sub get_element_type {
	my $self = shift;
	my $constant = shift;
	my $local_vars_ary = shift;
	my $strbuf   = shift;
	my $p = $_[0];
	if (exists $operators{$p}) { return 'op'; }		# 演算子
	if ($p =~ /^\x01\[\x01(\d+)\]$/) {			# 文字列
		# 該当文字列を評価する
		my $num = $1;
		my $local_vars = $local_vars_ary->[ $#$local_vars_ary ];
		$strbuf->[$num] =~ s/\x01<([^>]+?)\#(\d+)>/&get_object($1, $local_vars) . "->[$2]"/eg;
		$strbuf->[$num] =~ s/\x01<([^>]+?)>/(exists $constant->{$1}) ? $constant->{$1} : &get_object($1,$local_vars,1)/eg;
		return substr($strbuf->[$num],0,1) eq "'" ? 'const' : 'string';
	}
	if ($p =~ /^'[^\']*'$/) {		# 文字定数
		return 'const';
	}
	if ($p =~ /^([\d\.]+)([KMGT]|week|day|hour|min|sec)B?$/) {	# 単位付き数値
		$p *= $unit2num{$2};
		$_[0] = int($p);
		return 'const';
	}
	if ($p =~ /[^\w\.]/)   { return 'error'; }	# 不正な文字列／エラー
	if ($p =~ /^[\d\.]+$/) { return 'const'; }	# 数値（加工しない）
	if ($p =~ /^0[xb][\dA-Fa-f]+$/) { return 'const'; }		# 2進数 16進数
	if ($p =~ /^([\d\.]+)([KMGT]|week|day|hour|min|sec)B?$/) {	# 単位付き数値
		$p *= $unit2num{$2};
		$_[0] = int($p);
		return 'const';
	}
	if ($p =~ /^(\d+)\.\w+$/) {		# 説明付きの数値  10.is_cache_on など
		$_[0] = $1; return 'const';
	}
	if ($p =~ /^(begin.*)/) {		# array
		# ローカル変数環境を退避する
		my %h = %{ $local_vars_ary->[ $#$local_vars_ary ] };
		push(@$local_vars_ary, \%h);
		$_[0] = "\x01[$1]"; return 'array';
	}
	if ($p =~ /^end(.*)/ || $p =~ /^else(.*)/) {
		# ローカル変数環境を元に戻す
		if ($#$local_vars_ary) {
			pop(@$local_vars_ary);
		}
		$_[0] = "end$1"; return 'block';
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
	if ($p eq 'undef') { return 'const'; }
	if ($p eq '__undef__') { $_[0]=''; return 'const'; }
	if (exists $constant->{$p}) { $_[0] = "'".$constant->{$p}."'"; return 'const'; }

	return 'obj';
}

#------------------------------------------------------------------------------
# ●[04] begin - end ブロックの取り出しと文字列の置換
#------------------------------------------------------------------------------
sub split_begin_block {
	my ($self, $buf, $local_var_tmp_ary) = @_;

	# 処理ループ
	my $line = 0;		# 行カウンタ
	my @arybuf = ([]);	# 先頭に dummy を積む
	my @newbuf;
	while(@$buf) {
		$line++;
		my $line = shift(@$buf);
		# begin ブロックの切り出し
		if (ord($line) == 1 && $line =~ /[\x01\x02]\[begin.*?\]/) {
			unshift(@$buf, $line);
			$self->split_begin(\@newbuf, $buf, \@arybuf);
			next;
		}
		if ($line =~ /^\x01\d\d\d\dend(?:\.([^#]*))?/) {
			my $lnum = &get_line_num_int($line);
			my $end     = &get_line_data($line);
			$self->error($lnum, "Exists 'end' without 'begin' (%s)", $end );
			$line = "<!-- compiler : block end exists, but corresponded end no exists ($end) -->";
		}
		push(@newbuf, $line);
	}
	# @arybuf に end が残ってないか確認する（エラーチェック）
	foreach my $ary (@arybuf) {
		foreach(@$ary) {
			if ($_ =~ /^\x01\d\d\d\dend(?:\.([^#]*))?/) {
				my $lnum = &get_line_num_int($_);
				my $end     = &get_line_data($_);
				$self->error($lnum, "Exists 'end' without 'begin' (%s)", $end );
				$_ = "<!-- compiler : block end exists, but corresponded end no exists ($end) -->";
			}
		}
	}
	# arybuf先頭に実行文本体を入れる
	$arybuf[0] = \@newbuf;

	return \@arybuf;
}
#-----------------------------------------------------------
# ○begin block 処理メイン（再起対応）
#-----------------------------------------------------------
sub split_begin {
	my ($self, $newbuf, $buf, $arybuf) = @_;

	my @if_blocks;
	my $info = 0;
	my $t = shift(@$buf);
	if ($t =~ /(.*?)\#(\d+)$/s) { $t=$1; $info=$2; }

	while (ord($t) == 1 && $t =~ /(.*?)([\x01\x02])\[(begin.*?)\](.*)/s) {
		my $left  = $1;
		my $flag  = $2;
		my $begin = $3;
		my $right = $4;
		my ($mode, $blockname) = split(/\./, $begin, 2);
		my $ary = $self->splice_block($buf, $mode, $blockname, $arybuf);
		if (! defined $ary) {
			my $lnum = &get_line_num_int($t);
			$self->error($lnum, "Exists 'begin' without crresponded 'end' (%s)", $begin );
			$t = "<!-- compiler : begin block error($begin) -->";	# エラー行を置換
			last;
		}

		# 前処理
		if ($mode eq 'begin_string' || $mode eq 'begin_array' || $mode eq 'begin_hash' || $mode eq 'begin_hash_order') {
			my @newary;
			my $line = [];
			foreach(@$ary) {
				push(@$line, $_);
				my $flag = ord($_);
				if ($flag>3 && ($_ =~ /[\r\n]$/)) {
					push(@newary, $line);
					$line = [];
				}
			}
			if (@$line) { push(@newary, $line); }
			# 最初や最後が空白だけの行なら除去
			if (@newary) {
				my $x = $newary[0];
				if ($#$x == 0 && $x->[0] =~ /^[\s\r\n]*$/) { shift(@newary); }
				my $y = $newary[$#newary];
				if ($#$y == 0 && $y->[0] =~ /^[\s\r\n]*$/) { pop(@newary);   }
			}
			$ary = \@newary;
		}
		# 各行の行頭、行末スペースと改行を消去
		if ($mode eq 'begin_array' || $mode eq 'begin_hash' || $mode eq 'begin_hash_order') {
			foreach(@$ary) {
				while(@$_ && $_->[0] =~ /^\s*$/) {
					shift(@$_);
				}
				$_->[0] =~ s/^\s*//;

				# 行末
				my $flag = @$_ && ord($_->[$#$_]) || 0;
				if ($flag>3){
					$_->[$#$_] =~ s/[\r\n]*$//;
				}
				while(@$_ && $_->[$#$_] =~ /^\s*$/) {
					pop(@$_);
				}
				if ($flag>3){
					$_->[$#$_] =~ s/\s*$//;
				}
			}
		}

		if ($mode eq 'begin_string') {	 # 文字列要素
			my @ary2;
			foreach(@$ary) {
				push(@ary2, @$_);
			}
			$ary = $self->chain_lines(\@ary2);

		} elsif ($mode eq 'begin_array') {	 # ブロック要素（リスト）
			foreach(@$ary) {
				$_ = $self->chain_lines($_);
			}
			$ary = '[' . join(',', @$ary) . ']';
			$ary =~ s/[\x01-\x03]//g;

		} elsif ($mode eq 'begin_hash' || $mode eq 'begin_hash_order') {	 # ブロック要素（ハッシュ）
			my %hash;
			if ($mode eq 'begin_hash_order') { $hash{_order}=1; }
			my @order;	# key順序保存配列
			my $order_ng;	# 順序保持不可フラグ
			my @out;
			foreach my $line (@$ary) {
				# xx = yyyy の = の位置を特定する
				my @key;
				my @val;
				foreach(0..$#$line) {
					my $x = $line->[$_];
					if (ord($x)<4) { next; }
					if ($x !~ /^(.*?)\s*=\s*(.*)/) { next; }
					# = 発見
					@val = splice(@$line, $_+1);	# 順次変更不可！
					@key = splice(@$line, 0, $_);
					if ($2 ne '') { unshift(@val, $2); }
					if ($1 ne '') {    push(@key, $1); }
					last;
				}
				if (!@key) {
					if (join('',@$line) ne '') {
						my $lnum = &get_line_num($t);
						$self->warning($lnum, "Contaion line is not defined hash in '%s'", $mode);
						$self->warning($lnum, "-->" . join('',@$line));
					}
					next;
				}

				my $is_string = 1;
				foreach(@key) {
					if (ord($_)>3) { next; }
					$is_string = 0;
					last;
				}
				if ($is_string) {
					# key が文字列でのみ構成されている。
					my $key = join('',@key);
					my $val = $self->chain_lines(\@val);
					if (exists $hash{$key}) {
						my $lnum = &get_line_num($t);
						$self->warning($lnum, "Dupulicate Hash key '%s' in '%s'", $key, $mode);
					}
					$hash{$key} = $val;
					if ($key eq '_order') { next; }

					&into_single_quot_string($key);
					push(@order, $key);		# 順番保持用
					push(@out, "$key=>$val");	# 出力
					next;

				}
				# key部に変数やコマンドが含まれる
				$order_ng = 1;
				my $key = $self->chain_lines(\@key);
				my $val = $self->chain_lines(\@val);
				push(@out, "$key=>$val");	# 出力
			}
			# ハッシュ定義として整形する
			if ($hash{_order}) {
				if ($order_ng) {
					my $lnum = &get_line_num($t);
					$self->warning($lnum, "Don't use ordering hash (contaion variable key) in '%s'", $mode);
				} else {
					my $ord = join(',',@order);
					push(@out, "_order=>[$ord]");	# 出力
				}
			}
			$ary = '{' . join(',', @out) . '}';

		} elsif ($mode eq 'begin' && $flag eq "\x02") {	# 実行構文のブロック展開
			push(@if_blocks, $ary);
			if ($left =~ /(.*?),\s*$/s) { $left = $1; }	# , より手前
			$t = $left . $right;
			$ary='';

		} elsif ($mode eq 'begin') {	# 実行構文（無名関数）
			push(@$arybuf, $ary);
			$ary = "\x04[$#$arybuf]\x04";

		} else {		# 未知のbegin
			my $lnum = &get_line_num($t);
			$self->error($lnum, "Unknown begin type (%s)", $mode );
			$t = "<!-- compiler : Unknown begin type ($mode) -->";	# エラー行を置換
			last;
		}
		$t = $left . $ary . $right;
		## print $_, "\n";
	}
	#------------------------------------------------------------
	# ○ブロック展開処理
	#------------------------------------------------------------
	if (@if_blocks) {
		$t =~ s/^(\x01\d\d\d\d)ifexec\(/${1}if (/;
		if ($t =~ /\x02\{.*?\}\x02/) {
			$t =~ s/\x02\{(.*?)\}\x02//g;
			push(@$newbuf, "$t {$1#$l_no_change");
		} else {
			push(@$newbuf, "$t {#$l_no_change");
		}
		my $block = shift(@if_blocks);
		&info_rewrite($block, $info & $l_replace);
		push(@$newbuf, @$block);
		# else ?
		if (@if_blocks) {
			push(@$newbuf, "\x01$line_num_zero} else {#$l_no_change");
			$block = shift(@if_blocks);
			&info_rewrite($block, $info & $l_replace);
			push(@$newbuf, @$block);
		}
		push(@$newbuf, "\x01$line_num_zero}#$l_no_change");
		return ;
	}
	$t .= "#$info";
	push(@$newbuf, $t);
}

#-----------------------------------------------------------
# ○ブロックの取り出し, split_begin と対
#-----------------------------------------------------------
sub splice_block {
	my ($self, $buf, $blockmode, $blockname, $arybuf) = @_;
	my @ary;
	while(@$buf) {
		my $line = shift(@$buf);
		if ($line =~ /^\x01\d\d\d\dend(?:\.([^#]*))?/ && $1 eq $blockname) {
			return \@ary;
		}
		if (ord($line) == 1 && $line =~ /[\x01\x02]\[begin.*?\]/) {
			unshift(@$buf, $line);
			$self->split_begin(\@ary, $buf, $arybuf);
			next;
		}
		if ($line ne '') {
			push(@ary, $line);
		}
	}
	return undef;		# ブロックの終わりが見つからない
}

#-----------------------------------------------------------
# ○ブロックの行情報書き換え
#-----------------------------------------------------------
sub info_rewrite {
	my ($block, $replace) = @_;
	foreach(@$block) {
		if (ord($_) != 1) {
			if (!$replace) { $_=''; }
			next;
		}
		my $info;
		if ($_ =~ /(.*?)\#(\d+)$/s) { $_=$1; $info=$2; }
		if (!$replace) { $info &= (0x7fffffff - $l_replace); }
		$info += $l_indent;
		$_ .= "#$info";
	}
}


#-----------------------------------------------------------
# ○複数行を一つのperl式にまとめる
#-----------------------------------------------------------
sub chain_lines {
	my $self = shift;
	my $ary  = shift;
	my @ary2;
	my $chain = 0;
	# 非コマンド行の連続を連結する
	foreach(@$ary) {
		if (ord($_) < 4) {
			push(@ary2, $_);
			$chain = 0;
			next;
		}
		if ($chain) {
			$ary2[$#ary2] .= $_;
		} else {
			push(@ary2, $_);
		}
		$chain = 1;
	}

	my @ary3;
	foreach(@ary2) {
		my ($flag, $info, $cmd) = $self->parse_line_to_cmd( $_ );
		if ($flag == 1) {	# cmd
			if (!($info & $l_replace)) {	# 置換しない
				$cmd = "('',$cmd)[0]";
			}
			if (!($info & $l_single)) {	# 定数ではない
				$cmd = "($cmd)";
			}
		}
		if ($flag>3 && substr($cmd,0,1) ne "'" && $#ary2>0) {
			# single quote されてなかったら（数値等）quote する
			$cmd = "'$cmd'";
		}
		push(@ary3, $cmd);
	}
	return @ary3 ? join('.', @ary3) : "''";
}

#------------------------------------------------------------------------------
# ●[05] 不要な行を削除し、行をまとめる
#------------------------------------------------------------------------------
sub optimize {
	my ($self, $arybuf) = @_;

	my $pragma = $self->{pragma};			# プラグマロード
	foreach my $ary (@$arybuf) {
		my @new_ary = ('dummy');		# 処理の都合で、積んでおく
		my $str;
		foreach (@$ary) {
			my $f = ord($_);
			if ($_ eq '' || $f > 3) {	# 普通の文
				$str .= $_;
				next;
			}
			#
			# コマンド or 置換文
			#
			if($str ne '') {
				if (~$pragma & $p_cmd_only) { push(@new_ary, $str); }
				$str = '';
			}
			push(@new_ary, $_);
		}
		shift(@new_ary);	# dummy を読み捨て
		if ($str ne '' && (~$pragma & $p_cmd_only)) { push(@new_ary, $str); }
		$ary = \@new_ary;
	}
	return $arybuf;
}

#------------------------------------------------------------------------------
# ●[06] arrayブロックを１つのサブルーチンに置き換える
#------------------------------------------------------------------------------
# inline 関数を展開する。
sub array2sub {
	my ($self, $arybuf) = @_;
	my $pragma = $self->{pragma};

	my @Builtin_funcs;
	my %Builtin_funcs_cache;
	my $is_main = 1;
	my $is_function = $pragma & $p_is_function;
	my $subhead = <<'SUB_START';
sub {
	my $O = shift;
	my $R = shift;
	my $v = $R->{v};
	$_[1] = \$v;
SUB_START
	foreach my $ary (@$arybuf) {
		my @sub_array;
		my $base_indent = "\t";
		if (! $is_main) {
			$base_indent = "\t\t";
			push(@sub_array, $subhead);
			$sub_array[$#sub_array] =~ s/\n\t/\n\t\t/g;
		}
		# indent 処理
		my $indent = $base_indent;
		foreach(@$ary) {
			my ($flag, $info, $cmd) = $self->parse_line_to_cmd( $_ );
			# unknown
			if ($flag == 0) { next; }
			# そのまま出力
			if ($flag > 1) {
				# xxx.yy.zz 形式のデータに置換
				# xxx.yy.zz 形式で xx がローカル変数
				# コマンド外文字列
				push(@sub_array, $indent . "push(\@\$O, $cmd);\n");
				next;
			}
			#--------------------------
			# $flag==1 コマンド行
			#--------------------------
			# indent 処理
			$indent = $base_indent . ("\t" x ($info >> $l_indent_bits));

			# 行番号
			my $lnum = &get_line_num_int($_);

			# 加工禁止
			if ($info & $l_no_change) {
				push(@sub_array, "$indent$cmd\n");
				if ($cmd =~ /^if\s*\(.*\)\s*\{/ || $cmd =~ /^}\s*else\s*\{/ || $cmd =~ /^my \$X/) { $indent .= "\t"; }
				next;		# $cmd =~ /^my \$X/ は forexec のため
			}
			# 置換処理
			if (!$is_function && $info & $l_replace) {	# 置換
				if ($cmd =~ /;,/) { $cmd = "push(\@\$O, do{ $cmd });"; }
				             else { $cmd = "push(\@\$O, $cmd);"; }
			} else {
				$cmd .= ';';
			}

			# 行番号が必要？（エラーが起こらない行では不要）
			if ($info & $l_line_number) { $cmd  = "\$_[0]=$lnum; " . $cmd; }
			# v の値をロード
			if ($info & $l_v_load)      { $cmd .= " \$v=\$R->{v};"; }
			# break flag を確認？
			if ($info & $l_break_check) { $cmd .= " \$R->{Break} && return;"; }
			# コマンドを出力
			push(@sub_array, "$indent$cmd\n");
		}
		if ($is_function) {	# 関数処理なら最後にreturnする
			push(@sub_array, "\treturn;\n");
		}
		push(@sub_array, $is_main ? "}\n" : "\t}\n");
		$ary = join('', @sub_array);

		$is_main=0;
	}

	#-----------------------------------------------------------
	# arrray buf を1つの関数に納める
	#-----------------------------------------------------------
	my $main = shift(@$arybuf);
	foreach(@$arybuf) {
		chomp( $arybuf->[($1-1)] );
		$main =~ s/\x04\[(\d+)\]\x04/$arybuf->[($1-1)]/eg;
	}
	my $subs = '';
	my $use_funcs = $self->{use_builtin_ary};
	foreach (@$use_funcs) {
		chomp($_);
		$_ = "push(\@F, $_);\n";
		$subs .= $_;
	}
	if ($subs ne '') { $subs = "\tmy \@F;\n" . $subs; }

	my $append='';
	if ($pragma & $p_is_function) {
		# 関数処理ならば、それを Base.pm に通知する
		$append .= "\t\$R->{Is_function}=1;\n";
	}
	return [$subhead . $append . $subs . $main];
}

#-----------------------------------------------------------
# 行情報からのPerl実行形式に変換する
#-----------------------------------------------------------
sub parse_line_to_cmd {
	my $self = shift;
	my $line = shift;
	my $use_builtin_ary  = $self->{use_builtin_ary};
	my $use_builtin_hash = $self->{use_builtin_hash};

	my $flag = ord($line);
	my $info = 0;

	# そのまま出力
	if ($flag > 3) {
		&into_single_quot_string($line);
		return ($flag, $info, $line);
	}
	# xxx.yy.zz 形式のデータに置換
	if ($flag == 2) {
		my $obj = &get_object( substr($line, 1) );
		return ($flag, $info, $obj);
	}
	# xxx.yy.zz 形式で xx がローカル変数
	if ($flag == 3) {
		$line =~ /^\x03((\w+).*)$/;
		my $obj = &get_object( $1, {$2 => 1} );
		return ($flag, $info, $obj);
	}

	# unknown
	if ($flag == 0) { return ($flag, 0, ''); }

	#-----------------------------------
	# 実行式 ($flag = 1)
	#-----------------------------------
	my $cmd = &get_line_data($line);

	# 行情報分離
	if ($cmd =~ /(.*?)\#(\d+)$/s) {
		$cmd  = $1;	# コマンド
		$info = $2;	# 行情報
	}

	# 組み込み関数?
	$cmd =~ s!\x04(\w+)\(!
		my $arg = $Builtin_func{"$1.arg"};
		if (exists($use_builtin_hash->{$1})) {
			'&{$F[' . $use_builtin_hash->{$1} . ']}(' . $arg;
		} else {
			# 初めて使用する組み込み関数
			push(@$use_builtin_ary, $Builtin_func{$1});
			$use_builtin_hash->{$1} = $#$use_builtin_ary;
			'&{$F[' . $#$use_builtin_ary . ']}(' . $arg;
		}
	!eg;
	return ($flag, $info, $cmd);
}



#------------------------------------------------------------------------------
# ●[07] 文字列を復元する
#------------------------------------------------------------------------------
sub recover_string {
	my ($self, $arybuf, $strbuf) = @_;

	foreach my $ary (@$arybuf) {
		if (! ref($ary)) {
			$ary =~ s/\x01\[\x01(\d+)\]/$strbuf->[$1]/g;
			next;
		}
		foreach(@$ary) {
			$_ =~ s/\x01\[\x01(\d+)\]/$strbuf->[$1]/g;
		}
	}
	return $arybuf;
}


###############################################################################
# ■エラー処理
###############################################################################
sub error {
	my $self  = shift;
	my $line  = shift;
	my $error = shift;
	$self->{errors}++;
	if ($line) { $line="[line $line] "; }
	$error = $line . $self->{ROBJ}->message_translate($error, @_);
	push( @{ $self->{error_msg} }, $error);
}

sub debug {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $str  = "[Compiler] $self->{src_file} : " . $ROBJ->message_translate(@_);
	return $ROBJ->debug($str,1,@_); # debug-safe
}
sub warning {
	my $self = shift;
	my $line  = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{warnings}++;
	if ($line) { $line=" at line " . int($line); }
	my $str = "[Compiler] $self->{src_file}$line : " . $ROBJ->message_translate(@_);
	return $ROBJ->_warning($str,2,@_);
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●名前からオブジェクトの取得
#------------------------------------------------------------------------------
sub get_object {
	my ($name, $local_vars, $in_string) = @_;
	$local_vars ||= {};
	if ($name eq 'v')         { return '$v'; }
	if ($local_vars->{$name}) { return $in_string?"\${$name}":"\$$name"; }
	my ($class, $name) = &get_object_sep(@_);
	return "$class\-\>{$name}";
}

sub get_object_sep {			# ■■注意■■ この仕様を変更する場合は、
	my $name       = shift;		# convert_reversed_poland も必ず変更すること。
	my $local_vars = shift || {};
	$name =~ s/[^\w\.]//g;			# 半角英数と _ . 以外の文字を除去
	if ($name eq '') { return 'undef'; }	# エラー時未定義を示すオブジェクトを返す

	$name =~ s/\.(\.*)/#$1/g;
	my @ary = split(/#/, $name);
	my $obj  = "\$R";
	my $last = pop(@ary);
	# 最適化機能
	my $first = $ary[0];
	if ($first eq 'v')              { $obj='$v';       shift(@ary); }
	  elsif ($local_vars->{$first}) { $obj="\$$first"; shift(@ary); }
	# print "$first $obj $local_vars->{$first}\n";
	foreach $name (@ary) {
		if (index($name, '.')<0) {
			$obj .= "->{$name}";
			next;
		}
		$obj .= "->{'$name'}";
	}
	if (index($last, '.')>=0) { $last="'$last'"; }
	return ($obj, $last);
}

sub get_objects_array {
	my $names = shift;
	my $types = shift;
	if (!ref $names) { $names = [$names]; }
	if (!ref $types) { $types = [$types]; }

	my @ary;
	foreach(0..$#$names) {
		my $name = $names->[$_];
		my $type = $types->[$_];
		if ($type eq 'obj' || $type eq 'const_var') {
			$name = &get_object($name, @_);
		}
		push(@ary, $name);
	}
	return @ary;
}

sub array2quote_string {
	my $names = shift;
	my $types = shift;
	if (!ref $names) { $names = [$names]; }
	if (!ref $types) { $types = [$types]; }

	my @ary;
	foreach(0..$#$names) {
		my $name = $names->[$_];
		my $type = $types->[$_];
		if ($type eq 'obj' || $type eq 'const_var') {
			$name =~ s/'//g;
			$name = "'$name'";
		}
		push(@ary, $name);
	}
	return @ary;
}

#------------------------------------------------------------------------------
# ●'' 中に入った文字列として加工する
#------------------------------------------------------------------------------
sub into_single_quot_string {
	foreach(@_) {
		if ($_ =~ /^\d+$/) { next; }		# 1234
		if ($_ =~ /^\d+\.\d*$/) { next; }	# 12.34
		$_ =~ s/([\\'])/\\$1/g;
		$_ = "'$_'";
	}
}

#------------------------------------------------------------------------------
# ●タグ除去
#------------------------------------------------------------------------------
sub tag_escape {
	foreach(@_) {
		$_ =~ s/"/&quot;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/</&lt;/g;
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●break判定が必要な関数か？
#------------------------------------------------------------------------------
# Ret) 1:true 0:false
my %break_function_cache;
sub check_break_function {
	my $func = shift;
	if (exists $break_function_cache{$func}) {
		return $break_function_cache{$func};
	}

	my $flag=0;
	foreach(@break_functions) {
		if (index($func,$_) == -1) { next; }
		$flag=1;
		last;
	}
	return ($break_function_cache{$func} = $flag)
}



###############################################################################
# ■デバッガ
###############################################################################
sub debug_save {
	my ($self, $filename, $buf, $lnum, $strbuf, $arybuf) = @_;
	my $ROBJ = $self->{ROBJ};
	my @lines;

	#---------------------------------------------------
	# 表示形式に変換
	#---------------------------------------------------
	if (ref $buf eq 'ARRAY') {
		@lines = @$buf;
		&conv_display_style(\@lines, $lnum);
	}

	#---------------------------------------------------
	# 表示形式に変換
	#---------------------------------------------------
	if (ref $arybuf) {
		my $no = 0;
		foreach my $ary (@$arybuf) {
			if ($no) { push(@lines, sprintf("\nARRAY:[%02d]", $no) . "--------------------------------------------------------------------\n"); }
			$no++;
			if (! ref($ary)) {	# 配列ではない
				push(@lines, $ary);
				next;
			}
			my @ary = @$ary;
			&conv_display_style(\@ary);
			foreach(@ary) {
				push(@lines, $_);
			}
		}
	}
	#---------------------------------------------------
	# 文字列復元
	#---------------------------------------------------
	foreach(@lines) {
		$_ =~ s/\x01\[(\d+?)\]/$strbuf->[$1]/g;
		$_ =~ s/[\x00-\x04]//g;	# 制御文字除去
	}
	# save
	$ROBJ->fwrite_lines($filename, \@lines);
}

#---------------------------------------------------
# 表示用の加工処理
#---------------------------------------------------
sub conv_display_style {
	my ($lines, $lnum) = @_;
	if (ref $lnum ne 'ARRAY') { $lnum = []; }

	my $line = 0;	# 行カウンタ
	my $this_line_default = '-' x $line_num_length;
	foreach(@$lines) {
		$line++;
		my $s = '::';
		my $this_line = $this_line_default;
		if ($lnum->[$line]) { $this_line = sprintf("%0${line_num_length}d", $lnum->[$line]); }
		if (ref $_ eq 'ARRAY') {	# 逆ポーランド記法の場合
			my @ary = @$_;
			$s = 'p)' . pop(@ary);
			$_ = join(' ', @ary);
		} elsif (ord($_) == 1) {	# eval - perl 式
			$s         = 'e$';
			$this_line = &get_line_num($_);	# 行番号取り出し
			$_         = &get_line_data($_);
			# 行情報取得
			my $info = 0;
			if ($_ =~ /\#(\d+)$/ && $1 & $l_replace) { $s = 'e@'; }
		} elsif (ord($_) == 2) {	# replace 単一式
			$s = 'R)';
			$_ = substr($_, 1);
		} elsif (ord($_) == 3) {	# replace 単一式 / ローカル変数
			$s = 'r)';
			$_ = substr($_, 1);
		}
		$_ =~ s/\n/\\n/g;	# 改行置換
		$_ =  "$this_line $s $_\n";
	}
}


1;
