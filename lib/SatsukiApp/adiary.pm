use strict;
#-------------------------------------------------------------------------------
# ブログシステム - adiary
#					(C)2006-2014 nabe@abk / ABK project
#-------------------------------------------------------------------------------
package SatsukiApp::adiary;
use Satsuki::AutoLoader;
use Fcntl ();
#-------------------------------------------------------------------------------
our $VERSION = '2.914';
our $OUTVERSION = '3.00';
our $SUBVERSION = 'beta1.5';
###############################################################################
# ■システム内部イベント
###############################################################################
my %SysEvt;
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

###############################################################################
# ●コンストラクタ
###############################################################################
sub new {
	my ($class, $ROBJ, $DB, $self) = @_;
	if (ref($self) ne 'HASH') { $self={}; }
	bless($self, $class);

	$self->{ROBJ}    = $ROBJ;	# root object save
	$self->{DB}      = $DB;
	$self->{VERSION} = $VERSION;
	$self->{OUTVERSION} = $OUTVERSION;
	$self->{SUBVERSION} = $SUBVERSION;

	# ディフォルト値の設定
	$self->SetDefaultValue();
	$ROBJ->{secure_id_len} ||= 6;
	$self->{scripts}  = {};
	$self->{cssfiles} = {};
	$self->{_loaded_bset} = {};
	$self->{server_url} = $ROBJ->{Server_url};
	$self->{http_agent} = "adiary $VERSION on Satsuki-system $ROBJ->{VERSION}";

	# 現在の日時設定（日付変更時間対策）
	$self->{now} = $ROBJ->{Now};

	# Cache環境向け Timer のロード
	if ($ROBJ->{CGI_cache} && $ENV{Timer} ne '0' && !$Satsuki::Timer::VERSION) {
		require Satsuki::Timer;
	}
	return $self;
}

