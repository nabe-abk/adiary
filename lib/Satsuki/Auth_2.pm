use strict;
#------------------------------------------------------------------------------
# ユーザー認証・管理モジュール
#						(C)2009 nabe / nabe@abk.nu
#------------------------------------------------------------------------------
use Satsuki::Auth ();
package Satsuki::Auth;
my $_SALT = 'eTUMs6mRN8vqiSCHWaOGwynJKFbBpdA29txZEDcYluVgr75hLPQXfIk/j4o3z.10';
###############################################################################
# ■認証ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ログイン
#------------------------------------------------------------------------------
sub login {
	my $self = shift;
	my $id   = shift;
	my $pass = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	$self->userdb_init();

	# IP/HOST制限
	if (! $ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) {
		return { ret=>1, msg=>'security error' };
	}

	# 無条件認証
	if (! $self->{exists_admin} && $self->{start_up}) {
		$self->{ok}    = 1;
		$self->{pkey}  = -1;
		$self->{id}    = "root*";
		$self->{name}  = "root*";
		$self->{email} = '';
		$self->{auto}  = 1;
		$self->{isadmin} = 1;	# 管理者権限
		$self->{isroot}  = 1;
		$self->log_save('root*', 'login');
		return { ret=>0, sid=>'auth (no exist user)' };
	}

	# ID確認
	my $table = $self->{table};
	my $udata;
	if ($id ne '' && $self->{uid_alt_col} ne '') {
		# idではないカラムをid代わりに利用する
		$udata = $DB->select_match_limit1($table, $self->{uid_alt_col}, $id);
	}
	if (!$udata) {
		$udata = $DB->select_match_limit1($table, 'id', $id);
	}
	if (!$udata || !%$udata) {	# uid が存在しない
		$self->log_save_fail($id, 'login');
		return { ret=>10, msg => $ROBJ->translate('Username or password incorrect') };
	}
	$id = $udata->{id};

	# 失敗カウントを参照
	# 一定時間経過したら、失敗カウンタを 0 に初期化
	my $fails = $udata->{fail_c};
	if ($udata->{fail_tm} + $self->{fail_minute}*60 < $ROBJ->{TM}) { $fails=0; }
	if ($fails > $self->{fail_count}) {
		return { ret=>11, msg => $ROBJ->translate('Too many failed. Please retry in %d minutes', $self->{fail_minute}) };
	}
	if (!$self->check_pass($udata->{pass}, $pass)) {
		$fails++;
		$DB->update_match($table, {fail_c => $fails, fail_tm => $ROBJ->{TM}}, 'id', $id);
		$self->log_save_fail($id, 'login');
		return { ret=>10, msg => $ROBJ->translate('Username or password incorrect') };
	}
	if ($udata->{disable}) {
		$self->log_save_fail($id, 'login');
		return { ret=>20, msg => $ROBJ->translate('This account is disable') };
	}

	# 既にログイン済の場合、ログアウト
	if ($self->{id}) {
		$self->logout();
	}

	# ログイン成功
	$self->set_logininfo($udata);

	# 同一IDの古いログインセッションを削除
	my @del_pkeys;
	my $sessions = $DB->select_match($table.'_sid', 'id', $id);
	if ($#$sessions >= $self->{sessions}-1) {	# セッションが多い
		# 降順ソート
		$sessions = [ sort {$b->{login_tm} <=> $a->{login_tm}} @$sessions ];
		my $max = $self->{max_sessions}-1;	# 最大ログイン数
		if ($max<0) { $max=0; }			# safety logic
		while($#$sessions >= $max) {
			my $x = pop(@$sessions);
			push(@del_pkeys, $x->{pkey});
		}
		if (@del_pkeys) {
			$DB->delete_match($table.'_sid', 'pkey', \@del_pkeys);
		}
	}

	# セッションIDの生成と保存
	my $sid = $self->generate_SessionID();
	$DB->insert("${table}_sid", {
		id       => $id,
		sid      => $sid,
		login_tm => $ROBJ->{TM},
	});
	# ログイン回数加算
	my $login_c = ++$self->{ext}->{login_c};
	$DB->update_match($table, { login_c=>$login_c, login_tm=>$ROBJ->{TM} }, 'id', $id);

	# ログ保存
	$self->log_save($id, 'login');
	return { ret=>0, sid=>$sid };
}

