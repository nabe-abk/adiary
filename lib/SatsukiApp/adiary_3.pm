use strict;
#-------------------------------------------------------------------------------
# adiary_3.pm (C)2014 nabe@abk
#-------------------------------------------------------------------------------
# ・画像管理
# ・デザイン関連
# ・ブログの設定
# ・記事、コメントなどの削除関連
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
package SatsukiApp::adiary;
###############################################################################
# ■画像管理
###############################################################################
#------------------------------------------------------------------------------
# ●画像dir関連の初期化
#------------------------------------------------------------------------------
sub init_image_dir {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir = $self->blogimg_dir();
	$ROBJ->mkdir($dir);
	$ROBJ->mkdir($dir . '.trashbox/');	# ごみ箱フォルダ

	# ファイルリストの生成
	$self->genarete_imgae_dirtree();
	
	
}

#------------------------------------------------------------------------------
# ●画像ディレクトリツリーの生成
#------------------------------------------------------------------------------
sub genarete_imgae_dirtree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir  = $self->blogimg_dir();
	my $tree = $self->get_dir_tree("$dir", sub{
		my ($dir, $dirs, $files) = @_;
		$ROBJ->mkdir("${dir}.thumbnail");
		foreach(@$files) {
			# サムイネイル生成
		}
	});

	my $json = $self->generate_dynatree_json($tree->{children}, 'name', ['size', 'date', 'count']);
	$ROBJ->fwrite_lines( $self->{blogpub_dir} . 'images.json', $json);

	$self->debug("$tree->{count} files found!");


}

#------------------------------------------------------------------------------
# ●ディレクトリ階層の全データ取得
#------------------------------------------------------------------------------
sub get_dir_tree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $dir  = $ROBJ->get_filepath(shift);
	my ($func) = @_;	# callback

	my @ary;
	my $cnt=0;	# ファイル数カウント
	my $files = $ROBJ->search_files($dir, {dir=>1});
	foreach(@$files) {
		if (ord($_) == ord('.')) { next; }	# .file は無視
		my @st = stat("$dir$_");
		if (substr($_,-1) ne '/') {
			# ただのファイル
			push(@ary, {
				name => $_,
				size => $st[7],
				date => $st[9]
			});
			$cnt++;
			next;
		}
		# ディレクトリ
		my $tree = $self->get_dir_tree("$dir$_", @_);
		push(@ary, {
			name  => $_,
			count => $tree->{count},
			date  => $st[9],
			children => $tree->{children}
		});
		$cnt += $tree->{count};
	}

	if ($func) {	# callback
		&$func($dir, \@ary);
	}

	return {children => \@ary, count => $cnt};
}

#------------------------------------------------------------------------------
# ●画像dir関連の初期化
#------------------------------------------------------------------------------
sub blogimg_dir {
	my $self = shift;
	return $self->{blogpub_dir} . 'image/';
}

###############################################################################
# ■設定関連
###############################################################################
#------------------------------------------------------------------------------
# ●ブログの設定変更（保存）
#------------------------------------------------------------------------------
sub save_blogset {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my ($new_set, $blogid) = @_;

	# 権限確認
	my $blog;
	if ($blogid eq '') {
		if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 10; }
		$blogid = $self->{blogid};
		$blog   = $self->{blog};
	} else {
		# 他のブログ or デフォルト設定
		if (! $auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 11; }
		$blog = $self->load_blogset( $blogid );
		if (! $blog) { $ROBJ->message("Blog '%s' not found", $blogid); return 12; }
	}

	if ($blogid ne '*') {
		# 通常のブログ設定保存
		$self->update_blogset($blogid, $new_set);

		# プライベートモードチェック
		$self->save_private_mode( $blogid );

		# ブログ一覧情報に保存
		$self->update_bloginfo($blogid, {
			private   => $blog->{private},
			blog_name => $blog->{blog_name}
		});
	} else {
		# デフォルトのブログ設定値保存
		# 新規設定値をマージ
		$ROBJ->into($blog, $new_set);	# %$blog <- %$new_set

		# 固定値
		$blog->{arts} = 0;
		$blog->{coms} = 0;

		# ファイルに保存
		$ROBJ->fwrite_hash($self->{my_default_setting_file}, $blog);
	}

	return 0;
}

