use strict;
#-------------------------------------------------------------------------------
# adiary_4.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・ユーザー管理
# ・システム管理
# ・インポート、エクスポート
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
use SatsukiApp::adiary_4 ();
package SatsukiApp::adiary;
###############################################################################
# ■ユーザー管理
###############################################################################
#------------------------------------------------------------------------------
# ●ユーザー追加
#------------------------------------------------------------------------------
sub _ajax_user_add {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}

	$form->{id} = $form->{msys_id};
	delete $form->{msys_id};

	return $auth->user_add($form);
}

#------------------------------------------------------------------------------
# ●ユーザー編集
#------------------------------------------------------------------------------
sub _ajax_user_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}
	return $auth->user_edit($form);
}

#------------------------------------------------------------------------------
# ●ユーザー削除
#------------------------------------------------------------------------------
sub _ajax_user_delete {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	if (!$auth->{isadmin}) {
		return { ret=>1, msg => $ROBJ->translate('Operation not permitted') };
	}
	return $auth->user_delete($form->{id} || $form->{id_ary});
}

#------------------------------------------------------------------------------
# ●ユーザー自身によるパスワード, ユーザー名の変更
#------------------------------------------------------------------------------
sub _ajax_self_change_name {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	return $auth->change_user_info(@_);
}
sub _ajax_self_change_pass {
	my $self = shift;
	my $auth = $self->{ROBJ}->{Auth};
	return $auth->change_pass(@_);
}

###############################################################################
# ■ブログの作成と削除
###############################################################################
#------------------------------------------------------------------------------
# ●ブログを作る
#------------------------------------------------------------------------------
sub blog_create {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	my $id   = shift;
	my $opt  = shift;
	my $copy_id = $opt->{copy_id};

	if (! $auth->{ok}) { $ROBJ->message('Not login'); return 1; }
	if ($self->{sys}->{blog_create_root_only} && ! $auth->{isadmin}) {
		$ROBJ->message('Operation not permitted');
		return 5;
	}
	if (! $auth->{isadmin}) {
		$id = $auth->{id};
		$copy_id = undef;
	}
	if ($copy_id && !$self->find_blog($copy_id)) {
		$ROBJ->message("Can't find copy blog id '%s'", $copy_id);
		return 20;
	}
	# blogidの確認
	if (! $auth->{isadmin}) {
		$id = $auth->{id};
	} elsif ($id =~ /[^a-z0-9_]/ || $id !~ /^[a-z]/) {
		$ROBJ->message("Can't allow character used");
		return 9;
	}
	if ($self->find_blog($id)) {
		$ROBJ->message('Blog `%s` already existed',$id);
		return 10;
	}

	# データベーステーブル生成
	my $r = $self->create_tables($id);
	if ($r) {
		$ROBJ->message('Blog create failed');
		$self->drop_tables($id);
	} else {
		# ディレクトリの作成
		$ROBJ->mkdir( "$self->{data_dir}blog/" );
		if (!$copy_id) {
			$ROBJ->mkdir( $self->blog_dir   ( $id ) );
			$ROBJ->mkdir( $self->blogpub_dir( $id ) );
		}
		# キャッシュ除去
		delete $self->{_cache_find_blog}->{$id};
	}

	if ($r || !$copy_id) { return $r; }

	# ブログデータのコピー
	$ROBJ->dir_copy( $self->blog_dir   ( $copy_id ), $self->blog_dir   ( $id ) );
	$ROBJ->dir_copy( $self->blogpub_dir( $copy_id ), $self->blogpub_dir( $id ) );

	# データコピーはプラグインインストール後に
	my $current = $self->{blogid};
	my $blog    = $self->set_and_select_blog( $id );
	if ($blog->{private}) {
		my $postfix = $self->change_blogpub_dir_postfix( $id );
		if ($postfix) {
			$self->update_blogset($blog, 'blogpub_dir_postfix', $postfix);
			$self->{blogpub_dir} = $self->blogpub_dir();
		}
	}
	
	# アルバム初期化
	if ($opt->{clear_image}) {
		my $imgdir = $self->blogimg_dir();
		$ROBJ->dir_delete($imgdir);
	}

	# 再構築
	$self->copy_tables($copy_id, $id);
	$self->save_blogset($blog, $id);
	$self->reinstall_plugins();
	$self->rebuild_blog();

	$self->set_and_select_blog_force( $current );
	return $r;
}

#------------------------------------------------------------------------------
# ●ブログの削除
#------------------------------------------------------------------------------
sub blog_drop {
	my ($self) = @_;
	my $ROBJ   = $self->{ROBJ};
	my $blogid = $self->{blogid};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $r = $self->drop_tables($blogid);
	if ($r) { $ROBJ->message('Blog delete failed'); return $r; }

	# 内部変数の初期化
	delete $self->{_cache_find_blog}->{$blogid};
	$self->set_and_select_blog('');

	# ユーザーディレクトリの消去
	$ROBJ->dir_delete($self->blog_dir   ($blogid));
	$ROBJ->dir_delete($self->blogpub_dir($blogid));

	return 0;
}

#------------------------------------------------------------------------------
# ●すべての記事の削除
#------------------------------------------------------------------------------
sub blog_clear {
	my ($self) = @_;
	my $ROBJ   = $self->{ROBJ};
	my $DB     = $self->{DB};
	my $blogid = $self->{blogid};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# テーブルから記事などの削除
	$DB->delete_match("${blogid}_com");
	$DB->delete_match("${blogid}_tagart");
	$DB->delete_match("${blogid}_tag");
	$DB->delete_match("${blogid}_art");

	# イベント処理
	$self->call_event('BLOG_CLEAR');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');

	return 0;
}