#------------------------------------------------------------------------------
# ●セッションの認証
#------------------------------------------------------------------------------
sub session_auth {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# IP/HOST制限
	if (! $ROBJ->check_ip_host($self->{allow_ip}, $self->{allow_host})) { return ; }

	# 認証処理
	my $r = $self->do_session_auth(@_);
	if ($r) { return $r; }

	# 失敗したとき
	$self->userdb_init();

	# ユーザー未登録時に自動認証？
	if (! $self->{exists_admin} && $self->{start_up}) {	# 無条件認証
		$self->{ok}    = 1;
		$self->{pkey}  = -1;
		$self->{id}    = "root*";
		$self->{name}  = "root*";
		$self->{auto}  = 1;
		$self->{isadmin} = 1;	# 管理者権限
		$self->{isroot}  = 1;
		return 2;
	}
	return $r;
}

sub do_session_auth {
	my ($self, $id, $session_id, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	$opt ||= {};

	if ($id eq 'root*') { return; }
	if ($id eq '' || $session_id eq '') { return; }

	# セッションの認証
	if (!$opt->{force_auth}) {
		$DB->set_noerror(1);
		my $session = $DB->select_match_limit1($self->{table}.'_sid', 'id', $id, 'sid', $session_id);
		$DB->set_noerror(0);
		if (! $session) { return; }

		my $expires = $self->{expires};
		if (0<$expires && $session->{login_tm} + $expires < $ROBJ->{TM}) {	# 期限切れ
			$DB->delete_match($self->{table}.'_sid', 'pkey', $session->{pkey});
			return;
		}
	}

	# user data load
	my $auth = $DB->select_match_limit1($self->{table}, 'id', $id);
	$self->set_logininfo($auth);

	# 認証失敗
	if ($auth->{disable}) {
		$ROBJ->message('This account is disable');
		return ;
	}

	# ログイン成功
	$self->{_sid} = $session_id;		# ログアウトで使用
	return 1;
}

#------------------------------------------------------------------------------
# ●IDを指定してログイン認証処理
#------------------------------------------------------------------------------
sub force_auth {
	my ($self, $id) = @_;
	return $self->session_auth($id, '', {force_auth => 1});
}

#------------------------------------------------------------------------------
# ●ログアウト
#------------------------------------------------------------------------------
sub logout {
	my ($self) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $id   = $self->{id};

	# ログアウト
	undef $self->{ok};
	undef $self->{pkey};
	undef $self->{id};
	undef $self->{name};
	undef $self->{isadmin};
	undef $self->{isroot};
	undef $self->{ext};

	# セッション情報の消去
	my $table = $self->{table} . '_sid';
	if ($self->{all_logout} || $self->{max_sessions} < 2) {
		$DB->delete_match($table, 'id', $id);
	} else {
		$DB->delete_match($table, 'id', $id, 'sid', $self->{_sid});
	}

	# ログ
	$self->log_save($id, 'logout');
	return ;
}

###############################################################################
# ■サービスルーチン
###############################################################################
#-------------------------------------------------------------------------------
# ●ユーザーの情報取得
#-------------------------------------------------------------------------------
sub get_userinfo {
	my ($self, $id, $col) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{ok}) { $ROBJ->message('Operation not permitted'); return undef; }

	if (! $self->{isadmin}) {
		$id  = $self->{id};
		$col = 'id';
	}
	if ($col eq '' || $col eq 'pass') {
		$col = 'id';
	}

	my $h = $DB->select_match_limit1($self->{table}, $col, $id);
	if ($h && %$h) {
		delete $h->{pass};
	}
	return $h;
}