#------------------------------------------------------------------------------
# ●プライベートモードの現在の状態保存
#------------------------------------------------------------------------------
sub save_private_mode {
	my $self = shift;
	my $blogid = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->load_blogset($blogid);

	my $postfix = $blog->{blogpub_dir_postfix};
	my $evt_name;
	if ($blog->{private} && $postfix eq '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid, $self->{sys}->{dir_postfix_len} || $self->{dir_postfix_len} );
		$evt_name = "PRIVATE_MODE_ON";
	} elsif (!$blog->{private} && $postfix ne '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid, 0 );
		$evt_name = "PRIVATE_MODE_OFF";
	} else {
		return ;	# 特に変更がなければ何もしない
	}
	if (!defined $postfix) {
		$ROBJ->error('Rename failed blog public directory (%s)', $blogid);
		return 1;
	}
	$blog->{blogpub_dir_postfix} = $postfix;

	$self->call_event($evt_name);
	$self->rebuild_blog();
}

#------------------------------------------------------------------------------
# ●ブログ公開ディレクトリ名の変更
#------------------------------------------------------------------------------
sub change_blogpub_dir_postfix {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($blogid, $len) = @_;
	$len = int($len) || 6;

	my $postfix = '';
	if ($len > 0) {
		if (32<$len) { $len=32; }
		$postfix = $ROBJ->get_rand_string_salt($len);
		$postfix =~ s/\W/-/g;
		$postfix = '.' . $postfix;
	}

	# ディレクトリ名変更
	my $cur_dir = $ROBJ->get_filepath( $self->blogpub_dir($blogid) );
	chop($cur_dir);
	my $new_dir = $cur_dir;
	$new_dir =~ s|\.[^./]+$||;
	$new_dir .= $postfix;

	# リネーム
	my $r = rename( $cur_dir, $new_dir );
	if (!$r) { return undef; }

	return $postfix;
}

###############################################################################
# ■タグの編集処理
###############################################################################
#------------------------------------------------------------------------------
# ●タグの編集
#------------------------------------------------------------------------------
sub tag_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $joins = $form->{join_ary} || [];
	my $dels  = $form->{del_ary}  || [];
	my $edits = $form->{tag_ary};

	# タグリスト
	my @tags;
	{
		my $ary = $DB->select_match("${blogid}_tag");
		foreach(@$ary) {
			$tags[ $_->{pkey} ] = $_;
		}
	}

	my %e_art;	# 編集したarticleのpkey
	# 中で e_art を参照しているので順番を逆にしてはいけない。
	foreach(@$joins) {
		my ($master, @slaves) = split(',',$_);
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', \@slaves, '*cols', ['a_pkey', 'a_enable'] );
		$DB->delete_match("${blogid}_tagart", 't_pkey', [$master, @slaves]);
		$DB->delete_match("${blogid}_tag", 'pkey', \@slaves);
		foreach(@$ta) {
			if ($e_art{ $_->{a_pkey} }) { next; }
			$DB->insert("${blogid}_tagart", {
				a_pkey => $_->{a_pkey},
				t_pkey => $master,
				a_enable => $_->{a_enable}
			});
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの削除
	if(@$dels) {
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $dels, '*cols', 'a_pkey' );
		$DB->delete_match("${blogid}_tagart", 't_pkey', $dels);
		$DB->delete_match("${blogid}_tag"   ,   'pkey', $dels);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの編集
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$name) = split(',',$_,4);
		$ROBJ->string_normalize($name);
		$ROBJ->tag_escape($name);
		if($upnode) {
			$name = $tags[ $upnode ]->{name} . '::' . $name;
		}
		my $org = $tags[ $pkey ];
		if ($upnode != $org->{upnode} || $name ne $org->{name}) {
			my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $pkey);
			foreach(@$ta) {
				$e_art{ $_->{a_pkey} } = 1;
			}
		} elsif ($priority == $org->{priority}) {
			next;	# 変更なし
		}
		my %h = (
			upnode   => ($upnode==0 ? undef : $upnode),
			priority => $priority,
			name     => $name
		);
		$DB->update_match("${blogid}_tag", \%h, 'pkey', $pkey);
		$h{pkey} = $pkey;
		$tags[ $pkey ] = \%h;
	}

	# 変更があったarticleのタグ情報を書き換える
	foreach my $a_pkey (keys(%e_art)) {
		my $ta = $DB->select_match("${blogid}_tagart", 'a_pkey', $a_pkey, '*cols', 't_pkey');
		my @t_pkeys = map { $_->{t_pkey} } @$ta;

		# upnodeのいずれかのタグを含まないかチェック
		my %h;
		foreach(@t_pkeys) {
			my $up = $tags[$_]->{upnode};
			while($up) {
				$h{$up} = 1;
				$up = $tags[$up]->{upnode};
			}
		}
		my @tag;
		my @dels;
		foreach(@t_pkeys) {
			if ($h{$_}) {
				push(@dels, $_);
				next;
			}
			push(@tag, $tags[ $_ ]->{name});
		}
		# ツリー組み換えにより重複したタグを削除
		$DB->delete_match("${blogid}_tagart", 'a_pkey', $a_pkey, 't_pkey', \@dels);

		# 新しいタグ情報に書き換え
		my $tag = join(',', @tag);
		$DB->update_match("${blogid}_art", {tags => $tag}, 'pkey', $a_pkey);
	}
	$self->update_taglist();

	return 0;
}