#------------------------------------------------------------------------------
# ●ディフォルト値の設定
#------------------------------------------------------------------------------
sub SetDefaultValue {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my %h = (
blog_cache_unit  => 100,	# ブログ記事キャッシュ保存時の分割単位
dir_postfix_len  => 8,
theme_skeleton_level => 10,
user_skeleton_level  => 20,
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

###############################################################################
# ●デストラクタ
###############################################################################
sub Finish {
	my $self = shift;
	$self->save_blogset_sys();
	$self->save_sysdat();
}

###############################################################################
# ■メイン処理
###############################################################################
sub main {
	my $self  = shift;
	my $ROBJ  = $self->{ROBJ};

	# security for IE8-
	$ROBJ->set_header('X-Content-Type-Options','nosniff');

	# システム情報のロード
	my $sys = $self->load_sysdat();

	# Cookieログイン処理
	$self->authorization();

	# pinfoとブログの選択
	my $blogid = $self->blogid_and_pinfo();

	# Query/Form処理（ログイン処理より後にすること！）
	$self->read_query_form();

	# 表示スケルトン選択
	$self->select_skeleton( $ROBJ->{Query}->{sk} || $self->{query0} );

	#-------------------------------------------------------------
	# pop タイマー処理
	#-------------------------------------------------------------
	if ($self->{pop_timer}) {
		my $tm = $ROBJ->get_file_modtime( $self->{pop_log_file} );
		if ($tm + $self->{pop_timer} < $ROBJ->{TM}) {
			$self->{pop_check_flag} = 1;
		}
	}

	#-------------------------------------------------------------
	# POST actionの呼び出し
	#-------------------------------------------------------------
	my $action = $ROBJ->{Form}->{action};
	if ($ROBJ->{POST} && (my ($dir,$file) = $self->parse_skel($action))) {
		local($self->{skel_dir}) = $dir;
		$self->{action_data} = $ROBJ->call( "${dir}_action/$file" );
	}

	#-------------------------------------------------------------
	# スケルトン呼び出し（出力）
	#-------------------------------------------------------------
	$self->output_html();
}

###############################################################################
# ■メイン処理ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●Cookie と Authorization 処理
#------------------------------------------------------------------------------
sub authorization {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	my $cookie = $ROBJ->get_cookie();
	my $session = $cookie->{session};
	if (ref $session eq 'HASH') {	# ログインセッション処理
		$auth->session_auth($session->{id}, $session->{sid});
		$ROBJ->make_csrf_check_key($session->{sid});
	}
	# 管理者 trust mode 設定
	if ($self->{admin_trust_mode} && $auth->{isadmin}) {
		$self->{trust_mode} = 1;
	}
}

#------------------------------------------------------------------------------
# ●Query/Form処理
#------------------------------------------------------------------------------
sub read_query_form {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	$ROBJ->read_form();
	my $query = $ENV{QUERY_STRING};
	my $q = $ROBJ->read_query({'t'=>1});	# t= をarray扱い
	if ($query ne '') {
		$self->{query} = $query;
		$query =~ m|^([\w/]+)|;
		$self->{query0} = exists($q->{q}) ? '' : $1;	# 検索Queryをスケルトン指定と誤解しないため
	}
}

#------------------------------------------------------------------------------
# ●pinfoとブログ選択処理
#------------------------------------------------------------------------------
sub blogid_and_pinfo {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $myself  = $ROBJ->{Myself};
	my $myself2 = $ROBJ->{Myself2};
	my @pinfo   = @{ $ROBJ->read_path_info() };	# PATH_INFO

	# URLなど基本設定
	my $authid  = $ROBJ->{Auth}->{id};
	my $pinfoid = exists($pinfo[1]) ? $pinfo[0] : ''; # 'bloid/'のように'/'付のみ有効
	my $blogid;
	my $default = $self->{sys}->{default_blogid};
	my $selected;

	if ($default) {
		#-----------------------------------------------
		# デフォルトブログモード
		#-----------------------------------------------
		if ($pinfoid =~ /^[a-z][a-z0-9_]*$/ && $pinfoid ne $default && $self->find_blog($pinfoid)
		 && ($selected = $self->set_and_select_blog($pinfoid)) ) {
			shift(@pinfo);
			$blogid = $pinfoid;
		} else {
			$blogid = $default;
		}
		# 自分のブログ
		$self->{myself3} = ($authid eq $default) ? $myself : "$myself2$authid/";

	} elsif ($self->{subdomain_mode}) {
		#-----------------------------------------------
		# サブドメインモード
		#-----------------------------------------------
		my $host_name = $ENV{SERVER_NAME};
		$host_name =~ s/[^\w\.\-]//g;
		my $domain = $self->{subdomain_mode};
		if (! $self->{subdomain_secure}) {	# Cookieを全ドメインで共通化
			$ROBJ->{Cookie_domain} = $domain;
		}
		if ((my $x = index($host_name, ".$domain")) > 0) {
			$blogid = substr($host_name, 0, $x);
		} else {
			$blogid = shift(@pinfo);
			$blogid =~ s/\W//g;
			if ($blogid ne '') {
				$ROBJ->redirect("http://$blogid.$domain/" . join('/', @pinfo));
			}
		}
		$self->{myself3} = "http://$authid.$domain/";	# 自分のブログ
	} else {
		#-----------------------------------------------
		# マルチユーザーモード
		#-----------------------------------------------
		shift(@pinfo);
		$blogid = $pinfoid;
		$blogid =~ s/\W//g;
		my $add_myself3;
		if ($default ne $authid) { $add_myself3 = "$authid/"; }
		$self->{myself3} = $myself2 . $add_myself3;	# 自分のブログ
	}
	# 未設定ならブログを選択 ※$blogidが未設定でも選択すること
	if (!$selected) { $self->set_and_select_blog( $blogid ); }

	# テーマの設定
	my $theme = $self->{blog}->{theme};
	if (!$theme || $self->load_theme($theme)) {
		$self->load_theme( $self->{default_theme} );
	}

	# pinfoの保存
	my $pinfo = join('/', @pinfo);
	$self->{pinfo}   = $pinfo;
	$ROBJ->encode_uri( $pinfo );
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

#------------------------------------------------------------------------------
# ●スケルトン選択（theme.htmlからも呼び出される）
#------------------------------------------------------------------------------
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
	if ($mode eq '' && !$self->{path_blogid}) {
		return $self->{top_skeleton};
	} elsif ($mode ne '' && $mode !~ /^[1-9]\d+$/ || $mode eq '' && $self->{query} eq '' && $self->{blog}->{frontpage}) {
		return $self->{article_skeleton};
	}
	return $self->{main_skeleton};
}

#------------------------------------------------------------------------------
# ●HTMLの生成と出力
#------------------------------------------------------------------------------
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

	# mainフレームあり？
	my $frame_name = $self->{frame_skeleton};
	if ($frame_name ne '') {
		# 外フレームを処理する
		$out = $ROBJ->call($frame_name, $out);
	}

	if (!$self->{output_stop}) {
		$ROBJ->print_http_headers();
		$ROBJ->output_array($out);	# HTML出力
	}
}

###############################################################################
# ■ブログの存在確認と設定ロード
###############################################################################
#------------------------------------------------------------------------------
# ●ブログの存在確認	※キュッシュ仕様を変更したら blog_create/blog_drop も変更すること!!
#------------------------------------------------------------------------------
sub find_blog {
	my $self = shift;
	my $blogid = shift;
	if ($blogid =~ /\W/) { return ; }

	if(exists $self->{_cache_find_blog}->{$blogid}) {
		return $self->{_cache_find_blog}->{$blogid};
	}
	return ($self->{_cache_find_blog}->{$blogid} = $self->{DB}->find_table("${blogid}_art"));
}

#------------------------------------------------------------------------------
# ●ブログの設定ロード
#------------------------------------------------------------------------------
# ※書き換えは瞬時に反映され、$blog->{_update}=1 ならばプログラム終了時に保存される。
sub load_blogset {
	my ($self, $blogid) = @_;	# * = default
	my $ROBJ = $self->{ROBJ};
	if ($self->{'_loaded_bset'}->{$blogid}) { return $self->{'_loaded_bset'}->{$blogid}; }
	if ($blogid ne '*' && !$self->find_blog($blogid)) { return undef; }

	my $file = $self->blog_dir($blogid) . 'setting.dat';
	if ($blogid eq '*' || !-e $file) {
		$file = $ROBJ->get_filepath($self->{my_default_setting_file});
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

#------------------------------------------------------------------------------
# ●ブログの権限と初期設定
#------------------------------------------------------------------------------
# ブログを選択し、内部変数に権限を設定する。
# ブログがみつからないか閲覧できないときは undef が返る
sub set_and_select_blog {
	my ($self, $blogid, $force) = @_;
	my $ROBJ = $self->{ROBJ};
	# myself設定
	$self->{myself}  = $ROBJ->{Myself};
	$self->{myself2} = $ROBJ->{Myself2};
	if (!$force && $self->{blogid} eq $blogid) { return $self->{blog}; }

	# 内部変数初期化
	$self->{blogid} = undef;
	$self->{blog}   = undef;
	$self->{allow_edit} = undef;
	$self->{allow_com}  = undef;
	$self->{blog_admin} = undef;
	$self->{blog_dir}    = undef;
	$self->{blogpub_dir} = undef;

	# スケルトン登録の削除
	$ROBJ->delete_skeleton($self->{user_skeleton_level});

	# blogid の設定
	if ($blogid eq '') { return; }				# 内部変数初期化時に使用
	my $blog = $self->load_blogset( $blogid );
	if (!$blog || !%$blog || $blogid eq '*') { return; }	# blogidが存在しない

	# 権限設定
	my $view_ok = $self->set_blog_permission($self, $blog);
	if (!$view_ok) { return; }	# プライベートモードのブログの閲覧権限がない

	# ブログ情報設定
	$self->{blogid} = $blogid;
	$self->{blog}   = $blog;
	$self->{blog_dir}    = $self->blog_dir();
	$self->{blogpub_dir} = $self->blogpub_dir();

	# myself(通常用,QUERY用)、myself2(PATH_INFO用) の設定
	if ($self->{subdomain_mode}) {
		$self->{server_url} = ($self->{subdomain_proto} ? $self->{subdomain_proto} : 'http://') . $blogid . '.' . $self->{subdomain_mode};
		$self->{myself}  = '/';
		$self->{myself2} = '/';	
	} elsif ($blogid ne $self->{sys}->{default_blogid}) {
		$self->{myself}  = $ROBJ->{Myself2} . "$blogid/";
		$self->{myself2} = $ROBJ->{Myself2} . "$blogid/";
	}

	# ブログ個別スケルトンの登録（プラグイン等で生成される）
	if (!$self->{stop_all_plugins}) {
		$ROBJ->regist_skeleton($self->{blog_dir} . 'skel/', $self->{user_skeleton_level});
	}

	# 日付変更時間の設定（元日とエイプリルフールは日付変更時間を無視）
	my $now = $ROBJ->{Now};
	my $change_hour = (($now->{mon}==1 || $now->{mon}==4) && $now->{day}==1) ? 0 : $blog->{change_hour_int};
	$ROBJ->{Change_hour} = $change_hour;
	$self->{now} = $change_hour ? $ROBJ->time2timehash( $ROBJ->{TM} ) : $ROBJ->{Now};

	return $blog;
}

#------------------------------------------------------------------------------
# ●ブログの権限設定
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●ブログの設定保存	※Finish()から呼ばれる
#------------------------------------------------------------------------------
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

###############################################################################
# ■スケルトン用サブルーチン
############################################################################### 
#------------------------------------------------------------------------------
# ●システムモードへ
#------------------------------------------------------------------------------
sub system_mode {
	my ($self, $title, $mode_class) = @_;
	my $ROBJ = $self->{ROBJ};
	$self->{system_mode} = 1;
	if ($title ne '') { $self->{title} = $title; }
	if ($mode_class ne '') { $self->{mode_class} = ' ' . $mode_class; }

	if ($self->{blog}->{sysmode_notheme}){
		# デフォルトテーマの選択
		$self->load_theme( $self->{default_theme} );
	}
}

#------------------------------------------------------------------------------
# ●記事の読み込み
#------------------------------------------------------------------------------
sub load_articles_current_blog {
	my ($self, $mode, $query, $opt) = @_;
	my $blog = $self->{blog};

	$opt->{pagemode}=1;
	$opt->{loads} = $blog->{load_items};
	$opt->{blog_only} = $blog->{separate_blog};

	if ($self->{allow_edit}) {
		$opt->{load_hidden} = 1;
	}
	return $self->load_articles($self->{blogid}, $mode, $query, $opt);
}

#------------------------------------------------------------------------------
# ●単一記事のロード
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●記事のロード
#------------------------------------------------------------------------------
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
#
sub load_articles {
	my ($self, $blogid, $mode, $query, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $blog = $self->load_blogset( $blogid );
	if (! $blog) { return []; }

	#---------------------------------------------------------------
	# ●モードセレクタ
	#---------------------------------------------------------------
	my $loads = int($opt->{loads}) || 5;

	my %q;		# DB-query
	my %ret;	# 戻り値
	#---------------------------------------------------------------
	# 記事pkey
	#---------------------------------------------------------------
	if ($mode =~ /^0(\d+)$/) {
		$ret{mode} = 'pkey';

		$q{match} = {pkey => int($1)};
		$q{limit} = 1;

	#---------------------------------------------------------------
	# 年月日指定 / YYYYMMDD
	#---------------------------------------------------------------
	} elsif ($mode =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
		$ret{mode} = 'day';

		my $err = $self->check_date($1, $2, $3);
		if ($err ne '') {
			$ROBJ->message($err);
			return [];
		}
		$ret{year} = $1;
		$ret{mon}  = $2;
		$ret{day}  = $3;

		$q{match}    = {yyyymmdd => $mode};
		$q{sort}     = 'tm';
		$q{sort_rev} = 0;

	#---------------------------------------------------------------
	# tm指定
	#---------------------------------------------------------------
	} elsif ($mode =~ /^(\d{9,})$/) {
		$ret{mode} = 'day';

		$q{match}    = {tm => $1};
		$q{sort}     = 'pkey';
		$q{sort_rev} = 0;

	#---------------------------------------------------------------
	# Query
	#---------------------------------------------------------------
	} elsif ($mode =~ /^(\d\d\d\d)(\d\d)?$/ || $query->{t} || $query->{q} !~ /^\s*$/) {
		$ret{mode} = 'search';

		# 年月指定 / YYYYMM
		if ($mode =~ /^(\d\d\d\d)(\d\d)?$/) {
			if ($2) {
				my $err = $self->check_date($1, $2);
				if ($err ne '') {
					$ROBJ->message($err);
					return [];
				}
			}
			$ret{yyyymm} = $mode;
			$ret{year} = $1;
			$ret{mon}  = $2;

			if ($2) {
				$q{min} = {yyyymmdd => "$1${2}01"};
				$q{max} = {yyyymmdd => "$1${2}31"};
			} else {
				$q{min} = {yyyymmdd => "${1}0101"};
				$q{max} = {yyyymmdd => "${1}1231"};
			}
		}

		# タグの指定
		if ($query->{t}) {
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
			}
			if (%t) {
				$ret{t} = \@tags_txt;
			}
			if (%arts) {
				my $c = @$tags;		# 指定されたタグの数
				my @ary = grep { $arts{$_} == $c } keys(%arts);
				$q{match}->{pkey} = @ary ? \@ary : [-1];
			}
		}

		#--------------------------------------
		# 記事の検索
		#--------------------------------------
		if ($query->{q} !~ /^\s*$/) {
			my $q = $query->{q};
			my @buf;
			$q =~ s!"([^"]+)"!
				push(@buf, $1);
				" \x04[$#buf] ";
			!eg;
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
			$q{search_cols}  = $query->{all} ? ['title','_text'] : ['title'];

			$q =~ s/\x04\[(\d+)\]/"$buf[$1]"/g;
			$ROBJ->tag_escape( $q );
			$ret{q} = $q;
			$ret{words} = \@words;
		}

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;
		$ret{pagemode} = 1;
		$ret{narrow} = 1;	# 絞り込み

	#---------------------------------------------------------------
	# コンテンツ指定
	#---------------------------------------------------------------
	} elsif ($mode =~ /^[^&]/) {	# wiki的指定
		$ret{mode} = 'wiki';
		$q{match} = {link_key => $mode};

	#---------------------------------------------------------------
	# 指定なし（最近 n 件）
	#---------------------------------------------------------------
	} else {
		$ret{mode} = '';
		$ret{pagemode} = 1;

		$q{sort}     = ['yyyymmdd', 'tm'];
		$q{sort_rev} = [1, 1];
		$q{limit}    = $loads;
	}

	#---------------------------------------------------------------
	# ●ロード対象
	#---------------------------------------------------------------
	$q{flag}={};
	if (!$opt->{load_hidden}) {
		$q{flag}->{enable} = 1;
	}
	if (!$opt->{load_draft}) {
		$q{not_null} = ['tm'];
	}
	if ($opt->{blog_only}) {
		$q{match}->{ctype} = '';
	}

	#---------------------------------------------------------------
	# ●データのロード
	#---------------------------------------------------------------
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
			my %tags;
			my %year;
			my %mon;
			foreach(@$all) {
				my $ymd = $_->{yyyymmdd};
				$year{ substr($ymd,0,4) }++;
				$mon { substr($ymd,0,6) }++;
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
			}
			foreach(keys(%tags)) {
				if ($tags{$_} == $hits) { delete $tags{$_}; }
			}
			foreach(keys(%year)) {
				if ($year{$_} == $hits) { delete $year{$_}; }
			}
			foreach(keys(%mon)) {
				if ($mon{$_} == $hits) { delete $mon{$_}; }
			}
			my %ymd = %year ? %year : %mon;
			if (%tags) { $ret{narrow_tags} = \%tags; $tags{_order} = [ sort(keys(%tags)) ]; }
			if (%ymd)  { $ret{narrow_ymd}  = \%ymd;  $ymd {_order} = [ sort(keys( %ymd)) ]; }
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

	#---------------------------------------------------------------
	# ●ページ送り処理
	#---------------------------------------------------------------
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

	#---------------------------------------------------------------
	# フラグのオーバーライド確認
	#---------------------------------------------------------------
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

	#---------------------------------------------------------------
	# 記事データの前処理
	#---------------------------------------------------------------
	foreach(@$logs) {
		$self->post_process_article( $_, $opt );
	}

	#---------------------------------------------------------------
	# 記事指定時の日付処理
	#---------------------------------------------------------------
	if ($logs->[0] && ($ret{mode} eq 'pkey' || $ret{mode} eq 'wiki')) {
		$ret{year} = $logs->[0]->{year};
		$ret{mon}  = $logs->[0]->{mon};
		$ret{day}  = $logs->[0]->{day};
	}
	if ($logs->[0] && $ret{mode} eq 'search' && $ret{year} && !$ret{day}) {
		$ret{mon}  = $logs->[0]->{mon};
	}

	return wantarray ? ($logs, \%ret) : $logs;
}

#------------------------------------------------------------------------------
# ●１件の記事データの加工（後処理）
#------------------------------------------------------------------------------
sub post_process_article {
	my $self = shift;
	my ($dat, $opt) = @_;
	my $ROBJ = $self->{ROBJ};

	my $yyyymmdd = $dat->{yyyymmdd};
	my $year = $dat->{year} = substr($yyyymmdd, 0, 4);
	my $mon  = $dat->{mon}  = substr($yyyymmdd, 4, 2);
	my $day  = $dat->{day}  = substr($yyyymmdd, 6, 2);

	# wiki関連
	my $key = $dat->{link_key};
	if ($key ne "0$dat->{pkey}") { $dat->{wiki}=1; }
	$dat->{elink_key} = $key;
	$self->link_key_encode( $dat->{elink_key} );

	# 下書き?
	$dat->{draft} = $dat->{tm} ? 0 : 1;

	# 曜日の取得
	$dat->{wday} = $self->get_dayweek($dat->{year}, $dat->{mon}, $dat->{day});
	$dat->{wday_name}  = $ROBJ->{WDAY_name}->[ $dat->{wday} ];
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

#------------------------------------------------------------------------------
# ●コメントのロードと加工
#------------------------------------------------------------------------------
# $a_pkey の代わりに記事のデータ（ハッシュ）を与えたほうが高速
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
	my $c = $self->load_comments($self->{blogid}, $a_pkey, $opt);

	# >>44とかのリンクを有効に
	if (!$opt->{link_stop}) {
		foreach(@$c) {
			$_->{text} =~ s|&gt;&gt;(\d+)|<a href="#c$1" data-reply="$1">&gt;&gt;$1</a>|g;
		}
	}
	return $c;
}

#------------------------------------------------------------------------------
# ●コメントのロード
#------------------------------------------------------------------------------
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
	$h{sort}  = 'tm';
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


###############################################################################
# ■プラグインシステム
###############################################################################
#------------------------------------------------------------------------------
# ●指定したイベントを呼び出す
#------------------------------------------------------------------------------
sub call_event {
	my $self = shift;
	my $evt_name = shift;	# イベント名
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	if (!$blog) { return 0; }
	if ($evt_name eq '') {
		$ROBJ->message('"event name" is null.');
		return -99;
	}

	my $evt    = $self->{stop_all_plugins} ? '' : $blog->{"event:$evt_name"};
	my $sysevt = $SysEvt{$evt_name} || [];
	if (!$evt && !@$sysevt) { return 0; }

	my $ret=0;
	$evt_name =~ s/^([^:]*):.*$/$1/;	# : 以降を除去
	local($self->{event_name}) = $evt_name;
	foreach(@$sysevt,split(/\r?\n/, $evt)) {
		# plugin_name=(value)
		my $x = index($_, '=');
		if ($x == -1) {
			# system 設定のイベント処理
			my $r = $self->$_(@_);
			$ret += $r ? 1 : 0;
			next;
		}

		# プラグインによるイベント処理
		my $v = substr($_, $x+1);
		my $name = substr($_, 0, $x);

		my $r;
		if ($v =~ m|^func/([\w\-]+\.pm)$|) {
			# ファイルをロードして無名ルーチンを呼び出す
			$r = $self->call_plugin_function($1, $name, @_);
		} elsif ($v =~ m|^skel/([\w/-]+)\.[\w-]+$|) {
			# スケルトンファイルを呼び出す
			$r = $ROBJ->call($1, $name, @_);
		} else {
			$ROBJ->error("[plugin=%s] Unknown method : %s", $name, $v);
			$r = -1;
		}
		# 結果の保存
		$self->{return}->{$name} = $r;
		$ret += $r ? 1 : 0;
	}
	return $ret;
}

#------------------------------------------------------------------------------
# ●プラグインファイルをロードして無名ルーチンを呼び出す
#------------------------------------------------------------------------------
sub call_plugin_function {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $ROBJ->get_filepath($self->{blog_dir} . "func/$name");
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

#------------------------------------------------------------------------------
# ●プラグインのロードとコンパイル（キャッシュ付）
#------------------------------------------------------------------------------
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
	sysopen($fh, $file, Fcntl::O_RDONLY);
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

#------------------------------------------------------------------------------
# ●JavaScriptプラグインをロード
#------------------------------------------------------------------------------
sub load_js_events {
	my $self = shift;
	if (!$self->{blog}) { return []; }
	if ($self->{stop_all_plugins}) { return []; }

	my $evt = $self->{blog}->{'event:JS'};
	my $dir = $self->{blogpub_dir};

	my @ary;
	foreach(split("\n", $evt)) {
		my ($name, $file) = $self->split_equal($_);
		if (!$name) { next; }
		if (substr($file,0,3) ne 'js/') {
			$self->{ROBJ}->error("[plugin=%s] JS event error : %s", $name, $file);
			next;
		}
		push(@ary, "$dir$file");
	}
	return \@ary;
}

#------------------------------------------------------------------------------
# ●プラグイン用の設定をロード
#------------------------------------------------------------------------------
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

###############################################################################
# ■システム情報 / ブログ情報の管理
###############################################################################
#------------------------------------------------------------------------------
# ●システムdatをロードする
#------------------------------------------------------------------------------
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
	return $sys;
}

#------------------------------------------------------------------------------
# ●システムdatを更新する
#------------------------------------------------------------------------------
sub update_sysdat {
	my $self = shift;
	my ($k, $v) = @_;
	if (ref($k)) {
		foreach(keys(%$k)) {
			$self->{sys}->{$_}=$k->{$_};
		}
	} elsif ($k ne '') {
		$self->{sys}->{$k}=$v;
	}
	$self->{sys}->{_update}=1;
}

#------------------------------------------------------------------------------
# ●システムdatを保存する	※Finish()から呼ばれる
#------------------------------------------------------------------------------
sub save_sysdat {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $sys = $self->{sys};
	if (! $sys->{_update}) { return 0; }
	delete $sys->{_update};
	$ROBJ->fwrite_hash($self->{system_config_file}, $sys);
}

#------------------------------------------------------------------------------
# ●タグデータのロード
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（ブログ記事）
#------------------------------------------------------------------------------
sub load_art_node {
	my ($self, $pkey) = @_;
	my $con = $self->load_arts_cache( $pkey );
	my %c = %{ $con->{$pkey} || {} };
	$c{prev} = $con->{ $c{prev} };
	$c{next} = $con->{ $c{next} };
	return \%c;
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
		my @a=split("\t", $_);
		$h{$a[0]} = { pkey=>$a[0], prev=>$a[1], next=>$a[2], title=>$a[3] };
	}
	return \%h;
}

