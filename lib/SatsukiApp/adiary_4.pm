use strict;
#-------------------------------------------------------------------------------
# adiary_4.pm (C)2011 nabe@abk
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
package SatsukiApp::adiary;
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
	if (! $auth->{ok}) { $ROBJ->message('Not login'); return 1; }
	if ($self->{sys}->{blog_create_root_only} && ! $auth->{isadmin}) {
		$ROBJ->message('Operation not permitted');
		return 5;
	}
	if (! $auth->{isadmin}) {
		$id = $auth->{id};
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
		$ROBJ->mkdir( $self->blog_dir   ( $id ) );
		$ROBJ->mkdir( $self->blogpub_dir( $id ) );
	}
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
	$DB->delete_match("${blogid}_log");
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
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my $blogid = $self->{blogid};
	my $arts = $DB->select_match("${blogid}_art", '*cols', ['pkey', '_text', 'parser', 'yyyymmdd', 'tm']);

	my $r=0;
	my %update;
	foreach(@$arts) {
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
		my ($text, $text_s) = $parser->text_parser( $_->{_text} );
		if ($text eq $text_s) { $text_s=""; }

		# 許可タグ以外の除去処理
		my $escape = $self->load_tag_escaper( 'article' );
		$text   = $escape->escape($text);
		$text_s = $escape->escape($text_s);

		# 値保存
		my %h;
		$h{text}   = $text;
		$h{text_s} = $text_s;	# 短いtext
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
sub blogs_info_rebuild {
	my $self   = shift;
	my $blogid = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	if ($blogid eq '' && ! $auth->{isadmin}
	 || $blogid ne '' && ! $self->{blog_admin} ) { $ROBJ->message('Operation not permitted'); return 5; }

	my @ary = ($blogid);
	if ($blogid eq '') {
		my $blogs = $DB->select_match($self->{bloglist_table}, '*cols', 'id');
		@ary = map { $_->{id} } @$blogs;
	}

	my $now_blogid = $self->{blogid};
	foreach(@ary) {
		# ブログ選択
		$self->set_and_select_blog($_);

		# イベント処理
		$self->call_event('BLOG_INFO_REBUILD');
		$self->call_event('ARTICLE_STATE_CHANGE');
		$self->call_event('COMMENT_STATE_CHANGE');
		$self->call_event('ARTCOM_STATE_CHANGE');
	}
	$self->set_and_select_blog($now_blogid);

	return 0;
}

###############################################################################
# ■データベースがらみサブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●記事テーブルの作成
#------------------------------------------------------------------------------
sub create_tables {
	my ($self, $table) = @_;
	my $DB = $self->{DB};
	my $r=0;

  { # 記事テーブル
	my %info;
	$info{text}    = [ qw(title parser tags name id ip host agent link_key ctype) ];
	$info{ltext}   = [ qw(text text_s _text) ];
	$info{int}     = [ qw(yyyymmdd tm update_tm coms coms_all revision upnode priority) ];
	$info{flag}    = [ qw(enable com_ok hcom_ok) ];
	$info{idx}     = [ qw(title name tags id link_key ctype upnode yyyymmdd tm update_tm coms coms_all revision enable priority) ];
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

  { # リビジョン管理テーブル
	my %info;
	$info{text}    = [ qw(title parser note name id ip host agent) ];
	$info{ltext}   = [ qw(text _text) ];
	$info{int}     = [ qw(tm a_pkey) ];
	$info{flag}    = [ qw(elock) ];
	$info{idx}     = [ qw(title id tm a_pkey elock) ];
	$info{unique}  = [ qw() ];
	$info{notnull} = [ qw(a_pkey elock tm) ];
	$info{ref}     = { a_pkey => "${table}_art.pkey" };
	$r = $DB->create_table_wrapper("${table}_log", \%info);
	if ($r) { return 400 + $r; }
  }

  { # コメントテーブル
	my %info;
	$info{text}    = [ qw(text email url name id ip host agent a_title a_elink_key) ];
	$info{int}     = [ qw(tm num a_pkey a_yyyymmdd) ];
	$info{flag}    = [ qw(enable hidden) ];
	$info{idx}     = [ qw(name id ip enable hidden num tm a_pkey a_yyyymmdd) ];
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
# ●記事テーブルの削除
#------------------------------------------------------------------------------
sub drop_tables {
	my ($self, $table) = @_;
	my $DB = $self->{DB};

	my $r = 0;
	$r += $DB->drop_table("${table}_com");
	$r += $DB->drop_table("${table}_log");
	$r += $DB->drop_table("${table}_tagart");
	$r += $DB->drop_table("${table}_tag");
	$r += $DB->drop_table("${table}_art");

	# ブログリストから削除
	$self->delete_bloglist($table);

	return $r;
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
# ●記事テーブルの削除
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
	# セッションファイルのオープン
	my $session = $ROBJ->loadapp("adiary::session_file", $self);
	$session->open();
	$session->autoflush();

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
	if (! ref($form->{file}) || ! $form->{file}->{file_size}) {
		$session->msg('Not selected file'); return -2;
	}
	$session->msg("Import file size: %f KB", int($form->{file}->{file_size}/1024 + 0.5));

	# クラスオプション（$type:xxx=val を xxx=val として取り出す）
	my %opt;
	{
		my %h;
		my $class = ($form->{class} || $type) . ':';
		my $len   = length($class);
		foreach(keys(%$form)) {
			if (index($_,':')<0) {	# クラス表記を含まない
				$h{$_}=$opt{$_}=$form->{$_};
				next;
			}
			if (substr($_,0,$len) ne $class) { next; }
			my $x = substr($_,$len);
			$opt{$x} = $form->{$_};
			$h{$x}   = $form->{$_};
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
	my $p2p = $opt{pkey2pkey};
	foreach(@{$opt{upnodes}}) {
		my $pkey   = $_->{pkey};
		my $upnode = $_->{upnode};
		my $up_pkey = $p2p->{$upnode};
		if ($upnode != $up_pkey && $up_pkey) {
			$DB->update_match("${blogid}_art", {upnode => $up_pkey}, 'pkey', $pkey);
		}
	}
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
		$self->call_event('IMPORT_AFTER',         $opt{a_pkeys}, $opt{c_pkeys});
		$self->call_event('ARTICLE_STATE_CHANGE', $opt{a_pkeys}, $opt{c_pkeys});
		$self->call_event('COMMENT_STATE_CHANGE', $opt{a_pkeys}, $opt{c_pkeys});
		$self->call_event('ARTCOM_STATE_CHANGE' , $opt{a_pkeys}, $opt{c_pkeys});
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

#------------------------------------------------------------------------------
# ●記事を１件保存する
#------------------------------------------------------------------------------
# $self->save_article(\%art, \@coms, \@tbs, \%opt, $session);
# Ret:	0:成功  0以外:失敗
#
#※変更点メモ
#・カテゴリ→タグ
#
#
# $art->{enable}	1:表示許可 0:表示不可
# $art->{ctype}		コンテンツのタイプ（通常は指定不要）
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
# $art->{pkey}		記事ID(pkey)
# $art->{save_pkey}	1:pkeyを保持してimportする 0:pkeyを保持しない
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
			$art->year = $h->{year};
			$art->mon  = $h->{mon};
			$art->day  = $h->{day};
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
				$session->msg("'%s' is duplicate : %s", 'pkey', $pkey);
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
			$session->msg("Save article failed(%d) : %s", $ret, $art->{title} );
			return 11;
		}
		$pkey = $ret->{pkey};
		$pkeys->{ $pkey } = 1;
		push(@{ $opt->{a_pkeys} }, $pkey);

		# upnode対策用の処理
		if ($ret->{ctype} && $art->{pkey}) {
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
	$session->msg("[import] %s", $art->{title});
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
		my %opt;
		$opt{ip}    = $_->{ip};
		$opt{host}  = $_->{host};
		$opt{agent} = $_->{agent};
		$opt{tm}    = $_->{tm};
		$opt{num}   = $_->{num};

		#---------------------------------------------------
		# 投稿処理
		#---------------------------------------------------
		my ($r,$c_pkey) = $self->regist_comment( $blogid, $_, $art, \%opt );
		if ($r) {
			my $type = $_->{_tb} ? 'Trackback' : 'Comment';
			$session->msg("$type import failed(%d) : %s", $r, "$art->{yyyymmdd} - $pkey");
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
	$msg = $ROBJ->message_translate($msg, @_);
	$ROBJ->tag_escape($msg);
	$ROBJ->error("$head $msg");
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
	my $type  = $form->{type};
	$type =~ s/\W//g;
	if ($type eq '') {
		$ROBJ->message('Please select export type');
		return 11;
	}

	# オプション
	my %opt;
	my $class = $form->{class};
	foreach(keys(%$form)) {
		my $x = index($_, ':');
		if ($x<0) { $opt{$_}=$form->{$_}; next; }
		if (substr($_,0,$x) ne $class) { next; }
		$opt{ substr($_,$x+1) } = $form->{$_};
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
		$q{match}->{type} = $opt{article_type};
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
	$ROBJ->call( $self->{skel_dir} . "_export/$type", $logs, \%opt );

	return $ROBJ->{export_return};
}

#------------------------------------------------------------------------------
# ●textの分割・加工処理（エクスポート処理から呼ばれる）
#------------------------------------------------------------------------------
sub text_split_for_mt {
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

1;
