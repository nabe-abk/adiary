use strict;
#-------------------------------------------------------------------------------
# データインポート for JUGEM形式(xml)
#                                                   (C)2013 nabe@abk
#-------------------------------------------------------------------------------
# 全体的に、Movable Type形式の属性を拡張して、XMLに収めたような構文です。
#
package SatsukiApp::adiary::ImportJUGEM;
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
# ●JUGEM形式のデータインポート
#-------------------------------------------------------------------------------
sub import_arts {
	my ($self, $aobj, $form, $session) = @_;
	my $ROBJ = $self->{ROBJ};

	# データチェック
	my $data = $form->{file}->{data};
	delete $form->{file};
	{
		my $check_data = substr($data, 0, 1024);
		if ($check_data !~ /<\?xml .*? encoding="([\w\-]*)".*?\?>.*<blog>/s) {
			$session->msg('Data format error (%s)', 'JUGEM');
			return -1;
		}
		my $file_coding = $1 || 'UTF-8';
		$file_coding =~ tr/a-z/A-Z/;

		# 文字コード変換
		my $system_coding = $ROBJ->{System_coding};
		if ($system_coding ne $file_coding) {
			my $jcode = $ROBJ->load_codepm();
			$jcode->from_to(\$data, $file_coding, $system_coding);
		}
		# 改行コード変換
		$data =~ s/\r\n|\r/\n/g;
	}

	# CDATAの退避
	my @cdata;
	$data =~ s|<!\[CDATA\[(.*?)\]\]>|push(@cdata, $1),"<c$#cdata>"|seg;
	# エントリー抽出
	my @days;
	$data =~ s|<entry>(.*?)</entry>|push(@days, $1),''|seg;
	undef $data;

	# 引数設定
	my $change_hour = $form->{change_hour_int};
	my $lf2br       = $form->{lf2br};
	my $lf2br_force = $form->{lf2br_force};
	my $tz          = int($form->{tz}) * 3600;
	if ($lf2br eq '') { $lf2br=1; }

	#-----------------------------------------------------------------------
	# ログの解析と保存
	#-----------------------------------------------------------------------
	foreach my $log (@days) {
		#---------------------------------------------------------------
		# コメント、トラックバックの抽出
		#---------------------------------------------------------------
		my $comments='';
		my $trackbacks='';
		$log =~ s/<comments>(.*?)<\/comments>/$comments=$1,''/se;
		$log =~ s/<trackbacks>(.*?)<\/trackbacks>/$trackbacks=$1,''/se;

		#---------------------------------------------------------------
		# 記事データの解析
		#---------------------------------------------------------------
		my %art;
		$log =~ s|<(\w+)>(.*?)</\1>|$art{$1}=$2,''|seg;
		&xml_decode( \%art, \@cdata );
		# 日付変換
		my $tm = $art{tm} = &date2utc($art{date}, $tz);
		if (! $tm) { next; }	# DATE がないデータは無視
		my $h = $ROBJ->time2timehash( $art{tm}, $change_hour );
		$art{year} = $h->{year};
		$art{mon}  = $h->{mon};
		$art{day}  = $h->{day};
		# 執筆者
		$art{name} = $art{author};
		# フラグ系の解析
		if ($art{status} =~ /publish/i) { $art{enable}=1; } # 表示
		if ($art{status} =~ /draft/i)   { $art{enable}=0; } # 非表示
		if (exists $art{allowcomments}) {	# sb仕様 ＞ 0:不許可 1:許可 2:要承認
			if($art{allowcomments}) { $art{allowcomments}=1; } else { $art{allowcomments}=0; }
		}
		if (exists $art{allowpings})    {	# sb仕様 ＞ 0:不許可 1:許可 2:要承認
			if($art{allowpings}) { $art{allowpings}=1; } else { $art{allowpings}=0; }
		}
		$art{com_ok} = $art{allowcomments};

		#---------------------------------------------------------------
		# コメントの解析
		#---------------------------------------------------------------
		my @comments;
		if ($comments ne '') {
			my @ary;
			$comments =~ s/<comment>(.*?)<\/comment>/push(@ary, $1),''/seg;
			foreach(@ary) {
				my %h;
				$_ =~ s|<(\w+)>(.*?)</\1>|$h{$1}=$2,''|seg;
				&xml_decode( \%h, \@cdata );
				$h{tm}   = &date2utc($h{date}, $tz);
				$h{text} = $h{description};
				delete $h{description};

				$h{text} =~ s/<br(?:\s*\/)?>/\n/g;	# <br>→\n に戻す
				push(@comments, \%h);
			}
		}

		#---------------------------------------------------------------
		# トラックバックの解析
		#---------------------------------------------------------------
		my @trackbacks;
		if ($trackbacks ne '') {
			my @ary;
			$trackbacks =~ s/<trackback>(.*?)<\/trackback>/push(@ary, $1),''/seg;
			foreach(@ary) {
				my %h;
				$_ =~ s|<(\w+)>(.*?)</(\1)>|$h{$1}=$2,''|seg;
				&xml_decode( \%h, \@cdata );
				push(@trackbacks, \%h);
			}
		}

		#---------------------------------------------------------------
		# JUGEM形式の記事データをadiaryの適当なスタイル向けに整形
		#---------------------------------------------------------------
		my $convert_breaks = $art{convertbreaks};
		if ($convert_breaks eq '' || $lf2br_force) { $convert_breaks = $lf2br; }

		my $body    = $art{description};
		my $ex_body = $art{sequel};
		while(substr(   $body, -1) eq "\n") { chop(   $body); }
		while(substr($ex_body, -1) eq "\n") { chop($ex_body); }
		if ($body =~ /^\s*$/) { next; }		# 本文ないデータは無視
		# 行頭 ==== をエスケープ
		$body    =~ s/\n====/ ====/g;
		$ex_body =~ s/\n====/ ====/g;
		if ($ex_body !~ /^\s*$/) {		# 追記を続きを読むで処理
			$body .= "\n\n====\n$ex_body";
		}
		# 段落処理モード？
		if ($convert_breaks) { $art{parser} = 'simple_br'; }
				else { $art{parser} = 'simple';   }
		# <br /> を除去
		$body    =~ s/<br( \/)?>//g;
		# 変数に格納
		$art{text} = $body;
		$body = $ex_body = undef;
		delete $art{description};
		delete $art{sequel};

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
# ●xmlのエンコードを戻す
#-------------------------------------------------------------------------------
sub xml_decode {
	my ($h, $cdata) = @_;
	while(my ($k,$v) = each(%$h)) {
		if ($v =~ /^<c(\d+)>$/) {
			$v = $cdata->[$1];
		} else {
			$v =~ s/&lt;/</g;
			$v =~ s/&gt;/>/g;
			$v =~ s/&quot;/"/g;
			$v =~ s/&amp;/&/g;
			$v =~ s/&#(\d+);/chr($1)/eg;
		}
		$h->{$k} = $v;
	}
	return $h;
}
#-------------------------------------------------------------------------------
# ●JUGEM形式の日付データを UTC に変換
#-------------------------------------------------------------------------------
#	MM/DD/YYYY hh:mm:ss
#	MM/DD/YYYY hh:mm:ss AM/PM
sub date2utc {
	my $date = shift;
	my $tz   = shift;
	if ($date !~ /^(\d\d\d\d)\/(\d\d)\/(\d\d) (\d\d):(\d\d):(\d\d)(.*)/) { return ; }
	my $year = $1;
	my $mon  = $2;
	my $day  = $3;
	my $hour = $4;
	my $min  = $5;
	my $sec  = $6;
	my $add  = $7;	# 一致部より後ろ
	if ($add =~ /\+(\d\d):(\d\d)/) { $tz =  $1*3600+$2*60; }
	if ($add =~ /\-(\d\d):(\d\d)/) { $tz = -$1*3600-$2*60; }
	return (Time::Local::timegm($sec,$min,$hour,$day,$mon-1,$year) - $tz);
}

1;
