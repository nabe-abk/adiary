use strict;
#------------------------------------------------------------------------------
# buffer 付データ読み込みルーチン
#						(C)2006-04 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package Satsuki::Base::BufferedRead;
our $VERSION = '1.00';
#------------------------------------------------------------------------------
my $boundary_max        =     1024;	# 境界記号の最大長指定
my $buffer_size_default = 256*1024;	# バッファサイズのデフォルト
# 最低限 $boundary_max <= $buffer_size_default であること。
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;

	$self->{fh}          = shift || 'STDIN';	# データを読み出す FileHandle
	$self->{read_size}   = 0;			# 読み出した量
	$self->{read_max}    = int(shift);		# 最大読み込み量
	$self->{buffer_size} = int(shift) || $buffer_size_default;
	if ($self->{buffer_size} > $self->{read_max}) {
		$self->{buffer_size} = $self->{read_max};
	}
	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●データを読み出し
#------------------------------------------------------------------------------
# ※buffer_size = boundary_size の条件で動作チェック済 (2006/4/22)
#
sub read_line {
	my $self = shift;
	my ($output, $boundary, $output_max_size) = @_;
	# 入力データチェック
	my $boundary_size = length($boundary);
	if ($boundary_size == 0 || $boundary_size > $boundary_max) { return ; }
	my $output_is_file;
	if (ref($output) ne 'SCALAR' && ($output eq '' || !fileno($output))) { $output = \( $_[0] ); }
	if (ref($output) eq 'SCALAR') { $$output = ''; }

	# buffer の状態読み込み
	my $read_size = $self->{read_size};
	my $read_max  = $self->{read_max};
	my $buf       = $self->{buffer};
	my $offset    = $self->{buffer_offset};
	my $fh        = $self->{fh};
	my $buf_size  = $self->{buffer_size}+0;
	if ($buf_size < $boundary_max) { $buf_size = $buffer_size_default; }

	my $out_size_total;
	while (1) {
		my $find = index($buf, $boundary, $offset);
		if ($find >= 0) {
			my $size  = $find - $offset;
			&output($output, \$out_size_total, $output_max_size, $buf, $offset, $size);
			$offset  += $size + $boundary_size;		# 読み込んだ分だけずらす
			last;
		}
		#-------------------------------------------
		# buffer が空になった
		#-------------------------------------------
		# データもすべて読み終わり
		if ($self->{file_eof}) {
			my $size = length($buf) - $offset;
			&output($output, \$out_size_total, $output_max_size, $buf, $offset, $size);
			$self->{data_end}=1;
			last;
		}
		# 後ろから境界サイズ-1 分を残して出力
		my $read_buf_offset = 0;
		if ($buf ne '') {
			my $size = $buf_size - $offset;
			if ($size >= $boundary_size-1) {
				# 残りサイズ >= 境界文字列サイズ-1
				$read_buf_offset = $boundary_size-1;	# 境界文字列サイズ-1 をずらして残す
				$size -= $boundary_size-1;		# 境界文字列サイズ-1 を残して出力
			} else {
				# 残りサイズ <  境界文字列サイズ-1
				$read_buf_offset = $size;		# 残りサイズ分すべてをずらして残す
				$size  = 0;				# 出力しない
			}
			&output($output, \$out_size_total, $output_max_size, $buf, $offset, $size);
			substr($buf, 0, $read_buf_offset) = substr($buf, -$read_buf_offset);	# 先頭部にcopy
			$offset = 0;
		}
		# buffer へ追加読み込み
		my $try_read_size = $buf_size - $read_buf_offset;
		if ($read_max && ($read_max < $read_size + $try_read_size)) {	# 最大サイズ < 読み出しサイズ
			$try_read_size = $read_max - $read_size;
		}
		my $read_bytes = read($fh, $buf, $try_read_size, $read_buf_offset);
		$read_size += $read_bytes;
		# file eof か 最大読み込み量まで読み込んだ
		if (($read_bytes+$read_buf_offset) < $buf_size || ($read_max && $read_max <= $read_size)) {
			$self->{file_eof} = 1;
		}
	}
	# 値の保存
	$self->{buffer}        = $buf;
	$self->{buffer_offset} = $offset;
	$self->{read_size}     = $read_size;
	return $out_size_total;
}

#-----------------------------------------------------------
# ○データを出力する
#-----------------------------------------------------------
sub output {
	my ($output, $out_size, $out_max_size, $buf, $offset, $size) = @_;
	my $new_out_size = $$out_size + $size;
	if ($out_max_size && $new_out_size > $out_max_size) {
		$size = $size - ($new_out_size - $out_max_size);
	}
	if ($size < 1) { return $$out_size; }	# 0以下なら出力せず return
	if (ref($output) eq 'SCALAR') {
		$$output .= substr($buf, $offset, $size);
	} else {
		syswrite($output, $buf, $size, $offset);
	}
	return ($$out_size += $size);		# 累計出力サイズ
}


1;