#------------------------------------------------------------------------------
# ●記事情報キャッシュのロード（コンテンツ）
#------------------------------------------------------------------------------
sub load_content_node {
	my ($self, $pkey) = @_;
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
			$c{family} = [ grep {$_->{pkey} != $pkey} @fam ];
		}
	}
	return \%c;
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

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●blog_dirを取得
#------------------------------------------------------------------------------
sub blog_dir {
	my ($self, $blogid) = @_;
	$blogid ||= $self->{blogid};
	$blogid =~ s/\W//;
	return ($self->{ROBJ}->get_filepath("$self->{data_dir}blog/$blogid/"));
}
sub blogpub_dir {
	my ($self, $blogid) = @_;
	$blogid ||= $self->{blogid};
	$blogid =~ s/\W//;
	my $blog = $self->load_blogset($blogid);
	my $postfix = $blog ? $blog->{blogpub_dir_postfix} : '';
	return ($self->{ROBJ}->get_filepath("$self->{pub_dir}$blogid$postfix/"));
}
sub blogimg_dir {
	my $self = shift;
	return $self->{blogpub_dir} . 'image/';
}

#------------------------------------------------------------------------------
# ●指定したblogidのURLを取得
#------------------------------------------------------------------------------
sub get_blog_path {
	my ($self, $blogid) = @_;
	my $ROBJ = $self->{ROBJ};
	$blogid =~ s/[^\w\-]//g;
	if ($self->{subdomain_mode}) {
		my $url = "http://$blogid\.$self->{subdomain_mode}";
		return $ROBJ->{Server_url} eq $url ? '/' : "$url/";
	}
	my $myself2 = $ROBJ->{Myself2};
	return ($blogid eq $self->{sys}->{default_blogid}) ? $myself2
		: $myself2 . $blogid . '/';
}

