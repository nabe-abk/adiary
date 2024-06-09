use strict;
#-------------------------------------------------------------------------------
# ブログシステム - adiary
#						(C)2006-2024 nabe@abk
#-------------------------------------------------------------------------------
package SatsukiApp::adiary;
use Satsuki::AutoLoader;
use Fcntl;
#-------------------------------------------------------------------------------
our $VERSION    = 3.50;
our $OUTVERSION = "3.50p";
our $DATA_VERSION = 3.50;
################################################################################
# ■システム内部イベント
################################################################################
my %SysEvt;
$SysEvt{ARTICLE_FIRST_VISIBLE_PING} = [qw(
	send_update_ping
)];
$SysEvt{ARTICLE_STATE_CHANGE} = [qw(
	update_bloginfo_article
	update_taglist
	update_contents_list
)];
$SysEvt{COMMENT_STATE_CHANGE} = [qw(
	update_bloginfo_comment
)];
$SysEvt{ARTCOM_STATE_CHANGE} = [qw(
	generate_rss
)];
$SysEvt{'ARTCOM_STATE_CHANGE#after'} = [qw(
	generate_spmenu
)];
$SysEvt{EDIT_DESIGN} = [qw(
	save_spmenu_all_items
	check_spmenu_items
	generate_spmenu
)];

################################################################################
# ●コンストラクタ
################################################################################
sub new {
	my ($class, $ROBJ, $DB, $self) = @_;
	if (ref($self) ne 'HASH') { $self={}; }
	bless($self, $class);
	$self->{__FINISH} = 1;

	$self->{ROBJ}    = $ROBJ;
	$self->{DB}      = $DB;
	$self->{VERSION} = $VERSION;
	$self->{OUTVERSION} = $OUTVERSION;

	# ディフォルト値の設定
	$self->SetDefaultValue();
	$self->{_loaded_bset} = {};
	$self->{http_agent} = "adiary $OUTVERSION on Satsuki-system $ROBJ->{VERSION}";

	# 現在の日時設定（日付変更時間対策）
	$self->{now} = $ROBJ->{Now};

	# スマホ判別
	$self->{sphone} = $self->sphone_checker();

	# Cache環境向け Timer のロード
	if ($ROBJ->{CGI_cache} && $ENV{SatsukiTimer} ne '0' && !$Satsuki::Timer::VERSION) {
		require Satsuki::Timer;
	}

	return $self;
}

#-------------------------------------------------------------------------------
# ●スマホ判別
#-------------------------------------------------------------------------------
sub sphone_checker {
	my $ua = $ENV{HTTP_USER_AGENT};
	return 0<index($ua,'Android') || 0<index($ua,'iPhone') || 0<index($ua,'iPad');
}

#-------------------------------------------------------------------------------
# ●ディフォルト値の設定
#-------------------------------------------------------------------------------
sub SetDefaultValue {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my %h = (
blog_cache_unit  => 100,	# ブログ記事キャッシュ保存時の分割単位
dir_postfix_len  => 8,
theme_skeleton_level => 10,
user_skeleton_level  => 20,
sphone_skeleton_level => 100,
default_tag_priority => 100000,
default_wiki_priority=> 100000,
bloglist_table  => '_bloglist',	# DBのブログ管理テーブル
top_skeleton	=> '_top',
main_skeleton	=> '_main',
article_skeleton=> '_article',
frame_skeleton	=> '_frame'
	);
	foreach(keys(%h)) {
		$self->{$_} = $h{$_};
	}
}

################################################################################
# ●デストラクタ
################################################################################
sub FINISH {
	my $self = shift;
	$self->save_blogset_sys();
	$self->save_sysdat();
}

################################################################################
# ■メイン処理
################################################################################
sub main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# システム情報のロード
	my $sys = $self->load_sysdat();

	# Cookieログイン処理
	$self->authorization();

	# ServerURLのセキィリティを確保
	$self->secure_http_host();

	# pinfoとブログの選択。テーマ選択
	my $blogid = $self->blogid_and_pinfo();

	# キャッシュの処理
	if ($ROBJ->{CGI_cache} && $sys->{html_cache}) {
		$self->regist_cache_checker();
	}

	# Query/Form処理  ※テーマ選択より後に処理
	$self->read_query_form();

	# スマホ向け処理
	if ($self->{sphone}) { $self->init_for_sphone(); }

	# 表示スケルトン選択
	$self->select_skeleton( $ROBJ->{Query}->{_} || $self->{query0} );

	#-------------------------------------------------------------
	# POST action判定
	#-------------------------------------------------------------
	my $action = $ROBJ->{POST} && $ROBJ->{Form}->{action};

	if ($action ne '_ajax_login') {
		# 表示パスワードチェック
		if ($self->{view_pass}) { $self->check_view_pass(); }

		# メンテナンスモード
		if ($sys->{mainte_mode} || $self->{require_update}) { $self->mainte_mode(); }
	}

	#-------------------------------------------------------------
	# POST actionの呼び出し
	#-------------------------------------------------------------
	if ($action) {
		if ($action =~ /^_ajax_\w+$/) {
			my $data = $self->ajax_function( $action );

			# Append debug message
			if ($ROBJ->{Develop} && ref($data) eq 'HASH') {
				$data->{_develop} = 1;
				if (my $err = ($ROBJ->clear_error() . join("\n", @{$ROBJ->{Message}}, @{$ROBJ->{Debug}}))) {
					$data->{_debug} = $err;
				}
			}
			$self->{action_data} = $ROBJ->generate_json( $data );

		} elsif (my ($dir,$file) = $self->parse_skel($action)) {
			local($self->{skel_dir}) = $dir;
			$self->{action_data} = $ROBJ->call( "${dir}_action/$file" );

			# キャッシュのクリア
			if ($ROBJ->{Auth}->{ok} || $ROBJ->{action_return} eq '0') {
				$self->clear_cache();
			}
		}
	}

	#-------------------------------------------------------------
	# スケルトン呼び出し（出力）
	#-------------------------------------------------------------
	$self->output_html();
}

################################################################################
# ■メイン処理ルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●Cookie と Authorization 処理
#-------------------------------------------------------------------------------
sub authorization {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	my $cookie = $ROBJ->get_cookie();
	my $session = $cookie->{session};
	if (ref $session eq 'HASH') {	# ログインセッション処理
		$auth->session_auth($session->{id}, $session->{sid});
	}
	# 管理者 trust mode 設定
	if ($self->{admin_trust_mode} && $auth->{isadmin}) {
		$self->{trust_mode} = 1;
	}
}

#-------------------------------------------------------------------------------
# ●HTTP_HOST インジェクション対策
#-------------------------------------------------------------------------------
sub secure_http_host {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	if ($self->{subdomain_mode}) { return; }

	my $srv  = $ROBJ->{ServerURL};
	my $save = $self->{sys}->{ServerURL};

	if (!$ROBJ->{Auth}->{isadmin}) {
		$ROBJ->{ServerURL} = $save || $srv;
	} elsif ($srv ne $save) {
		# 管理者ログイン時の ServerURL を保存しておく
		$self->update_sysdat('ServerURL', $srv);
	}
}