###############################################################################
# ■再構築機能
###############################################################################
#------------------------------------------------------------------------------
# ●ブログの全記事の再構築
#------------------------------------------------------------------------------
sub rebuild_blog {
	my $self = shift;
	my $opt  = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $blogid = $self->{blogid};

	# trust_mode解除処理
	my $t = $self->{trust_mode};
	local($self->{trust_mode}) = $t;
	if ($self->{admin_trust_mode} && $t) {
		my $auth = $ROBJ->{Auth};
		my $user = $auth->sudo('get_userinfo', $blogid);
		if ($user && !$user->{isadmin}) {
			$self->{trust_mode} = 0;
		}
	}

	my $arts = $opt->{logs} || $DB->select_match("${blogid}_art", '*cols', ['pkey', '_text', 'parser', 'yyyymmdd', 'tm', 'link_key']);
	my $filter = $opt->{filter};
	my %update;
	my $r=0;
	foreach(@$arts) {
		if ($filter && !&$filter($_)) { next; }		# rebuild filter

		my $parser_name = $_->{parser};
		if ($parser_name eq '') { next; }

		my $parser = $self->load_parser( $parser_name );
		if (! ref($parser)) {
			$ROBJ->message("Load parser '%s' failed", $parser);
			$r++;
			next;
		}
		# プリプロセッサはブログ環境で処理内容が異なることはないので
		# 再構築時は実行しない。

		# パース準備
		$self->post_process_link_key( $_ );
		$parser->{thisurl}  = $self->get_blog_path( $blogid ) . $_->{elink_key};
		$parser->{thispkey} = $_->{pkey};
		my ($text, $text_s) = $parser->parse( $_->{_text} );
		if ($text eq $text_s) { $text_s=""; }

		# 許可タグ以外の除去処理
		my $escape = $self->load_tag_escaper( 'article' );
		$text   = $escape->escape($text);
		$text_s = $escape->escape($text_s);

		# 値保存
		my %h;
		$h{text}   = $text;
		$h{text_s} = $text_s;	# 短いtext
		if ($opt->{logs}) {
			$h{_text} = $_->{_text};
		}
		# 記事概要の生成
		$self->set_description(\%h);

		$update{ $_->{pkey} } = \%h;
	}

	#-----------------------------------------------
	# DBに対するupdateを一気に発行する
	#-----------------------------------------------
	$DB->begin();
	foreach(keys(%update)) {
		$DB->update_match("${blogid}_art", $update{$_}, 'pkey', $_);
	}
	$r += $DB->commit();

	# タグ情報の再構築
	$self->tagart_rebuild();

	# イベント処理
	$self->call_event('BLOG_REBUILD');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');
	return $r;
}

#------------------------------------------------------------------------------
# ●付加情報の再生成
#------------------------------------------------------------------------------
sub blog_info_rebuild {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if (!$self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# タグ情報の再構築
	$self->tagart_rebuild();

	# イベント処理
	$self->call_event('BLOG_INFO_REBUILD');
	$self->call_event('ARTICLE_STATE_CHANGE');
	$self->call_event('COMMENT_STATE_CHANGE');
	$self->call_event('ARTCOM_STATE_CHANGE');
	return 0;
}

#------------------------------------------------------------------------------
# ●全タグ情報の再生成
#------------------------------------------------------------------------------
sub tagart_rebuild {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (!$self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $blogid = $self->{blogid};
	my $ary = $DB->select_match("${blogid}_art",
			'*cols', ['pkey', 'enable', 'tags']
		);

	$DB->begin();
	$DB->delete_match("${blogid}_tagart");
	foreach my $art (@$ary) {
		my $tag = $art->{tags};
		if ($tag eq '') { next; }

		my $pkeys = $self->regist_tags($blogid, [split(',', $tag)]);
		$pkeys = ref($pkeys) ? $pkeys : [];
		foreach(@$pkeys) {
			$DB->insert("${blogid}_tagart", {
				'a_pkey'   => $art->{pkey},
				'a_enable' => $art->{enable},
				't_pkey'   => $_
			});
		}
	}
	$DB->commit();
}

###############################################################################
# ■プラグイン/デザイン関連
###############################################################################
#------------------------------------------------------------------------------
# ●全プラグインの再インストール
#------------------------------------------------------------------------------
sub reinstall_plugins {
	my $self = shift;
	my $pd = $self->load_plugins_dat();

	my $r1 = $self->reinstall_normal_plugins($pd);
	my $r2 = $self->reinstall_design_plugins($pd);
	return ($r1 || $r2);
}
#------------------------------------------------------------------------------
# ●通常プラグインの再インストール
#------------------------------------------------------------------------------
sub reinstall_normal_plugins {
	my $self = shift;
	my $pd   = shift;
	my $plgs = $self->load_plugins_info();

	my %h;
	foreach(@$plgs) {
		$h{ $_->{name} } = 0;	# uninstall
	}
	$self->save_use_plugins(\%h);
	foreach(@$plgs) {
		$h{ $_->{name} } = $pd->{ $_->{name} } ? 1 : 0;	# reinstall
	}
	return $self->save_use_plugins(\%h);
}

#------------------------------------------------------------------------------
# ●デザインモジュールの再インストール
#------------------------------------------------------------------------------
sub reinstall_design_plugins {
	my $self = shift;
	my $pd   = shift;
	my $ROBJ = $self->{ROBJ};
	my $plgs = $self->load_plugins_info();

	# デザインモジュールの現在の状態をロードしておく
	my $des = $self->load_design_info();
	if (! %$des) { return 0; }

	# reinistall
	my $h = $self->parse_design_dat( $des );
	if ($des->{version}<6) {
		$h->{save_ary} = [ '_sidebar', '_header' ];
		if (!$des->{header}) { return -1; }
	}
	if ($des->{version}<7) {
		$h->{mart_h_ary} = $h->{art_h_ary};
		$h->{mart_f_ary} = [ 'dea_com-count' ];
	}
	# uninstall
	$self->reset_design({no_event => 1});

	# dem_footer を無効にする
	$h->{main_b_ary} = [ grep {$_ ne 'dem_footer'} @{$h->{main_b_ary}} ];

	return $self->save_design($h);
}

#------------------------------------------------------------------------------
# ●設定の存在するプラグイン一覧
#------------------------------------------------------------------------------
sub get_plugins_setting {
	my $self = shift;
	my $set  = $self->{blog};
	my %p;
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\-]+(?:,\d+)?)/) { next; }
		$p{$1}=1;
	}
	return [ sort(keys(%p)) ];
}

#------------------------------------------------------------------------------
# ●設定の存在するプラグイン一覧
#------------------------------------------------------------------------------
sub reset_plugins {
	my $self = shift;
	my $ary  = shift || [];

	# delete setting
	my $set = $self->{blog};
	my %n   = map {$_ => 1} @$ary;
	my %del;
	foreach(keys(%$set)) {
		if ($_ !~ /^p:([\w\-]+(?:,\d+)?)/) { next; }
		if (!$n{$1}) { next; }
		$del{$1}=1;
		$self->update_blogset($set, $_, undef);
	}

	my $cnt=0;
	foreach(keys(%del)) {
		$self->reset_plugin_setting($_);
		$cnt++;
	}

	return wantarray ? (0, $cnt) : 0;
}

#------------------------------------------------------------------------------
# ●design.datの解析
#------------------------------------------------------------------------------
sub parse_design_dat {
	my $self = shift;
	my $dat  = shift;
	my %h;
	foreach(keys(%$dat)) {
		$h{"${_}_ary"} = [ split(/\n/, $dat->{$_}) ];
	}
	$h{version} = $dat->{version};
	return \%h;
}