#------------------------------------------------------------------------------
# ●skeleton dirを取得
#------------------------------------------------------------------------------
sub parse_skel {
	my ($self, $str) = @_;
	if ($str !~ m|^((?:[A-Za-z0-9]\w*/)*)([A-Za-z0-9]\w*)?$|) { return ; }
	my $b = ($1 ne '' && $2 eq '') ? 'index' : $2;
	return wantarray ? ($1,$b) : "$1$b";
}

#------------------------------------------------------------------------------
# ●テーマの選択
#------------------------------------------------------------------------------
sub load_theme {
	my ($self, $theme) = @_;
	if ($self->{theme} eq $theme) { return 0; }
	my $ROBJ = $self->{ROBJ};

	if ($theme !~ m|^([\w-]+)/([\w-]+)/?$| ) { return -1; }	# error
	my $theme = $2;
	my $dir = $ROBJ->get_filepath( $self->{theme_dir} . "$1/" );
	if (! -r "$dir$theme/$theme.css") { return 1; }		# not found

	# 内部変数に記録
	$self->{template} = $1;
	$self->{theme}    = $2;
	$self->{theme_js} = -r "$dir$theme/$theme.js";

	# スケルトンテンプレートの登録
	if (-r "${dir}_skel") {
		$ROBJ->regist_skeleton($dir, $self->{theme_skeleton_level});
	} else {
		$ROBJ->delete_skeleton($self->{theme_skeleton_level});
	}
	return 0;
}

