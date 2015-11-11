use strict;
#-------------------------------------------------------------------------------
# adiary_2.pm (C)2011 nabe@abk
#-------------------------------------------------------------------------------
# ・記事の管理
# ・コメント投稿
# ・RSS生成
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
package SatsukiApp::adiary;
###############################################################################
# ■情報表示関連
###############################################################################
#------------------------------------------------------------------------------
# ●記事リストのロード
#------------------------------------------------------------------------------
sub load_arts_list {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $sort = $opt->{sort};
	my $rev  = $opt->{rev};

	# sortのチェック
	my %a = ('enable'=>1,'yyyymmdd'=>1,'ctype'=>1,'name'=>1,'tm'=>1,'update_tm'=>1,'coms'=>1,'coms_all'=>1);
	$sort =~ s/\W//g;
	if (!$a{$sort} || $sort eq '') { $sort='yyyymmdd'; }
	$rev = ($rev eq '' || $rev) ? 1 : 0;

	my %h;
	$h{sort} = [$sort];
	$h{sort_rev} = [$rev];
	if ($sort ne 'yyyymmdd') {
		push(@{$h{sort}}, 'yyyymmdd');
		push(@{$h{sort_rev}}, $rev);
	}
	if ($sort ne 'tm') {
		push(@{$h{sort}}, 'tm');
		push(@{$h{sort_rev}}, $rev);
	}
	# 検索
	if ($opt->{q} !~ /^\s*$/) {
		$h{search_words} = [split(/\s+/, $opt->{q})];
		$h{search_cols}  = ['title', 'tags', 'name'];
		# エスケープした状態で保存されているのでエスケープして検索する必要がある
		$ROBJ->tag_escape(@{ $h{search_words} });
	}

	# オフセット、ロード数
	if ($opt->{offset}) {
		$h{offset} = int($opt->{offset});
	}
	if ($opt->{loads}) {
		$h{limit} = int($opt->{loads});
	}
	if ($opt->{require_hits}) {
		$h{require_hits} = 1;
	}

	# ロード対象記事オプション
	if (! $self->{allow_edit}) {
		$h{flag} = {enable => 1};
	} elsif ($opt->{draft_only}) {
		$h{is_null} = ['tm'];
	} elsif (!$opt->{load_draft}) {
		$h{not_null} = ['tm'];
	}

	# ロードカラム
	$h{cols} = [qw(pkey link_key title tags ctype name id yyyymmdd tm update_tm coms coms_all enable)];

	my $blogid = $self->{blogid};
	my ($logs,$hits) =  $DB->select("${blogid}_art", \%h);

	my %name;
	my %ctype;
	foreach(@$logs) {
		$self->post_process_link_key( $_ );
	}

	my %ret;
	$ret{hits} = $hits;
	$ret{sort} = $sort;
	$ret{rev}  = $rev;
	return wantarray ? ($logs, \%ret) : $logs;
}

#------------------------------------------------------------------------------
# ●コメントリストのロード
#------------------------------------------------------------------------------
sub load_coms_list {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $sort = $opt->{sort};
	my $rev  = $opt->{rev};

	# sortのチェック
	my %a = ('enable'=>1,'tm'=>1,'name'=>1,'a_yyyymmdd'=>1);
	$sort =~ s/\W//g;
	if (!$a{$sort} || $sort eq '') { $sort='tm'; }
	$rev = ($rev eq '' || $rev) ? 1 : 0;

	my %h;
	$h{sort} = [$sort];
	$h{sort_rev} = [$rev];

	# オフセット、ロード数
	if ($opt->{offset}) {
		$h{offset} = int($opt->{offset});
	}
	if ($opt->{loads}) {
		$h{limit} = int($opt->{loads});
	}
	if ($opt->{require_hits}) {
		$h{require_hits} = 1;
	}

	# ロード対象記事オプション
	if (! $self->{allow_edit}) {
		$h{flag} = {enable => 1};
	}

	my $blogid = $self->{blogid};
	my ($logs,$hits) =  $DB->select("${blogid}_com", \%h);

	foreach(@$logs) {
		$_->{text_nobr} = $_->{text}; 
		$_->{text_nobr} =~ s/<br>/ /g;
	}

	my %ret;
	$ret{hits} = $hits;
	$ret{sort} = $sort;
	$ret{rev}  = $rev;
	return wantarray ? ($logs,\%ret) : $logs;
}

#------------------------------------------------------------------------------
# ●ブログリストのロード
#------------------------------------------------------------------------------
sub load_blog_list {
	my ($self, $sort) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# sortのチェック
	my %a = ('id'=>1,'arts'=>1,'coms'=>1,'art_tm'=>1,'com_tm'=>1);
	$sort =~ s/\W//g;
	if (! $a{$sort}) { $sort='art_tm'; }
	if ($sort eq '') { $sort='art_tm'; }

	my %h;
	$h{sort} = [$sort];
	$h{sort_rev} = [0];
	$h{no_error} = 1;
	if ($sort ne 'id')     { $h{sort_rev}->[0] = 1; }
	if ($sort ne 'art_tm') { $h{sort}->[1] = 'art_tm'; $h{sort_rev}->[1] = 1;}
	if (! $ROBJ->{Auth}->{isadmin}) { $h{flag} = {private => 0}; }

	my $blogs = $DB->select($self->{bloglist_table}, \%h);
	foreach(@$blogs) {
		$_->{url} = $self->get_blog_path($_->{id});
	}
	return $blogs;
}

