use strict;
#------------------------------------------------------------------------------
# 記事のメール更新用モジュール
#						(C)2007 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
package SatsukiApp::adiary::Mail_post;
our $VERSION = '1.00';
#------------------------------------------------------------------------------
use Fcntl;	# for sysopen
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	my $self  = {};
	bless($self, $class);	# $self をこのクラスと関連付ける
	$self->{ROBJ}      = shift;
	$self->{list_file} = shift;
	$self->{auth_hours} = 2;
	return $self;
}

###############################################################################
# ■メインルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●メール更新のメイン
#------------------------------------------------------------------------------
sub main {
	my ($self) = @_;
	my $ROBJ = $self->{ROBJ};

	# pop モード
	if ($self->{pop_mode}) {
		return $self->output_html("mail/do_pop");
	}
	# pop モード以外で HTTP からの操作
	if (exists $ENV{REQUEST_METHOD}) {
		return $self->output_html("mail/not_pop_mode");
	}
	
	# メールを stdin から受け取る
	my $max_size = $self->{max_size} || 0x100000;	# 1MB default
	my $size = 0;
	my @ary;
	while(1) {
		my $x = <STDIN>;
		push(@ary, $x);
		$size += length($x);
		if ($x eq '' || $size > $max_size) { last; }
	}
	return $self->one_mail( \@ary );
}

#------------------------------------------------------------------------------
# ●skeleton の処理と出力
#------------------------------------------------------------------------------
sub output_html {
	my ($self, $skeleton) = @_;
	my $ROBJ = $self->{ROBJ};

	my $out = $ROBJ->call( $skeleton );
	$ROBJ->print_http_headers("text/html");
	$ROBJ->output_array($out);      # HTML出力
}

#------------------------------------------------------------------------------
# ●メールをpopして受信
#------------------------------------------------------------------------------
sub do_pop {
	my ($self) = @_;
	my $ROBJ = $self->{ROBJ};

	# ログファイル確認
	my $fh;
	my $file = $ROBJ->get_filepath( $self->{pop_log_file} );
	if (! sysopen($fh, $file, O_CREAT | O_WRONLY | O_APPEND) ) {
		$ROBJ->message("File can't open for lock '%s'", $file);
	}
	chmod($ROBJ->{File_mode}, $file);
	if (! $ROBJ->lock($fh, 6)) {	# LOCK_EX | LOCK_NB
		$ROBJ->message("Now mail checking");
		close($fh); return -1;
	}
	my $r = $self->_do_pop();
	# 結果の記録
	if ($r) {
		print $fh "$ROBJ->{Timestamp} pop fail (" . join('',@{$ROBJ->{Message}}) . ")\n";
	} else {
		print $fh "$ROBJ->{Timestamp} pop success ($self->{count} mails)\n";
	}
	close($fh);
	return $r;
}