###############################################################################
# ■コンテンツの編集処理
###############################################################################
#------------------------------------------------------------------------------
# ●コンテンツの編集
#------------------------------------------------------------------------------
sub contents_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	# タグリスト
	my %cons;
	{
		my $ary = $DB->select_match("${blogid}_art",
			'enable', 1,
			'-ctype', '',
			'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'coms_all']
		);
		%cons = map { $_->{pkey} => $_ } @$ary;
	}

	# タグの編集
	my $edits = $form->{contents_ary};
	my $com_edit;
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$link_key) = split(',',$_,4);
		$ROBJ->string_normalize($link_key);
		if ($link_key =~ /^[\"\',]/ || $link_key =~ /^\s*$/ || $link_key =~ m|^[\d&]|) {
			$link_key = '';
		}
		my $org = $cons{ $pkey };
		my %h;
		if ($upnode != $org->{upnode} && $cons{$upnode}) {
			$h{upnode} = $upnode;
		}
		if ($link_key ne '' && $link_key ne $org->{link_key}) {
			$h{link_key} = $link_key;
		}
		if ($priority != $org->{priority}) {
			$h{priority} = $priority;
		}
		if (!%h) { next; }

		$DB->update_match("${blogid}_art", \%h, 'pkey', $pkey);
		if (exists($h{link_key}) && $cons{$pkey}->{coms_all}) {
			my $elkey = $h{link_key};
			$self->link_key_encode($elkey);
			my $r = $DB->update_match("${blogid}_com", { a_elink_key=>$elkey }, 'a_pkey', $pkey);
			if ($r) { $com_edit=1; }
		}
	}

	# イベント処理
	my $a_pkeys = keys(%cons);
	$self->call_event('ARTICLE_STATE_CHANGE', $a_pkeys);
	if ($com_edit) {
		$self->call_event('COMMENT_STATE_CHANGE', $a_pkeys);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', $a_pkeys);

	return 0;
}

###############################################################################
# ■ユーザー定義記法タグ、ユーザーCSSの設定
###############################################################################
#------------------------------------------------------------------------------
# ●ユーザー定義タグファイルのロード
#------------------------------------------------------------------------------
sub load_usertag {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $ROBJ->get_filepath( $self->{blog_dir} . 'usertag.txt' );
	if (!-e $file) { $file = $self->{default_usertag_file}; }
	return join('', @{ $ROBJ->fread_lines($file) });
}