#------------------------------------------------------------------------------
# ●日付指定のチェック（確認処理）
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●指定月の日数取得
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# ●曜日の取得
#------------------------------------------------------------------------------
sub get_dayweek {
	my $self = shift;
	my ($y, $m, $d) = @_;
	if ($m < 3) { $y--; $m+=12; }
	return ($y + ($y>>2) - int($y/100) + int($y/400) + int((13*$m + 8)/5) + $d) % 7;
}

#------------------------------------------------------------------------------
# ●yyyymmdd文字列の加工
#------------------------------------------------------------------------------
sub format_ymd {
	my $self = shift;
	my $ymd  = shift;
	my $sep  = shift || '-';
	return substr($ymd,0,4) . $sep . substr($ymd,4,2). $sep . substr($ymd,6,2);
}

#------------------------------------------------------------------------------
# ●key=val表記を分離
#------------------------------------------------------------------------------
sub split_equal {
	my $self = shift;
	my $str  = shift;
	my $x = index($str, shift || '=');
	if ($x == -1) { return ; }
	my $k = substr($str, 0, $x);
	my $v = substr($str, $x+1);
	return ($k,$v);
}

#------------------------------------------------------------------------------
# ●モジュール名から、モジュール番号を分離
#------------------------------------------------------------------------------
sub split_number {
	my $self = shift;
	my $str = shift;
	$str =~ s/,(\d+)$//;
	return wantarray ? ($str,$1) : $str;
}