#-------------------------------------------------------------------------------
# ●pinfoとブログ選択処理
#-------------------------------------------------------------------------------
sub blogid_and_pinfo {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $myself  = $ROBJ->{myself};
	my $myself2 = $ROBJ->{myself2};
	my @pinfo   = @{ $ROBJ->read_path_info() };	# PATH_INFO

	# URLなど基本設定
	my $authid  = $ROBJ->{Auth}->{id};
	my $pinfoid = exists($pinfo[1]) ? $pinfo[0] : ''; # 'bloid/'のように'/'付のみ有効
	my $blogid;
	my $default = $self->{sys}->{default_blogid};
	if ($pinfoid !~ /^[a-z][a-z0-9_]*$/) { $pinfoid=''; }	# blogid format check

	if ($default) {
		#-------------------------------------------
		# デフォルトブログモード
		#-------------------------------------------
		if ($pinfoid ne $default && $self->find_blog($pinfoid) && $self->set_and_select_blog($pinfoid)) {
			shift(@pinfo);
			$blogid = $pinfoid;
		} else {
			$blogid = $default;
		}
		# 自分のブログ
		$self->{myself3} = ($authid eq $default) ? $myself : "$myself2$authid/";

	} elsif ($self->{subdomain_mode}) {
		#-------------------------------------------
		# サブドメインモード
		#-------------------------------------------
		my $host_name = $ENV{SERVER_NAME};
		$host_name =~ s/[^\w\.\-]//g;
		my $domain = $self->{subdomain_mode};
		if (! $self->{subdomain_secure}) {	# Cookieを全ドメインで共通化
			$ROBJ->{CookieDomain} = $domain;
		}
		$self->{subdomain_proto} ||= 'http://';

		if ((my $x = index($host_name, ".$domain")) > 0) {
			$blogid = substr($host_name, 0, $x);
		} else {
			$blogid = shift(@pinfo);
			$blogid =~ s/\W//g;
			if ($blogid ne '') {
				$ROBJ->redirect("//$blogid.$domain/" . join('/', @pinfo));
			}
		}
		$self->{myself3} = "//$authid.$domain/";	# 自分のブログ
	} else {
		#-------------------------------------------
		# マルチユーザーモード
		#-------------------------------------------
		shift(@pinfo);
		$blogid = $pinfoid;
		my $add_myself3;
		if ($default ne $authid) { $add_myself3 = "$authid/"; }
		$self->{myself3} = $myself2 . $add_myself3;	# 自分のブログ
	}
	# 未設定ならブログを選択 ※$blogidが未設定でも選択すること
	if (!$self->{blog}) { $self->set_and_select_blog( $blogid ); }

	# テーマの設定
	my $theme = $self->{blog}->{theme};
	if (!$theme || $self->load_theme($theme)) {
		$self->load_theme( $self->{default_theme} );
	}

	# pinfoの保存
	my $pinfo = join('/', @pinfo);
	$self->{pinfo}   = $pinfo;
	$self->link_key_encode( $pinfo );
	$self->{e_pinfo} = $pinfo;
	$self->{thisurl} = $pinfo eq '' ? $self->{myself} : ($self->{myself2} . $pinfo);

	#-------------------------------------------------------------
	# ブログの存在確認
	#-------------------------------------------------------------
	if ($authid && $self->find_blog($authid) ) {
		$self->{exists_my_blog} = 1;
	}
	if ($blogid ne '') {	# ブログIDの指定あり
		$self->{path_blogid} = $blogid;
		$self->{others_blog} = ($blogid ne $authid) ? 1 : 0;
	}
}

#-------------------------------------------------------------------------------
# ●Query/Form処理
#-------------------------------------------------------------------------------
sub read_query_form {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$ROBJ->read_form();
	my $query = $ENV{QUERY_STRING};
	my $q = $ROBJ->read_query({'t'=>1});
	delete $q->{''};

	# 特殊Queryの処理
	foreach(qw(_sphone _theme)) {
		if (!$q->{$_}) { next; }
		my $v = $q->{$_};
		$v =~ s|[^\w\-/]||g;

		if ($_ eq '_sphone') {		# スマホ表示
			$self->{sphone}=$v;
		} elsif ($_ eq '_theme') {	# テーマ指定
			$self->load_theme( $v );
		}
		$ROBJ->{no_robots}=1;
		$self->{sp_query} .= "&$_=$v";
		delete $q->{$_};
	}

	# スケルトン指定解釈
	if (%$q) {
		$self->{query} = $query;
		$query =~ m|^([\w\.\-/=]*)|;
		my $q0 = $self->{query0} = index($1,'=')<0 ? $1 : '';	# 検索Queryをスケルトン指定と誤解しないため
		if ($q0 ne '') { delete $q->{$q0}; }
	}
}

#-------------------------------------------------------------------------------
# ●スマホ向け処理
#-------------------------------------------------------------------------------
sub init_for_sphone {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->{theme_dir} . '_sphone/_skel/';
	$ROBJ->regist_skeleton($dir, $self->{sphone_skeleton_level});

	# スマホ用初期化ルーチンを呼ぶ
	$ROBJ->call( '_init_sphone' );
}

#-------------------------------------------------------------------------------
# ●スケルトン選択（theme.htmlからも呼び出される）
#-------------------------------------------------------------------------------
sub select_skeleton {
	my $self = shift;
	my ($dir,$file) = $self->parse_skel( @_ );
	my $skel = "$dir$file";
	my $ROBJ = $self->{ROBJ};

	# スケルトンの存在確認
	if ($skel ne '' && !$ROBJ->check_skeleton($skel)) {
		$ROBJ->redirect( $self->{myself} );
	}
	$self->{skeleton}  = $skel || $self->select_default_skeleton(  );
	$self->{skel_dir}  = $dir;
	$self->{skel_name} = $file;
}

sub select_default_skeleton {
	my $self = shift;
	my $mode = shift || $self->{pinfo};
	my $blog = $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (!$ROBJ->{POST} && $blog->{album_mode}) {
		$ROBJ->redirect( $self->{myself} . '?album/' );
	} elsif ($mode eq '' && !$self->{path_blogid}) {
		return $self->{top_skeleton};
	} elsif ($mode ne '' && $mode !~ /^[1-9]\d+$/ || $mode eq '' && $self->{query} eq '' && $blog->{frontpage}) {
		return ($self->{view_event} = $self->{article_skeleton});
	}
	return ($self->{view_event} = $self->{main_skeleton});
}

#-------------------------------------------------------------------------------
# ●HTMLの生成と出力
#-------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# HTML生成
	my $out;
	if ($self->{action_is_main}) {
		$out = $self->{action_data};
	} else {
		$out = $ROBJ->call( $self->{skeleton} );
	}

	# view event?
	my $view = $self->{view_event};	# _article, _main
	if ($view) {
		$view =~ tr/a-z/A-Z/;
		if ($self->{blog}->{"event:VIEW$view"}) {
			$self->{post_html} = $ROBJ->call( '_view' . $self->{view_event} );
		}
	}

	# mainフレームあり？
	my $frame_name = $self->{frame_skeleton};
	if ($frame_name ne '') {
		# 外フレームを処理する
		$out = $ROBJ->call($frame_name, $out);
	}

	if (!$self->{output_stop}) {
		$ROBJ->output($out);
	}
}

################################################################################
# ■ブログの存在確認と設定ロード
################################################################################
#-------------------------------------------------------------------------------
# ●ブログの存在確認	※キュッシュ仕様を変更したら blog_create/blog_drop も変更すること!!
#-------------------------------------------------------------------------------
sub find_blog {
	my $self = shift;
	my $blogid = shift;
	if ($blogid =~ /\W/) { return ; }

	if(exists $self->{_cache_find_blog}->{$blogid}) {
		return $self->{_cache_find_blog}->{$blogid};
	}
	return ($self->{_cache_find_blog}->{$blogid} = $self->{DB}->find_table("${blogid}_art"));
}

#-------------------------------------------------------------------------------
# ●ブログの設定ロード
#-------------------------------------------------------------------------------
# ※書き換えは瞬時に反映され、$blog->{_update}=1 ならばプログラム終了時に保存される。
sub load_blogset {
	my ($self, $blogid) = @_;	# * = default
	my $ROBJ = $self->{ROBJ};
	if ($self->{'_loaded_bset'}->{$blogid}) { return $self->{'_loaded_bset'}->{$blogid}; }
	if ($blogid ne '*' && !$self->find_blog($blogid)) { return undef; }

	my $file = $self->blog_dir($blogid) . 'setting.dat';
	if ($blogid eq '*' || !-e $file) {
		$file = $self->{my_default_setting_file};
		if (!-e $file) {
			$file = $self->{default_setting_file};
		}
	}

	# 設定のロード
	my $blog = $ROBJ->fread_hash_cached($file);
	if (%$blog) {
		$blog->{blogid} = $blogid;
		$self->{_loaded_bset}->{$blogid} = $blog;
	}
	return $blog;
}