#------------------------------------------------------------------------------
# ●テーマカスタム情報の再生成
#------------------------------------------------------------------------------
sub remake_theme_custom_css {
	my $self  = shift;
	my $theme = shift || $self->{blog}->{theme};
	my $ROBJ  = $self->{ROBJ};
	if (!$theme) { return 0; }

	my $file = $self->get_theme_custom_css($theme);
	if (!-r $file) { return 0; }	# カスタムファイルが無い

	# 再度書き換える
	my ($col,$opt,$css) = $self->load_theme_info( $theme, '' );
	if (!$css) { return; }

	my $ary = $self->css_rewrite($css, $col, $opt);
	$ROBJ->fwrite_lines($file, $ary);
	return 0;
}

###############################################################################
# ■全ブログに対する処理
###############################################################################
#------------------------------------------------------------------------------
# 全ブログの再構築
#------------------------------------------------------------------------------
sub rebuild_all_blogs {
	my $self = shift;
	return $self->do_all_blogs('rebuild_blog', @_);
}

#------------------------------------------------------------------------------
# 全ブログ付加情報の再構築
#------------------------------------------------------------------------------
sub rebuild_all_blogs_info {
	my $self = shift;
	return $self->do_all_blogs('blog_info_rebuild');
}

#------------------------------------------------------------------------------
# 全ブログの全プラグインを再インストール
#------------------------------------------------------------------------------
sub reinstall_all_plugins {
	my $self = shift;

	$self->{stop_plugin_install_msg} = 1;
	my $r = $self->do_all_blogs('reinstall_plugins');
	$self->{stop_plugin_install_msg} = 0;

	return $r;
}

#------------------------------------------------------------------------------
# 全ブログのカスタムCSS再設定
#------------------------------------------------------------------------------
sub remake_all_custom_css {
	my $self = shift;
	return $self->do_all_blogs('remake_theme_custom_css');
}

