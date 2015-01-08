use strict;
#-------------------------------------------------------------------------------
# JPEGファイルのExif操作のためのモジュール
#							(C)2015 nabe@abk
#-------------------------------------------------------------------------------
# Class::MOPのまね事です。
package Satsuki::Jpeg;
our $VERSION = '1.00';
our $CHECK_SIZE = 1024;
use Fcntl;
#------------------------------------------------------------------------------
# ●コンストラクタ
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({
		ROBJ => shift,
		__CACHE_PM => 1
	}, $class);
}

#------------------------------------------------------------------------------
# ●Exifの存在確認
#------------------------------------------------------------------------------
sub exists_exif {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = $ROBJ->get_filepath(shift);
	# if ($file =~ /\.jpe?g$/i) { return; }

	my $fh;
	my $head;
	sysopen($fh, $file, O_RDONLY);
	binmode($fh);
	sysread($fh, $head, $CHECK_SIZE);
	close($fh);

	my $exif = ($head =~ /\xFF\xE1..Exif/s);
	return $exif;
}

#------------------------------------------------------------------------------
# ●Exifの削除
#------------------------------------------------------------------------------
sub strip {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $file = $ROBJ->get_filepath(shift);

	my $fh;
	my $data;
	sysopen($fh, $file, O_RDWR) || return -999;
	binmode($fh);
	$ROBJ->write_lock($fh);
	sysread($fh, $data, -s $fh);

	my $r=0;
	my @segs;
	while(1) {
		if (substr($data, 0, 2) ne "\xFF\xD8") { $r=-1; last; }
		my $p   = 2;
		my $len = length($data);
		while($p < $len) {
			my %h;
			my $marker = substr($data, $p, 2);
			if (substr($marker,0,1) ne "\xFF") { last; }	# err

			$h{marker} = $marker;
			$h{offset} = $p;
			$h{size}   = (ord(substr($data, $p+2, 1))<<8) + ord(substr($data, $p+3, 1)) +2;
			$p += $h{size};
			push(@segs, \%h);

			if ($marker ne "\xFF\xDA") { next; }
			# SOSマーカー（データの開始）を発見
			$h{size} = $h{size} + ($len -$p) +2;
			$p = $len-2;
			if (substr($data, $p, 2) eq "\xFF\xD9") { $p += 2; }	# EOIセグメント
			last;
		}
		if ($p != $len) { $r=-2; last; }

		# ファイルの書き出し
		seek($fh, 2, 0);
		foreach(@segs) {
			my $m = ord( substr($_->{marker},1,1) );
			if ((0xE1 <= $m && $m <0xEF) || $m == 0xFE) {
				# APP1 - 15と、コメントセグメント(0xFE)は無視
				# APP1 = Exif
				next;
			}
			syswrite($fh, $data, $_->{size}, $_->{offset});
		}
		# 現在の位置でファイル切り詰め
		truncate($fh, sysseek($fh, 0, 1));	# tell($fh)では動作しない!!
		last;
	}
	close($fh);
	return $r;
}

1;