#------------------------------------------------------------------------------
# ●blog一覧を表示ok？
#------------------------------------------------------------------------------
sub allow_blogs {
	my $self  = shift;
	my $allow = $self->{sys}->{blogs_allow};
	if ($allow eq '') { return 1; }		# OK
	
	my $auth = $self->{ROBJ}->{Auth};
	if ($allow eq 'users') { return $auth->{ok}; }
	return $auth->{isadmin};	# $allow == 'admin'
}

#------------------------------------------------------------------------------
# ●link_keyエンコード
#------------------------------------------------------------------------------
sub link_key_encode {
	my $self = shift;
	my $fp = $self->{blog}->{frontpage};
	foreach(@_) {	# ここを修正したら adiary.js、contents_list.html も修正のこと
		if ($_ eq $fp) { $_=''; next; }
		$_ =~ s/([^\w!\(\)\*\-\.\~\/:;=&])/'%' . unpack('H2',$1)/eg;
		$_ =~ s|^/|.//|;
		# myself2が / のとき //lkey となって http://lkey と解釈されるのを防ぐ
	}
	return $_[0];
}

#------------------------------------------------------------------------------
# ●rssファイル取得
#------------------------------------------------------------------------------
sub load_rss_files {
	my $self = shift;
	return [ split(',', ($self->{blog} || {})->{rss_files}) ];
}

#------------------------------------------------------------------------------
# ●js/cssファイルの登録
#------------------------------------------------------------------------------
sub regist_js {
	my $self = shift;
	return $self->regist_jscss($self->{scripts}, @_);
}
sub regist_css {
	my $self = shift;
	return $self->regist_jscss($self->{cssfiles}, @_);
}
sub regist_jscss {
	my $self = shift;
	my $h = shift;
	my $num = keys(%$h);
	foreach(@_) { $h->{$_}=($num++); }
}
sub load_jscss {
	my $self = shift;
	my $h = shift;
	return [ sort { $h->{$a} <=> $h->{$b} } keys(%$h) ];
}

#------------------------------------------------------------------------------
# ●記事編集権限チェック
#------------------------------------------------------------------------------
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

1;
