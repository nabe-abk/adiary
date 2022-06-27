use strict;
#-------------------------------------------------------------------------------
# データインポート for Movable Type形式
#                                                   (C)2013 nabe@abk
#-------------------------------------------------------------------------------
# http://www.sixapart.jp/movabletype/manual/mtimport.html
package SatsukiApp::adiary::ImportMT;
use Time::Local;
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift}, $class);
}

################################################################################
# ■データインポータ
################################################################################
#-------------------------------------------------------------------------------
# ●Movable Type形式のデータインポート
#-------------------------------------------------------------------------------
sub import_arts {
	my ($self, $aobj, $form, $session) = @_;
	my $ROBJ = $self->{ROBJ};

	# データチェック
	my $data = $form->{file}->{data};
	delete $form->{file};
	{
		my $check_data = substr($data, 0, 1024);
		if ($check_data !~ /DATE:\s+\d\d\/\d\d\/\d\d\d\d\s+\d\d:\d\d:\d\d.*?\n-----\n/s) {
			$session->msg('Data format error (%s)', 'Movable Type');
			return -1;
		}

		# 文字コード変換
		my $system_coding = $ROBJ->{SystemCode};
		my $jcode = $ROBJ->load_codepm();
		$jcode->from_to(\$data, '', $system_coding);

		# 改行コード変換
		$data =~ s/\r\n|\r/\n/g;
	}

	my @days = split("\n--------\n", $data);
	undef $data;
	if ($days[$#days] =~ /^[\n\s]*$/s) { pop(@days); }

	# 日付変更時間
	my $lf2br       = $form->{lf2br};
	my $lf2br_force = $form->{lf2br_force};
	my $tz          = int($form->{tz}) * 3600;
	if ($lf2br eq '') { $lf2br=1; }

	#-----------------------------------------------------------------------
	# ログの解析と保存
	#-----------------------------------------------------------------------
	foreach my $log (@days) {
		my @ary = split("\n", $log);
		undef $log;
		#---------------------------------------------------------------
		# 記事情報の読み出し
		#---------------------------------------------------------------
		my %art;
		my $convert_breaks = $lf2br;
		my @tags;
		while(@ary) {
			my $line = shift(@ary);
			if ($line eq '-----') { last; }	# separator/block end
			# XXXX: value を解析
			$line =~ /^([A-Z ]+):\s*(.*)\s*$/;
			my $key = $1;
			my $val = $2;
			if ($key eq '' || $val eq '') { next; }
			# 個別処理
			if ($key eq 'DATE') {	# 日付データ解析
				$art{tm} = &date2utc($val, $tz);
				my $h = $ROBJ->time2timehash( $art{tm} );
				$art{year} = $h->{year};
				$art{mon}  = $h->{mon};
				$art{day}  = $h->{day};
				next;
			}
			# カテゴリ→タグ
			if ($key eq 'PRIMARY CATEGORY' || $key eq 'CATEGORY') { push(@tags, $val); next; }

			# その他フィールド
			if ($key eq 'STATUS' && $val =~ /draft/i)   { $art{enable} = 0; next; }
			if ($key eq 'STATUS' && $val =~ /publish/i) { $art{enable} = 1; next; }
			if ($key eq 'AUTHOR') { $art{name}  = $val; next; }
			if ($key eq 'TITLE')  { $art{title} = $val; next; }
			# 数値フィールド処理
			if ($val ne '0' && $val ne '1') { next; }
			if ($key eq 'ALLOW COMMENTS') { $art{allow_com}=$val; next; }
			if ($key eq 'ALLOW PINGS')    { $art{allow_tb} =$val; next; }
			if ($key eq 'CONVERT BREAKS') { $convert_breaks  =$val; next; }
			if ($key eq 'NO ENTRY')       { $art{no_entry} =$val; next; } # not use
		}
		if ($lf2br_force) { $convert_breaks=$lf2br; }	# 強制指定
		if (!$art{tm} || $art{no_entry}) { next; }	# DATE がない or NO ENTRY のデータは無視

		# タグ情報
		$art{tags} = join(',',@tags);

		#---------------------------------------------------------------
		# 複数フィールドの処理（フィールドの出現順を当て込まない）
		#---------------------------------------------------------------
		my $body;
		my $ex_body;
		my @comments;
		my @trackbacks;
		while(@ary) {
			my $line = shift(@ary);
			if ($line !~ /^([A-Z ]+):\s*$/) { next; }
			my $key = $1;
			# 本文
			if ($key eq 'BODY')          { $body    = &load_section(\@ary); next; }
			if ($key eq 'EXTENDED BODY') { $ex_body = &load_section(\@ary); next; }
			# コメント
			if ($key eq 'COMMENT') {
				my %comment;
				while(@ary && $ary[0] =~ /([A-Z ]+):\s*(.*)/) {
					shift(@ary);
					if ($1 eq 'AUTHOR') { $comment{name} = $2; next; }
					if ($1 eq 'EMAIL')  { $comment{email}= $2; next; }
					if ($1 eq 'URL')    { $comment{url}  = $2; next; }
					if ($1 eq 'IP')     { $comment{ip}   = $2; next; }
					if ($1 eq 'DATE')   { $comment{tm}   = &date2utc($2, $tz); next; }
				}
				$comment{text} = join("\n", @{ &load_section(\@ary) });
				$comment{text} =~ s/<br>/\n/g;
				if ($comment{name} eq '') { $comment{name}='(no name)'; }
				if ($comment{text} eq '') { next; }	# 本文がないデータは無視
				push(@comments, \%comment);
				next;
			}
			# トラックバック
			if ($key eq 'PING') {
				my %tb;
				while(@ary && $ary[0] =~ /([A-Z ]+):\s*(.+)/) {
					shift(@ary);
					if ($1 eq 'TITLE')     { $tb{title}     = $2; next; }
					if ($1 eq 'URL')       { $tb{url}       = $2; next; }	# not use
					if ($1 eq 'IP')        { $tb{ip}        = $2; next; }
					if ($1 eq 'BLOG NAME') { $tb{blog_name} = $2; next; }
					if ($1 eq 'DATE')      { $tb{tm}        = &date2utc($2, $tz); next; }
				}
				$tb{excerpt} = join("\n", @{ &load_section(\@ary) });
				if ($tb{url} eq '') { next; }	# URLがないデータは無視
				push(@trackbacks, \%tb);
				next;
			}
			# 一応ロードするが adiary に該当する実装がない（未対応）のフィールド
			if ($key eq 'EXCERPT')  { $art{execrpt}  = &load_section(\@ary); next; }	# 読み捨て
			if ($key eq 'KEYWORDS') { $art{keywords} = &load_section(\@ary); next; }	# 読み捨て
			# その他の未知のフィールドは読み捨て
			&load_section(\@ary);
		}

		#---------------------------------------------------------------
		# 本文抽出とパーサーの選択処理
		#---------------------------------------------------------------
		foreach(@$body)    { $_ =~ s/^====/ ====/; }
		foreach(@$ex_body) { $_ =~ s/^====/ ====/; }
		while(@$body    &&    $body->[    $#$body ] eq '') { pop(@$body);    }
		while(@$ex_body && $ex_body->[ $#$ex_body ] eq '') { pop(@$ex_body); }
		$body    = join("\n", @$body);
		$ex_body = join("\n", @$ex_body);
		if ($body =~ /^\s*$/) { next; }		# 本文ないデータは無視
		if ($ex_body !~ /^\s*$/) {		# 追記を続きを読むで処理
			$body .= "\n\n====\n$ex_body";
		}
		# 段落処理モード？
		if ($convert_breaks) { $art{parser} = 'simple_br'; }
				else { $art{parser} = 'simple';   }
		# 変数に格納
		$art{text} = $body;
		$body = $ex_body = undef;

		#---------------------------------------------------------------
		# データを保存
		#---------------------------------------------------------------
		$aobj->save_article(\%art, \@comments, \@trackbacks, $form, $session);
	}
	return 0;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●Movable Type形式の日付データを UTC に変換
#-------------------------------------------------------------------------------
#	MM/DD/YYYY hh:mm:ss
#	MM/DD/YYYY hh:mm:ss AM/PM
sub date2utc {
	my $date = shift;
	my $tz   = shift;
	if ($date !~ /^(\d\d)\/(\d\d)\/(\d\d\d\d) (\d\d):(\d\d):(\d\d)\s*(\w*)/) { return ; }
	my $mon  = $1;
	my $day  = $2;
	my $year = $3;
	my $hour = $4;
	my $min  = $5;
	my $sec  = $6;
	if ($7 && $hour == 12) { $hour=0; }
	if (uc($7) eq 'PM') { $hour += 12; }
	
	my $tm = Time::Local::timegm($sec,$min,$hour,$day,$mon-1,$year) - $tz;
	return $tm<1 ? 1 : $tm;
}
#-------------------------------------------------------------------------------
# ●「-----」で区切られたセクションの終わりまでロード
#-------------------------------------------------------------------------------
sub load_section {
	my $ary = shift;
	my @section;
	while(@$ary) {
		my $data = shift(@$ary);
		if ($data eq '-----') { last; }
		push(@section, $data);
	}
	if ($section[ $#section ] eq '') { pop(@section); }	# 最後の空行を切り捨て
	return \@section;
}


1;
