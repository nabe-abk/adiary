use strict;
#------------------------------------------------------------------------------
# データインポート for WordPress形式(xml)
#                                                   (C)2013 nabe
#------------------------------------------------------------------------------
# WordPress 2.1.x 以降に実装された XML 形式。
#
package SatsukiApp::adiary::ImportWordPressXML;
use Time::Local;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	return bless({ROBJ => shift}, $class);
}

###############################################################################
# ■データインポータ
###############################################################################
#------------------------------------------------------------------------------
# ●WordPress(xml)形式のデータインポート
#------------------------------------------------------------------------------
sub import_arts {
	my ($self, $aobj, $form, $session) = @_;
	my $ROBJ = $self->{ROBJ};

	my $input_coding = 'UTF-8';

	# データチェック
	my $data = $form->{file}->{data};
	delete $form->{file};
	{
		my $check_data = substr($data, 0, 4096);
		if ($check_data !~ m|<!--\s*generator="wordpress/|i
		 || $check_data !~ m|<\?xml [^>]*? encoding="([\w\-]*)".*?\?>|) {
			$session->msg('Data format error (%s)', "WordPress(XML)");
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
	$data =~ s|<item>(.*?)</item>|push(@days, $1),''|seg;
	# カテゴリ抽出
	my @category;
	$data =~ s|<wp:category>(.*?)</wp:category>|push(@category, $1),''|seg;
	undef $data;

	#---------------------------------------------------------------------
	# カテゴリの解析
	#---------------------------------------------------------------------
	my %category;
	{
		my %c;
		foreach(@category) {
			my %h;
			$_ =~ s|<([\w:]+)>(.*?)</\1>|$h{$1}=$2,''|seg;
			&xml_decode( \%h, \@cdata );
			my $name = $h{'wp:cat_name'};
			if ($name eq '') { next; }

			$c{ $h{'wp:category_nicename'} } = {
				name   => $name,
				parent => $h{'wp:category_parent'}
			};
		}
		foreach my $nice (keys(%c)) {
			my $name = $c{$nice}->{name};
			my $par  = $c{$nice}->{parent};
			my $fullname = $name;
			while($par) {
				my $par_name = $c{$par}->{name};
				if ($par_name eq '') { last; }
				$fullname = $par_name . '::' . $fullname;
				$par = $c{$par}->{parent};
			}
			$category{ $name } = $fullname;
		}
	}

	# 引数設定
	my $change_hour   = $form->{change_hour_int};
	my $import_static = $form->{import_static};	# 静的ページをインポート
	my $tags4static   = $form->{tags_for_static};	# 静的ページに付加するタグ
	my $no_auth_com   = $form->{no_auth};		# 非承認コメントをインポートしない
	#---------------------------------------------------------------------
	# ログの解析と保存
	#---------------------------------------------------------------------
	foreach my $log (@days) {
		#-------------------------------------------------------------
		# コメント、トラックバックの抽出
		#-------------------------------------------------------------
		my @comments_data;
		$log =~ s/<wp:comment>(.*?)<\/wp:comment>/push(@comments_data,$1),''/seg;

		#-------------------------------------------------------------
		# 記事データの解析
		#-------------------------------------------------------------
		my %art;
		my $day = {};
		my @cats;
		my @tags;
		$log =~ s|<category [^>]*domain="category"[^>]*>(.*?)</category>|push(@cats,$1),''|ieg;
		$log =~ s|<category [^>]*>(.*?)</category>|push(@tags, $1),''|ieg;
		$log =~ s|<([\w:]+)>(.*?)</\1>|$day->{$1}=$2,''|seg;
		&xml_decode( \@cats, \@cdata );
		&xml_decode( \@tags, \@cdata );
		&xml_decode( $day,   \@cdata );

		# カテゴリは階層付きで取り込む
		foreach(@cats) {
			$_ = exists($category{$_}) ? $category{$_} : $_;
		}
		unshift(@tags, @cats);

		# 公開・非公開？
		my $status = $day->{'wp:status'};
		if ($status eq 'publish') {
			$art{enable} = 1;
		} elsif ($status eq 'private') {
			$art{enable} = 0;
		} elsif ($status eq 'draft') {
			$art{draft} = 1;
		} else {	# if attachment/object
			next;
		}
		if ($day->{'wp:post_password'} ne '') {
			$art{enable} = 0;	# パスワード保護ページは非公開に
		}

		# 固定ページ？
		my $type = $day->{'wp:post_type'};
		if ($type eq 'page') {
			if (!$import_static) { next; }
			if ($tags4static ne '') {
				push(@tags, $tags4static);
			}
		}

		# タイトル、タグ、投稿者
		$art{title} = $day->{title};
		$art{tags}  = join(',', @tags);
		$art{name}  = $day->{'dc:creator'};

		# 日付情報
		my $gmt = &date2utc($day->{'wp:post_date_gmt'});
		if ($gmt) {
			# 記事につける日付
			my $h = $ROBJ->time2timehash( $gmt, $change_hour );
			$art{year}= $h->{year};
			$art{mon} = $h->{mon};
			$art{day} = $h->{day};
			$art{tm}  = $gmt;
		} elsif ($status eq 'draft') {
			# エラー
			$session->msg('Not set date draft "%s", import to day of "%s"', $art{title}, '1999-01-01');
			$art{year}= 1999;
			$art{mon} = 1;
			$art{day} = 1;
		} else {
			next;	# エラー
		}
		# コメント/トラックバックの許可
		$art{com_ok} = $day->{'wp:comment_status'} eq 'open' ? 1 : 0;

		#-------------------------------------------------------------
		# 記事本文の処理と加工
		#-------------------------------------------------------------
		my $body = $day->{'content:encoded'};
		if ($body =~ /^\s*$/) { next; }
		$body =~ s/\\r\\n|\\r|\\n/\n/g;
		# 続きを読む記号のエスケープ
		$body =~ s/(\G|\n)====\n/$1 ====\n/g;
		# 続きを読む記号の置き換え
		$body =~ s/(\G|\n)<!--more-->/$1====\n/;
		# 変数に格納
		$art{text}   = $body;
		$art{parser} = 'simple_p';

		#-------------------------------------------------------------
		# コメント・トラックバックの解析
		#-------------------------------------------------------------
		my @comments;
		my @trackbacks;
		foreach(@comments_data) {
			my %h;
			my %data;
			$_ =~ s|<wp:comment_(\w+)>(.*?)</wp:comment_\1>|$data{$1}=$2,''|seg;
			&xml_decode( \%data, \@cdata );
			# 日付情報
			$h{tm} = &date2utc($data{date_gmt});
			# 公開フラグ
			if ($data{approved} eq '0' && $no_auth_com) { next; }
			$h{enable} = int($data{approved});
			# 接続者・投稿者情報
			$h{ip}    = $data{author_IP};
			$h{agent} = $data{agent};
			$h{url}   = $data{author_url};
			#-------------------------------------------------------------
			# 本文処理
			#-------------------------------------------------------------
			my $body = $data{content};
			# <br> to \n
			$body =~ s/<br.*?>|\\r\\n|\\r|\\n/\n/g;
			# タグを除去
			$ROBJ->tag_delete($body);

			if ($body =~ /^\s*$/) { next; }
			if ($data{type} ne 'trackback') {
				#-------------------------------------------------------------
				# コメントの処理
				#-------------------------------------------------------------
				$h{name}  = $data{author};
				$h{email} = $data{author_email};
				$h{text}  = $body;	# コメント本文
				push(@comments, \%h);
				next;
			}
			#-------------------------------------------------------------
			# トラックバックの処理
			#-------------------------------------------------------------
			$h{blog_name} = $data{author};
			if ($body =~ /^(.*?)\.\.\.\n\n(.*)/) {
				$h{title} = $1;
				$body     = $2;
			}
			$body =~ s/ \(more\.\.\.\)$/.../g;	# 最後の (more...) を ... に置き換え
			$h{excerpt} = $body;
			push(@trackbacks, \%h);
		}

		#-------------------------------------------------------------
		# データを保存
		#-------------------------------------------------------------
		$aobj->save_article(\%art, \@comments, \@trackbacks, $form, $session);
	}
	return 0;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●xmlのエンコードを戻す
#------------------------------------------------------------------------------
sub xml_decode {
	my ($h, $cdata) = @_;
	my $is_ary = ref($h) eq 'ARRAY';
	my $ary = $is_ary ? $h : [ keys(%$h) ];
	foreach(@$ary) {
		my $v = $is_ary ? $_ : $h->{$_};
		if ($v =~ /^<c(\d+)>$/) {
			$v = $cdata->[$1];
		} else {
			$v =~ s/&lt;/</g;
			$v =~ s/&gt;/>/g;
			$v =~ s/&quot;/"/g;
			$v =~ s/&amp;/&/g;
			$v =~ s/&#(\d+);/chr($1)/eg;
		}
		if ($is_ary) {
			$_ = $v;
		} else {
			$h->{$_} = $v;
		}
	}
	return $h;
}

#------------------------------------------------------------------------------
# ●WordPress XML形式の日付データを UTC に変換
#------------------------------------------------------------------------------
#	YYYY-MM-DD hh:mm:ss
sub date2utc {
	my $date = shift;
	my $tz   = shift;
	if ($date !~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) { return ; }
	if ($1 == 0) { return ; }	# 無効な日付
	my $year = $1;
	my $mon  = $2;
	my $day  = $3;
	my $hour = $4;
	my $min  = $5;
	my $sec  = $6;
	return Time::Local::timegm($sec,$min,$hour,$day,$mon-1,$year);
}

1;