#-------------------------------------------------------------------------------
# ●ブログの権限と初期設定
#-------------------------------------------------------------------------------
# ブログを選択し、内部変数に権限を設定する。
# ブログがみつからないか閲覧できないときは undef が返る
sub set_and_select_blog_force {
	my ($self, $blogid) = @_;
	$self->set_and_select_blog($blogid, 1);
}
sub set_and_select_blog {
	my ($self, $blogid, $force) = @_;
	my $ROBJ = $self->{ROBJ};
	if (!$force && $blogid ne '' && $self->{blogid} eq $blogid) { return $self->{blog}; }

	# myself設定
	$self->{myself}     = $ROBJ->{myself};
	$self->{myself2}    = $ROBJ->{myself2};

	# 内部変数初期化
	$self->{blogid} = undef;
	$self->{blog}   = undef;
	$self->{allow_edit} = undef;
	$self->{allow_com}  = undef;
	$self->{blog_admin} = undef;
	$self->{blog_dir}    = undef;
	$self->{blogpub_dir} = undef;
	$ROBJ->{Change_hour} = 0;
	$self->{now} = $ROBJ->{Now};

	# スケルトン登録の削除
	$ROBJ->delete_skeleton($self->{user_skeleton_level});

	# blogid の設定
	if ($blogid eq '') { return; }				# 内部変数初期化時に使用
	my $blog = $self->load_blogset( $blogid );
	if (!$blog || !%$blog || $blogid eq '*') { return; }	# blogidが存在しない

	# 表示権限
	my $view_ok = $self->set_blog_permission($self, $blog);
	if (!$view_ok) {	# プライベートモードのブログの閲覧権限がない
		if ($blog->{view_pass} eq '') { return; }
		$self->{view_pass} = $blog->{view_pass};
	}

	# ブログ情報設定
	$self->{blogid} = $blogid;
	$self->{blog}   = $blog;
	$self->{blog_dir}    = $self->blog_dir();
	$self->{blogpub_dir} = $self->blogpub_dir();
	# myself(通常用,QUERY用)、myself2(PATH_INFO用) の設定
	if ($self->{subdomain_mode}) {
		$self->{myself}  = '/';
		$self->{myself2} = '/';	
	} elsif ($blogid ne $self->{sys}->{default_blogid}) {
		$self->{myself}  = $ROBJ->{myself2} . "$blogid/";
		$self->{myself2} = $ROBJ->{myself2} . "$blogid/";
	}

	# ブログ個別スケルトンの登録（プラグイン等で生成される）
	if (!$self->{stop_all_plugins}) {
		$ROBJ->regist_skeleton($self->{blog_dir} . 'skel/', $self->{user_skeleton_level});
	}

	# 日付変更時間設定
	my $ch_hour = $blog->{change_hour_int};
	$ROBJ->{Change_hour} = $ch_hour;
	if ($ch_hour) {
		$self->{now} = $ROBJ->time2timehash( $ROBJ->{TM} );
	}

	return $blog;
}

#-------------------------------------------------------------------------------
# ●ブログの権限設定
#-------------------------------------------------------------------------------
sub set_blog_permission {
	my $self = shift;
	my $h    = shift;
	my $blog = shift;
	my $ROBJ = $self->{ROBJ};

	# 設定を解釈
	my $auth   = $ROBJ->{Auth};
	my $authok = $auth->{ok};
	my $authid = $auth->{id};
	if ($authid eq $blog->{blogid} || $auth->{isadmin}) {	# 自分のブログか管理者は許可
		$h->{blog_admin} = 1;
		$h->{allow_edit} = 1;
		$h->{allow_com}  = 1;
		return 1;
	}

	# 記事の執筆／編集許可／閲覧許可を判別
	my $allow_view = ! $blog->{private};
	if ($authok) {
		$h->{blog_admin} = $h->users_check($blog->{admin_users}, $authid);
		$h->{allow_edit} = $h->{blog_admin} || $h->users_check($blog->{editors}, $authid);
		$allow_view    ||= $h->{allow_edit} || $h->users_check($blog->{viewers}, $authid);
	}

	# コメントの許可
	my $allow_com = $blog->{allow_com_users};
	if ($allow_view) {
		if ($allow_com eq '*' || ($allow_com eq 'user*' && $authok)) {
			$self->{allow_com} = 1;
		} elsif ($allow_com ne '' && $authok) {
			$allow_com =~ s|\s*,\s*|,|g;
			$self->{allow_com} = (0 < index(",$allow_com,",$authid)) ? 1 : 0;
		}
	}
	return $allow_view;
}

#--------------------------------------
# 許可ユーザー判別
#--------------------------------------
sub users_check {
	my ($self,$users,$uid) = @_;
	if ($users eq '*') { return 1; }
	$users =~ s|\s*,\s*|,|g;
	return (0 < index(",$users,",$uid)) ? 1 : 0;
}

#-------------------------------------------------------------------------------
# ●ブログの設定保存	※Finish()から呼ばれる
#-------------------------------------------------------------------------------
sub save_blogset_sys {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $x = $self->{'_loaded_bset'};

	foreach(keys(%$x)) {
		my $h = $x->{$_};
		if (ref($h) ne 'HASH' || !$h->{_update}) { next; }
		delete $h->{_update};
		delete $h->{blogid};
		$ROBJ->fwrite_hash($self->blog_dir($_) . 'setting.dat', $h);
	}
}

################################################################################
# ■スケルトン用サブルーチン
############################################################################### 
#-------------------------------------------------------------------------------
# ●システムモードへ
#-------------------------------------------------------------------------------
sub system_mode {
	my ($self, $title) = @_;
	my $ROBJ = $self->{ROBJ};
	$self->{system_mode}    = 1;
	$ROBJ->{no_robots}      = 1;
	if ($title ne '') { $self->{title} = $title; }

	if ($self->{blog}->{sysmode_notheme}){
		# デフォルトテーマの選択
		$self->load_theme( $self->{default_theme} );
	}
}

#-------------------------------------------------------------------------------
# ●Ajax汎用処理
#-------------------------------------------------------------------------------
sub ajax_function {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$self->{action_is_main} = 1;
	$self->{frame_skeleton} = undef;
	$ROBJ->set_content_type('application/json');

	my $h = $self->do_ajax_function(@_);
	if (!ref($h)) { return { ret => $h } }
	if (ref($h) ne 'ARRAY') { return $h; }

	my %r = (ret => shift(@$h));
	if (@$h) {
		my $v = shift(@$h);
		$r{ref($v) ? 'errs' : 'msg'} = $v;
	}
	if (@$h) { $r{data} = shift(@$h); }
	return \%r;
}
sub do_ajax_function {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};

	if ($func ne '_ajax_login' && !$ROBJ->{Auth}->{ok}) {
		return [ -99.1, 'Security Error' ];
	}

	my $r;
	eval { $r = $self->$func( $ROBJ->{Form} ); };
	if (!$@) { return $r; }

	# eval error
	if ($self->can($func)) {
		return [ -99.9, $@ ];
	}
	return [ -99.2, "function not found: $func()" ];
}

#-------------------------------------------------------------------------------
# ●ログイン
#-------------------------------------------------------------------------------
sub _ajax_login {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $id   = $form->{adiary_id};

	my $r = $auth->login($id, $form->{pass});
	if ($r->{ret}) {	# error
		if (!$ROBJ->{Develop}) { $r->{ret} = 1; }	# 1固定
		return $r;
	}

	# login
	$ROBJ->set_cookie('session', {
		id  => $id,
		sid => $r->{sid}
	}, $auth->{expires});
	$r->{_no_debug}=1;
	return $r;
}