###############################################################################
# ■編集・執筆関連
###############################################################################
#------------------------------------------------------------------------------
# ●記事を書く／編集する
#------------------------------------------------------------------------------
sub edit_article {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	# 書き込み権限確認
	my $blogid = $self->{blogid};
	my $blog = $self->{blog};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	#----------------------------------------------------------------------
	# データチェックなど
	#----------------------------------------------------------------------
	my $ping    = $form->{ping}    ? 1:0;
	my $tw_ping = $form->{tw_ping} ? 1:0;
	$form->{id}   = $auth->{id};
	$form->{name} = $auth->{name};
	$self->delete_ip_host_agent($form);

	# 日付の分解
	if (exists $form->{ymd}) {
		my ($y,$m,$d) = split(m|[/-]|, $form->{ymd});
		if ($y =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
			$y = $1; $m = $2; $d = $3;
		}
		$form->{year} = $y;
		$form->{mon}  = $m;
		$form->{day}  = $d;
	}

	# タグの解析
	if (exists $form->{tag_ary}) {
		$form->{tags} = join(',', @{ $form->{tag_ary} });
	}

	my %opt;
	$opt{edit_pkey} = $form->{edit_pkey_int};

	# イベント呼び出し
	my $er = $self->call_event('ARTICLE_BEFORE', $form);
	if ($er) { return; }
	if ($opt{edit_pkey})  { $er = $self->call_event('ARTICLE_BEFORE_EDIT', $form); }
			 else { $er = $self->call_event('ARTICLE_BEFORE_POST', $form); }
	if ($er) { return }

	#----------------------------------------------------------------------
	# 書き込み
	#----------------------------------------------------------------------
	my ($art, $elink_key) = $self->regist_article($blogid, $form, \%opt);
	if (!ref($art)) {
		# エラー
		return $art;
	}

	#----------------------------------------------------------------------
	# 後処理
	#----------------------------------------------------------------------
	$art->{elink_key} = $elink_key;
	$art->{absolute_url}  = $self->{server_url} . $self->{myself2} . $elink_key;
	$art->{first_visible} = $opt{first_visible};

	# イベント呼び出しと固定の後処理
	if ($opt{first_visible}) {
		$self->call_event('ARTICLE_FIRST_VISIBLE', $art, $form);
	}
	$self->call_event('ARTICLE_AFTER', $art, $form);
	if ($opt{edit_pkey})  { $self->call_event('ARTICLE_AFTER_EDIT', $art, $form); }
			 else { $self->call_event('ARTICLE_AFTER_POST', $art, $form); }

	$self->call_event('ARTICLE_STATE_CHANGE', [ $art->{pkey} ], !$opt{tag_state_change});

	if ($opt{comment_edit}) {
		$self->call_event('COMMENTS_EDIT', [ $art->{pkey} ]);
		$self->call_event('COMMENT_STATE_CHANGE', [ $art->{pkey} ]);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', [ $art->{pkey} ]);

	# 正常終了
	return wantarray ? (0, $art) : 0;
}

#------------------------------------------------------------------------------
# ●記事を登録する
#------------------------------------------------------------------------------
# opt.edit_pkey		編集対象記事
# opt.iha_default	ip/host/agentのデフォルト値
# opt.save_pkey		pkeyを指定して保存する
# opt.tm		tmを直接指定する
#ret:
#	opt.first_visible	初めての公開
#	opt.comment_edit	コメントのキャッシュ情報を書き換えた
#	opt.comment_disable	コメントが非表示になった可能性がある
#
sub regist_article {
	my ($self, $blogid, $form, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->load_blogset($blogid);
	if (!$blog) {
		$ROBJ->message("Blog '%s' not found", $blogid);
		return -1;
	}
	$ROBJ->clear_form_error();

	#------------------------------------------------------------
	# フラグ
	#------------------------------------------------------------
	my %art;
	$art{enable} = $form->{enable}  ? 1 : 0;
	$art{com_ok} = $form->{com_ok}  ? 1 : 0;
	$art{hcom_ok}= $form->{hcom_ok} ? 1 : 0;

	#------------------------------------------------------------
	# 日付
	#------------------------------------------------------------
	my $now   = $ROBJ->{Now};
	my $year  = int($form->{year}) || $self->{now}->{year};
	my $mon   = int($form->{mon})  || $self->{now}->{mon};
	my $day   = int($form->{day})  || $self->{now}->{day};
	my $r = $self->check_date($year, $mon, $day);
	if ($r ne '') {
		$ROBJ->form_error('ymd', $r);
	}
	$art{yyyymmdd} = sprintf("%04d%02d%02d", $year, $mon, $day);

	#------------------------------------------------------------
	# テキスト
	#------------------------------------------------------------
	my $title = $form->{title};
	my $tags = $form->{tags};
	my $name = $form->{name};
	my $id   = $form->{id};
	$ROBJ->string_normalize($title, $tags, $name);
	$ROBJ->tag_escape_amp($title, $tags, $name);
	$id =~ s/\W//g;
	if ($title =~ /^\s*$/) {	# タイトルがない場合、タイトルを日付にする
		$title = sprintf("%04d-%02d-%02d", $year, $mon, $day);
	}
	$art{title}= $title;

	#------------------------------------------------------------
	# タグ
	#------------------------------------------------------------
	my @tag = $self->tag_normalize($tags);
	$art{tags} = $tags = join(",",@tag);

	#------------------------------------------------------------
	# 古い記事内容を取得
	#------------------------------------------------------------
	my $old = {};
	my $edit_pkey = int($opt->{edit_pkey});
	if ($edit_pkey) {
		$old = $DB->select_match_limit1("${blogid}_art", 'pkey', $edit_pkey);
		if (! $old) {
			$ROBJ->form_error('edit_pkey', "Can't find the article (key: %d)", $edit_pkey);
			return 10;
		}
	} else {
		$art{name} = $name;
		$art{id}   = $id;
	}

	#------------------------------------------------------------
	# コンテンツタイプ処理
	#------------------------------------------------------------
	my $ctype = $form->{ctype};
	$ctype =~ s/[^\w\-]//g;
	if ($ctype ne '') {
		# link_key/upnode の設定	※この２つは escpae しない
		my $link_key = $form->{link_key};
		# 前後の空白を除去
		$ROBJ->string_normalize($link_key);

		# 特殊文字除去		※ここを変更したら contents_edit も変更すること
		if ($link_key =~ /^["',]/) {
			$ROBJ->form_error('link_key', 'Can not use character "%s" in content key', '"\',');
		} elsif ($link_key =~ m!((?:^|/)\.+/)!) {
			$ROBJ->form_error('link_key', 'Can not use string "%s" in content key', "$1");
		} elsif ($link_key =~ /^\s*$/) {
			$ROBJ->form_error('link_key', 'Content key is empty');
		} elsif ($link_key =~ m|^[\d&]|) {
			$ROBJ->form_error('link_key', 'Content key is not allow "%s" as first character', '0-9');
		}

		# link_key の重複回避
		my $cons = $self->load_contents_cache();
		my %h = map { $cons->{$_}->{link_key} => 1 } keys(%$cons);
		my $ary = $DB->select("${blogid}_art", {	# 非公開記事
			flag => {enable => 0},
			not_match => {ctype => ''},
			cols => ['link_key']
		});
		foreach(@$ary) {
			$h{ $_->{link_key} } = 1;
		}
		delete $h{ $old->{link_key} };	# この記事の旧keyを削除
		if ($h{$link_key}) {
			my $i=2;
			while ($h{"$link_key$i"}) { $i++; }
			$i && ($link_key .= "$i");
		}

		# upnode判定
		my $upnode = int($form->{upnode});
		if ($upnode && !$cons->{$upnode}) {
			$upnode = 0;
		}

		# 自己参照防止
		if ($upnode eq $link_key) { $upnode=""; }

		$art{link_key} = $link_key;
		$art{upnode}   = $upnode;
		$art{priority} = int($form->{priority});

		# ctype
		$ctype = 'wiki';
		if ($link_key =~ m[^(?:/|https?://)]) {
			$ctype = 'link';
		}
	}
	$art{ctype} = $ctype;
	if ($ctype eq '') {
		# 通常のblog記事
		$art{priority} = 0;
		$art{upnode}   = undef;
	}

	#------------------------------------------------------------
	# エラー処理
	#------------------------------------------------------------
	if ($ROBJ->form_error()) { return 2; }

	#------------------------------------------------------------
	# 記事pkey生成
	#------------------------------------------------------------
	my $pkey = $edit_pkey;
	if (!$pkey) {	# 記事の新規作成
		if ($opt->{save_pkey}) {
			$pkey = int($opt->{save_pkey});
		} else {
			$pkey = $DB->generate_pkey("${blogid}_art");
			if (!$pkey) {
				$ROBJ->message('Article post failed');
				return 9;
			}
		}
		# 初期値設定
		$art{coms}     = 0;
		$art{coms_all} = 0;
	}

	#------------------------------------------------------------
	# 時刻設定と記事の初公開判定
	#------------------------------------------------------------
	my $first_visible;
	$art{update_tm} = $ROBJ->{TM};	# 最終更新日時

	if ($form->{draft}) {
		$art{enable} = 0;
		$art{tm} = undef;
	} elsif ($art{enable} && !$old->{tm}) {
		$first_visible=1;
		$opt->{first_visible}=1;
		$art{tm} = $opt->{tm} || $ROBJ->{TM};
	} elsif (!$edit_pkey) {
		$art{tm} = $opt->{tm} || $ROBJ->{TM};

	} elsif (!$form->{draft} && !$art{enable} && !$old->{tm}) {
		# 下書きを非公開で保存したとき。
		# → 初公開してすぐ非公開にしたと解釈する。
		$art{tm} = $opt->{tm} || $ROBJ->{TM};
	}

	#------------------------------------------------------------
	# link_keyの生成
	#------------------------------------------------------------
	if ($ctype eq '') {
		$art{link_key} = "0$pkey";
	}
	my $elink_key = $art{link_key};
	$self->link_key_encode( $elink_key );

	#------------------------------------------------------------
	# パーサー処理
	#------------------------------------------------------------
	my $_text  = $form->{body_txt} ne '' ? $form->{body_txt} : $form->{text};
	$_text =~ s/^(.*?)\n*$/$1/s;	# 行末の改行を取る

	my $parser_name = $form->{parser};
	$art{parser} = $parser_name;

	if ($parser_name ne '') {
		my $parser = $self->load_parser( $parser_name );
		if (! ref($parser)) {
			$ROBJ->message("Load parser '%s' failed", $parser);
			return 3;
		}

		# プリプロセッサ
		if ($parser->{use_preprocessor} && $_text ne '') {
			$parser->preprocessor( $_text );
		}

		# パース準備
		$parser->{thisurl}  = $self->get_blog_path( $blogid ) . $elink_key;
		$parser->{thispkey} = $pkey;
		$parser->{thisymd}  = $art{yyyymmdd};	# 時刻付見出し記法に使用
		my ($text, $text_s) = $parser->text_parser( $_text );
		if ($text eq $text_s) { $text_s=""; }

		# 許可タグ以外の除去処理
		my $escape = $self->load_tag_escaper( 'article' );
		$text   = $escape->escape($text);
		if ($text_s ne '') {
			$text_s = $escape->escape($text_s);
		}

		# 値保存
		$art{_text}  = $_text;	# parse 前のテキスト
		$art{text}   = $text;
		$art{text_s} = $text_s;	# 短いtext（$text ne $text_sの時のみ）
	} else {
		# パーサーなし
		my $text = "<section>\n$_text\n</section>";
		$self->load_tag_escaper( 'article' )->escape($text);

		$art{parser} = '';
		$art{_text}  = $_text;
		$art{text}   = $text;
		$art{text_s} = '';
	}
	$self->set_description(\%art);

	#------------------------------------------------------------
	# DBに書き込み
	#------------------------------------------------------------
	if ($edit_pkey) {
		my $r = $DB->update_match("${blogid}_art", \%art, 'pkey', $pkey);
		if (!$r) {
			$ROBJ->message('Article edit failed');
			return 11;
		}
		$art{pkey} = $pkey;
	} else {
		$self->set_ip_host_agent(\%art, $form, $opt->{iha_default});
		$art{pkey} = $pkey;
		my $r = $DB->insert("${blogid}_art", \%art);
		if (!$r) {
			$ROBJ->message('Article post failed');
			return 12;
		}
	}

	#------------------------------------------------------------
	# 変更があった場合のコメントデータの書き換え
	#------------------------------------------------------------
	if ($edit_pkey) {
		my %update;
		if (!$art{enable}  && $old->{enable})   { $update{enable}      = 0; }
		if ($art{title}    ne $old->{title})    { $update{a_title}     = $art{title}; }
		if ($art{yyyymmdd} ne $old->{yyyymmdd}) { $update{a_yyyymmdd}  = $art{yyyymmdd}; }
		if ($art{link_key} ne $old->{link_key}) { $update{a_elink_key} = $elink_key; }

		# コメントの書き換え
		if (%update && $old->{coms_all}) {
			my $r = $DB->update_match("${blogid}_com", \%update, 'a_pkey', $pkey);
			if ($r) {
				$opt->{comment_edit}    = 1;
				$opt->{comment_disable} = exists($update{enable});
			 }
		}
	}

	#------------------------------------------------------------
	# タグ情報の書き換え
	#------------------------------------------------------------
	if ($old->{tags} ne $tags || $old->{enable} != $art{enable}) {
		my $pkeys = $self->regist_tags($blogid, \@tag);
		$edit_pkey && $DB->begin();
		if (ref($pkeys)) {
			if ($edit_pkey) {
				$DB->delete_match("${blogid}_tagart", 'a_pkey', $pkey);
			}
			foreach(@$pkeys) {
				$DB->insert("${blogid}_tagart", {
					'a_pkey'   => $pkey,
					'a_enable' => $art{enable},
					't_pkey'   => $_
				});
			}
		}
		$edit_pkey && $DB->commit();
		$opt->{tag_state_change}=1;
	}

	return wantarray ? (\%art, $elink_key) : \%art;	# 書き込み成功
}

#------------------------------------------------------------------------------
# ●記事のメイン画像と概要を生成
#------------------------------------------------------------------------------
sub set_description {
	my $self = shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	my $text = $h->{text};

	while($text =~ /<img\s+(?:[\w-]+\s*=\s*"[^"]*"\s+)*src\s*=\s*"([^"]+)"/gi) {
		my $img = $1;
		my $dir = $ROBJ->{Basepath} . $self->blogimg_dir();
		if (substr($img,0, length($dir)) ne $dir) { next; }
		
		# 代表画像
		$img = substr($img, length($dir));
		$img =~ s!(^|/).thumbnail/(.+)\.jpg$!$1$2!;
		$h->{main_image} = $img;
		last;
	}

	$text = substr($text, 0, 4096);		# 長文への対策
	$text =~ s/[\r\n]//g;
	$ROBJ->tag_delete($text);
	$h->{description} = $self->string_clip($text, $self->{blog}->{desc_len} || 64);
}

#------------------------------------------------------------------------------
# ●記事の表示状態変更、削除する
#------------------------------------------------------------------------------
sub edit_articles {
	my ($self, $mode, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	if ($keylist !~ /^\d+$/ && $keylist->[0] !~ /^\d+$/) {
		return wantarray ? (0,0) : 0;
	}

	# 初期状態設定
	my $blogid = $self->{blogid};
	if ($self->{blog}->{edit_by_author_only} && !$self->{blog_admin}) {
		# 他人の記事は編集できないので、IDが一致するかチェックする
		my $id = $auth->{id};
		my $ary = $DB->select_match("${blogid}_art", 'pkey', $keylist, '*cols', ['pkey','id']);
		my @pkeys;
		foreach(@$ary) {
			if ($_->{id} ne $id) { next; }
			push(@pkeys, $_->{pkey});
		}
		if (!@pkeys) {
			# 該当記事なし
			return wantarray ? (0,0) : 0;
		}
		$keylist = \@pkeys;
	}

	# 削除
	my $cnt;
	my $com;
	my $comkeylist;
	my $event_name;
	my $cevent_name;
	if ($mode eq 'delete') {
		$event_name  = 'ARTICLES_DELETE';
		$cevent_name = 'COMMENTS_DELETE';

		$DB->delete_match("${blogid}_tagart", 'a_pkey', $keylist);
		# $DB->delete_match("${blogid}_rev", 'a_pkey', $keylist);
		$comkeylist = $DB->select_match_colary("${blogid}_com", 'pkey', 'a_pkey', $keylist);
		$com = $DB->delete_match("${blogid}_com", 'a_pkey', $keylist);
		$cnt = $DB->delete_match("${blogid}_art", 'pkey', $keylist);
	} elsif ($mode eq 'enable') {
		$event_name = 'ARTICLES_EDIT';
		$cnt = $DB->update_match("${blogid}_art",
			{ enable => 1 },
			'enable', 0,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist,
		);
	} else {
		$event_name  = 'ARTICLES_EDIT';
		$cevent_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("${blogid}_art",
			{ enable => 0 },
			'enable', 1,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist
		);
		# 非公開にした記事にコメントがあれば
		my $ary = $DB->select_match("${blogid}_art",
			'enable', 0,
			'-coms', 0,	# 公開コメントがある
			'pkey', $keylist,
			'*cols', ['pkey']
		);
		my @pkeys = map { $_->{pkey} } @$ary;
		if (@pkeys) {
			$com = $DB->update_match("${blogid}_com",
				{ enable => 0 },
				'enable',  1,
				'a_pkey', \@pkeys
			);
		}
	}

	# イベント処理
	if ($cnt) {
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            $keylist, $cnt);
		$self->call_event('ARTICLE_STATE_CHANGE', $keylist);
		if ($com) {
			$self->call_event($cevent_name,           $keylist);
			$self->call_event('COMMENT_STATE_CHANGE', $keylist);
		}
		$self->call_event('ARTCOM_STATE_CHANGE',  $keylist);
	}

	return wantarray ? (0, $cnt) : 0;
}

#------------------------------------------------------------------------------
# ●更新通知Pingの送信
#------------------------------------------------------------------------------
sub send_update_ping {
	my $self = shift;
	my ($art, $form) = @_;
	if (!$form->{ping}) { return 0; }

	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	my @servers = split("\n", $self->{sys}->{ping_servers_txt});

	# 更新通知情報
	my %ping;
	$ping{blog_name} = $blog->{blog_name};	# blogタイトル
	$ping{url}       = $self->{server_url} . $self->{myself};
	$ping{rssurl}    = $self->{server_url} . $ROBJ->{Basepath} . $self->{blogpub_dir} . $self->load_rss_files()->[0];
	$ping{art_title} = $art->{title};

	# see http://www.xmlrpc.com/weblogsCom
	my $jcode;
	my $system_coding = $ROBJ->{System_coding};
	if ($system_coding ne 'UTF-8') {
		$jcode = $ROBJ->load_codepm();
		$ping{blog_name} = $jcode->from_to($ping{blog_name}, $system_coding, 'UTF-8');
		$ping{art_title} = $jcode->from_to($ping{art_title}, $system_coding, 'UTF-8');
	}
	my $send;
	foreach(@servers) {
		if ($_ eq '' || substr($_, 0, 1) eq '#') { next; }
		if (!$send) {
			# $ROBJ->notice("***Ping sending result***");
			$send=1
		}
		$ping{ping_server} = $_;
		my $xml = $self->send_weblogUpdates_Ping(\%ping);
		if (!ref $xml) { next; }
		if (! exists $xml->{flerror}) {
			$ROBJ->notice('Error : Illegal response "%s". (Is it ping server?)', $_);
			next;
		}
		if ($xml->{flerror} || $xml->{faultCode}) {
			my $err_msg = $xml->{message} || $xml->{faultString};
			$jcode && $jcode->from_to(\$err_msg, 'UTF-8', $ROBJ->{System_coding});
			$ROBJ->notice('Error : %s (from %s)', $err_msg, $_);
			next;
		}
		my $msg = $xml->{message};
		$jcode && $jcode->from_to(\$msg, 'UTF-8', $ROBJ->{System_coding});
		$ROBJ->notice("Ping sended : %s (from %s)", $msg, $_);
	}
	return 0;
}
#------------------------------------------------------------------------------
# ●更新通知Pingを送信（拡張仕様準拠）
#------------------------------------------------------------------------------
# Extended Ping XML-RPC Request
#	$data->{ping_server}	PingサーバURL
#	$data->{blog_name}	blogのタイトル
#	$data->{url}		blogのURL
#	$data->{rssurl}		RSSのURL
# 参考にした資料(Thanks)
#	http://isnot.jp/?p=XML-RPC%A1%F8%B9%B9%BF%B7Ping%A4%CE%C1%F7%BF%AE
#
sub send_weblogUpdates_Ping {
	my ($self, $data) = @_;
	my $ROBJ = $self->{ROBJ};

	# ライブラリロード
	my $http = $ROBJ->loadpm('Base::HTTP');
	$http->set_timeout( $self->{sys}->{http_timeout} );
	$http->set_agent( $self->{http_agent} );

	# option load
	my $post_url = $data->{ping_server};
	my ($option, $timeout);
	($post_url, $option) = split('#', $post_url);
	($option, $timeout)  = split(',', $option);
	if (0 < $timeout && $timeout < 61) { $http->set_timeout( $timeout ); }

	#------------------------------------------------------------
	# POST bodyの生成
	#------------------------------------------------------------
	my $url       = $data->{url};
	my $blog_name = $data->{blog_name};
	my $rssurl    = $data->{rssurl};
	my $method    = "weblogUpdates.ping";
	my $check_url = $url;
	if ($option eq 'ex')     { $method="weblogUpdates.extendedPing"; }
	if ($option eq 'adiary') {	# adiary extended
		$method    = "weblogUpdates.adiary-extendedPing";
		$check_url = $data->{art_title};
	}
	# XML
	$ROBJ->tag_escape_for_xml($blog_name, $url, $check_url, $rssurl);
	my $post_body = <<POST_BODY;
<?xml version="1.0"?>
<methodCall>
	<methodName>$method</methodName>
	<params>
		<param><value>$blog_name</value></param>
		<param><value>$url</value></param>
		<param><value>$check_url</value></param>
		<param><value>$rssurl</value></param>
	</params>
</methodCall>
POST_BODY

	#------------------------------------------------------------
	# POST の発行
	#------------------------------------------------------------
	my ($status, $header, $res) = $http->post($post_url, undef, $post_body);
	if ($status != 200 || !defined $res) {
		$ROBJ->notice( $http->{error_msg} );
		return 100;
	}

	#------------------------------------------------------------
	# レスポンスの解析（注：手抜きです）
	#------------------------------------------------------------
	my $data = join('', @$res);
	$data =~ s/[\r\n]//g;
	$data =~ s[\s*(?:<boolean>(.*?)</boolean>|<int>(.*?)</int>|<string>(.*?)</string>)\s*][$1$2$3]g;
	my %xml;
	while($data =~ m|<member>(.*?)</member>|sg) {
		my $member = $1;
		my ($name, $value);
		if ($member =~ /<name>(.*?)<\/name>/)   { $name =$1; } 
		if ($member =~ /<value>(.*?)<\/value>/) { $value=$1; } 
		$xml{$name} = $value;
	}
	return \%xml;		# 成功
}

###############################################################################
# ■タグ関連
###############################################################################
#------------------------------------------------------------------------------
# ●タグの登録とpkeyリストの取得
#------------------------------------------------------------------------------
sub regist_tags {
	my ($self, $blogid, $tags, $esc_flag) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	if ($esc_flag) {
		foreach(@$tags) {
			$ROBJ->tag_escape($_);
		}
	}

	# aaa::bbb を aaa と aaa::bbb に分解
	my @match;
	foreach my $tag (@$tags) {
		my $t;
		foreach(split('::',$tag)) {
			$t = $t ne '' ? "$t\::$_" : $_;
			push(@match, $t);
		}
	}
	my $db = $DB->select_match("${blogid}_tag", 'name', \@match, '*cols', ['pkey', 'name']);

	my %name2pkey = map {$_->{'name'} => $_->{'pkey'}} @$db;
	my @ary;
	foreach(@$tags) {
		if ($name2pkey{$_}) {
			push(@ary, $name2pkey{$_});
			next;
		}
		# 新たに登録
		my @x = split('::', $_);
		my $t;
		my $up= 0;
		my $lastpkey;
		foreach(@x) {
			$t = $t ? "$t\::$_" : $_;
			if ($name2pkey{$t}) {
				$up = $name2pkey{$t};
				next;
			}
			my %in;
			$in{name} = $t;
			$in{qt} = 0;
			$in{upnode} = $up==0 ? undef : $up;
			$in{priority} = $self->{default_tag_priority};
			my $pkey = $DB->insert("${blogid}_tag", \%in);
			if (!$pkey) {
				$ROBJ->error("Tag '%s' create fail", $t);
				return -1;
			}
			$lastpkey = $pkey;
			$name2pkey{$t} = $pkey;
			$up = $pkey;
		}
		push(@ary, $lastpkey);
	}

	return \@ary;
}

#------------------------------------------------------------------------------
# ●タグ情報の更新
#------------------------------------------------------------------------------
sub update_taglist {
	my $self = shift;
	my $akeys= shift;
	## my $no_change= shift && return 0;	# タグの状態が変化してない
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->{blog};
	my $blogid = $blog->{blogid};

	my $ary = $DB->select_match("${blogid}_tagart", 'a_enable', 1);
	my %tag;
	foreach(@$ary) {
		$tag{ $_->{t_pkey} }+=1;
	}
	$DB->begin();
	foreach(keys(%tag)) {
		$DB->update_match("${blogid}_tag", {qt => $tag{$_}}, 'pkey', $_, '-qt', $tag{$_});
	}
	$DB->update_match("${blogid}_tag", {qt => 0}, '-pkey', [ keys(%tag) ], '-qt', 0);
	$DB->commit();

	# タグツリーと、タグキャッシュ生成
	my $tree = $self->generate_tag_tree($blogid);

	# JSONの生成
	my $json = $self->generate_json($tree->{children}, ['sname', 'pkey', 'qt', 'children'], {sname=>'title', pkey=>'key'});
	$ROBJ->fwrite_lines( $self->{blogpub_dir} . 'taglist.json', $json);

	# イベント処理
	$self->call_event('TAG_STATE_CHANGE', $tree);

	return 0;
}

#------------------------------------------------------------------------------
# ●タグリストの生成
#------------------------------------------------------------------------------
sub generate_tag_tree {
	my ($self, $blogid) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# 記事のpkeyリスト
	my @tagarts;
	{
		my $ary = $DB->select("${blogid}_tagart");
		foreach(@$ary) {
			push(@{ $tagarts[ $_->{t_pkey} ] ||= [] }, $_->{a_pkey});
		}
	}

	# 情報ファイルの生成
	my $tree = $self->load_tag_tree($blogid);
	my $all  = $tree->{_all};
	my @tags;
	foreach (@$all) {
		my $pkey = $_->{pkey};
		my $children = $_->{children};
		$children = $children ? join(',', map {$_->{pkey}} @$children):'';
		my $arts = join(',', @{ $tagarts[$pkey] || [] });
		$tags[ $pkey ] = int($_->{upnode}) . "\t" . int($_->{qt}) . "\t" . int($_->{qtall})
				. "\t$_->{priority}\t$children\t$arts\t$_->{name}\n";
	}
	@tags = map { defined $_  ? $_ : "\n" } @tags;
	$ROBJ->fwrite_lines($self->blog_dir($blogid) . "tag_cache.txt", \@tags);

	return $tree;
}

#------------------------------------------------------------------------------
# ●タグツリーの取得
#------------------------------------------------------------------------------
sub load_tag_tree {
	my ($self, $blogid) = @_;
	my $DB = $self->{DB};

	my $taglist = $DB->select("${blogid}_tag", { sort=>['priority', 'pkey'] });
	my %tree = map { $_->{pkey} => $_ } @$taglist;
	$tree{0} = { children => [], _all=>$taglist, root=>1 };	# root node

	foreach(@$taglist) {
		my $x = rindex($_->{name},'::');
		$_->{sname} = $x<0 ? $_->{name} : substr($_->{name}, $x+2);
		my $up = int($_->{upnode});
		my $ary = $tree{$up}->{children} ||= [];
		push(@$ary, $_);
	}

	# リーフをすべて含む記事数を計算する
	foreach (@$taglist) {
		my $qt = $_->{qtall} = $_->{qt};
		my $up = $_->{upnode};
		while($up) {
			$tree{$up}->{qtall} += $qt;
			$up = $tree{$up}->{upnode};
		}
	}

	return $tree{0};	# root node
}

###############################################################################
# ■コンテンツ関連
###############################################################################
#------------------------------------------------------------------------------
# ●blog/コンテンツツリーの生成
#------------------------------------------------------------------------------
sub update_contents_list {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	# 情報のロード
	my ($tree, $arts, $pkey_max) = $self->load_contents_tree($blogid);

	# キャッシュ保存ディレクトリ
	my $dir = $self->{blog_dir} . 'arts/';
	$ROBJ->mkdir($dir);

	# コンテンツ情報JSON、キャッシュの生成
	{
		my $all = $tree->{_all};
		my $json= $self->generate_json($tree->{children}, ['title', 'pkey', 'upnode', 'link_key', 'children'], {pkey=>'key'});
		$ROBJ->fwrite_lines( $self->{blogpub_dir} . 'contents.json', $json);

		# upnode, children, titleのキャッシュ
		my @ary;
		foreach(@$all) {
			my $ch = $_->{children} ? join(',', map {$_->{pkey}} @{$_->{children}}) : '';
			push(@ary, "$_->{pkey}\t$_->{link_key}\t$_->{upnode}\t$_->{prev}\t$_->{next}\t$ch\t$_->{title}\n");
		}
		my $file = $dir . 'contents.dat';
		$ROBJ->fwrite_lines($file, \@ary);
	}

	# blog情報キャッシュの生成
	my %arts = map {$_->{pkey} => $_} @$arts;
	my $unit = $self->{blog_cache_unit} || $pkey_max;
	my $max  = int(($pkey_max+$unit-1)/$unit);
	for(my $cnt=0; $cnt<$max; $cnt++) {
		my $base = $cnt*$unit;
		my $end  = $base+$unit;
		my %list;
		for(my $i=$base; $i<$end; $i++) {
			if (!exists($arts{$i})) { next; }
			my $h = $list{$i} = $arts{$i};
			foreach($h->{prev}, $h->{next}) {
				if (!$_ || !exists $arts{$_}) { next; }
				$list{$_} = $arts{$_};
			}
		}
		# 情報を加工して保存
		my $file = $dir . sprintf("%04d", $cnt) . '.dat';
		if (!%list) {
			$ROBJ->file_delete($file);
			next;
		}
		my @ary;
		foreach(sort {$a <=> $b} keys(%list)) {
			my $h = $list{$_};
			push(@ary, "$h->{pkey}\t$h->{prev}\t$h->{next}\t$h->{title}\n");
		}
		# ファイルに保存
		$ROBJ->fwrite_lines($file, \@ary);
	}

	# イベント処理
	$self->call_event('CONTENT_STATE_CHANGE', $tree);
	return $tree;
}

#------------------------------------------------------------------------------
# ●ブログ情報のjsonを生成する
#------------------------------------------------------------------------------
sub generate_blog_json {
	my $self = shift;
	my $data = shift;
	my $zero = shift;
	my $ROBJ = $self->{ROBJ};
	my @ary;
	if ($zero) {
		push(@ary, "\"0\": $zero");
	}
	foreach(@$data) {
		my $title = $_->{title};
		my $lkey  = $_->{link_key};
		$ROBJ->tag_escape($lkey);
		$title =~ s/\\/&#92;/g;
		$lkey  =~ s/\\/&#92;/g;
		my $line = "\"title\": \"$title\", \"lkey\": \"$lkey\"";
		if ($_->{prev}) { $line .= ", \"prev\": $_->{prev}"; }
		if ($_->{next}) { $line .= ", \"next\": $_->{next}"; }
		push(@ary, "\"$_->{pkey}\": {$line}");
	}
	return "{\n" . join(",\n", @ary) . "\n}";
}

#------------------------------------------------------------------------------
# ●コンテンツツリーの取得
#------------------------------------------------------------------------------
sub load_contents_tree {
	my ($self, $blogid) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blog = $self->load_blogset($blogid);

	# 全記事を取得
	my $ary = $DB->select_match("${blogid}_art",
		'enable', 1,
		'*sort', 'yyyymmdd',
		'*sort', 'tm',
		'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'ctype']
	);
	my @contents;
	my @arts;
	my $pkey_max=0;
	foreach(@$ary) {
		my $a = $_->{ctype} eq '' ? \@arts : \@contents;
		push(@$a, $_);
		if ($pkey_max<$_->{pkey}) { $pkey_max=$_->{pkey}; }
	}

	# コンテンツツリーの生成
	@contents = sort {$a->{priority} <=> $b->{priority}} @contents;
	my %tree = map { $_->{pkey} => $_ } @contents;
	$tree{0} = { children => [], _all=>\@contents, root=>1 };		# root node
	my %lkeys;
	foreach(@contents) {
		$self->post_process_link_key($_);
		my $up = int($_->{upnode});
		if (!exists $tree{$up}) { $up=0; }
		my $ary = $tree{$up}->{children} ||= [];
		push(@$ary, $_);
		$lkeys{$_->{link_key}} = $_;
	}
	# FrontPage処理
	my $fp;
	foreach(qw(FrontPage top index)) {
		if ($lkeys{$_}) { $fp=$_; last; }
	}
	$self->update_blogset($blogid, 'frontpage', $fp);

	# 前後リンクの生成
	my @cons;
	$self->tree2list(\@cons, $tree{0}->{children});
	$self->contents_next_prev_link(\@arts);
	$self->contents_next_prev_link(\@cons);

	return wantarray ? ($tree{0}, \@arts, $pkey_max) : $tree{0};
}

sub tree2list {
	my ($self,$ary,$tree) = @_;
	foreach(@$tree) {
		push(@$ary, $_);
		if ($_->{children}) { $self->tree2list($ary, $_->{children}); }
	}
}

sub contents_next_prev_link {
	my $self = shift;
	my $ary  = shift;
	my $max  = $#$ary;
	
	# ブログ記事の前後リンク
	for(my $i=1; $i<$#$ary; $i++) {
		$ary->[$i]->{next} = $ary->[$i+1]->{pkey};
		$ary->[$i]->{prev} = $ary->[$i-1]->{pkey};
	}
	# 最初と最後の記事の処理
	if ($max > 0) {
		$ary->[   0]->{next} = $ary->[     1]->{pkey};
		$ary->[$max]->{prev} = $ary->[$max-1]->{pkey};
	}
	return $ary;
}

###############################################################################
# ■RSSの生成処理
###############################################################################
#------------------------------------------------------------------------------
# ●RSSを生成
#------------------------------------------------------------------------------
sub generate_rss {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};
	my $blogid = $self->{blogid};

	# 文字コード変換
	my $jcode = $ROBJ->load_codepm();

	#-----------------------------------------------
	# RSS生成
	#-----------------------------------------------
	my $ret;
	my @files;
	my $file = $self->{blogpub_dir} . "rss.xml";
	if ($blog->{rss_items_int}) {
		my $rss = $ROBJ->call_and_chain( $self->{rss_skeleton}, {
			no_comment => $blog->{rss_no_comment},
			items => $blog->{rss_items_int}
		});
		$jcode->from_to($rss, $ROBJ->{System_coding}, 'UTF-8');

		# ファイルに書き込み
		$ret = $ROBJ->fwrite_lines($file, $rss);
		push(@files, 'rss.xml');
	} else {
		$ROBJ->file_delete($file);
	}

	#-----------------------------------------------
	# 2つ目のRSS生成
	#-----------------------------------------------
	my $file2 = $self->{blogpub_dir} . "rss2.xml";
	if ( $blog->{rss2_tag} ne '' ) {
		my $rss = $ROBJ->call_and_chain( $self->{rss_skeleton}, {
			no_comment => $blog->{rss2_no_comment},
			tag   => $blog->{rss2_tag},
			title => $blog->{rss2_title},
			items => $blog->{rss_items_int}
		});
		$jcode->from_to($rss, $ROBJ->{System_coding}, 'UTF-8');
		$ROBJ->fwrite_lines($file2, $rss);
		push(@files, 'rss2.xml');
	} else {
		$ROBJ->file_delete($file2);
	}

	# RSSファイル情報記録（,区切り）
	$self->update_blogset($blog, 'rss_files', join(',', @files));

	return $ret;
}

#------------------------------------------------------------------------------
# ●RSS用に記事をロード
#------------------------------------------------------------------------------
sub load_arts_for_rss {
	my ($self, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->{blog};

	# load
	$opt->{loads} ||= $opt->{items} || 10;
	$opt->{blog_only} = $blog->{separate_blog};
	my $query;
	if ($opt->{tag}) {
		$query->{t} = [ $opt->{tag} ];
	}
	my $logs = $self->load_articles( $self->{blogid}, '', $query, $opt );

	#-----------------------------------------------
	# RSSのタグエスケーパー
	#-----------------------------------------------
	my $escaper = $self->load_tag_escaper_force( 'rss' );

	# RSS のための加工処理
	my $tm_max     = 0;
	my $update_max = 0;
	foreach(@$logs) {	# ログ
		# 最終作成日 / 更新日
		if ($_->{tm}        > $tm_max)     { $tm_max     = $_->{tm};        }
		if ($_->{update_tm} > $update_max) { $update_max = $_->{update_tm}; }

		# 日付加工  (dc sample)2006-05-02T13:54:30+09:00
		$_->{dc_date}    = $self->dc_date ( $_->{tm} );
		$_->{rfc_date}   = $ROBJ->rfc_date( $_->{tm} );
		$_->{dc_update}  = $self->dc_date ( $_->{update_tm} );
		$_->{rfc_update} = $ROBJ->rfc_date( $_->{update_tm} );

		# テキストロード
		my $text = $escaper->escape( $_->{text_s} || $_->{text} );
		$text =~ s/\]\]>/]]&gt;/g;
		$_->{description} = $text;
		
		# link_keyの加工
		$self->post_process_link_key( $_ );

		# & のエスケープ
		$ROBJ->tag_escape_for_xml($_->{title}, $_->{name}, $_->{tags});
	}
	# 全体変数のセット
	my %h;
	$h{art_tm}     = $tm_max;
	$h{update_tm}  = $update_max;
	$h{dc_date}    = $self->dc_date ( $tm_max );
	$h{rfc_date}   = $ROBJ->rfc_date( $tm_max );
	$h{dc_update}  = $self->dc_date ( $update_max );
	$h{rfc_update} = $ROBJ->rfc_date( $update_max );
	return ($logs, \%h);
}

#------------------------------------------------------------------------------
# ○xmlns:dc="http://purl.org/dc/elements/1.1/" 形式の日付に変換
#------------------------------------------------------------------------------
sub dc_date {
	my $self = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( shift );
	return sprintf("%04d-%02d-%02dT%02d:%02d:%02d+00:00", $year+1900, $mon+1, $mday, $hour, $min, $sec);
}

###############################################################################
# ■コメント関連
###############################################################################
#------------------------------------------------------------------------------
# ●コメントを書く
#------------------------------------------------------------------------------
sub post_comment {
	my ($self, $form) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my $blog = $self->{blog};
	my $blogid = $self->{blogid};
	if (! $self->{allow_com}) { $ROBJ->message('Operation not permitted'); return 5; }

	# SPAM対策 secu_id の確認
	my $a_pkey = int($form->{a_pkey});
	if (! $auth->{ok}) {
		my $secure_id = $form->{secure_id};
		my $secu_id_now = $ROBJ->make_secure_id($blogid . $a_pkey);
		my $secu_id_old = $ROBJ->make_secure_id($blogid . $a_pkey, 1);
		if ($secure_id ne $secu_id_now && $secure_id ne $secu_id_old) {
			$ROBJ->message('Security error. Please repost.');
			return 9;
		}
	}

	# 記事を確認
	my $art = $self->load_article_current_blog("0$a_pkey");
	if (!$art) {
		$ROBJ->message("Article '0%d' not found", $a_pkey);
		return 11;
	}
	if (! $art->{com_ok} || $blog->{com_ok_force} eq '0') {
		# コメント不許可
		$ROBJ->message('This article not allow comments');
		return 12;
	}
	if ($form->{hidden} && (! $art->{hcom_ok} || $blog->{hcom_ok_force} eq '0')) {
		# 非公開コメント不許可
		$ROBJ->message('This article not allow hidden comments');
		return 13;
	}
	# データ整理
	if ($auth->{ok}) {
		$form->{name} = $auth->{name};
		$form->{id}   = $auth->{id};
	} else {
		delete $form->{id};
	}
	# 実体参照の無効化
	$form->{name}        =~ s/&/&amp;/g;
	$form->{comment_txt} =~ s/&/&amp;/g;

	# フォーム値から値削除
	$self->delete_ip_host_agent($form);
	delete $form->{tm};

	# コメント保留
	$form->{enable} = 1;
	my $defer = int($blog->{defer_com});	# 0=off, 1=保留, 2=ユーザー以外保留
	if ($self->{allow_edit}) { $defer=0; }	# 編集権限者のコメントは保留しない
	if (!$self->{allow_edit} && $defer) {
		if ($defer==2 && $auth->{ok}) { $defer=0; }	# ユーザーのみ許可
	}
	if ($defer) { $form->{enable}=0; }	# コメント保留

	# コメント投稿前イベント
	my $er = $self->call_event('COMMENT_BEFORE', $form, $art);
	if ($er) { return $er; }

	# コメントの登録
	my ($r,$pkey) = $self->regist_comment($blogid, $form, $art);
	if ($r) {
		return $r;	# error
	}
	$form->{pkey} = $pkey;

	# コメント数記録
	$self->calc_comments($blogid, $a_pkey);

	# コメント投稿後イベント
	$self->call_event('COMMENT_AFTER', $form, $art);

	# 新着記録
	if (! $self->{allow_edit}) {
		$self->update_blogset($blog, 'newcom_flag', 1);
		# 新着コメントイベント
		$self->call_event('COMMENT_NEW', $form, $art);

	}
	$self->call_event('COMMENT_STATE_CHANGE', [$a_pkey], [$pkey]);
	$self->call_event('ARTCOM_STATE_CHANGE',  [$a_pkey], [$pkey]);

	return 0;
}

#------------------------------------------------------------------------------
# ●コメントを登録する
#------------------------------------------------------------------------------
# 以下に信頼できない情報が入力されないように注意すること。
#
sub regist_comment {
	my ($self, $blogid, $form, $art, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $name   = $form->{name};
	my $email  = $form->{email};	# 任意
	my $url    = $form->{url};	# 任意
	my $text   = $form->{comment_txt} ne '' ? $form->{comment_txt} : $form->{text};
	my $hidden = $form->{hidden} ? 1 : 0;
	$text =~ s/^(?:\s*\n)*//;	# 先頭は空行のみ除去
	$text =~ s/[\s*\n]*$//;		# 末尾は\n\s全部除去
	$ROBJ->trim($name, $email, $url);
	$ROBJ->tag_escape( $name, $text );
	$ROBJ->clear_form_error();

	# データチェック
	if ($text eq '') { $ROBJ->form_error('text', 'comment text is empty'); }
	if ($name eq '') { $ROBJ->form_error('name', 'name is empty'); }
	$text =~ s/\r?\n/<br>/g;	# 改行を br に置換

	# URL/メールアドレスの安全確認
	if ($email !~ /^[-_\.a-zA-Z0-9]+\@[-_\.a-zA-Z0-9]+$/) { $email=undef; }
	if ($url =~ m|^https?://[-_\.a-zA-Z0-9]+|) {
		$ROBJ->encode_uri( $url );
	} else {
		$url='';
	}

	# 記事情報がなければロード
	if (!$art) {
		my $art = $self->load_article($blogid, "0" . int($art->{a_pkey}));
		if (!$art) {
			$ROBJ->message('a_pkey', "Article '0%d' not found", int($art->{a_pkey}));
			return 11;
		}
	}
	my $a_pkey = $art->{pkey};

	# エラー処理
	if ($ROBJ->form_error()) { return 99; }	# エラーがあった

	# コメントの書き込み処理
	my %com;
	$com{text}  = $text;
	$com{email} = $email;
	$com{url}   = $url;
	$com{name}  = $name;
	my $id = $form->{id};
	if ($id ne '') {
		$id =~ s/\W//g;
		$com{id} = $id;
	}
	$self->set_ip_host_agent(\%com, $opt);

	$com{tm} = int($opt->{tm}) || $ROBJ->{TM};
	if ($opt->{num} != 0) {
		$com{num} = int($opt->{num});
	}
	$com{enable} = ($form->{enable} && !$form->{hidden} && $art->{enable}) ? 1 : 0;
	$com{hidden} =  $form->{hidden} ? 1 : 0;

	# 記事の情報をキャッシュして保存
	$com{a_pkey}     = $a_pkey;
	$com{a_yyyymmdd} = $art->{yyyymmdd};
	$com{a_title}    = $art->{title};
	$com{a_elink_key}= $art->{link_key};
	$self->link_key_encode( $com{a_elink_key} );

	# save_pkey
	if ($opt->{save_pkey}) {
		my $pkey = int($form->{pkey});
		if ($pkey) { $com{pkey} = $pkey; }
	}

	my $com_pkey = $DB->insert("${blogid}_com", \%com);
	if (!$com_pkey) {
		$ROBJ->message('Comment post failed');
		return 20;
	}
	return wantarray ? (0,$com_pkey) : 0;
}

#------------------------------------------------------------------------------
# ●コメントの表示状態変更、または削除
#------------------------------------------------------------------------------
sub edit_comment {
	my ($self, $mode, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	if ($keylist !~ /^\d+$/ && $keylist->[0] !~ /^\d+$/) {
		return (0,0);
	}

	# 該当する記事のリスト
	my $ary = $DB->select_by_group("${blogid}_com",{
		group_by => 'a_pkey',
		match => { pkey => $keylist }
	});
	my @a_pkeys = map { $_->{a_pkey} } @$ary;

	# 削除
	my $cnt;
	my $event_name;
	if ($mode eq 'delete') {
		$event_name = 'COMMENTS_DELETE';
		$cnt = $DB->delete_match("${blogid}_com", 'pkey', $keylist);

	} elsif ($mode eq 'enable') {
		$event_name = 'COMMENTS_EDIT';

		# 非公開記事のコメントは公開しない
		my $ary = $DB->select_match("${blogid}_art", 
			'pkey', \@a_pkeys,
			'*cols', ['pkey', 'enable']
		);
		my @exlist;
		foreach(@$ary) {
			if ($_->{enable}) { next; }
			push(@exlist, $_->{pkey});
		}
		$cnt = $DB->update_match("${blogid}_com",
			{ enable => 1 },
			'enable', 0,
			'hidden', 0,
			'pkey', $keylist,
			'-a_pkey', \@exlist	# not match
		);
	} else {
		$event_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("${blogid}_com",
			{ enable => 0 },
			'enable',  1,
			'pkey', $keylist
		);
	}

	# イベント処理
	if ($cnt) {
		foreach( @a_pkeys ) {
			$self->calc_comments($blogid, $_);
		}
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            \@a_pkeys, $keylist, $cnt);
		$self->call_event('COMMENT_STATE_CHANGE', \@a_pkeys, $keylist);
		$self->call_event('ARTCOM_STATE_CHANGE',  \@a_pkeys, $keylist);
	}

	return wantarray ? (0, $cnt) : 0;
}

#------------------------------------------------------------------------------
# ●コメント数を計算し記録（コメント番号も設定）
#------------------------------------------------------------------------------
sub calc_comments {
	my ($self, $blogid, $a_pkey) = @_;
	my $DB = $self->{DB};

	my %h;
	$h{match} = {a_pkey => $a_pkey};
	$h{cols}  = ['pkey', 'enable', 'num'];
	$h{sort}  = ['pkey'];
	my $com = $DB->select("${blogid}_com", \%h);
	my $c = 0;
	my $num=0;
	foreach(@$com) {
		if ($_->{enable}) { $c++; }
		if ($_->{num}) { $num=$_->{num}; next; }
		# コメント番号が未定義
		$DB->update_match("${blogid}_com", {num => ++$num}, 'pkey', $_->{pkey});
	}

	my %update;
	$update{coms}     = $c;
	$update{coms_all} = $#$com + 1;
	return $DB->update_match("${blogid}_art", \%update, 'pkey', $a_pkey);
}

###############################################################################
# ■ブログ管理テーブル更新、ブログの設定保存、プラグイン設定保存
###############################################################################
#------------------------------------------------------------------------------
# ●記事数情報の更新
#------------------------------------------------------------------------------
sub update_bloginfo_article {
	my $self = shift;
	my $blogid = $self->{blogid};
	my $DB = $self->{DB};

	my ($ary,$hits) = $DB->select("${blogid}_art",{
		flag     => { enable => 1 },
		cols     => [ 'title', 'tm' ],
		sort     => [ 'yyyymmdd', 'tm' ],
		sort_rev => [ 1, 1 ],
		limit    => 1,
		require_hits => 1
	});

	my %up;
	if ($ary && @$ary) {
		$up{newest_title} = $ary->[0]->{title};
		$up{arts}   = $hits;
		$up{art_tm} = $ary->[0]->{tm};
	} else {
		$up{newest_title} = undef;
		$up{arts}   = 0;
		$up{art_tm} = 0;
	}
	$self->update_blogset($blogid, 'arts', $up{arts});
	$self->update_bloginfo($blogid, \%up);
}

#------------------------------------------------------------------------------
# ●コメント数情報の更新
#------------------------------------------------------------------------------
sub update_bloginfo_comment {
	my $self = shift;
	my $blogid = $self->{blogid};
	my $DB = $self->{DB};

	my ($ary,$hits) = $DB->select("${blogid}_com",{
		flag     => { enable => 1 },
		cols     => [ 'tm' ],
		sort     => 'tm',
		sort_rev => 1,
		limit    => 1,
		require_hits => 1
	});

	my %up;
	if ($ary && @$ary) {
		$up{coms}   = $hits;
		$up{com_tm} = $ary->[0]->{tm};
	} else {
		$up{coms}   = 0;
		$up{com_tm} = 0;
	}
	$self->update_blogset($blogid, 'coms', $up{coms});
	$self->update_bloginfo($blogid, \%up);
}

#------------------------------------------------------------------------------
# ●ブログ管理テーブルの更新
#------------------------------------------------------------------------------
sub update_bloginfo {
	my ($self, $blogid, $update) = @_;
	my $ROBJ = $self->{ROBJ};

	$update->{tm} = $ROBJ->{TM};
	my $r  = $self->{DB}->update_match($self->{bloglist_table}, $update, 'id', $blogid);
	if (!$r) { return 2; }	# Fail
	return 0;		# Success
}

#------------------------------------------------------------------------------
# ●ブログの設定の変更
#------------------------------------------------------------------------------
sub update_blogset {
	my ($self, $blogid, $k, $v) = @_;
	my $blog = ref($blogid) ? $blogid : $self->load_blogset($blogid);
	$self->update_hash( $blog, $k, $v );
	$blog->{_update}=1;
}
sub update_cur_blogset {
	my $self = shift;
	$self->update_blogset( $self->{blog}, @_ );
}

#------------------------------------------------------------------------------
# ●プラグイン用の設定を保存
#------------------------------------------------------------------------------
sub update_plgset {
	my ($self,$name,$h,$val) = @_;
	if (!$h) { return; }
	if (ref($h) ne 'HASH') {	# $h is key
		return $self->update_cur_blogset("p:$name:$h", $val);
	}

	my $head = "p:$name";
	my %up;
	foreach(keys(%$h)) {
		$up{"$head:$_"} = $h->{$_};
	}
	delete $up{_blogid};
	$self->update_cur_blogset(\%up);
}

###############################################################################
# ■編集ロック機能
###############################################################################
#
# 同じ記事をロックしている場合に、警告を出すシステム
#
#------------------------------------------------------------------------------
# ●ロック状態をチェック
#------------------------------------------------------------------------------
sub edit_check_lock {
	my $self = shift;
	my $name = shift;

	my ($fh, $ary) = $self->load_lock_file( $name );
	close($fh);

	my $json= $self->generate_json($ary, ['id', 'sid', 'tm']);
	return (0, $json);
}

#------------------------------------------------------------------------------
# ●ロックをかける
#------------------------------------------------------------------------------
sub edit_unlock {
	my $self = shift;
	$self->edit_lock($_[0], $_[1], 'unlock');
}
sub edit_lock {
	my $self = shift;
	my ($name, $sid, $unlock) = @_;
	my $ROBJ = $self->{ROBJ};
	my $id   = $ROBJ->{Auth}->{id};
	$sid =~ s/[\x00-\x1f]//g;

	if (!$self->{allow_edit}) { return -1; }
	if ($name eq '') { return -2; }
	if ($self->{sys}->{edit_lock_time} < 1) { return 1; }

	# lock処理
	my ($fh, $ary) = $self->load_lock_file( $name );
	if (!$fh) { return 7; }
	$ary = [ grep {$_->{id} ne $id || $_->{sid} ne $sid} @$ary ];
	if ($sid ne '') {
		if (!$unlock) {
			push(@$ary, {
				id => $id,
				sid=> $sid,
				tm => $ROBJ->{TM}
			});
		}
		$self->update_lock_file($fh, $ary);
		pop(@$ary);
	} else {
		close($fh);
	}

	# ロック状況を返す
	my $json= $self->generate_json($ary, ['id', 'sid', 'tm']);
	return (0, $json);
}

#------------------------------------------------------------------------------
# ●ロックファイルのロード
#------------------------------------------------------------------------------
sub load_lock_file {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	$name =~ s/[^\w\-:]//g;

	# 時間
	my $ctime = $self->{sys}->{edit_lock_time};

	# tmpwatch
	my $dir =  $self->{blog_dir} . 'lock/';
	$ROBJ->mkdir($dir);
	$ROBJ->tmpwatch( $dir, $ctime+10 );

	# lock処理
	my $file = $dir . $name;
	my ($fh,$lines) = $ROBJ->fedit_readlines($file);
	if (!$fh) { return ; }

	my @ary;
	my $obs_time = $ROBJ->{TM} - ($self->{sys}->{edit_lock_time}+5);
	foreach(@$lines) {
		my %h;
		chomp($_);
		($h{id}, $h{sid}, $h{tm}) = split("\t", $_);
		if ($h{tm} < $obs_time) { next; }
		push(@ary, \%h);
	}
	return ($fh, \@ary);
}

#------------------------------------------------------------------------------
# ●ロックファイルのアップデート
#------------------------------------------------------------------------------
sub update_lock_file {
	my $self = shift;
	my $fh   = shift;
	my $ary  = shift;
	my $ROBJ = $self->{ROBJ};

	my @lines = map { "$_->{id}\t$_->{sid}\t$_->{tm}\n" } @$ary;
	return $ROBJ->fedit_writelines($fh, \@lines);
}

###############################################################################
# ■スマホメニュー再生成
###############################################################################
#------------------------------------------------------------------------------
# ●スマホメニューの生成
#------------------------------------------------------------------------------
sub generate_spmenu {
	my $self = shift;
	my $blog = $self->{blog};

	my $ary = $self->load_spmenu_info();
	if (! @$ary) {
		$self->update_cur_blogset('spmenu', '');
		return 0;
	}

	# 要素がある
	my $out = "<ul>\n";
	foreach(@$ary) {
		my $title = $_->{title};
		my $html  = $blog->{"p:$_->{name}:html"};
		my $h = $self->parse_html_for_spmenu($html);
		my $url = $h->{url} || '#';
		$out .= "<li><a href=\"$url\">$title</a>\n$h->{html}\n</li>\n";
	}
	$out .= "</ul>\n";
	if ($#$ary > 0) {
		my $title = $blog->{spmenu_title} || 'menu';
		$out = "<ul><li><a href=\"#\">$title</a>\n$out</li></ul>\n";
	}
	$self->update_cur_blogset('spmenu', $out);
	return 0;
}

#------------------------------------------------------------------------------
# ●保存してあるスマホメニュー情報を分解
#------------------------------------------------------------------------------
sub load_spmenu_info {
	my $self = shift;
	my $blog = $self->{blog};
	my $info = $blog->{spmenu_info};

	my @ary = split("\n", $info);
	my @ary2;
	my $f;
	foreach(@ary) {
		chomp($_);		# $_に処理しないように
		my ($name,$title) = split(/=/, $_, 2);
		push(@ary2, {
			name  => $name,
			title => $title
		});
	}
	return \@ary2;
}

#------------------------------------------------------------------------------
# ●メニュー用に要素を加工
#------------------------------------------------------------------------------
sub parse_html_for_spmenu {
	my $self = shift;
	my $html = shift;
	my $ROBJ = $self->{ROBJ};

	my %h;
	my $title;
	$html =~ s|<div\s*class="\s*hatena-moduletitle\s*">(.*?)</div>|$title=$1,''|e;
	if ($title =~ /<a.*? href\s*=\s*"([^"]+)"/) {
		$h{url} = $1;
	}
	$ROBJ->tag_delete($title);

	my $escaper = $self->load_tag_escaper_force( 'spmenu' );
	$title = $escaper->escape( $title );
	$html  = $escaper->escape( $html  );

	$html =~ s|</a>(.*?)</li>|$1</a></li>|g;
	$html =~ s/^[\s\n\r]+//;
	$html =~ s/[\s\n\r]+$//;
	if ($html !~ m|^<ul>|) { return; }
	if ($html !~ m|</ul>$|) { return; }

	$h{html}  = $html;
	$h{title} = $title;
	return \%h;
}

###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●特別なシステムモードへ
#------------------------------------------------------------------------------
sub special_system_mode {
	my $self = shift;
	$self->system_mode(@_);

	# フラグ設定
	$self->{special_system_mode} = 1;
	# デフォルトテーマの強制ロード
	$self->load_theme( $self->{default_theme} );
}

#------------------------------------------------------------------------------
# ●表示パスワード機能
#------------------------------------------------------------------------------
sub check_view_pass {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $pass = $self->{view_pass};
	my $ckey = 'view-pass-' . $self->{blogid};

	# cookie
	my $cpass = $ROBJ->get_cookie()->{$ckey};
	if ($pass eq $cpass) { return; }

	# パスワード要求
	$ROBJ->set_status(403);
	$ROBJ->{POST} = 0;
	$ROBJ->{Form} = {};
	$self->{skeleton} = '_sub/input_view_pass';
	$self->{view_pass_key} = $ckey;
}

#------------------------------------------------------------------------------
# ●メンテナンスモード
#------------------------------------------------------------------------------
sub mainte_mode {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	# 管理者
	if ($auth->{isadmin}) {
		if (!$ROBJ->{POST}) {
			$ROBJ->message($self->{require_update} ? 'Require update' : 'Now maintenance mode');
		}
		return ;
	}
	# POSTはログインのみ許可
	my $form = $ROBJ->{Form};
	if ($form->{action} ne 'login') {
		$ROBJ->{POST} = 0;
		$ROBJ->{Form} = {};
	}
	if (!$ROBJ->{POST} && $self->{skeleton} !~ /^login\w*$/) {
		$ROBJ->set_status(503);
		$self->{skeleton} = '_sub/maintenance_msg';
	} else {
		$self->set_and_select_blog_force('');
	}
	return;
}

#------------------------------------------------------------------------------
# ●hash/arrayツリーからjsonを生成する
#------------------------------------------------------------------------------
sub generate_json {
	my $self = shift;
	my $data = shift;
	my $cols = shift;	# データカラム
	my $ren  = shift || {};	# カラムのリネーム情報
	my $tab  = shift || '';
	my @ary;
	
	sub encode {
		my $v = shift;
		if ($v =~ /^\d+$/) { return $v; }
		# 文字列
		$v =~ s/\\/&#92;/g;
		$v =~ s/\n/\\n/g;
		$v =~ s/\t/\\t/g;
		$v =~ s/"/\\"/g;
		return '"' . $v . '"';
	}

	my $is_hash = ref($data) eq 'HASH';
	my $dat = $is_hash ? [$data] : $data;
	foreach(@$dat) {
		if (!ref($_)) {
			push(@ary, &encode($_));
			next;
		}
		my @a;
		my @b;
		my $_cols = $cols ? $cols : [ keys(%$_) ];
		foreach my $x (@$_cols) {
			my $k = exists($ren->{$x}) ? $ren->{$x} : $x;
			my $v = $_->{$x};
			if (!ref($v)) {
				push(@a, "\"$k\": " . &encode( $v ));
				next;
			}
			# 入れ子
			my $ch = $self->generate_json( $v, $cols, $ren, "\t$tab" );
			push(@b, "\"$k\": $ch");
		}
		push(@ary, $is_hash
			? "{\n$tab\t" . join(",\n$tab\t", @a, @b) . "\n$tab}"
			: "$tab\t{"   . join(", "       , @a, @b) . "}"
		);
	}
	return $is_hash ? $ary[0] : "[\n" . join(",\n", @ary) . "\n$tab]";
}

#------------------------------------------------------------------------------
# ●タグのノーマライズ
#------------------------------------------------------------------------------
# aaa,bbb::ccc,bbb,ddd,aaa → aaa,bbb::ccc,ddd
sub tag_normalize {
	my $self = shift;
	my $tags = shift;
	if (!ref($tags)) {
		$tags =~ s/^\s*(.*)?\s*$/$1/g;
		$tags = [ split(/\s*,\s*/, $tags) ];
	}
	# 重複除去
	my %h;
	my @ary;
	foreach(@$tags) {
		$_ =~ s/\s+/ /g;	# space 1個に
		if (0 <= index(":$_:", ':::')) { next; }
		if ($h{$_}) { next; }	# 重複

		push(@ary, $_);
		# 重複除去のためのフラグ
		$h{$_}=1;
		my @x = split('::', $_);
		my $s = shift(@x);
		foreach(@x) {	# aa::bb::ccのときの aa と aa::bb が -1 になる
			$h{$s}=-1;
			$s .= "::$_";
		}
	}
	return grep { $h{$_} != -1 } @ary;
}

#------------------------------------------------------------------------------
# ●parserのロード
#------------------------------------------------------------------------------
sub load_parser {
	my $self = shift;
	my $name = shift;
	if ($name =~ /\W/) { return; }

	my $cid = $self->{blogid} . $name;
	my $cache = $self->{__parser_cache} ||= {};
	if ($cache->{$cid}) { return $cache->{$cid}; }

	return ($cache->{$cid} = $self->{ROBJ}->call( '_parser/' . $name ));
}

#------------------------------------------------------------------------------
# ●TagEscapeのロード
#------------------------------------------------------------------------------
sub load_tag_escaper {
	my $self = shift;
	my $obj  = $self->load_tag_escaper_force(@_);
	$obj->{allow_anytag} = $self->{trust_mode};
	return $obj;
}
sub load_tag_escaper_force {
	my $self = shift;

	my $head = $self->{allow_tags_head};
	my @ary  = map { "$head$_.txt" } @_;
	my $obj  = $self->_load_tag_escaper(@ary);
	return $obj;
}
sub _load_tag_escaper {
	my $self  = shift;
	my $key   = join('*',@_);
	my $cache = $self->{__tag_escaper_cache} ||= {};
	my $obj   = $cache->{$key} || $self->{ROBJ}->loadpm('TextParser::TagEscape', @_);
	return ($cache->{$key} = $obj);
}

#------------------------------------------------------------------------------
# ●指定文字数でクリップする
#------------------------------------------------------------------------------
sub string_clip {
	my ($self, $string, $j_len) = @_;
	my $jcode = $self->{ROBJ}->load_codepm();
	my $len_orig = length($string);
	$string = $jcode->jsubstr($string, 0, $j_len);
	if ($len_orig > length($string)) {	# 省略時 ... を付加
		$string .= $self->{sys}->{clip_append} || '...';
	}
	return $string;
}

#------------------------------------------------------------------------------
# ●IP, HOST, AGENTを安全に設定する
#------------------------------------------------------------------------------
sub set_ip_host_agent {
	my ($self, $h, $default) = @_;
	my $ROBJ = $self->{ROBJ};

	my $flag = $default->{ip};
	$h->{ip}    = $flag ? $default->{ip}    : $ENV{REMOTE_ADDR};
	$h->{host}  = $flag ? $default->{host}  : $ENV{REMOTE_HOST};
	$h->{agent} = $flag ? $default->{agent} : $ENV{HTTP_USER_AGENT};

	$ROBJ->tag_escape($h->{ip}, $h->{host}, $h->{agent});
}

#------------------------------------------------------------------------------
# ●フォームのIP, HOST, AGENT情報を削除
#------------------------------------------------------------------------------
sub delete_ip_host_agent {
	my ($self, $h) = @_;
	delete $h->{ip};
	delete $h->{host};
	delete $h->{agent};
}

#------------------------------------------------------------------------------
# ●#a0b0c0 → 160, 176, 192
#------------------------------------------------------------------------------
sub hex2rgb {
	my ($self, $hex) = @_;
	if ($hex !~ /#([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])/) { return ; }
	return hex($1) . ',' . hex($2) . ',' . hex($3);
}

#------------------------------------------------------------------------------
# ●セッションログのオープン
#------------------------------------------------------------------------------
sub open_session {
	my $session = &open_session_for_load(@_);
	$session->open();
	$session->autoflush();
	return $session;
}

sub open_session_for_load {
	my ($self, $snum) = @_;
	my $ROBJ = $self->{ROBJ};
	my $session = $ROBJ->loadpm("Base::SessionFile", $ROBJ->{Cookie}->{session}->{sid}, int($snum));
}

#------------------------------------------------------------------------------
# ●コールバックの登録
#------------------------------------------------------------------------------
sub regist_end_callback {
	my $self = shift;
	my $k = shift;
	$self->{end_callback}->{$k} = shift;
}

#------------------------------------------------------------------------------
# ●プラグイン番号の取得（プラグイン側から呼ばれる）
#------------------------------------------------------------------------------
sub plugin_num {
	my $self = shift;
	return ($_[0] =~ /^(?:[A-Za-z][\w\-]*),(\d+)$/) ? $1 : undef;
}

1;