sub _do_pop {
	my ($self) = @_;
	my $ROBJ = $self->{ROBJ};

	# POPモジュールの呼び出し
	eval { require Net::POP3;  };
	if ($@) { $ROBJ->message("Can't load 'Net::POP3' module."); return 1; }

	# サーバに接続
	my $pop = Net::POP3->new( $self->{pop_host}, Timeout => 10 );
	if (!$pop) { $ROBJ->message("Connection failed : $self->{pop_host}"); return 2; }

	# user / pass;
	my $r;
	if ($self->{pop_mode} eq 'apop') {
		$r = $pop->apop($self->{pop_user}, $self->{pop_pass});
	} else {
		$pop->user( $self->{pop_user} );
		$r = $pop->pass( $self->{pop_pass} );
	}
	if (!$r) { $ROBJ->message("User/Password error"); return 3; }

	# メール受信処理
	my $count = 0;
	my $list = $pop->list();
	my @keys = sort { $a <=> $b } keys(%$list);
	my $max_size = $self->{max_size} || 0x100000;	# 1MB default
	foreach(@keys) {
		my $size = $list->{$_};
		if ($size <= $max_size) {	# 大きすぎるメールは無視
			my $ary = $pop->get($_);
			# １つのメールを処理
			$self->one_mail( $ary );
			$count++;
		}
		# 受信メール削除
		$pop->delete($_);
	}
	$pop->quit();
	$self->{count} = $count;
	return 0;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●１通のメールを処理
#------------------------------------------------------------------------------
sub one_mail {
	my $self = shift;
	my $ary  = shift;
	my $ROBJ = $self->{ROBJ};
	my $Diary    = $ROBJ->{Diary};
	my $mail_obj = $ROBJ->loadpm('Satsuki::Base::Mail');
	if ($self->{debug}) { $mail_obj->{debug}=1; }

	# メールの解析
	my $mail = $mail_obj->parse_mail($ary);
	my $from = $mail->{from_address};
	my $text = $mail->{text} || $mail->{html};
	$text =~ s/\r\n/\n/g;
	$text =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]//g;
	if ($from eq '') { return 2; }

	# エラーメール？　ならば無視
	if ($from =~ /MAILER.*DAEMON/i) { return -1; }

	# 承認モード？
	my $auth_string = $ROBJ->message_translate('mail-auth');
	my $text2 = $text;
	$text2 =~ s/^(.*?)\n/$1/;	# 最初の１行
	$text2 =~ s/\s//g;		# 空白削除
	if (length($text)<32 && $text2 eq $auth_string) {	# 「メール承認」だけの本文
		if ($self->{debug}) { print "[Mail_post.pm] mail_address_auth ($from)\n"; }
		return $self->mail_address_auth($from);
	}

	# メール投稿動作
	my $force_post = $self->{force_post};
	my $regist_list = $ROBJ->fread_hash_cached($self->{list_file});
	my ($art_id, $poster) = split(':', $regist_list->{$from});	# 投稿先 記事帳
	my $DB = $ROBJ->{DB};
	if ($force_post) { $art_id = $force_post; }
	if ($art_id eq '' || !$DB->find_table("${art_id}_diary")) {
		my $msg = $ROBJ->message_translate('Not registered mail address : %s', $from);
		if ($self->{debug}) { print "[Mail_post.pm] $msg\n"; }
		$ROBJ->call("mail/send_error_message", $from, $msg);
		return 3;
	}
	if ($self->{debug}) { print "[Mail_post.pm] art_id = $art_id\n"; }

	# 書き込みパスワードの確認
	my $set  = $Diary->load_daybook_setting($art_id);
	my $pass = $set->{write_pass};
	if ($pass ne '') {
		$text =~ s/^(.*?)\n//s;		# 最初の行を削除
		if ($force_post eq '' && $1 ne $pass) {
			if ($self->{debug}) { print "[Mail_post.pm] write pass error. '$1' ne '$pass'\n"; }
			$ROBJ->call("mail/send_pass_error", $from);
			return 4;
		}
	}
	if ($poster ne '') {	# 書き込みのための権限付与
		$auth->force_auth($poster);
	}

	# 書き込み日付をメールヘッダから生成（pop_mode時のみ）
	my $date = $mail->{date};
	my %now  = %{ $ROBJ->{Now} };
	if ($self->{pop_mode} &&
	    $date =~ /\w\w\w, (\d\d?) (\w\w\w) (\d\d\d\d) (\d\d):(\d\d):(\d\d)(?: ([\+\-])(\d\d)(\d\d))?/) {
		my $mon = int(index('JanFebMarAprMayJunJulAugSepOctNovDec', $2)/3);
		$now{year}=$3; $now{mon}=$mon+1; $now{day}=$1;
		$now{hour}=$4; $now{min}=$5;     $now{sec}=$6;
		require Time::Local;
		my $gmt=Time::Local::timegm($6,$5,$4,$1,$mon,$3-1900);
		my $tz =($8*3600+$9*60)*($7 eq '+' ? 1:-1);
		$Diary->{tm} = $gmt - $tz;
	}

	# 添付画像の処理
	$Diary->set_and_select_blog( $blogid );
	my $uploader = $ROBJ->{Uploader};
	my $attaches  = $mail->{attaches} || [];
	if (defined $uploader && @$attaches) {
		$ROBJ->{Pinfo} = [sprintf("%04d%02d", $now{year}, $now{mon} )];
		$uploader->initalize( $blogid );		# 必ず Pinfo の後
		$uploader->make_currentfolder();
		# 添付画像処理
		my $allow_ex = $uploader->{allow_ex};
		my @inserts;
		foreach(@$attaches) {
			if ($_->{content_type} !~ /image/) { next; }
			my $filename = $_->{filename};
			$filename =~ tr|\\|/|;
			if ($filename =~ /\/([^\/]*)$/) { $filename = $1; }
			$filename =~ s/[\r\n\x00\"]//g;
			# 拡張子チェック
			my $ext;
			my $image_ex = $self->{image_files};
			if ($filename =~ /\.(\w+)$/) { $ext=$1; }
			$ext =~ tr/A-Z/a-z/;
			if (! grep { $ext eq $_ } @$image_ex ) { next; }
			# ファイル名の書き換え？
			if ($set->{mail_file_rename}) {
				$filename = sprintf("%04d%02d%02d-%02d%02d%02d_%d",
							$now{year}, $now{mon}, $now{day},
							$now{hour}, $now{min}, $now{sec}, $#inserts+2) . ".$ext";
				if ($self->{debug}) { print "[Mail_post.pm] write filename : $filename\n"; }
			}
			# アップロードする
			my %file;
			$file{data} = $_->{data};
			$file{file_name} = $filename;
			$file{file_size} = length($_->{data});
			my %ret;
			my $r = $uploader->do_upload( \%file, \%ret );
			if ($self->{debug}) { print "[Mail_post.pm] upload $filename (ret:$r)\n"; }
			if (! $r) {
				push(@inserts, $ret{tag});
			} elsif ($r==10) {
				# 同名ファイルがある場合強制リネームする
				$filename = sprintf("%04d%02d%02d-%02d%02d%02d_%d",
							$now{year}, $now{mon}, $now{day},
							$now{hour}, $now{min}, $now{sec}, $#inserts+1) . ".$ext";
				if ($self->{debug}) { print "[Mail_post.pm] samefile, rename : $filename\n"; }
				$file{file_name} = $filename;
				$r = $uploader->do_upload( \%file, \%ret );
				if ($self->{debug}) { print "[Mail_post.pm] upload $filename (ret:$r)\n"; }
				if (! $r) {
					push(@inserts, $ret{tag});
				} else {
					push(@inserts, "<!-- 同じ名前のファイルがあります : $filename -->");
				}
			}
		}
		# 画像挿入
		my $image_string = $ROBJ->message_translate('image-insert');
		$text =~ s/$image_string/ pop(@inserts) /eg;
		if (@inserts) {
			my $tags =  join(' ', @inserts) . "\n";
			if ($set->{mail_image_under}) {
				if (substr($text, -1) ne '\n') { $tags="\n$tags"; }
				$text .= $tags;
			} else {
				$text = $tags . $text;
			}
		}
	}
	if ($self->{debug}) { print "[Mail_post.pm] text = $text\n"; }

	# 書き込み準備
	if (exists $mail->{x_mailer}) {
		$ENV{HTTP_USER_AGENT} = $mail->{x_mailer};
		$ROBJ->tag_escape( $ENV{HTTP_USER_AGENT} );
	}
	if (!defined $Diary->{myself}) {
		$Diary->{myself} = $Diary->{myself2} = $Diary->get_blog_url( $blogid );
		if ($Diary->{subdomain_mode} eq '') { $Diary->{server_url} = $ROBJ->{Server_url}; }
	}
	
	$Diary->{phone_mode}  = 1;
	my %form;
	$form{title}    = $mail->{subject};
	$form{category} = $set->{phone_dafault_category};
	$form{parser}   = $set->{phone_parser} || $set->{parser};
	foreach(keys(%form)) {
		$form{$_} =~ s/[\x00-\x08\x0a-\x1f\x7f]//g
	}
	$form{body_txt} = $text;
	# 書き込みステータス（フラグ）
	my $set = $Diary->{blog_setting};
	foreach(qw(enable allow_com allow_hcom allow_tb disp_ref)) {
		if (!exists $form{$_}) { $form{$_}=$set->{$_}; }	# default
	}
	# 書き込み処理
	my $r = $Diary->art_edit( \%form, "force_write", 1);	# 1=force write flag
	if ($r) {	# 失敗
		$ROBJ->call("mail/send_error_message", $from, "art_write() error : $r");
		return $r;
	}
	# 成功通知
	if ($set->{mail_send_success}) {
		$ROBJ->call("mail/send_post_success", $from);
	}
	return 0;
}


###############################################################################
# ■メール更新の設定
###############################################################################
#------------------------------------------------------------------------------
# ●メール更新用のアドレスの設定
#------------------------------------------------------------------------------
sub get_mail_address_list {
	my ($self, $blogid, $list_file) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file = $self->{list_file};

	$blogid =~ s/\W//g;
	if ($blogid eq '') { return []; }

	# リストからメールアドレスを探す
	my $h = $ROBJ->fread_hash_no_error($file);
	my @list;
	foreach(keys(%$h)) {
		if ($h->{$_} ne $blogid) { next; }
		my ($address, $tm) = split('#', $_);
		if ($tm && $tm < $ROBJ->{TM}) { next; }		# 期限切れ
		push(@list, {address => $address, tm => $tm});
	}
	return \@list;

}

#------------------------------------------------------------------------------
# ●メール更新用のアドレスの登録・削除
#------------------------------------------------------------------------------
sub mail_address_edit {
	my ($self, $blogid, $regist_address, $delete_list) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file = $self->{list_file};

	$blogid =~ s/\W//g;
	if ($blogid eq '') { return 1; }
	if ($file eq '') { return -1; }

	# メールアドレス確認、前処理
	$regist_address =~ s/\s//g;
	if ($regist_address ne '' && $regist_address !~ /^[\w\-\.]+\@(?:[\w\-]+\.)+[\w\-]+$/) {
		$ROBJ->message("Mail address format error (%s)", $regist_address);
		$regist_address = undef;
	}
	my %del_hash;
	map { $del_hash{$_}=1 } @$delete_list;

	# ファイル編集処理
	my $regist = 0;
	my $delete = 0;
	my ($fh, $h) = $ROBJ->fedit_readhash($file);
	foreach(keys(%$h)) {
		my ($address, $tm) = split('#', $_);
		# 期限切れの削除
		if ($tm && $tm < $ROBJ->{TM}) {
			delete $h->{$_};
			next;
		}
		if ($h->{$_} ne $blogid) { next; }
		# 登録済？
		if (!$tm && $address eq $regist_address) {
			$ROBJ->message("Mail address already registed (%s)", $regist_address);
			$regist_address=undef;
		}
		# 削除
		if ($del_hash{$address} || $address eq $regist_address) {
			delete $h->{$_};
			$delete++;
		}
	}
	# 追加
	if ($regist_address ne '') {
		my $tm = $ROBJ->{TM} + $self->{auth_hours}*3600;
		$h->{"$regist_address#$tm"} = $blogid;
		$regist = 1;
		# 確認用メールの送信
		$ROBJ->call('mail/send_regist_check', $blogid, $regist_address);
	}
	$ROBJ->fedit_writehash($file, $fh, $h);
	# 戻り値
	$self->{regist} = $regist;
	$self->{delete} = $delete;
	return 0;
}

#------------------------------------------------------------------------------
# ●メール更新用のアドレスの承認
#------------------------------------------------------------------------------
sub mail_address_auth {
	my ($self, $auth_address) = @_;
	my $ROBJ = $self->{ROBJ};
	my $file = $self->{list_file};

	# ファイル編集処理
	my $blogid;
	my ($fh, $h) = $ROBJ->fedit_readhash($file);
	my %authed;
	foreach(keys(%$h)) {
		my ($address, $tm) = split('#', $_);
		if ($address eq $auth_address) {
			if ($tm > $ROBJ->{TM}) {
				$blogid = $h->{$_};
				$authed{$address} = $blogid;	# 正式登録
			}
			delete $h->{$_};		# 仮登録の削除
		}
	}
	$ROBJ->into($h, \%authed);	# %$h に %authed の内容copy
	
	# 結果を保存せず終了
	if ($blogid eq '') {
		$ROBJ->fedit_exit($file, $fh);
		$ROBJ->call('mail/send_regist_check_error', $auth_address);
		return 1;
	}
	# 承認成功
	$ROBJ->fedit_writehash($file, $fh, $h);
	# 登録通知メールの送信
	$ROBJ->call('mail/send_registed', $blogid, $auth_address);
	return 0;
}

1;
