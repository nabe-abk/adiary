###############################################################################
# ■カレンダー生成クラス
###############################################################################
sub {
	use strict;
#------------------------------------------------------------------------------
# ●クラス内変数
#------------------------------------------------------------------------------
my @holidays_list = (undef,
	# -n : 第n月曜日が休み
	[1,-2],			# 1
	[11],			# 2
	['shunbun'],		# 3
	[29],			# 4
	[3,4,5],		# 5
	[],			# 6
	[-3],			# 7
	[],			# 8
	[-3, 'shubun'],		# 9
	[-2],			# 10
	[3,23],			# 11
	[23]			# 12
);
my %holidays_name = (
	'1/1'  => '元日',
	'1/-2' => '成人の日',
	'2/11' => '建国記念の日',
	'3/shunbun' => '春分の日',
	'4/29' => '昭和の日',
	'5/3'  => '憲法記念日',
	'5/4'  => 'みどりの日',
	'5/5'  => 'こどもの日',
	'7/-3' => '海の日',
	'9/-3' => '敬老の日',
	'9/shubun' => '秋分の日',
	'10/-2'=> '体育の日',
	'11/3' => '文化の日',
	'11/23'=> '勤労感謝の日',
	'12/23'=> '天皇誕生日',
	'13/1' => '国民の休日',
	'13/2' => '振り替え休日'
);
my $noday_html = "\t<td></td>\n";

#------------------------------------------------------------------------------
# ●コンストラクタ（無名クラスを生成する）
#------------------------------------------------------------------------------
my $mop;
{
	my $aobj = shift;
	my $ROBJ = $aobj->{ROBJ};
	my $self = $ROBJ->loadpm('MOP', $aobj->{call_file});	# 無名クラス生成用obj
	$self->{aobj} = $aobj;
	$mop = $self;
}
#------------------------------------------------------------------------------
# ●カレンダー生成
#------------------------------------------------------------------------------
$mop->{generate_calendar} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};
	my $now  = $aobj->{now};
	my ($year, $mon, $day) = @_;

	my $today;
	if (!$year) {
		$year = $now->{year};
		$mon  = $now->{mon};
		$day  = $now->{day};
		$today = $day;
	} elsif ($year == $now->{year} && $mon == $now->{mon}) {
		$today = $now->{day};
	}

	#--------------------------------------------------
	# 記事のある日付をロード
	#--------------------------------------------------
	my $art_days = $self->load_artdays_in_month( $year, $mon );

	#--------------------------------------------------
	# カレンダー生成
	#--------------------------------------------------
	my $wday = $aobj->get_dayweek($year, $mon, 1);
	my $days = $aobj->get_mdays  ($year, $mon);

	my @holidays;
	my $ary = $holidays_list[$mon];
	my $m = int($mon);
	foreach(@$ary) {
		my $day = $_;
		my $name = $holidays_name{"$m/$_"};
		if ($_ =~ /^[A-Za-z]/) {	# 春分の日、秋分の日
			$day = $self->$_($year);
		} elsif ($_ < 0) {		# ハッピーマンデー
			my $x = -5 - $wday + 7*($wday > 1);
			$day = ($_*-7) + $x;
		}
		if ($day > 2 && $holidays[$day-2] && !$holidays[$day-1]) {	# 祝日と祝日の間は休日
			$holidays[$day-1] = $holidays_name{"13/1"};
		}
		$holidays[$day] = $name;
	}

	# 表示中の日付のクラス → day-selected
	my @lines;
	push(@lines, "<tr>\n");
	for(my $i=0; $i<$wday; $i++) {
		push(@lines, $noday_html);
	}
	my $path = $aobj->{myself2} . ($year*100 + $mon);
	for(my $i=1; $i<=$days; $i++, $wday++) {
		if ($wday == 7) {
			push(@lines, "</tr>\n<tr>\n");
			$wday = 0;
		}
		my $c="calendar-day w$wday";
		my $n=$holidays[$i];
		if ($n ne '') {
			$c .= ' holiday';
			if (!$wday) { # 祝日が日曜の場合、その後の「国民の祝日」でない日を休日
				my $j=$i;
				while ($holidays[$j]) { $j++; }
				$holidays[$j] = $holidays_name{"13/2"};
			}
			$n=" title=\"$n\"";
		}
		if ($day   == $i) { $c .= ' day-selected'; }
		if ($today == $i) { $c .= ' day-today'; }
		my $d = $art_days->[$i] ? "<a href=\"$path" . substr(100+$i,-2) . "\">$i</a>" : $i;
		push(@lines, "\t<td class='$c'$n>$d</td>\n");
	}
	for( ;$wday<7; $wday++) {
		push(@lines, $noday_html);
	}
	push(@lines, "</tr>\n");

	return \@lines;
};

#------------------------------------------------------------------------------
# ●指定月に存在する記事のロード
#------------------------------------------------------------------------------
$mop->{load_artdays_in_month} = sub {
	my ($self, $year, $mon) = @_;
	my $aobj = $self->{aobj};
	my $DB     = $aobj->{DB};
	my $blogid = $aobj->{blogid};
	if ($blogid eq '') { return []; }
	my $yyyymm = $year*100 + $mon;

	# データベースからロード
	my %h;
	$h{min}  = {yyyymmdd => "${yyyymm}01"};
	$h{max}  = {yyyymmdd => "${yyyymm}31"};
	$h{cols} = ['yyyymmdd'];
	$h{not_null} = ['tm'];
	if (!$self->{allow_edit}) {
		$h{flag}->{enable} = 1;
	}

	my $data = $DB->select("${blogid}_art", \%h);
	my @days;
	foreach(@$data) {
		@days[ substr($_->{yyyymmdd}, -2) ] = 1;
	}
	return \@days;
};
#------------------------------------------------------------------------------
# ●先月、翌月を取得
#------------------------------------------------------------------------------
$mop->{prev_month} = sub {
	my ($self, $yyyymm) = @_;
	if ($yyyymm < 198002) { return '198001'; }
	my $mon = substr($yyyymm, -2);
	if ($mon eq '01') {
		return $yyyymm -100 +11;
	}
	return $yyyymm-1;
};
$mop->{next_month} = sub {
	my ($self, $yyyymm) = @_;
	if ($yyyymm > 999911) { return '999912'; }
	my $mon = substr($yyyymm, -2);
	if ($mon eq '12') {
		return $yyyymm +100 -11;
	}
	return $yyyymm+1;
};
#------------------------------------------------------------------------------
# ●春分の日、秋分の日
#------------------------------------------------------------------------------
# --- およそ2150年程度まで使える簡易春分・秋分計算 ---
$mop->{shunbun} = sub {
	my $self = shift;
	my $y = $_[0] -2000;
	return int(20.69115 + 0.011 + 0.242194*$y - int($y/4) + int($y/100));
};
$mop->{shubun} = sub {
	my $self = shift;
	my $y = $_[0] -2000;
	return int(23.10260 - 0.02  + 0.242194*$y - int($y/4) + int($y/100));
};
###############################################################################
###############################################################################
	return $mop;
}