#-------------------------------------------------------------------------------
# ●記事の読み込み
#-------------------------------------------------------------------------------
sub load_articles_current_blog {
	my ($self, $mode, $query, $opt) = @_;
	my $blog = $self->{blog};

	$opt->{pagemode}  = 1;
	$opt->{loads}     = $opt->{load_items} || $blog->{load_items};
	$opt->{blog_only} = $blog->{separate_blog};

	if ($self->{allow_edit}) {
		$opt->{load_hidden} = 1;
	}
	return $self->load_articles($self->{blogid}, $mode, $query, $opt);
}

#-------------------------------------------------------------------------------
# ●単一記事のロード
#-------------------------------------------------------------------------------
sub load_article_current_blog {
	my ($self, $mode, $query, $opt) = @_;

	if ($self->{allow_edit}) {
		$opt->{load_hidden} = 1;
		$opt->{load_draft}  = 1;
	}
	return $self->load_article($self->{blogid}, $mode, $query, $opt);
}

sub load_article {
	my $self = shift;
	my ($art, $ret) = $self->load_articles(@_);
	if (($ret->{mode} ne 'pkey' && $ret->{mode} ne 'wiki') || $#$art != 0) {
		return undef;
	}
	$art = $art->[0];
	return wantarray ? ($art, $ret) : $art;
}