#------------------------------------------------------------------------------
# ●ユーザー定義タグの保存
#------------------------------------------------------------------------------
sub save_usertag {
	my ($self, $tag_txt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $r = $ROBJ->fwrite_lines( $self->{blog_dir} . 'usertag.txt', $tag_txt );
	if ($r) {
		$ROBJ->message('Save failed');
		return 1;
	}
	return 0;
}

#------------------------------------------------------------------------------
# ●ユーザーCSSファイルのロード
#------------------------------------------------------------------------------
sub load_usercss {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $file = $ROBJ->get_filepath( $self->{blogpub_dir} . 'usercss.css' );
	if (!-e $file) { $file = $self->{default_usercss_file}; }
	return join('', @{ $ROBJ->fread_lines($file) });
}

#------------------------------------------------------------------------------
# ●ユーザーCSSの保存
#------------------------------------------------------------------------------
sub save_usercss {
	my ($self, $css_txt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $file = $self->{blogpub_dir} . 'usercss.css';
	if ($css_txt =~ /^\s*$/) {
		$ROBJ->file_delete( $file );
		return 0;
	}

	# XSS対策チェック
	if (! $self->{trust_mode}) { $css_txt = $self->css_escape( \$css_txt ); }

	my $r = $ROBJ->fwrite_lines( $file, $css_txt );
	if ($r) {
		$ROBJ->message('Save failed');
		return 1;
	}
	return 0;
}

#------------------------------------------------------------------------------
# ●スタイルシートのエスケープ処理（XSS対策）
#------------------------------------------------------------------------------
sub css_escape {
	my ($self, $_css) = @_;
	my $css;
	if (ref($_css) eq 'ARRAY')  { $_css = join('', @$_css); }
	if (ref($_css) eq 'SCALAR') { $css = $_css; } else { $css = \$_css; }

	# tab lf 以外の制御文字を除去
	$$css =~ s/[\x00-\x08\x0b-\x1f]//g;
	# コメントの退避
	my @comment;
	$$css =~ s|/\*(.*?)\*/ ? ?|push(@comment, $1), "\x01$#comment\x01"|seg;
	# 文字列退避
	my @str;
	$$css =~ s/(['"])((?:\\.|.)*?)\1/push(@str, $2), "\x02$#str\x02"/seg;
	foreach(@str) {
		$_ =~ s/\x0a//g;	# 改行除去
		$_ =~ s/\\"|"/\\22/g;
		$_ =~ s/\\'|'/\\27/g;
		if (ord(substr($_, -1)) > 0x7f) { $_ = $_ . ' '; }
	}
	# \ による実体参照の防止
	$$css =~ s/\\([^"'\*\#])/$1/g;
	# 全角文字を除去
	$$css =~ s/[\x80-\xff]//g;
	# 危険文字の除去
	$$css =~ s/\@//g;
	while($$css =~ m[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include]i) {	# 危険記号の除去
		$$css =~ s[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include][]ig;
	}
	my $check = $$css;
	$check =~ s/[\x02-\x1f]//g;	# 制御記号除去
	if ($check =~ m[/\*|\*/&#|script|behavior|behaviour|java|exp|eval|cookie|include]i) {	# 危険記号あり
		$$css =~ s/([\x02-\x1f])/ $1/g;	# space追加
	}
	# url() の確認
	$$css =~ s#url\(\s*(.*?)\s*\)#
		my $x  = $1;
		$x =~ s/'/%27/g;
		$x =~ s/"/%22/g;
		$x =~ s|\x02(\d+)\x02|$str[$1]|;
		if (substr($x,0,7) ne 'http://' && substr($x,0,8) ne 'http://' && substr($x,0,1) ne '/' && substr($x,0,2) ne './' && substr($x,0,3) ne '../') {
			$x = "./$x";
		}
		"url('$x')";
		#sieg;
	# 文字列の復元
	$$css =~ s|\x02(\d+)\x02|"$str[$1]"|g;
	# コメントの復元
	$$css =~ s|\x01(\d+)\x01|/*$comment[$1]*/  |g;

	return $$css;
}

###############################################################################
# ■プラグインの設定
###############################################################################
#------------------------------------------------------------------------------
# ●plugin/以下のプラグイン情報取得
#------------------------------------------------------------------------------
sub load_modules_info {
	my $self = shift;
	return $self->load_plugins_info(1);
}
sub load_plugins_info {
	my $self = shift;
	my $modf = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $ROBJ->get_filepath( $self->{plugin_dir} );
	my $files = $ROBJ->search_files($dir, {dir_only => 1});
	my @ary;
	foreach( sort @$files ) {
		my $f = (substr($_,0,4) eq 'des_');	# デザインモジュール？
		if (!$modf && $f || $modf && !$f) { next; }
		# load
		push(@ary, $self->load_plugin_info($_, $dir));
	}
	return \@ary;
}

sub load_plugins_dat {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	return $ROBJ->fread_hash_cached( $self->{blog_dir} . 'plugins.dat', {NoError => 1} );
}

#------------------------------------------------------------------------------
# ●ひとつのプラグイン情報取得
#------------------------------------------------------------------------------
sub load_module_info {
	return &load_plugin_info(@_);
}
sub load_plugin_info {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $name = shift;
	my $dir  = shift || $ROBJ->get_filepath( $self->{plugin_dir} );

	# キャッシュ
	my $cache = $self->{"_plugin_info_cache"} ||= {};
	if ($cache->{"$dir$name"}) { return $cache->{"$dir$name"}; }

	if (substr($name,-1) eq '/') { chop($name); }
	my $n = $self->plugin_name_check( $name );
	if (!$n) { return; }		# プラグイン名, $name=プラグインのインストール名

	my $h = $ROBJ->fread_hash_no_error( "$dir$n/plugin.info" );
	if (!$h || !%$h) { next; }
	$h->{readme} = -r "$dir$n/README.txt" ? 'README.txt' : undef;
	$h->{name} = $name;

	# sample.html/module.htmlが存在する
	if (-r "$dir$n/sample.html") {
		$h->{sample_html} ||= join('', @{ $ROBJ->fread_lines("$dir$n/sample.html") });
	}
	if (-r "$dir$n/module.html") {
		$h->{module_html} ||= join('', @{ $ROBJ->fread_lines("$dir$n/module.html") });
	}

	# <@this>の置換
	$h->{files}  =~ s/<\@this>/$name/g;
	$h->{events} =~ s/<\@this>/$name/g;
	$h->{module_html} =~ s/<\@this>/$name/g;
	$h->{module_html} =~ s/<\@id>/$h->{module_id}/g;

	# タグの除去
	foreach(keys(%$h)) {
		if (substr($_,-4) eq 'html') { next; }
		$ROBJ->tag_escape($h->{$_});
	}

	# setting.html
	$h->{module_setting} = -r "$dir$n/setting.html";
	# モジュールジェネレーター
	$h->{module_html_generator} = -r "$dir$n/html_generator.pm";

	# 多重インストールモジュール？
	if ($h->{module_type} && $h->{module_id} eq '') {
		$h->{multiple} = 1;
	}

	# キャッシュ
	$cache->{"$dir$name"} = $h;

	return $h;
}

#------------------------------------------------------------------------------
# ●使用するプラグイン設定を保存する
#------------------------------------------------------------------------------
sub save_use_modules {
	my $self = shift;
	return $self->save_use_plugins($_[0], 1);
}
sub save_use_plugins {
	my $self = shift;
	my $form = shift;
	my $modf = shift;
	my $blog = $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $pd      = $self->load_plugins_dat();
	my $plugins = $self->load_plugins_info($modf);
	my $ary = $plugins;
	if ($modf) {
		# モジュールの場合
		# ※1つのモジュールを複数配置することがあるので、その対策。
		# 　その場合 $name:"des_name,1", $n:"des_name" となる
		my %pl = map { $_->{name} => $_ } @$plugins;
		my %common;
		$ary=[];
		foreach(keys(%$form)) {
			my $n = $self->plugin_name_check( $_ );
			if (!$n || !$pl{$n}) { next; }
			if ($n eq $_) {
				if ($pl{$n}->{multiple}) { next; }
				push(@$ary, $pl{$_});
				next;
			}

			# 複数インストールを許可しているか？
			if (! $pl{$n}->{multiple}) { next; }

			# エイリアスを保存
			my %h = %{ $pl{$n} };
			$h{name} = $_;
			push(@$ary, \%h);
			$common{$n} = $form->{$n} ||= $form->{$_};
		}
		foreach(keys(%common)) {
			# エイリアスのコモン名のinstall/uninstall設定
			if ($form->{$_}) {
				unshift(@$ary, $pl{$_});	# install
			} else {
				push(@$ary, $pl{$_});	# unisntall
			}
		}
	}
	my $err = 0;
	my $flag= 0;
	my %fail;
	my @install_plugins;
	foreach(@$ary) {
		my $name = $_->{name};
		my $inst = $form->{$name} ? 1 : 0;
		if ($_->{adiary_version} > $self->{VERSION}) { $inst=0; }	# 非対応バージョン
		if ($pd->{$name} == $inst) { next; }				# 変化なし

		# 状態変化あり
		my $func = $inst ? 'plugin_install' : 'plugin_uninstall';
		my $msg  = $inst ? 'Install'        : 'Uninstall';

		# $cname:コモン名、$name:インストール名
		my $cname = $self->plugin_name_check( $name );

		# アンインストールイベント
		if (!$inst) {
			my $r = $self->call_event("UNINSTALL:$name");
			if ($r) {
				$ROBJ->message("[plugin:%s] Uninstall event failed", $name);
				# アンインストールイベント処理に失敗しても、
				# アンインストール処理は継続させる。
				# $fail{$cname}=1;
				# next;
			}
		}

		# 多重インストール処理
		if ($_->{multiple} && $cname ne $name) {
			if ($inst) {
				# install
				if ($fail{$cname}) { $fail{$name}=1; next; }

				$pd->{"$name"} = 1;
				$pd->{"$name:events"} = $_->{events};
				push(@install_plugins, $name);
			} else {
				# uninstall
				delete $pd->{"$name"};
				delete $pd->{"$name:events"};
			}
			$flag=1;
			next;
		}

		# install/uninstall 実行
		my $r = $fail{$name} ? -1 : $self->$func( $pd, $_ );
		$err += $r;
		if ($r) {
			$fail{$name}=1;
			$ROBJ->message("[plugin:%s] $msg failed", $name);
			next;
		}
		$flag=1;
		$ROBJ->message("[plugin:%s] $msg success", $name);
		if ($inst) { push(@install_plugins, $name); }
	}
	# 状態変更があった？
	if ($flag) {
		# プラグイン情報の保存
		$ROBJ->fwrite_hash($self->{blog_dir} . 'plugins.dat', $pd);

		# イベント情報の登録
		$self->set_event_info($self->{blog}, $pd);

		# インストールイベントの呼び出し
		foreach(@install_plugins) {
			$self->call_event("INSTALL:$_");
		}
	}
	return wantarray ? (0, \%fail) : 0;
}

#------------------------------------------------------------------------------
# ●プラグインのインストール
#------------------------------------------------------------------------------
sub plugin_install {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($pd, $plugin) = @_;

	my $files  = $plugin->{files};
	my $events = $plugin->{events};
	my $name   = $plugin->{name};			# インストール名
	my $n      = $self->plugin_name_check( $name );	# プラグイン名

	# インストールディレクトリ
	my $func_dir = $self->{blog_dir} . 'func/';
	my $skel_dir = $self->{blog_dir} . 'skel/';
	my $js_dir   = $self->{blogpub_dir} . 'js/';
	my $plg_dir  = $self->{plugin_dir} . "$n/";

	my $copy = $self->{plugin_symlink} ? 'file_symlink' : 'file_copy';

	# 必要なディレクトリの作成
	$ROBJ->mkdir( $func_dir );
	$ROBJ->mkdir( $skel_dir );
	$ROBJ->mkdir( $js_dir   );

	# ファイルのインストール
	my $err=0;
	my @copy_files;
	foreach(split("\n",$files)) {
		# 親ディレクトリ参照などの防止
		$ROBJ->clean_path($_);

		# 最初のディレクトリ名分離
		my ($dir, $file) = $self->split_equal($_, '/');
		if ($dir eq '') { next; }

		# タイプ別のフィルタ
		my $des;
		if ($dir eq 'func') {
			$des = $func_dir . $file;
		}
		if ($dir eq 'js') {
			$des = $js_dir . $file;
		}
		if ($dir eq 'skel') {
			$self->mkdir_with_filepath( $skel_dir, $file );
			$des = $skel_dir . $file;
		}
		if (!$des) {
			$ROBJ->error("[plugin:%s] Not allow directory name : %s", $name, $_);
			$err++;
			next;
		}
		if (! -r $ROBJ->get_filepath("$plg_dir$_")) {
			$ROBJ->error("[plugin:%s] Original file not exists : %s", $name, $_);
			$err++;
			next;
		}

		# 既にファイルが存在している場合はエラー
		$des = $ROBJ->get_filepath($des);
		if (-e $des) {
			$ROBJ->error("[plugin:%s] File already exists : %s", $name, $des);
			$err++;
			next;
		}

		# ファイルをコピーしてインストール
		if ($err) { next; }	# エラーがあればコピーはしない
		my $r = $ROBJ->$copy( "$plg_dir$_", $des);
		if ($r || !-e $des) {
			$err++;
			next;
		}

		# インストールしたファイルを記録
		push(@copy_files, $des);
	}

	if ($err) {
		foreach(@copy_files) {
			$ROBJ->file_delete( $_ );
		}
		return $err;
	}

	# 情報の登録
	$pd->{$name} = 1;
	$pd->{"$name:version"} = $plugin->{version};
	$pd->{"$name:files"}   = join("\n", @copy_files);
	if (!$plugin->{multiple}) {
		$pd->{"$name:events"}  = $plugin->{events};
	}

	return 0;
}
#------------------------------------------------------------------------------
# ●プラグインのアンインストール
#------------------------------------------------------------------------------
sub plugin_uninstall {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($pd, $plugin) = @_;

	my $name = ref($plugin) ? $plugin->{name} : $plugin;
	my $files = $pd->{"$name:files"};
	my $err=0;
	foreach(split("\n", $files)) {
		my $r = $ROBJ->file_delete( $_ );
		if ($r) { next; }	# 成功
		$err++;
		$ROBJ->error("[plugin:%s] File delete failed : %s", $name, $_);
	}
	if ($err) { return $err; }

	# 情報の削除
	my $len = length("$name:");
	foreach(keys(%$pd)) {
		if (substr($_,0,$len) ne "$name:") { next; }
		delete $pd->{$_};
	}
	delete $pd->{$name};
	return 0;
}

#------------------------------------------------------------------------------
# ●パスを辿ってmkdir
#------------------------------------------------------------------------------
sub mkdir_with_filepath {
	my $self = shift;
	my ($dir, $file) = @_;
	my $ROBJ = $self->{ROBJ};

	my @ary = split('/', $file);
	pop(@ary);	# ファイル名を捨てる
	while(@ary) {
		$dir .= pop(@ary) . '/';
		$ROBJ->mkdir( $dir );
	}
}

#------------------------------------------------------------------------------
# ●プラグイン情報からイベントを登録
#------------------------------------------------------------------------------
my %SPECIAL_EVENTS = (	# イベント名が「INSTALL:plugin_name」のようになるもの
	INSTALL => 1,
	UNINSTALL => 1,
	SETTING => 1
);
sub set_event_info {
	my $self = shift;
	my ($blog, $pd) = @_;

	my @plugins = sort(grep { index($_, ':')<0 } keys(%$pd));
	my %evt;
	my %js_evt;
	foreach my $name (@plugins) {
		foreach( split("\n", $pd->{"$name:events"})) {
			my ($k,$v) = $self->split_equal($_);
			if ($k eq '') { next; }
			if ($SPECIAL_EVENTS{$k}) {
				$k .= ":$name";
			}
			# JSイベントは多重呼び出ししない
			if ($k =~ /^JS/) {
				my $cname = $self->plugin_name_check( $name );
				$js_evt{$k}->{$cname} = $v;
				next;
			}
			$evt{$k} ||= [];
			push(@{ $evt{$k} }, "$name=$v");
		}
	}

	# JSイベントを重複を避けて登録
	foreach my $k (keys(%js_evt)) {
		$evt{$k} = [];
		my $h = $js_evt{$k};
		foreach(keys(%$h)) {
			push(@{ $evt{$k} }, "$_=$h->{$_}");
		}
	}

	# 登録済イベントを初期化
	foreach(keys(%$blog)) {
		if (substr($_,0,6) ne 'event:') { next; }
		delete $blog->{$_};
	}

	# イベントの登録
	foreach(keys(%evt)) {
		$blog->{"event:$_"} = join("\n", @{ $evt{$_} });
	}
	$self->update_blogset($blog);

	return 0;
}

#------------------------------------------------------------------------------
# ●プラグインの設定を保存
#------------------------------------------------------------------------------
sub save_plugin_setting {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $name = $form->{module_name};

	my $n = $self->plugin_name_check($name);
	if (!$n) { return 1; }

	my $dir = $ROBJ->get_filepath($self->{plugin_dir} . $n);
	my $ret;
	my $pm = "$dir/validator.pm";
	if (-r $pm) {
		my $func = $self->load_plugin_function( $pm, $pm );
		$ret = &$func($self, $form);
	} else {
		$ret = $ROBJ->_call("$dir/validator.html", $form);
	}
	if (ref($ret) ne 'HASH') { return; }

	$self->update_plgset($name, $ret);
	$self->call_event("SETTING:$name");
	return 0;
}

#------------------------------------------------------------------------------
# ●プラグイン名のチェックとalias番号の分離
#------------------------------------------------------------------------------
sub plugin_name_check {
	my $self = shift;
	return ($_[0] =~ /^([A-Za-z][\w\-]*)(?:,\d+)?$/) ? $1 : undef;
}
sub plugin_num {
	my $self = shift;
	return ($_[0] =~ /^(?:[A-Za-z][\w\-]*),(\d+)$/) ? $1 : undef;
}

###############################################################################
# ■デザインモジュールの設定
###############################################################################
#------------------------------------------------------------------------------
# ●デザインの保存
#------------------------------------------------------------------------------
sub save_design {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $sa = $form->{side_a_ary} || [];
	my $sb = $form->{side_b_ary} || [];
	my @side_a = sort {$form->{"${a}_int"} cmp $form->{"${b}_int"}} @$sa;
	my @side_b = sort {$form->{"${a}_int"} cmp $form->{"${b}_int"}} @$sb;

	my %use_f = map {$_ => 1} (@side_a,@side_b);
	my $pd = $self->load_plugins_dat();
	foreach(keys(%$pd)) {	# 現在のinstall状態確認
		if (index($_,':')>0) { next; }
		if ($pd->{$_} && !$use_f{$_}) { $use_f{$_}=0; }	# uninstall
	}

	# プラグイン状況を保存
	my ($ret, $fail) = $self->save_use_modules(\%use_f);
	if ($ret) { return $ret; }	# error

	# HTMLを生成
	my @html;
	push(@html, $ROBJ->chain_array( $ROBJ->fread_skeleton('_format/sidebar_header') ));
	foreach(@side_a) {
		if ($fail->{$_}) { next; }
		push(@html, $self->load_module_html($_) . "\n");
	}
	push(@html, $ROBJ->chain_array( $ROBJ->fread_skeleton('_format/sidebar_separator') ));
	foreach(@side_b) {
		if ($fail->{$_}) { next; }
		push(@html, $self->load_module_html($_) . "\n");
	}
	push(@html, $ROBJ->chain_array( $ROBJ->fread_skeleton('_format/sidebar_footer') ));

	# そのブログ専用のスケルトンとして保存
	my $dir = $self->{blog_dir} . 'skel/';
	$ROBJ->mkdir($dir);
	my $r = $ROBJ->fwrite_lines($dir . '_sidebar.html', \@html);
	if ($r) {
		$ROBJ->message('Design edit failed');
	}
	return $r;
}

#------------------------------------------------------------------------------
# ●モジュールHTMLの生成
#------------------------------------------------------------------------------
sub load_module_html {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};

	# generatorの有無はファイルの存在で確認
	my $n = $self->plugin_name_check( $name );
	my $pm = $ROBJ->get_filepath( "$self->{plugin_dir}$n/html_generator.pm" );
	if (! -r $pm) {
		return ($self->load_plugin_info($name) || {})->{module_html};
	}

	my $func = $self->load_plugin_function( $pm, $pm );
	if (ref($func) ne 'CODE') {
		return ;
	}

	my $ret;
	eval {
		$ret = &$func($self, $name);
	};
	if ($@ || !defined $ret) {
		$ROBJ->error("[plugin:%s] Module's html generate failed : %s", $name, $@);
		return '';
	}
	return $ret;
}

#------------------------------------------------------------------------------
# ●モジュールHTMLのロードと実行
#------------------------------------------------------------------------------
sub load_and_call_module_html {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	# モジュールHTMLのロードが許可されているか？
	my $info = $self->load_plugin_info($name);
	if (!$info->{load_module_html_in_edit}) { return; }

	# インストールファイルがあるときはinstallされているか確認
	if ($info->{files}) {
		my $pd = $self->load_plugins_dat();
		if (!$pd->{$name}) { return; }
	}

	my $html = $self->load_module_html( $name );
	if (!$html) { return; }

	# ファイル展開して呼び出す
	my $file = "$self->{blog_dir}_call_module_html-$name.tmp";
	$ROBJ->fwrite_lines( $file, $html );
	my $ret = $ROBJ->_call( $file );
	$ROBJ->file_delete( $file );
	return $ret;
}
#------------------------------------------------------------------------------
# ●デザインの初期化
#------------------------------------------------------------------------------
sub reset_design {
	my $self = shift;
	my $form = shift;
	my $all  = shift;
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my %reset;
	my $pd = $ROBJ->fread_hash_cached( $self->{blog_dir} . 'plugins.dat', {NoError => 1} );
	foreach(keys(%$pd)) {
		if (index($_, ':') > 0) { next; }
		$reset{$_}=0;	# uninstall
	}
	my $ret = $self->save_use_modules(\%reset);

	# 生成スケルトンを消す
	$ROBJ->file_delete($self->{blog_dir} . 'skel/_sidebar.html');

	# 個別の設定もすべて消す
	if ($all) {
		my $blog = $self->{blog};
		foreach(keys(%$blog)) {
			if (substr($_,0,6) ne 'p:des_') { next; }
			delete $blog->{$_};
		}
		$self->update_blogset($blog);
	}

	return 0;
}

###############################################################################
# ■テーマ選択
###############################################################################
#------------------------------------------------------------------------------
# ●テンプレートリストのロード
#------------------------------------------------------------------------------
sub load_templates {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# テンプレートdir
	my $theme_dir  = $self->{theme_dir};
	my $dirs = $ROBJ->search_files($theme_dir, { dir_only => 1 });
	$dirs = [ grep(/^[A-Za-z]/, @$dirs) ];

	# satsuki で始まるテンプレートを優先的に表示
	$dirs  = [ sort {( (!index($b,'satsuki')) <=> (!index($a,'satsuki')) ) || $a cmp $b} @$dirs ];
	return $dirs;
}

#------------------------------------------------------------------------------
# ●テーマリストの作成
#------------------------------------------------------------------------------
sub load_themes {
	my ($self, $template) = @_;
	my $ROBJ = $self->{ROBJ};

	# テンプレートdir選択
	$template =~ s/[^\w\-]//g;
	if ($template eq '') { return; }
	my $dir = $ROBJ->get_filepath( "$self->{theme_dir}$template/" );

	# テーマリストの取得
	my @files = sort map { chop($_);$_ } @{ $ROBJ->search_files($dir, { dir_only => 1 }) };
	my @ary;
	foreach(@files) {
		if (substr($_,0,1) eq '_') { next; }	# 先頭 _ を無視
		my %h;
		$h{name}   = $_;
		$h{readme} = (-r "$dir$_/README" || -r "$dir$_/README.txt") ? 1 : 0;
		push(@ary, \%h);
	}
	return \@ary;
}

#------------------------------------------------------------------------------
# ●テーマリストの作成
#------------------------------------------------------------------------------
sub save_theme {
	my ($self, $theme) = @_;
	my $blog = $self->{blog};
	my $ROBJ = $self->{ROBJ};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	if ($theme !~ m|^([\w-]+)/([\w-]+)/?$|) {
		return 1;
	}

	# テーマ保存
	$self->update_blogset($blog, 'theme', $theme);
	return 0;
}


1;