#-------------------------------------------------------------------------------
# ●ユーザーの確認
#-------------------------------------------------------------------------------
sub get_uid {
	my ($self, $id, $col) = @_;
	if (!grep {$col eq $_} @{ $self->load_extcols() }) {
		$col='id';
	}
	my $DB = $self->{DB};
	my $h = $DB->select_match_limit1($self->{table}, $col, $id);
	return ($id ne '' && $h) ? $h->{id} : undef;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ログイン情報を内部変数に設定する
#------------------------------------------------------------------------------
sub set_logininfo {
	my $self = shift;
	my $user = shift;
	my $ROBJ = $self->{ROBJ};
	my $id = $user->{id};

	# ログイン成功
	$self->{ok}    = 1;
	$self->{pkey}  = $user->{pkey};
	$self->{id}    = $id;
	$self->{name}  = $user->{name};
	$self->{email} = $user->{email};
	$self->{isadmin} = $user->{isadmin};	# 管理者権限
	$self->{isroot}  = 0;
	
	# ユーザー拡張カラムロード
	foreach(@{$self->load_extcols()},'login_c','login_tm','fail_c','fail_tm') {
		$self->{ext}->{$_} = $user->{$_};
	}

	if (!$self->{isadmin}) { return; }

	# IP/HOST制限
	if (! $ROBJ->check_ip_host($self->{admin_allow_ip}, $self->{admin_allow_host})) {
		$self->{isadmin} = 0;
	}

	# セキュリティ拡張
	if ($self->{root_list} && $self->{root_list}->{$id}) {
		$self->{isroot}  = 1;

	} elsif ($self->{admin_list} && ! $self->{admin_list}->{ $id }) {
		$self->{isadmin} = 0;
	}
}

#------------------------------------------------------------------------------
# ●ユーザーデータベースの初期化
#------------------------------------------------------------------------------
sub userdb_init {
	my $self = shift;
	if (0 <= $self->{exists_admin}) { return $self->{exists_admin}; }
	my $DB = $self->{DB};

	# 管理者の存在確認
	$DB->set_noerror(1);
	my $h = $DB->select_match_limit1( $self->{table}, 'isadmin', 1, 'disable', 0, '*NoError', 1, '*cols', 'pkey' );
	$DB->set_noerror(0);

	# テーブルの確認
	if (!$h && !$DB->find_table( $self->{table} )) {
		$self->create_user_table();
	}
	return ($self->{exists_admin} = $h ? 1 : 0);
}

#------------------------------------------------------------------------------
# ●DBにログの記録
#------------------------------------------------------------------------------
sub log_save_fail {
	&log_save($_[0], $_[1], $_[2], 'fail')
}
sub log_save {
	my $self = shift;
	if ($self->{log_func}) {
		&{ $self->{log_func} }(@_);
	}
	if ($self->{log_stop}) { return; }

	my $id   = shift;
	my $type = shift;
	my $msg  = shift;
	my $DB   = $self->{DB};
	my $ROBJ = $self->{ROBJ};

	my $h = {id => $id, type => $type, msg => $msg};
	$h->{agent} = $ENV{HTTP_USER_AGENT};
	$h->{ip}    = $ENV{REMOTE_ADDR};
	$h->{host}  = $ENV{REMOTE_HOST};
	$h->{tm}    = $ROBJ->{TM};

	foreach(keys(%$h)) {
		$h->{$_} = substr($h->{$_}, 0, $self->{logtext_max});
		$ROBJ->tag_escape( $h->{$_} );
	}

	$DB->insert($self->{table} . '_log', $h);
}

#------------------------------------------------------------------------------
# ●セッションIDを生成する
#------------------------------------------------------------------------------
sub generate_SessionID {
	my $self = shift;
	my $sid;
	my $salt = $self->{ROBJ}->{SALT64chars} || $_SALT;
	my $base = $ENV{UNIQUE_ID} . $ENV{REMOTE_ADDR};
	my $sid  = $self->{ROBJ}->make_secure_id($base, int(rand(8192)), 8);
	for(my $i=0; $i<12; $i++) {
		$sid .= substr($salt, int(rand(256+ord(substr($base,$i,1))*256) % 64), 1);
	}
	$sid =~ tr|/|-|;	# 携帯電話用hack
	return $sid;
}

#------------------------------------------------------------------------------
# ●パスワードを認証する
#------------------------------------------------------------------------------
sub check_pass {
	my ($self, $crypted, $plain) = @_;
	if (crypt($plain, $crypted) eq $crypted) { return 1; }	# auth
	return 0;
}

#------------------------------------------------------------------------------
# ●ユーザーカラム名をロードする
#------------------------------------------------------------------------------
sub load_extcols {
	my $self = shift;
	return [ map {$_->{name}} @{ $self->{extcol} } ];
}

1;