#-------------------------------------------------------------------------------
# ●記事のロード
#-------------------------------------------------------------------------------
# opt.load_hidden	enableでないものもロード
# opt.loads		loadする記事数(max) 
# opt.pagemode		ページ処理する
# opt.no_override	公開フラグ等をオーバーライドしない
# opt.blog_only		ブログ記事のみをロードします
#
#Ret:
#	ret.mode	判別したモード
#	ret.pagemode	ページモードかどうか。
#	ret.page	現在のページ数
#	ret.title_tag	検索がタイトルかタグ検索のみ（mode が 'search'のときのみ）
#
sub load_articles {
	my ($self, $blogid, $mode, $query, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $blog = $self->load_blogset( $blogid );
	if (! $blog) { return []; }

	#-------------------------------------------------------------
	# ●モードセレクタ
	#-------------------------------------------------------------
	my $loads = int($opt->{loads}) || 5;

	my %q;		# DB-query
	my %ret;	# 戻り値
	#-------------------------------------------------------------
	# 記事pkey
	#-------------------------------------------------------------
	if ($mode =~ /^0(\d+)$/) {
		$ret{mode} = 'pkey';

		$q{match} = {pkey => int($1)};
		$q{limit} = 1;

	#-------------------------------------------------------------
	# 年月日指定 / YYYYMMDD
	#-------------------------------------------------------------
	} elsif ($query->{d} =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
		$ret{mode} = 'day';

		my $err = $self->check_date($1, $2, $3);
		if ($err ne '') {
			$ROBJ->message($err);
			return [];
		}
		$ret{year} = $1;
		$ret{mon}  = $2;
		$ret{day}  = $3;

		$q{match}    = {yyyymmdd => $query->{d}};
		$q{sort}     = 'tm';
		$q{sort_rev} = 0;

		if ($opt->{blog_only}) {
			$q{match}->{priority} = 0;
		}

	#-------------------------------------------------------------
	# tm指定
	#-------------------------------------------------------------
	} elsif ($query->{tm} =~ /^(\d{9,})$/) {
		$ret{mode} = 'day';

		$q{match}    = {tm => $1};
		$q{sort}     = 'pkey';
		$q{sort_rev} = 0;

	#-------------------------------------------------------------
	# Query
	#-------------------------------------------------------------
	} elsif ($query->{d} || $query->{t} || $query->{c} || $query->{q} !~ /^\s*$/) {
		$ret{mode} = 'search';
		my $title_tag;

		#-------------------------------------------
		# 年月指定 / YYYYMM
		#-------------------------------------------
		if ($query->{d} =~ /^(\d\d\d\d)(\d\d)?$/) {
			$title_tag = 0;
			if ($2) {
				my $err = $self->check_date($1, $2);
				if ($err ne '') {
					$ROBJ->message($err);
					return [];
				}
			}
			$ret{yyyymm} = $query->{d};
			$ret{year} = $1;
			$ret{mon}  = $2;

			if ($2) {
				$q{min} = {yyyymmdd => "$1${2}01"};
				$q{max} = {yyyymmdd => "$1${2}31"};
			} else {
				$q{min} = {yyyymmdd => "${1}0101"};
				$q{max} = {yyyymmdd => "${1}1231"};
			}
			if ($opt->{blog_only}) {
				$q{match}->{priority} = 0;
			}
		}

		#-------------------------------------------
		# タグの検索
		#-------------------------------------------
		if ($query->{t}) {
			if (!defined $title_tag) { $title_tag=1; }
			my $taglist = $self->load_tag_cache($blogid);
			my $name2pkey = $taglist->[0];
			my $tags = $query->{t};
			$ROBJ->tag_escape(@$tags);
			my %arts;
			my %t;
			my @tags_txt;
			foreach(@$tags) {
				if ($t{$_}) { next; }
				my $pkey = $name2pkey->{$_};
				if ($_ ne '' && !$pkey) {
					# 存在しないタグ
					$q{match}->{pkey} = -1;
					last;
				}
				push(@tags_txt, $_);
				$t{$_}=1;
				if ($_ eq '') {
					# タグのない記事
					$q{match}->{tags} = '';
					next;
				}
				# 記事のpkeyリストを取得
				my @que = ( $pkey );
				my %a;
				while(@que) {
					my $tag = $taglist->[ shift(@que) ];
					my $arts = $tag->{arts};
					foreach(@$arts) {
						$a{$_}=1;
					}
					push(@que, @{ $tag->{children} });
				}
				foreach(keys(%a)) {
					$arts{$_}++;
				}
				if (!%a){	# 所属が0のタグ
					$q{match}->{pkey} = -1;
				}
			}
			if (%t) {
				$ret{tags} = \@tags_txt;
			}
			if (%arts) {
				my $c = @$tags;		# 指定されたタグの数
				my @ary = grep { $arts{$_} == $c } keys(%arts);
				$q{match}->{pkey} = @ary ? \@ary : [-1];
			}
		}

		#-------------------------------------------
		# コンテンツタイプの検索
		#-------------------------------------------
		if (exists($query->{c})) {
			$title_tag = 0;
			$q{match}->{ctype} = $query->{c};
			$ret{ctype} = $query->{c};
		}

		#-------------------------------------------
		# 文字列検索
		#-------------------------------------------
		if ($query->{q} !~ /^\s*$/) {
			my $q = $query->{q};
			my @buf;
			$q =~ s!"([^"]+)"!
				push(@buf, $1);
				" \x04[$#buf] ";
			!eg;
			$q =~ s/^ \x04\[/\x04\[/;
			my $sep = $self->{words_separator} || '\s';

			require Encode;
			Encode::_utf8_on($q);
			$q =~ s/[$sep]+/ /g;
			Encode::_utf8_off($q);

			my @words = split(/ /, $q);
			foreach(@words) {
				$_ =~ s/\x04\[(\d+)\]/$buf[$1]/;
			}
			$q{search_words} = \@words;
			$q{search_cols}  = $query->{all} ? ['title','_text', 'tags'] : ['title'];
			if ($query->{all}) {
				$title_tag = 0;
			} else {
				if (!defined) { $title_tag = 1; }
			}

			$q =~ s/\x04\[(\d+)\]/"$buf[$1]"/g;
			$ROBJ->tag_escape_amp( $q );
			$ret{q} = $q;
			$ret{words} = \@words;
		}

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;
		$ret{pagemode}  = 1;
		$ret{narrow}    = 1;	# 絞り込み
		$ret{title_tag} = $title_tag;

	#-------------------------------------------------------------
	# コンテンツ指定
	#-------------------------------------------------------------
	} elsif ($mode =~ /^[^&]/) {
		$ret{mode} = 'wiki';
		$q{match} = {link_key => $mode};

	#-------------------------------------------------------------
	# 指定なし（最近 n 件）
	#-------------------------------------------------------------
	} else {
		$ret{mode} = '';
		$ret{pagemode} = 1;

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;

		if ($opt->{blog_only}) {
			$q{match}->{priority} = 0;
		}
	}

	#-------------------------------------------------------------
	# ●ロード対象
	#-------------------------------------------------------------
	$q{flag}={};
	if (!$opt->{load_hidden}) {
		$q{flag}->{enable} = 1;
	}
	if (!$opt->{load_draft}) {
		$q{not_null} = ['tm'];
	}

	#-------------------------------------------------------------
	# ●データのロード
	#-------------------------------------------------------------
	my $logs = [];
	my $page = 1;
	my $limit = $q{limit};
	my $next_page;
	if ($opt->{pagemode} && $ret{pagemode}) {
		$page = int($query->{p});
		if ($page < 1) { $page=1; }
	}
	if ($ret{narrow}) {
		#---------------------------------------------------------------
		# 全該当データを探し、絞り込み条件を作る
		#---------------------------------------------------------------
		$q{cols} = ['pkey', 'yyyymmdd', 'tags'];
		delete $q{limit};
		my $all = $DB->select("${blogid}_art", \%q);
		my $hits = @$all;

		if ($hits > 1) {
			my $taglist = $self->load_tag_cache($blogid);
			my $name2pkey = $taglist->[0];
			my $blog_only = $opt->{blog_only};
			my %tags;
			my %year;
			my %mon;
			my %ctype;
			foreach(@$all) {
				my $ymd = $_->{yyyymmdd};
				if (!$blog_only || !$_->{priority}) {
					$year{ substr($ymd,0,4) }++;
					$mon { substr($ymd,0,6) }++;
				}
				my @tags = split(',', $_->{tags});
				my %c;	# aa::b, aa::c 時、aaの重複カウント防止
				foreach my $tag (@tags) {
					my $t;
					foreach(split('::',$tag)) {
						$t = $t ne '' ? "$t\::$_" : $_;
						if ($c{$t}) { next; }
						$c{$t}=1;
						$tags{ $t }++;
					}
				}
				if ($_->{tags} eq '') {
					$tags{''}++;
				}
				$ctype{ $_->{ctype} }++;
			}
			foreach(keys(%tags)) {
				if ($tags{$_} == $hits) { delete $tags{$_}; }
			}
			foreach(keys(%ctype)) {
				if ($ctype{$_} == $hits) { delete $ctype{$_}; }
			}
			foreach(keys(%year)) {
				if ($year{$_} == $hits) { delete $year{$_}; }
			}
			foreach(keys(%mon)) {
				if ($mon{$_} == $hits) { delete $mon{$_}; }
			}
			my %ymd = %year ? %year : %mon;
			if (%tags)  { $ret{narrow_tags}  = \%tags;  $tags {_order} = [ sort(keys(%tags )) ]; }
			if (%ctype) { $ret{narrow_ctype} = \%ctype; $ctype{_order} = [ sort(keys(%ctype)) ]; }
			if (%ymd)   { $ret{narrow_ymd}   = \%ymd;   $ymd  {_order} = [ sort(keys(%ymd  )) ]; }
		}

		# 該当ページのデータだけ取り出す
		my $offset = ($page-1) * $limit;
		$ret{page}  = $page;
		$ret{pages} = int(($hits+$limit-1)/$limit);
		$ret{hits}  = $hits;
		$ret{next_page} = ($ret{pages} > $page);

		if ($hits) {
			my @pkeys;
			for(my $i=0; $i<$limit; $i++) {
				my $pkey = $all->[$offset+$i]->{pkey} || next;
				push(@pkeys, $pkey);
			}
			$logs = $DB->select("${blogid}_art", {
				match => { pkey => \@pkeys },
				sort     => $q{sort},
				sort_rev => $q{sort_rev}
			});
		}

	} else {
		if ($opt->{pagemode} && $ret{pagemode}) {
			$ret{page} = $page;
			$q{offset} = ($page-1) * $limit;
			$q{limit} += 1;
		}
		$logs = $DB->select("${blogid}_art", \%q);
		$ret{next_page} = ($ret{page} && $#$logs == $limit);	# 余計に取得した1件が存在する
		if ($ret{next_page}) { pop(@$logs); }			# その1件を読み捨て
	}

	#-------------------------------------------------------------
	# ●ページ送り処理
	#-------------------------------------------------------------
	my $path = $self->get_blog_path( $blogid );

	# 単一記事ページ送り
	if ($opt->{pagemode} && exists $blog->{keylist} && $logs->[0]
	 && ($ret{mode} eq 'pkey' || $ret{mode} eq 'wiki')) {
		my $key = $logs->[0]->{link_key} || $logs->[0]->{pkey};
		my $keylist = $blog->{keylist};
		if ($opt->{load_hidden}) { $keylist = $blog->{keylist_all}; }

		# key を探す
		$key =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/eg;
		if ($key && $keylist =~ /([^,]*),$key,([^,]*)/) {
			if ($1 ne '') {
				$ROBJ->encode_uricom(my $x = $1);
				$ret{next_page} = $path . $x;
			}
			if ($2 ne '') {
				$ROBJ->encode_uricom(my $x = $2);
				$ret{prev_page} = $path . $x;
			}
		}
	}

	#-------------------------------------------------------------
	# フラグのオーバーライド確認
	#-------------------------------------------------------------
	if (!$opt->{no_override}) {
		foreach my $flag (qw(com_ok hcom_ok)) {
			if ($blog->{"${flag}_force"} ne '') {
				my $ow = $blog->{"${flag}_force"};
				foreach(@$logs) {
					$_->{$flag} = $ow;
				}
			}
		}
	}

	#-------------------------------------------------------------
	# 記事データの前処理
	#-------------------------------------------------------------
	foreach(@$logs) {
		$self->post_process_article( $_, $opt );
	}

	#-------------------------------------------------------------
	# 記事指定時の日付処理
	#-------------------------------------------------------------
	if ($logs->[0] && ($ret{mode} eq 'pkey' || $ret{mode} eq 'wiki')) {
		$ret{year} = $logs->[0]->{year};
		$ret{mon}  = $logs->[0]->{mon};
		$ret{day}  = $logs->[0]->{day};
	}
	if ($logs->[0] && $ret{mode} eq 'search' && $ret{year} && !$ret{day}) {
		$ret{art_mon} = $logs->[0]->{mon};
	}

	return wantarray ? ($logs, \%ret) : $logs;
}

#-------------------------------------------------------------------------------
# ●１件の記事データの加工（後処理）
#-------------------------------------------------------------------------------
sub post_process_article {
	my $self = shift;
	my ($art, $opt) = @_;
	my $ROBJ = $self->{ROBJ};

	my $yyyymmdd = $art->{yyyymmdd};
	my $year = $art->{year} = substr($yyyymmdd, 0, 4);
	my $mon  = $art->{mon}  = substr($yyyymmdd, 4, 2);
	my $day  = $art->{day}  = substr($yyyymmdd, 6, 2);

	# コンテンツkey関連
	my $key = $art->{link_key};
	$art->{elink_key} = $key;
	$self->link_key_encode( $art->{elink_key} );

	# 下書き?
	$art->{draft} = $art->{tm} ? 0 : 1;

	# 曜日の取得
	$art->{wday} = $self->get_dayweek($art->{year}, $art->{mon}, $art->{day});
	$art->{wday_name} = $ROBJ->{WDAY_name}->[ $art->{wday} ];

	# メイン画像
	if ($art->{main_image} =~ /^(.*?)\?(\d+),(\d+)/) {
		$art->{main_image}   = $1;
		$art->{main_image_w} = $2;
		$art->{main_image_h} = $3;
	}
	return $art;
}

# link_key処理のみ
sub post_process_link_key {
	my $self = shift;
	my $dat = shift;
	$dat->{elink_key} = $dat->{link_key};
	return $self->link_key_encode( $dat->{elink_key} );
}

# タグ情報からタグリンクの生成
sub make_taglinks {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my @tags = split(',', shift);
	my $link = $self->{myself} . '?&amp;t=';
	foreach my $tag (@tags) {
		my $t;
		my $s='';
		foreach(split('::', $tag)) {
			$t  =  $t ne '' ? "$t\::$_" : $_;
			my $x = $t;
			$ROBJ->encode_uricom($x);
			$s .= ($s ne '' ? '::' : '') . "<a href=\"$link$x\">$_</a>";
		}
		$tag = "<span class=\"tag\">$s</span>";
	}
	return join('',@tags);
}

#-------------------------------------------------------------------------------
# ●コメントのロードと加工
#-------------------------------------------------------------------------------
# $a_pkey の代わりに記事のデータ（ハッシュ）を与えたほうが高速
#
sub load_comments_current_blog {
	my $self = shift;
	my $a_pkey = shift;
	my $num  = shift;
	my $opt  = shift || {};

	# コメント数を確認
	if (ref($a_pkey)) {
		my $art = $a_pkey;
		$a_pkey = $art->{pkey};
		if (!$art->{coms_all} || !$self->{allow_edit} && !$art->{coms}) {
			return [];
		}
	}

	if (!exists($opt->{enable_only})) {
		$opt->{enable_only} = $self->{allow_edit} ? 0 : 1;
	}
	$opt->{loads} = $num ? $num : undef;

	# ロード
	return $self->load_comments($self->{blogid}, $a_pkey, $opt);
}

#-------------------------------------------------------------------------------
# ●コメントのロード
#-------------------------------------------------------------------------------
# opt.loads		ロードするコメント数（上限）
# opt.enable_only	公開コメントのみ表示
#
sub load_comments {
	my $self = shift;
	my ($blogid, $a_pkey, $opt) = @_;
	my $DB   = $self->{DB};

	# コメントのロード
	my $blogid = $self->{blogid};
	my $loads  = $opt->{loads} ne '' ? int($opt->{loads}) : undef;
	my %h;
	$h{match} = {a_pkey => int($a_pkey)};
	$h{sort}  = ['num', 'tm'];
	if ($opt->{enable_only}) {
		$h{flag} = { enable => 1 };
	}
	if (defined $loads) {
		# 新しい方から指定数のみ取得する
		$h{sort_rev} = 1;
		$h{limit}    = $loads;
	}

	# ロード
	my $comments = $DB->select("${blogid}_com", \%h);
	if (defined $loads) {
		return [ reverse(@$comments) ];
	}
	return $comments;
}

################################################################################
# ■プラグインシステム
################################################################################
#-------------------------------------------------------------------------------
# ●指定したイベントを呼び出す
#-------------------------------------------------------------------------------
sub call_event {
	my $self = shift;
	my $evt  = shift;	# イベント名
	if ($evt eq '') {
		$self->{ROBJ}->message('"event name" is null.');
		return -99;
	}
	my $r=0;
	$r += $self->do_call_event("$evt#before", undef, @_);
	$r += $self->do_call_event( $evt        , undef, @_);
	$r += $self->do_call_event("$evt#after" , undef, @_);
	return $r;
}

sub do_call_event {
	my $self = shift;
	my $evt  = shift;	# イベント名
	my $blog = shift || $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (!$blog) { return 0; }

	my @evt = $self->{stop_all_plugins} ? () : split(/\r?\n/, $blog->{"event:$evt"});
	push(@evt, @{ $SysEvt{$evt} || [] });
	if (!@evt) { return 0; }

	my $ret=0;
	$evt =~ s/^(.*):.*$/$1/;	# : 以降を除去
	local($self->{event_name}) = $evt;
	my %h;
	my $once = 0 < index($evt, '#');
	foreach(@evt) {
		my $x = index($_, '=');
		my $name = $x<0 ? '' : substr($_, 0, $x);
		my $op   = substr($_, $x+1);

		if ($h{$op}) { next; }
		$h{$op} = $once;

		# system 設定のイベント処理
		if ($x == -1) {
			my $r = $self->$_(@_);
			$ret += $r ? 1 : 0;
			next;
		}

		# プラグインによるイベント処理
		my $r;
		if ($op =~ m|^func/([\w\-]+\.pm)$|) {
			# ファイルをロードして無名ルーチンを呼び出す
			$r = $self->call_plugin_function($1, $name, @_);
		} elsif ($op =~ m|^skel/([\w/-]+)$|) {
			# スケルトンファイルを呼び出す
			$r = $ROBJ->call($1, $name, @_);
		} else {
			$ROBJ->error("[plugin=%s] Unknown method : %s", $name, $op);
			$r = -1;
		}
		# 結果の保存
		$self->{return}->{$name} = $r;
		$ret += $r ? 1 : 0;
	}
	return $ret;
}

#-------------------------------------------------------------------------------
# ●プラグインファイルをロードして無名ルーチンを呼び出す
#-------------------------------------------------------------------------------
sub call_plugin_function {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->{blog_dir} . "func/$name";
	my $func = $self->load_plugin_function($name, $file);
	if (!ref($func)) {
		$ROBJ->error("[plugin=%s] Load error", $name);
		return $func;
	}

	my $r;
	$self->{call_file} = $file;
	eval { $r = &$func($self, @_) };
	delete $self->{call_file};
	if ($@) {
		$ROBJ->error("[plugin=%s] Execute error : %s", $name, $@);
		return -10;
	}
	return $r;
}

#-------------------------------------------------------------------------------
# ●プラグインのロードとコンパイル（キャッシュ付）
#-------------------------------------------------------------------------------
my %plugin_cache;
my %plugin_cache_tm;
sub load_plugin_function {
	my $self = shift;
	my ($name, $file) = @_;

	my @st = stat($file);
	if (!$st[9]) { return -1; }
	if ($plugin_cache_tm{$file} == $st[9]) {
		return $plugin_cache{$file};
	}

	my $fh;
	my $func;
	sysopen($fh, $file, O_RDONLY);
	my $r = sysread($fh, $func, $st[7]);
	close($fh);
	if ($r != $st[7]) { return -2; }	# 読み込んだバイト数確認

	# Perlでコンパイル
	eval "\$func=$func";
	if ($@) {
		$self->{ROBJ}->error("[plugin=%s] Compile error : %s", $name, $@);
		return -3;
	}
	# キャッシュ
	$plugin_cache_tm{$file} = $st[9];
	return ($plugin_cache{$file} = $func);
}

#-------------------------------------------------------------------------------
# ●JavaScript/CSSプラグインをロード
#-------------------------------------------------------------------------------
sub load_jscss_events {
	my $self = shift;
	my $name = shift;
	if (!$self->{blog}) { return []; }
	if ($self->{stop_all_plugins}) { return []; }

	$name =~ tr/a-z/A-Z/;
	my $evt = $self->{blog}->{"event:$name"};
	my $dir = $self->{blogpub_dir};

	my @ary;
	foreach(split("\n", $evt)) {
		my ($name, $file) = $self->split_equal($_);
		if (!$name) { next; }
		push(@ary, ($file =~ m!^/|^https?://!i ? '' : $dir) . $file);
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●プラグインの設定をロード
#-------------------------------------------------------------------------------
sub load_plgset {
	my ($self,$name,$key) = @_;
	my $blog = $self->{blog} || return;

	if ($key ne '') {
		return $blog->{"p:$name:$key"};
	}

	my $head = "p:$name:";
	my $len = length($head);
	my %h;
	foreach(keys(%$blog)) {
		if (substr($_,0,$len) ne $head) { next; }
		$h{ substr($_,$len) } = $blog->{$_};
	}
	$h{_blogid} = $blog->{blogid};
	return \%h;
}

################################################################################
# ■システム情報 / ブログ情報の管理
################################################################################
#-------------------------------------------------------------------------------
# ●システムdatをロードする
#-------------------------------------------------------------------------------
sub load_sysdat {
	my $self = shift;
	if ($self->{sys}) { return $self->{sys}; }
	my $ROBJ = $self->{ROBJ};
	my $sys = $ROBJ->fread_hash_cached($self->{system_config_file}, {NoError=>1});
	if (!$sys || !%$sys) {
		$sys = $ROBJ->fread_hash($self->{default_config_file});
		$sys->{_update}=1;
		$sys->{VERSION} = $self->{VERSION};
	}
	$self->{sys}=$sys;
	# Secret_word 自動設定
	if (!$sys->{Secret_word}) {
		$self->update_sysdat('Secret_word', $ROBJ->generate_nonce(40));
	}
	# Versionチェック
	if ($sys->{VERSION} < $DATA_VERSION) {
		$self->{require_update} = 1;
	}

	return $sys;
}

#-------------------------------------------------------------------------------
# ●システムdatを更新する
#-------------------------------------------------------------------------------
sub update_sysdat {
	my $self = shift;
	$self->update_hash( $self->{sys}, @_ );
	$self->{sys}->{_update}=1;
}

#-------------------------------------------------------------------------------
# ●システムdatを保存する	※Finish()から呼ばれる
#-------------------------------------------------------------------------------
sub save_sysdat {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $sys = $self->{sys};
	if (! $sys->{_update}) { return 0; }
	delete $sys->{_update};
	$ROBJ->fwrite_hash($self->{system_config_file}, $sys);
}

#-------------------------------------------------------------------------------
# ●タグデータのロード
#-------------------------------------------------------------------------------
# &generate_tag_tree で生成
sub load_tag_cache {
	my ($self, $blogid) = @_;
	my $ROBJ = $self->{ROBJ};

	my $file = $self->blog_dir($blogid) . "tag_cache.txt";
	return $ROBJ->fread_lines_cached($file, {
		NoError=>1,
		PostProcessor=>\&load_tag_postprocessor
	});
}

sub load_tag_postprocessor {
	my ($self, $ary) = @_;
	my %name2pkey;
	my $i=-1;
	$ary = [ map {
		chomp($_);
		$i++;
		my @a=split("\t");
		defined $a[1] && ($name2pkey{$a[6]}=$i);
		defined $a[1] ? { pkey=>$i, upnode=>int($a[0]), qt=>$a[1], qtall=>$a[2], priority=>$a[3], name=>$a[6],
		#	children=>$a[4], arts=>$a[5]
			children=> [split(',',$a[4])],
			arts    => [split(',',$a[5])]
		} : undef;
	} @$ary ];
	$ary->[0] = \%name2pkey;
	return $ary;
}

#-------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（ブログ記事）
#-------------------------------------------------------------------------------
sub load_art_node {
	my ($self, $pkey) = @_;

	my $cache = $self->{_loadart_cache} ||= {};
	my $key   = $self->{blogid} . ':' . $pkey;
	if ($cache->{$key}) { return $cache->{$key}; }

	my $con = $self->load_arts_cache( $pkey );
	my %c = %{ $con->{$pkey} || {} };
	$c{prev} = $con->{ $c{prev} };
	$c{next} = $con->{ $c{next} };
	return ($cache->{$key} = \%c);
}
sub load_arts_cache {
	my $self = shift;
	my $num  = sprintf("%04d", int((shift)/($self->{blog_cache_unit} || 0x7fffffff)));
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_lines_cached( $self->{blog_dir} . "arts/$num.dat", {
		NoError=>1,
		PostProcessor=>\&load_arts_postprocessor
	});
}
sub load_arts_postprocessor {
	my ($self, $ary) = @_;
	my %h;
	foreach(@$ary) {
		chomp($_);
		my @a=split("\t", $_);
		$h{$a[0]} = { pkey=>$a[0], prev=>$a[1], next=>$a[2], title=>$a[3] };
	}
	return \%h;
}

#-------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（コンテンツ）
#-------------------------------------------------------------------------------
sub load_content_node {
	my ($self, $pkey) = @_;

	my $cache = $self->{_loadcn_cache} ||= {};
	my $key   = $self->{blogid} . ':' . $pkey;
	if ($cache->{$key}) { return $cache->{$key}; }

	my $con = $self->load_contents_cache();
	my %c = %{ $con->{$pkey} || {} };
	$c{upnode} = $con->{ $c{upnode} };
	$c{prev}   = $con->{ $c{prev} };
	$c{next}   = $con->{ $c{next} };
	my @ch = map { $con->{$_} } split(",",$c{children});
	if (@ch) { $c{children} = \@ch; }
	if ($c{upnode} && $c{upnode}->{children}) {
		my @fam;
		my @fam = map { $con->{$_} } split(",",$c{upnode}->{children});
		if (@fam) {
			my @f = grep {$_->{pkey} != $pkey} @fam;
			if (@f) { $c{family} = \@f; }
		}
	}
	return ($cache->{$key} = \%c);
}
sub load_contents_cache {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_lines_cached( $self->{blog_dir} . 'arts/contents.dat', {
		NoError=>1,
		PostProcessor=>\&load_contents_postprocessor
	});
sub load_contents_postprocessor {
	my ($ROBJ, $ary) = @_;
	my %h;
	foreach(@$ary) {
		chomp($_);
		my @a=split("\t", $_);
		$h{$a[0]} = {
			pkey      => $a[0],
			link_key  => $a[1],
			upnode    => $a[2],
			prev      => $a[3],
			next      => $a[4],
			children  => $a[5],
			title     => $a[6]
		};
		$self->post_process_link_key( $h{$a[0]} );
	}
	return \%h;
}
}

################################################################################
# security id system for post of no login
################################################################################
#-------------------------------------------------------------------------------
# ●特殊IDルーチン
#-------------------------------------------------------------------------------
sub make_secure_id {
	my $self = shift;
	my $base = shift;
	my $old  = shift;
	my $ROBJ = $self->{ROBJ};

	my $stime = $ROBJ->{Secure_time} || 3600;
	my $code  = int($ROBJ->{TM} / $stime) - int($old);

	my $id = $ROBJ->crypt_by_string_nosalt($self->{sys}->{Secret_word}, $base . $code);
	$id =~ tr|/|-|;
	return substr($id, 0, 32);
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●blog_dirを取得
#-------------------------------------------------------------------------------
sub blog_dir {
	my ($self, $blogid) = @_;
	$blogid ||= $self->{blogid};
	$blogid =~ s/\W//;
	return "$self->{data_dir}blog/$blogid/";
}
sub blogpub_dir {
	my ($self, $blogid) = @_;
	$blogid ||= $self->{blogid};
	$blogid =~ s/\W//;
	my $blog = $self->load_blogset($blogid);
	my $postfix = $blog ? $blog->{blogpub_dir_postfix} : '';
	return "$self->{pub_dir}$blogid$postfix/";
}
sub blogimg_dir {
	my $self = shift;
	return $self->{blogpub_dir} . 'image/';
}

#-------------------------------------------------------------------------------
# ●指定したblogidのURLを取得
#-------------------------------------------------------------------------------
sub get_blog_path {
	my ($self, $blogid) = @_;
	my $ROBJ = $self->{ROBJ};
	$blogid =~ s/[^\w\-]//g;
	if ($self->{subdomain_mode}) {
		my $url = $self->{subdomain_proto} . "$blogid\.$self->{subdomain_mode}";
		return $ROBJ->{ServerURL} eq $url ? '/' : "$url/";
	}
	my $myself2 = $ROBJ->{myself2};
	return ($blogid eq $self->{sys}->{default_blogid}) ? $myself2
		: $myself2 . $blogid . '/';
}

#-------------------------------------------------------------------------------
# ●skeleton dirを取得
#-------------------------------------------------------------------------------
sub parse_skel {
	my ($self, $str) = @_;
	if ($str =~ m|\.\.|) { return; }	# safety
	if ($str !~ m|^((?:[A-Za-z0-9][\w\-]*/)*)([A-Za-z0-9][\w\-]*)?$|) { return ; }
	my $b = ($1 ne '' && $2 eq '') ? 'index' : $2;
	return wantarray ? ($1,$b) : "$1$b";
}

#-------------------------------------------------------------------------------
# ●テーマの選択
#-------------------------------------------------------------------------------
sub load_theme {
	my ($self, $theme) = @_;
	if ($self->{theme} eq $theme) { return 0; }
	my $ROBJ = $self->{ROBJ};

	if ($theme !~ m|^([\w-]+)/([\w-]+)/?$| ) { return -1; }	# error
	my $name = $2;
	my $dir = $self->{theme_dir} . "$1/";
	if (! -r "$dir$name/$name.css") { return 1; }		# not found

	# 内部変数に記録
	$self->{theme}      = $theme;
	$self->{template}   = $1;
	$self->{theme_name} = $name;

	# スケルトンテンプレートの登録
	if (-r "${dir}_skel") {
		$ROBJ->regist_skeleton("${dir}_skel/", $self->{theme_skeleton_level});
	} else {
		$ROBJ->delete_skeleton($self->{theme_skeleton_level});
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●日付指定のチェック（確認処理）
#-------------------------------------------------------------------------------
sub check_date {
	my ($self, $year, $mon, $day) = @_;
	if ($year < 1980) { return 'Can not specify before 1980'; }
	if ($year > 9999) { return 'Can not specify after 9999'; }
	if ($mon < 1 || 12 < $mon) { return 'Illegal month'; }
	if ($day > 0) {
		my $days = $self->get_mdays($year, $mon);
		if ($day < 1 || $days < $day) { return 'Illegal day'; }
	} elsif ($day ne '') { return 'Illegal day'; }
	return ;
}

#-------------------------------------------------------------------------------
# ●指定月の日数取得
#-------------------------------------------------------------------------------
sub get_mdays {
	my $self = shift;
	my ($year, $m) = @_; # 1  2  3  4  5  6  7  8  9 10 11 12
	my @mdays      = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
	if ($m != 2)   { return $mdays[$m]; }
	if ($year &   3) { return 28; }	# 4で割り切れない
	if ($year % 100) { return 29; }	# 100で割り切れない
	if ($year % 400) { return 28; }	# 400で割り切れない
	return 29;			# 400で割り切れる
}

#-------------------------------------------------------------------------------
# ●曜日の取得
#-------------------------------------------------------------------------------
sub get_dayweek {
	my $self = shift;
	my ($y, $m, $d) = @_;
	if ($m < 3) { $y--; $m+=12; }
	return ($y + ($y>>2) - int($y/100) + int($y/400) + int((13*$m + 8)/5) + $d) % 7;
}

#-------------------------------------------------------------------------------
# ●yyyymmdd文字列の加工
#-------------------------------------------------------------------------------
sub format_ymd {
	my $self = shift;
	my $ymd  = shift;
	my $sep  = shift || '-';
	return substr($ymd,0,4) . $sep . substr($ymd,4,2). $sep . substr($ymd,6,2);
}

#-------------------------------------------------------------------------------
# ●ハッシュを更新
#-------------------------------------------------------------------------------
sub update_hash {
	my $self = shift;
	my ($h, $k, $v) = @_;
	if (!ref($k)) {
		$h->{$k}=$v;
		return ;
	}
	foreach(keys(%$k)) {
		$h->{$_}=$k->{$_};
	}
}

#-------------------------------------------------------------------------------
# ●key=val表記を分離
#-------------------------------------------------------------------------------
sub split_equal {
	my $self = shift;
	my $str  = shift;
	my $x = index($str, shift || '=');
	if ($x == -1) { return ; }
	my $k = substr($str, 0, $x);
	my $v = substr($str, $x+1);
	return ($k,$v);
}

#-------------------------------------------------------------------------------
# ●blog一覧を表示ok？
#-------------------------------------------------------------------------------
sub allow_blogs {
	my $self  = shift;
	my $allow = $self->{sys}->{blogs_allow};
	if ($allow eq '') { return 1; }		# OK
	
	my $auth = $self->{ROBJ}->{Auth};
	if ($allow eq 'users') { return $auth->{ok}; }
	return $auth->{isadmin};	# $allow == 'admin'
}

#-------------------------------------------------------------------------------
# ●link_keyエンコード
#-------------------------------------------------------------------------------
sub link_key_encode {
	my $self = shift;
	my $fp = $self->{blog}->{frontpage};
	foreach(@_) {
		if ($_ eq $fp) { $_=''; next; }

		# ここを修正したら contents-edit.js も修正のこと
		$_ =~ s/([^\w!\(\)\*\-\.\~\/:;=])/'%' . unpack('H2',$1)/eg;
		$_ =~ s|^/|.//|;
		# myself2が / のとき //lkey となって http://lkey と解釈されるのを防ぐ
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●rssファイル取得
#-------------------------------------------------------------------------------
sub load_rss_files {
	my $self = shift;
	return [ split(',', ($self->{blog} || {})->{rss_files}) ];
}

#-------------------------------------------------------------------------------
# ●js/cssファイルの登録
#-------------------------------------------------------------------------------
sub regist_jslib {
	my $self = shift;
	push(@{ $self->{jslibfiles} ||=[] }, @_);
}
sub regist_js {
	my $self = shift;
	push(@{ $self->{jsfiles} ||=[] }, @_);
}
sub regist_csslib {
	my $self = shift;
	push(@{ $self->{csslibfiles} ||=[] }, @_);
}
sub regist_css {
	my $self = shift;
	push(@{ $self->{cssfiles} ||=[] }, @_);
}
sub load_jscss {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $base = $ROBJ->{Basepath};

	my @ary = @{ $self->{$name . 'files'} || []};
	push(@ary, @{ $self->load_jscss_events($name) });

	my %h;
	@ary = grep { $h{$_}++; $h{$_}<2 } @ary;
	foreach(@ary) {
		if ($_ =~ m!^/|^https?://!i) { next; }
		$_ = $base . $_ . '?' . $ROBJ->get_lastmodified( $_ );
	}
	return \@ary;
}
# ヘッダに追加
sub add_header {
	my $self = shift;
	$self->{extra_header} .= join('', @_);
}

#-------------------------------------------------------------------------------
# ●htmlの登録
#-------------------------------------------------------------------------------
sub regist_post_html {
	my $self = shift;
	$self->{post_html} .= join('', @_);
}

#-------------------------------------------------------------------------------
# ●記事編集権限チェック
#-------------------------------------------------------------------------------
sub check_editor {
	my $self  = shift;
	if (!$self->{allow_edit}) { return 0; }
	# 管理者か制限かかってなければ許可
	if ($self->{blog_admin} || !$self->{blog}->{edit_by_author_only}) {
		return 1;
	}
	# id確認
	my $artid = shift;
	my $auth = $self->{ROBJ}->{Auth};
	$artid = ref($artid) ? $artid->{id} : $artid;
	if ($artid =~ /^\d+$/) {
		my $h = $self->{DB}->select_match_limit1($self->{blogid} . "_art", 'pkey', $artid, '*cols', ['id']);
		if (!$h) { return ; }
		$artid = $h->{id};
	}
	return ($auth->{id} eq $artid);
}

#---------------------------------------------------------------------
# ●配列から指定した数をランダムにロードする
#---------------------------------------------------------------------
sub load_from_ary {
	my $self = shift;
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



1;