#------------------------------------------------------------------------------
# ●全ブログに対する処理
#------------------------------------------------------------------------------
sub do_all_blogs {
	my $self = shift;
	my $func = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (! $auth->{isadmin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $blogs = $self->load_all_blogid();
	my $cur_blogid = $self->{blogid};
	foreach(@$blogs) {
		$self->set_and_select_blog($_);
		if (ref($func)) {
			&$func($self, @_);
		} else {
			$self->$func(@_);
		}
	}
	$self->set_and_select_blog($cur_blogid);
	return 0;
}

#------------------------------------------------------------------------------
# ●全ブログidのロード
#------------------------------------------------------------------------------
sub load_all_blogid {
	my $self = shift;
	my $DB   = $self->{DB};
	my $blogs = $DB->select_match($self->{bloglist_table}, '*cols', 'id');
	$blogs = [ map { $_->{id} } @$blogs ];
	return $blogs;
}

###############################################################################
# ■HTMLキャッシュ処理
###############################################################################
my %CACHE;
my %CACHE_TM;
my $CACHE_cnt = 0;
#------------------------------------------------------------------------------
# ●cache処理
#------------------------------------------------------------------------------
sub regist_cache_checker {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($ROBJ->{cache_checker}) { return; }

	# クロージャ
	my $sys = $self->{sys};
	my $sysconf = $self->{system_config_file};
	my $systm   = $ROBJ->get_lastmodified( $sysconf );
	my $search_cache = $sys->{search_cache};
	my $cache_max    = $sys->{html_cache_max}     ||  16;
	my $timeout      = $sys->{html_cache_timeout} || 600;

	my $checker = sub {
		my $ROBJ = shift;
		$ROBJ->{cache_checker} = 1;

		# キャッシュクリア？
		if ($systm != $ROBJ->get_lastmodified( $sysconf )) {
			%CACHE = ();
			%CACHE_TM = ();
			$CACHE_cnt = 0;
			$ROBJ->regist_cache_cheker('');	# 自分自身を破棄
			return ;
		}

		if ($ENV{REQUEST_METHOD} ne 'GET' && $ENV{REQUEST_METHOD} ne 'HEAD') { return; }
		if (index($ENV{HTTP_COOKIE}, 'session=') >= 0) { return; }

		my $sphone = &{ \&sphone_checker }();
		my $key    = $sphone . $ENV{REQUEST_URI};
		my $query  = $ENV{QUERY_STRING};
		if (!$search_cache && $query ne '') { return; }
		if ($query !~ /^q=/ && $query =~ /^\w+/) { return; }

		# キャッシュ処理
		my $tm = $ROBJ->{TM};
		my $c = $CACHE{$key};
		$CACHE_TM{$key} = $tm;
		if ($c) {
			print $$c;
			$ROBJ->{Send} = length($$c);
		} else {
			$ROBJ->regist_html_cache($CACHE{$key} = \$c);
		}

		# キャッシュアウト処理を行うか？
		$CACHE_cnt++;
		if ($CACHE_cnt <16) { return $c; }
		$CACHE_cnt=0;

		# キャッシュアウト処理 (LRU)
		my @k = sort {$CACHE_TM{$b} <=> $CACHE_TM{$a}} keys(%CACHE_TM);
		my $max   = $cache_max;
		my $tmout = $tm - $timeout;
		foreach(@k) {
			if ($max-- > 0 && $CACHE_TM{$_} > $tmout) { next; }
			delete $CACHE_TM{$_};
			delete $CACHE{$_};
		}
		return $c;
	};
	$ROBJ->regist_cache_cheker( $checker );
}
#------------------------------------------------------------------------------
# ●cacheのクリア
#------------------------------------------------------------------------------
sub clear_cache {
	my $self = shift;
	$self->update_sysdat();		# cacheを飛ばす
}

###############################################################################
# ■データベースがらみサブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●ブログテーブルの作成
#------------------------------------------------------------------------------
sub create_tables {
	my ($self, $table) = @_;
	my $DB = $self->{DB};
	my $r=0;

  { # 記事テーブル
	my %info;
	$info{text}    = [ qw(title parser tags name id ip host agent link_key ctype main_image description) ];
	$info{ltext}   = [ qw(text text_s _text) ];
	$info{int}     = [ qw(yyyymmdd tm update_tm coms coms_all revision upnode priority) ];
	$info{flag}    = [ qw(enable com_ok hcom_ok) ];
	$info{idx}     = [ qw(name id link_key ctype upnode yyyymmdd tm update_tm coms coms_all enable priority) ];
	$info{idx_tdb} = [ qw(title tags) ];
	$info{unique}  = [ qw(link_key) ];
	$info{notnull} = [ qw(enable com_ok hcom_ok coms coms_all yyyymmdd link_key) ];
	$info{ref}     = { };	# upnode => "${table}_art.pkey" をすると記事が削除できなくなる
	$r = $DB->create_table_wrapper("${table}_art", \%info);
	if ($r) { return 100 + $r; }
  }

  { # タグテーブル
	my %info;
	$info{text}    = [ qw(name) ];
	$info{int}     = [ qw(qt upnode priority) ];
	$info{idx}     = [ qw(name qt upnode priority) ];
	$info{unique}  = [ qw(name) ];
	$info{notnull} = [ qw(name qt priority) ];
	$info{ref}     = { upnode => "${table}_tag.pkey" };
	$r = $DB->create_table_wrapper("${table}_tag", \%info);
	if ($r) { return 200 + $r; }
  }

  { # タグマッチングテーブル
	my %info;
	$info{int}     = [ qw(a_pkey t_pkey) ];
	$info{flag}    = [ qw(a_enable) ];
	$info{idx}     = [ qw(a_pkey t_pkey a_enable) ];
	$info{notnull} = [ qw(a_pkey t_pkey a_enable) ];
	$info{ref}     = { a_pkey => "${table}_art.pkey", t_pkey => "${table}_tag.pkey"  };
	$r = $DB->create_table_wrapper("${table}_tagart", \%info);
	if ($r) { return 300 + $r; }
  }

  { # コメントテーブル
	my %info;
	$info{text}    = [ qw(text email url name id ip host agent a_title a_elink_key) ];
	$info{int}     = [ qw(tm num a_pkey a_yyyymmdd) ];
	$info{flag}    = [ qw(enable hidden) ];
	$info{idx}     = [ qw(name id enable tm a_pkey) ];
	$info{idx_tdb} = [ qw(ip num a_yyyymmdd hidden) ];
	$info{unique}  = [ ];
	$info{notnull} = [ qw(enable hidden text tm a_pkey a_yyyymmdd) ];
	$info{ref}     = { a_pkey => "${table}_art.pkey" };
	$r = $DB->create_table_wrapper("${table}_com", \%info);
	if ($r) { return 800 + $r; }
  }

	# ブログリストに登録
	$self->insert_bloglist($table);

	return 0;
} # End of create_tanble

#------------------------------------------------------------------------------
# ●ブログテーブルの削除
#------------------------------------------------------------------------------
sub drop_tables {
	my ($self, $table) = @_;
	my $DB = $self->{DB};

	my $r = 0;	# blog_create の copy も変更するの忘れず
	$r += $DB->drop_table("${table}_com");
	$r += $DB->drop_table("${table}_tagart");
	$r += $DB->drop_table("${table}_tag");
	$r += $DB->drop_table("${table}_art");

	# ブログリストから削除
	$self->delete_bloglist($table);

	return $r;
}

#------------------------------------------------------------------------------
# ●ブログテーブルのコピー
#------------------------------------------------------------------------------
sub copy_tables {
	my ($self, $src, $des) = @_;
	my $DB = $self->{DB};

	my @tables = qw(_art _tag _tagart _com);
	$DB->begin();
	foreach my $table (@tables) {
		my $items = $DB->select("${src}$table");
		foreach(@$items) {
			$DB->insert("${des}$table", $_);
		}
	}
	$DB->commit();
}

###############################################################################
# ■ブログ管理テーブル
###############################################################################
#------------------------------------------------------------------------------
# ●ブログ管理テーブルへ追加
#------------------------------------------------------------------------------
sub insert_bloglist {
	my ($self, $blogid) = @_;
	my $DB = $self->{DB};

	if (!$DB->find_table($self->{bloglist_table})) {
		my $r = $self->create_bloglist_table();
		if ($r) { return 1; }		# error
	}

	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my %h;
	$h{tm}        = $ROBJ->{TM};
	$h{create_tm} = $ROBJ->{TM};
	$h{id}        = $blogid;

	# 初期値 = 0
	$h{arts}   = $h{coms}   = 0;
	$h{art_tm} = $h{com_tm} = 0;
	$h{private} = 0;

	# ディフォルトのブログ情報の取得
	my $blog = $self->load_blogset('*');
	$h{blog_name} = $blog->{blog_name};
	$h{private}   = $blog->{private};
	my $r  = $DB->insert($self->{bloglist_table}, \%h);

	if (!$r) { return 2; }
	return 0;		# 成功
}

#------------------------------------------------------------------------------
# ●ブログ管理テーブルから削除
#------------------------------------------------------------------------------
sub delete_bloglist {
	my ($self, $blogid) = @_;
	my $DB = $self->{DB};
	return $DB->delete_match($self->{bloglist_table}, 'id', $blogid);
}

#------------------------------------------------------------------------------
# ●ブログ管理テーブルの作成
#------------------------------------------------------------------------------
sub create_bloglist_table {
	my ($self) = @_;
	my $DB = $self->{DB};

	my %cols;
	$cols{text}    = [ qw(id blog_name newest_title) ];
	$cols{int}     = [ qw(arts coms art_tm com_tm tm create_tm) ];
	$cols{flag}    = [ qw(private) ];
	$cols{idx}     = [ qw(id arts coms art_tm com_tm tm private) ];
	$cols{unique}  = [ qw(id) ];
	$cols{notnull} = [ qw(id tm) ];
	return $DB->create_table_wrapper($self->{bloglist_table}, \%cols);
}

###############################################################################
# ■データインポータ
###############################################################################
sub art_import {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }
	my $blogid = $self->{blogid};

	#-------------------------------------------------------------
	# セッション開始
	#-------------------------------------------------------------
	my $session = $self->open_session( $form->{snum} );

	# データ形式
	my $type = $form->{type};
	$type =~ s/\W//g;
	my $importer;
	eval { $importer = $ROBJ->loadapp("adiary::Import$type"); };
	if ($@) {
		$ROBJ->message($@);
		$session->msg('Data type error (%s)', $type);
		return -1;
	}

	# ファイル選択チェック
	if (! ref($form->{file}) || ! $form->{file}->{size}) {
		$session->msg('Not selected file'); return -2;
	}
	$session->msg("Import file size: %f KB", int($form->{file}->{size}/1024 + 0.5));

	# ファイルがメモリになかったら読み込む
	if (!$form->{file}->{data}) {
		sysopen(my $fh, $form->{file}->{tmp}, O_RDONLY);
		sysread($fh, $form->{file}->{data}, $form->{file}->{size});
		close($fh);
	}

	# クラスオプション（$type:xxx=val を xxx=val として取り出す）
	my %opt;
	{
		my %h;
		foreach(keys(%$form)) {
			my $x = index($_,':');
			if ($x<0) {		# クラス表記を含まない
				$h{$_}=$opt{$_}=$form->{$_};
				next;
			}
			if (substr($_,0,$x) ne $type) { next; }
			my $y = substr($_,$x);
			$opt{$y} = $form->{$_};
			$h  {$y} = $form->{$_};
		}
		delete $h{file};
		delete $h{action};
		delete $h{ajax};
		delete $h{csrf_check_key};
		delete $h{class};
		foreach(sort(keys(%h))) {
			$session->say("[option] $_=$h{$_}");
		}
	}
	$form = 'undef';	# 間違って -> で参照しないように文字列を入れる

	# 付加タグとデフォルトタグをtrimしておく
	$ROBJ->trim( $opt{append_tags}, $opt{default_tags} );

	# キー重複チェック用
	{
		my $cols = ['pkey', 'link_key'];
		my $data = $DB->select("${blogid}_art", {cols => $cols});
		$opt{unique_pkeys} = { map { $_->{pkey}     => 1 } @$data };
	}

	#-------------------------------------------------------------
	# インポートの実行
	#-------------------------------------------------------------
	$opt{import_arts} = 0;
	$opt{find_arts}   = 0;
	$opt{a_pkeys} = [];
	$opt{c_pkeys} = [];
	# インポート時のupnode対応用
	$opt{pkey2pkey} = {};
	$opt{upnodes}   = [];

	$ROBJ->{Timer} && $ROBJ->{Timer}->start('import');
	my $tr = ! $opt{stop_transaction};	# トランザクションを使用し、高速処理
	if ($tr) {
		$session->say("[DB] BEGIN");
		$DB->begin();
	}
	my $r = $importer->import_arts($self, \%opt, $session);
	if ($r) {
		$session->msg("Error exit(%d)", $r);
		$session->close();
	}

	# upnode対応処理
	$self->import_build_tree($DB, $blogid, \%opt);

	if ($tr) {
		if ($DB->commit()) {
			$session->say("[DB] ROLLBACK");
			$opt{import_arts} = 0;	# インポート件数=0
		} else {
			$session->say("[DB] COMMIT");
		}
	}
	$session->msg("Import %d articles (find %d articles)", $opt{import_arts}, $opt{find_arts});

	#-------------------------------------------------------------
	# イベント処理
	#-------------------------------------------------------------
	if ($opt{import_arts}) {
		$self->import_events( \%opt );
	}

	#-------------------------------------------------------------
	# インポート終了
	#-------------------------------------------------------------
	$session->msg("Import finish");
	if ($ROBJ->{Timer}) {
		$session->msg("Import time %.2f sec", $ROBJ->{Timer}->stop('import'));
		$session->msg("Total time %.2f sec",  $ROBJ->{Timer}->check());
	}
	$session->close();

	return wantarray ? ($r, $opt{import_arts}) : $r;
}

sub import_build_tree {
	my $self = shift;
	my $DB   = shift;
	my $id   = shift;
	my $opt  = shift;
	my $p2p = $opt->{pkey2pkey};
	foreach(@{$opt->{upnodes}}) {
		my $pkey    = $_->{pkey};
		my $up_pkey = $p2p->{ $_->{upnode} };
		if ($up_pkey) {
			$DB->update_match("${id}_art", {upnode => $up_pkey}, 'pkey', $pkey);
		}
	}
}

sub import_events {
	my $self = shift;
	my $opt  = shift;
	$self->call_event('IMPORT_AFTER',         $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('ARTICLE_STATE_CHANGE', $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('COMMENT_STATE_CHANGE', $opt->{a_pkeys}, $opt->{c_pkeys});
	$self->call_event('ARTCOM_STATE_CHANGE' , $opt->{a_pkeys}, $opt->{c_pkeys});
}

#------------------------------------------------------------------------------
# ●記事を１件保存する
#------------------------------------------------------------------------------
# $self->save_article(\%art, \@coms, \@tbs, \%opt, $session);
# Ret:	0:成功  0以外:失敗
#
# $art->{enable}	1:表示許可 0:表示不可
# $art->{year}		1980～（年）
# $art->{mon}		1～12（月）
# $art->{day}		1～31（日）
# $art->{tm}		書き込み日時（UTC）
# $art->{tags}		タグ(「,」区切り）
# $art->{title}		タイトル
# $art->{name}		執筆者（$art->{author} ではないので注意）
# $art->{text}		記事本文（※必須）
# $art->{parser}	パーサー指定
#
# $art->{com_ok}	コメント受け付け
# $art->{hcom_ok}	非公開コメント受け付け
# $art->{allow_com}	※コメント受け付け（互換性のため）
# $art->{allow_hcom}	※非公開コメント受け付け（互換性のため）
#
# $art->{ctype}		コンテンツタイプ
# $art->{priority}	優先度, 重要度（整数値）
# $art->{upnode}	親記事
# $art->{link_key}	コンテンツキー
#
# $art->{ip}		IPアドレス
# $art->{host}		HOST名
# $art->{agent}		USER AGENT
#
#
# $c = $coms->[$n]	$n 番目の書き込み
# $c->{enable}		コメントが有効か？ 1:enable 0:disable（省略時:1）
# $c->{hidden}		非公開コメント？   1:非公開 0:公開   （省略時:0）
# $c->{name}		名前（※必須）
# $c->{text}		コメント本文（※必須） ※タグ無効、改行→<br>に変換される
# $c->{tm}		コメントが投稿された日時（UTC）
# $c->{email}		メールアドレス
# $c->{url}		URL
# $c->{ip}		IPアドレス(optional)
# $c->{host}		HOST名(optional)
# $c->{agent}		USER AGENT(optional)
#
#
# $tb=$tbs->[$n]	$n 番目のトラックバック
# $tb->{enable}		トラックバックが有効か？
# $tb->{blog_name}	トラックバック元のblog名
# $tb->{title}		トラックバックのタイトル
# $tb->{url}		トラックバック元URL（※必須）
# $tb->{tm}		TBが送信された日時（UTC）
# $tb->{author}		元記事の執筆者
# $tb->{excerpt}	概要  ※タグ無効
# $tb->{ip}		IPアドレス
# $tb->{host}		HOST名
# $tb->{agent}		USER AGENT
#
# ※タグを入力する必要のない（入力できない）カラムでは、
# 　&gt; &lt; &quot; を < > " に戻す必要はない。
#
sub save_article {
	my ($self, $art, $coms, $tbs, $opt, $session) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};

	my $blog   = $self->{blog};
	my $blogid = $self->{blogid};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	# コメントをインポートしない？
	if ($opt->{no_comment}) { $coms = []; }

	# トラックバックをコメントとしてインポート？
	if (!$opt->{tb_as_comment}) { $tbs = []; }

	# 記事発見数
	$opt->{find_arts}++;

	##############################################################
	# データ整形処理
	##############################################################
	my $now_tm = $ROBJ->{TM};
	$art->{parser} ||= 'default_p1';
	$art->{tm}     ||= $now_tm;
	$art->{name}   ||= $auth->{name};
	$art->{id}       = $auth->{id};

	# 投稿者を強制的に自分にする
	if ($opt->{force_author}) {
		$art->{name} = $auth->{name};
	}

	# タグを設定する
	if ($opt->{force_tag} || $art->{tags} eq '') {
		$art->{tags} = $opt->{default_tags};
	}
	# インポート記事付加タグ
	if ($opt->{append_tags}) {
		$art->{tags} = $art->{tags} eq '' ? $opt->{append_tags} : "$art->{tags},$opt->{append_tags}" ;
	}

	# コメントの投稿時刻
	foreach(@$coms) { $_->{tm} ||= $now_tm; }

	#-------------------------------------------------------------
	# 日付の確認
	#-------------------------------------------------------------
	{
		$art->{tm} = int( $art->{tm} );
		my $year = int( $art->{year} );
		my $mon  = int( $art->{mon}  );
		my $day  = int( $art->{day}  );
		my $err = $self->check_date($year, $mon, $day);
		if ($err ne '') {	# エラーあり
			my $h = $ROBJ->time2timehash( $art->{tm} );
			$art->{year} = $h->{year};
			$art->{mon}  = $h->{mon};
			$art->{day}  = $h->{day};
		}
	}

	#-------------------------------------------------------------
	# pkey, link_key の重複チェック
	#-------------------------------------------------------------
	my $pkey  = $opt->{save_pkey} && $art->{pkey};
	my $pkeys = $opt->{unique_pkeys};
	{
		my $ctype    = $art->{ctype};
		my $priority = int( $art->{priority} );
		my $upnode   = $art->{upnode};
		if ($priority && $ctype eq '') { $art->{ctype}=$ctype='wiki'; }

		# save pkey
		$pkey = ($pkey<1 || ($pkeys->{$pkey} && $opt->{avoid_pkey_collision})) ? 0 : $pkey;
		if ($pkey) {
			if ($pkeys->{$pkey}) {
				$session && $session->msg("'%s' is duplicate : %s", 'pkey', $pkey);
				return 10;
			}
			$pkeys->{$pkey}=1;
		}
	}

	#-------------------------------------------------------------
	# フラグチェック
	#-------------------------------------------------------------
	$art->{com_ok}  = defined $art->{com_ok}  ? $art->{com_ok}  : $art->{allow_com};
	$art->{hcom_ok} = defined $art->{hcom_ok} ? $art->{hcom_ok} : $art->{allow_hcom};

	my @flags = qw(enable com_ok hcom_ok);
	foreach(@flags) {
		if (!defined $art->{$_}) { $art->{$_} = $blog->{$_}; }
	}

	#-------------------------------------------------------------
	# 記事の書き込み処理
	#-------------------------------------------------------------
	{
		my %op;
		$op{save_pkey} = $pkey;
		$op{iha_default} = {
			ip    => $art->{ip},
			host  => $art->{host},
			agent => $art->{agent}
		};
		$op{tm} = $art->{tm};
		my $ret = $self->regist_article( $self->{blogid}, $art, \%op );
		if (!ref($ret)) {
			$session && $session->msg("Save article failed(%d) : %s", $ret, $art->{title} );
			return 11;
		}
		$pkey = $ret->{pkey};
		$pkeys->{ $pkey } = 1;
		push(@{ $opt->{a_pkeys} }, $pkey);

		# upnode対策用の処理
		if ($opt->{upnodes} && $ret->{ctype} && $art->{pkey}) {
			$opt->{pkey2pkey}->{ $art->{pkey}     } = $pkey;
			$opt->{pkey2pkey}->{ $art->{link_key} } = $pkey;
			push(@{$opt->{upnodes}}, {pkey=>$pkey, upnode=>$art->{upnode}});
		}

		# 書込済記事データに置き換える
		$art = $ret;
	}
	#-------------------------------------------------------------
	# 記事保存メッセージ
	#-------------------------------------------------------------
	$session && $session->msg("[import] %s", $art->{title});
	$opt->{import_arts}++;

	my %info;
	##############################################################
	# コメント、トラックバックの処理
	##############################################################
	#---------------------------------------------------
	# コメントとトラックバックを混ぜる
	#---------------------------------------------------
	my @ary = @$coms;
	foreach(@$tbs){
		$_->{_tb}=1;
		push(@ary, $_);
	}
	if (@$tbs) {
		# まぜた場合は時刻でソートする
		@ary = sort {$a->{tm} cmp $b->{tm}} @ary;
	}
	
	#---------------------------------------------------
	# 取り込み処理
	#---------------------------------------------------
	my $com_flag;
	foreach(@ary) {
		if ($_->{_tb}) {
			$_->{name} = $_->{author} ne '' ? $_->{author} : '(trackback)';
			my $text = '[Trackback]';
			if ($_->{title} ne '') {
				$text .= ' ' . $_->{title};
			}
			if ($_->{blog_name} ne '') {
				$text .= ' from ' . $_->{blog_name};
			}
			$_->{text} = $text . "\n\n" . $_->{excerpt};
		}
		# 公開設定処理
		$_->{enable} = $_->{enable} ne '' ? $_->{enable} : 1;
		# コメント投稿名
		$_->{name} = $_->{name} ne '' ? $_->{name} : '(no name)';

		#---------------------------------------------------
		# オプション構成
		#---------------------------------------------------
		my %op;
		$op{ip}    = $_->{ip};
		$op{host}  = $_->{host};
		$op{agent} = $_->{agent};
		$op{tm}    = $_->{tm};
		$op{num}   = $_->{num};
		if ($opt->{save_com_pkey} && !$_->{_tb}) {
			$opt->{save_pkey} = 1;
		}

		#---------------------------------------------------
		# 投稿処理
		#---------------------------------------------------
		my ($r,$c_pkey) = $self->regist_comment( $blogid, $_, $art, \%op );
		if ($r) {
			my $type = $_->{_tb} ? 'Trackback' : 'Comment';
			$session && $session->msg("$type import failed(%d) : %s", $r, "$art->{yyyymmdd} - $pkey");
		} else {
			# 成功
			push(@{ $opt->{c_pkeys} }, $c_pkey);
			$com_flag = 1;
		}
	}

	if ($com_flag) {
		# 記事のコメント数キャッシュを書き換え
		$self->calc_comments($blogid, $art->{pkey});
	}

	return 0;
}

#------------------------------------------------------------------------------
# ●インポートエラー
#------------------------------------------------------------------------------
sub import_error {
	my $self = shift;
	my $head = shift;
	my $msg  = shift;
	my $ROBJ = $self->{ROBJ};
	if (ref $self->{import_error} ne 'ARRAY') { $self->{import_error}=[]; }
	$msg = $ROBJ->translate($msg, @_);
	$ROBJ->tag_escape($msg);
	$ROBJ->error("$head $msg");
}


###############################################################################
# ■外部画像の取り込み
###############################################################################
#------------------------------------------------------------------------------
# ●記事データロード
#------------------------------------------------------------------------------
sub import_img_init {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }
	my $blogid = $self->{blogid};

	#-------------------------------------------------------------
	# 取得する記事の条件生成
	#-------------------------------------------------------------
	my %q;
	my $filename = $self->{blogid};
	if ($form->{enable_only}) {
		$q{flag} = {enable => 1};
	}
	if ($form->{tag} ne '') {
		#------------------------------------
		# タグ指定
		#------------------------------------
		my $taglist = $self->load_tag_cache($blogid);
		my $name2pkey = $taglist->[0];
		my $tag = $taglist->[ $name2pkey->{ $form->{tag} } ];

		# そのタグを持つ記事一覧
		my $arts = $tag->{arts};
		$q{match}->{pkey} = $arts ? $arts : -1;
	}

	#-------------------------------------------------------------
	# 記事の取得
	#-------------------------------------------------------------
	$q{sort} = ['yyyymmdd', 'tm'];	# ソート
	$q{cols} = ['pkey', 'yyyymmdd', 'tm', 'title', 'parser'];

	my $logs = $DB->select("${blogid}_art", \%q);

	if ($form->{html_only}) {
		$logs = [ grep { $_->{parser} =~ /^simple/  } @$logs ];
	}
	return $logs;
}

#------------------------------------------------------------------------------
# ●記事の画像データを外部ロード
#------------------------------------------------------------------------------
sub import_img {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $blogid = $self->{blogid};
	my $pkey = int($form->{pkey});

	my $log = $DB->select_match_limit1("${blogid}_art", 'pkey', $pkey);
	if (!$log) { return $ROBJ->message('Article not found.(pkey=%d)', $pkey); return 21; }

	my $tag   = $self->load_tag_escaper();
	my $html  = $tag->parse( $log->{_text} );
	my $media = $form->{media} ? 1 : 0;
	my $base  = $form->{base};
	if ($base !~ m|^(https?://\w+(?:\.\w+)*)/|i) {
		$base = undef;
	}
	my $base0 = $1;		# http://example.com まで

	my $folder= $form->{folder};
	$folder =~ s/%y/substr($log->{yyyymmdd},0,4)/eg;
	$folder =~ s/%m/substr($log->{yyyymmdd},4,2)/eg;

	$self->init_image_dir();
	my $dir  = $self->image_folder_to_dir_and_create( $folder );

	my $blogimg_url = $ROBJ->{ServerURL} . $ROBJ->{Basepath} . $self->blogimg_dir();

	my $msg = '';
	my $http = $ROBJ->loadpm("Base::HTTP");
	my %rep;
	my $error;
	foreach my $e ($html->getAll) {
		my $type = $e->type();
		if ($type ne 'tag') { next; }

		my $tag = $e->tag();
		if (!($tag eq 'img' || $media && ($tag eq 'source' || $tag eq 'audio'))) {
			next;
		}
		my $url_s = $e->attr->{src};
		my $prev  = $e->prev;
		my $url_l = ($prev->tag eq 'a') ? $prev->attr->{href} : '';
		if ($url_l eq $url_s) {
			$url_s = undef;
		}
		$url_s = $url_s =~ m!^(?:|http:|https:)//! ? $url_s : ($base && $url_s ? (substr($url_s,0,1) eq '/' ? $base0 : $base) . $url_s : '');
		$url_l = $url_l =~ m!^(?:|http:|https:)//! ? $url_l : ($base && $url_l ? (substr($url_l,0,1) eq '/' ? $base0 : $base) . $url_l : '');

		my $img_s;
		my $img_l;
		if ($url_s && index($url_s, $blogimg_url) != 0) {
			$img_s = $self->get_imgdata($http, $url_s);
			$msg  .= '  Download ' . ($img_s ? 'success' : 'fail!  ') . ' : ' . $url_s . "\n";
			if ($http->{error}) { $error = $http->{error}; }
		}
		if ($url_l && index($url_l, $blogimg_url) != 0) {
			$img_l = $self->get_imgdata($http, $url_l);
			$msg  .= '  Download ' . ($img_l ? 'success' : 'fail!  ') . ' : ' . $url_l . "\n";
			if ($http->{error}) { $error = $http->{error}; }
		}
		if ($img_s && !$img_l) {
			$url_l = $url_s;
			$img_l = $img_s;
			$url_s = undef;
			$img_s = undef;
		}

		# 保存ファイル名
		my $fname = $url_l =~ m|([^/]*)$| ? $1 : '';
		$ROBJ->tag_unescape($fname);
		$fname =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/$1/g;
		my $file = $fname;
		$ROBJ->tag_escape($file);
		$file = "$dir$file";

		if (!$img_l) { next; }
		if ($self->save_image_to_album($dir, $fname, $img_l)) {
			$msg  .= "  Save '$fname' fail!\n";
			next;	# save fail
		}

		# サムネイル保存
		my $thumb;
		my $thumb_file = $self->get_thumbnail_file($dir, $fname);
		while ($img_s) {
			if ($url_s !~ /\.jpe?g/i) {
				my ($fh, $file) = $ROBJ->open_tmpfile();
				if (!$fh) { last; }
				syswrite($fh, $img_s, length($img_s));
				close($fh);

				my $img = $self->load_image_magick();
				eval {
					$img->Read( $file );
					$img->Set( quality => ($self->{album_jpeg_quality} || 80) );
					$img->Write( $thumb_file );
				};
				if ($@) { last; }
				$thumb = 1;
			} else {
				$thumb = $ROBJ->fwrite_lines( $thumb_file, $img_s ) ? 1 : 0;
			}
			last;
		}

		$rep{$url_l} = $file;
		if ($img_s) {
			$rep{$url_s} = $thumb_file;
		}
	}

	#----------------------------------------------------
	# HTMLの書き換え
	#----------------------------------------------------
	my $data  = $self->{blog}->{image_data};
	$data =~ s/%k/$log->{pkey}/g;
	my @ary = split(/\s+/, $data);
	my $data = '';
	foreach(@ary) {
		if ($_ !~ /^([A-Za-z][\w\-]*)=(.*)$/) { next; }
		my $n = $1;
		my $v = $2;
		$ROBJ->tag_escape($v);
		$data .=" data-$n=\"$v\"";
	}

	my $rewrite = 0;
	if (%rep) {
		$log->{_text} =~ s{(<a\b[^>]*?\shref\s*=\s*)(["'])(.*?)\2}{
			my $url = $3;
			if ($rep{$3}) {
				$url = $rep{$url};
				$rewrite++;
			}
			"$1$2$url$2" . ($rep{$3} ? $data : '');
		}iseg;
		$log->{_text} =~ s{(<[^>]*?\ssrc\s*=\s*)(["'])(.*?)\2}{
			my $url = $3;
			if ($rep{$3}) {
				$url = $rep{$url};
				$rewrite++;
			}
			"$1$2$url$2";
		}iseg;

		if ($rewrite) {
			$msg .= "  Rewrite : $rewrite urls\n";
			$self->rebuild_blog({ logs => [ $log ] });
		}
	}
	if ($error) {
		$msg .= "\n(ERROR) $error\n";
	}
	chomp($msg);
	return (0,$msg);
}

#------------------------------------------------------------------------------
# ●指定したURLの画像データを取得
#------------------------------------------------------------------------------
sub get_imgdata {
	my $self = shift;
	my $http = shift;
	my ($st, $h, $res) = $http->get(@_);
	if (!$res || $st>299) { return ; }

	return join('', @$res);
}

#------------------------------------------------------------------------------
# ●画像データをアルバムに保存
#------------------------------------------------------------------------------
sub save_image_to_album {
	my $self = shift;
	my $dir  = shift;
	my $name = shift;
	my $data = shift;

	return $self->do_upload( $dir, {
		file_name => $name,
		file_size => length($data),
		data => $data
	});
}

###############################################################################
# ■データエクスポート
###############################################################################
#------------------------------------------------------------------------------
# ●エクスポート実行
#------------------------------------------------------------------------------
sub art_export {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }
	my $blogid = $self->{blogid};

	# 出力形式確認
	my $skel = $form->{file};
	$skel =~ s/\W//g;
	if ($skel eq '') {
		$ROBJ->message('Please select export type(skeleton)');
		return 11;
	}

	# オプション
	my %opt;
	{
		my $type = $form->{type};
		if ($type eq '') {
			$type = $skel;
			$type =~ s/[\d_]//g;
		}
		$opt{type} = $type;

		foreach(keys(%$form)) {
			my $x = index($_, ':');
			if ($x<0) { $opt{$_}=$form->{$_}; next; }
			if (substr($_,0,$x) ne $type) { next; }
			$opt{ substr($_,$x+1) } = $form->{$_};
		}
	}

	#-------------------------------------------------------------
	# 取得する記事の条件生成
	#-------------------------------------------------------------
	my %q;
	my $filename = $self->{blogid};
	if ($opt{enable_only}) {
		$q{flag} = {enable => 1};
	}
	{
		#------------------------------------
		# 日付指定
		#------------------------------------
		my $year = $opt{year};
		if ($year =~ /^\d\d\d\d$/) {
			$q{min} = {yyyymmdd => "${year}0000"};
			$q{max} = {yyyymmdd => "${year}1231"};
			$filename .= "-$year";
		} elsif ($year =~ m|^(\d\d\d\d)[/-]?(\d?\d)$|) {	# YYYYMM
			my $mon = sprintf("%02d", $2);
			$q{min} = {yyyymmdd => "$1${mon}00"};
			$q{max} = {yyyymmdd => "$1${mon}31"};
			$filename .= "-$1$mon";
		} elsif ($year =~ m|^(\d\d\d\d)(\d\d)(\d\d)$|
		      || $year =~ m|^(\d\d\d\d)[/-](\d?\d)[/-](\d?\d)$|) {	# YYYYMMDD
			my $yyyymmdd = sprintf("$1%02d%02d", $2, $3);
			$q{match}->{yyyymmdd} = $yyyymmdd;
			$filename .= "-$yyyymmdd";
		}
	}
	if ($opt{tag} ne '') {
		#------------------------------------
		# タグ指定
		#------------------------------------
		my $taglist = $self->load_tag_cache($blogid);
		my $name2pkey = $taglist->[0];
		my $tag = $taglist->[ $name2pkey->{ $opt{tag} } ];

		# そのタグを持つ記事一覧
		my $arts = $tag->{arts};
		$q{match}->{pkey} = $arts ? $arts : -1;
	}

	# コンテンツタイプ
	if ($opt{article_type} ne '*all*') {
		$q{match}->{ctype} = $opt{article_type};
	}

	#-------------------------------------------------------------
	# 記事の取得
	#-------------------------------------------------------------
	$q{sort} = ['yyyymmdd', 'tm'];	# ソート

	my $logs = $DB->select("${blogid}_art", \%q);
	if ($#$logs == -1) {
		$ROBJ->message('Not exists article');
		return 12;
	}

	#-------------------------------------------------------------
	# エクスポートの実行
	#-------------------------------------------------------------
	$opt{base_filename} = $filename;
	$opt{aobj} = $self;
	$ROBJ->call( $self->{skel_dir} . "_export/$skel", $logs, \%opt );

	return $ROBJ->{export_return};
}

#------------------------------------------------------------------------------
# ●textの分割・加工処理（エクスポート処理から呼ばれる）
#------------------------------------------------------------------------------
sub export_text_split {
	my $self = shift;
	my $h    = shift;

	my $parser = $h->{parser};
	if ($parser =~ /^simple/) {
		my $text = $h->{_text};
		my $append;
		if ($text =~ /^(.*?)\n====*\n(.*)/s) {
			$text   = $1;
			$append = $2;
		}
		$h->{body}    = $text;
		$h->{ex_body} = $append;
		$h->{convert_breaks} = 0;
		if ($parser eq 'simple_p' || $parser eq 'simple_br') {
			$h->{convert_breaks} = 1;
		}
	} else {
		my $text = $h->{text};

		# 記事内リンクの処理
		if ($parser =~ /^default/) {
			$self->post_process_link_key( $h );
			my $thisurl = $self->{myself2} . $h->{elink_key};
			$text =~ s!(<a\b[^>]*?href=)"([^"]*?)#!
					if (index($2, $thisurl)==0) {
						"$1\"#";	# PATH除去
					} else {
						"$1\"$2#";	# そのまま
					}
				!eg;
		}

		# 続きを読む、処理
		my $append;
		if ($text =~ /^(.*?)<!--%SeeMore%-->(.*)$/s) {	# Seemore
			$text   = $1;
			$append = $2;

			if ($text =~ m|^.*<section>(.*)$|si && index($1, '</section>')<=0) {
				$text .= "\n</section>";
			}
			if ($append =~ m|^(.*?)</section>.*$|si && index($1, '<section>')<=0) {
				$append = "<section>\n$append";
			}
		}
		$h->{body}    = $text;
		$h->{ex_body} = $append;
		$h->{convert_breaks} = 0;
	}
	
	# タグの分割
	$h->{tags_ary} = [ split(',', $h->{tags}) ];
	return $h;
}

#------------------------------------------------------------------------------
# ●ファイル名の加工
#------------------------------------------------------------------------------
sub export_escape_filename {
	my $self = shift;
	foreach(@_) {
		$_ =~ s![\\/:\*\?\"<>|]!-!g;
	}
	return $_[0];
}

1;
