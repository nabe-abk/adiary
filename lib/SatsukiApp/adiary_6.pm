use strict;
#-------------------------------------------------------------------------------
# adiary_6.pm (C)2014 nabe@abk
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
use SatsukiApp::adiary_4 ();
use SatsukiApp::adiary_5 ();
package SatsukiApp::adiary;
###############################################################################
# ■ワンライナーなサブルーチン等
###############################################################################
my @update_versions = (
	{ ver => 2.93, func => 'sys_update_293', rebuild=>1, plugin=>1 },
	{ ver => 2.94, func => 'sys_update_294' },
);
#------------------------------------------------------------------------------
# ●システムアップデート
#------------------------------------------------------------------------------
sub system_update {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (!$auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $cur_blogid = $self->{blogid};
	my $blogs = $self->load_all_blogid();

	my %opt;
	my $cur = $self->{sys}->{VERSION};
	foreach my $h (@update_versions) {
		if ($cur >= $h->{ver}) { next; }
		$ROBJ->message("System update for Ver %s", $h->{ver});
		$opt{rebuild} ||= $h->{rebuild};	# 全記事再構築
		$opt{plugin}  ||= $h->{plugin};		# プラグイン更新

		my $func = $h->{func};
		if ($func) {
			$self->$func($blogs);
		}
		$cur = $h->{ver};
	}
	$self->set_and_select_blog($cur_blogid);

	# 再構築？
	if ($opt{rebuild}) {
		$ROBJ->message("Rebuild all blogs");
		$self->rebuild_all_blogs();
	}
	# プラグイン再インストール
	if ($opt{plugin}) {
		$ROBJ->message("Reinstall all plugins");
		$self->reinstall_all_plugins();
	}

	$self->update_sysdat('VERSION', $cur);
	return 0;
}

#------------------------------------------------------------------------------
# ●システムアップデート for Ver2.93
#------------------------------------------------------------------------------
sub sys_update_293 {
	my $self  = shift;
	my $blogs = shift;
	my $ROBJ = $self->{ROBJ};
	foreach(@$blogs) {
		$self->update_blogset($_, 'http_rel');
		$self->update_blogset($_, 'image_rel');
		$self->update_blogset($_, 'image_data', 'lightbox=%k');
	}
}

#------------------------------------------------------------------------------
# ●システムアップデート for Ver2.94
#------------------------------------------------------------------------------
sub sys_update_294 {
	my $self  = shift;
	my $blogs = shift;
	my $ROBJ = $self->{ROBJ};
	foreach(@$blogs) {
		$self->set_and_select_blog( $_ );
		#
		my $dir  = $ROBJ->get_filepath( $self->{blogpub_dir} );
		my $file = $dir . 'usercss.css';
		if (-r $file) {
			my $lines = $ROBJ->fread_lines( $file );
			my $css = join('', @$lines);
			$self->save_usercss( $css );
			unlink( $file );
		}
	}
}

###############################################################################
# ■Version2 to 3 移行ルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●adiary.conf.cgiの解析
#------------------------------------------------------------------------------
sub parse_adiary_conf_cgi {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	my $lines = $ROBJ->fread_lines( $file );
	if (!@$lines) { return ; }

	if ($file !~ m|^(.*?/)[^/]*$|) { return ; }
	my $dir = $1;

	my %h;
	my %c;
	foreach(@$lines) {
		if ($_ =~ /^#/) { next; }
		if ($_ =~ /<#\$/) { next; }
		$_ =~ s/\r\n//g;
		$_ =~ s/"/'/g;

		# <$constant(public_dir) = 'public/'>
		if ($_ =~ /<\$constant\((\w+)\)\s*=\s*'([^']*)'\s*>/) {
			$c{$1} = $2;
			next;
		}

		# const処理
		$_ =~ s/<\@(\w+)>/$c{$1}/g;

		# lang
		if ($_ =~ /<\$load_language_file\s*\(.*(euc-jp|utf8)\.txt/) {
			$h{lang} = $1;
			next;
		}

		#<$DB = loadpm('DB_pseudo', "<@data_dir>db/")>
		#<$DB = loadpm('DB_cache', 'DB_mysql', 'database=adiary', 'adiary', 'test', 1.connection_pool, 'ujis')>
		if ($_ =~ /<\$DB\s*=\s*loadpm\((.*)\)\s*>\s*$/) {
			my $db = $1;
			$db =~ s/^\s*'DB_cache'\s*,\s*//;
			$db =~ s/,\s*1(?:\.\w+)?\s*//;
			$db =~ s/^\s*'DB_pseudo'\s*,\s*'([^']*)'/'DB_pseudo', '$dir$1'/;
			$h{db} = $db;
			next;
		}

		# <$Auth=loadpm("Auth", "<@data_dir>auth/")>
		if ($_ =~ /<\$Auth\s*=\s*loadpm\(\s*'Auth'\s*,\s*'([^']*)'\s*\)\s*>/) {
			$h{auth_dir} = $dir . $1;
			next;
		}

		# <$v.setting_dir = "<@data_dir>setting/">
		if ($_ =~ /<\$v.setting_dir\s*=\s*'([^']*)'\s*>/) {
			$h{setting_dir} = $dir . $1;
			next;
		}

		# <$v.usertag_dir = "<@data_dir>parser_tag/">
		if ($_ =~ /<\$v.usertag_dir\s*=\s*'([^']*)'\s*>/) {
			$h{usertag_dir} = $dir . $1;
			next;
		}

		# <$v.image_dir = "<@public_dir>image/">
		if ($_ =~ /<\$v.image_dir\s*=\s*'([^']*)'\s*>/) {
			$h{image_dir} = $dir . $1;
			next;
		}
	}
	return \%h;
}

#------------------------------------------------------------------------------
# ●adiary.conf.cgiの解析
#------------------------------------------------------------------------------
sub v2convert {
	my $self = shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};

	# sub routine -------------------------------------------------
	my $from  = $h->{lang};
	my $to    = $ROBJ->{System_coding};
	my $jcode = $ROBJ->load_codepm();
	sub conv_code {
		foreach(@_) {
			$jcode->from_to(\$_, $from, $to);
		}
	}
	sub conv_hash {
		my $h = shift;
		foreach(keys(%$h)) {
			&conv_code( $h->{$_} );
		}
	}

	#--------------------------------------------------------------
	# ユーザーの移行
	#--------------------------------------------------------------
	if ($h->{conv_users}) {
		my $lines = $ROBJ->fread_lines($h->{auth_dir} . '#userdb.txt.cgi');
		&conv_code(@$lines);

		foreach(@$lines) {
			chomp($_);
			my ($uid, $cpass, $isadmin, $name) = split(/\t/, $_);
			my $r = $auth->user_add({
				id => $uid,
				crypted_pass => $cpass,
				name => $name,
				isadmin => $isadmin,
				disable => ($cpass eq '*')
			});
			$ROBJ->notice("Add user : %s (ret=%d)", $uid, $r);
		}
	}


	#--------------------------------------------------------------
	# ブログの移行
	#--------------------------------------------------------------
	my $db_load = $h->{db};
	$db_load =~ s/^\s*'(.*?)'\s*$/$1/;
	my @opt = split(/'\s*,\s*'/, $db_load);
	if ($opt[0] eq 'DB_pseudo') { $opt[0] = 'DB_text'; }
	if ($opt[4] ne '') { $opt[4] = { Charset => $opt[4] }; }

	my %themes;
	{
		my $ary = $self->load_themes('satsuki2');
		foreach(@$ary) {
			$themes{$_->{name}} = 1;
		}
	}

	my $DBv2 = $ROBJ->loadpm(@opt);
	my $blogs = $DBv2->select('_daybooklist');
	foreach(@$blogs) {
		my $id = $_->{id};
		if ($id eq '') { next; }
		$ROBJ->notice("---");

		# ブログ作成
		my $r = $self->blog_create($id);
		# if ($r) { next; }	# すでに存在する

		# デフォルトデザインのロード
		$ROBJ->{Message_stop} = 1;
		$ROBJ->call('_sub/load_default_design', $id);
		$ROBJ->{Message_stop} = 0;

		# 設定のコピー
		my $s = $ROBJ->fread_hash($h->{setting_dir} . $id . '.dat');
		&conv_hash($s);
		$self->save_blogset({
			blog_name       => $s->{blog_name},
			description_txt => $s->{description},
			change_hour_int => $s->{change_hour_int},
			enable          => $s->{enable},
			private         =>($s->{enable_force} eq '0' ? 1 : 0),
			com_ok          => $s->{allow_com},
			com_ok_force    => $s->{allow_com_force},
			hcom_ok         => $s->{allow_hcom},
			hcom_ok_force   => $s->{allow_hcom_force},
			ping            => $s->{update_ping},
			wiki            => $s->{wiki},
			autolink        => $s->{autolink},
			parser          =>($self->{parsers}->{$s->{parser}} ? $s->{parser} : undef),
			allow_com_users =>($s->{allow_com_user} eq 'users' ? $s->{allow_com_users} : $s->{allow_com_user}),
			defer_com       => $s->{defer_com},
			com_email       => $s->{allow_comment_email},
			com_url         => $s->{allow_comment_url},
			admin_users     => $s->{admin_users},
			editors         => $s->{edit_users},
			edit_by_author_only => $s->{edit_self_only},
			section_anchor      => $s->{section_anchor},
			subsection_anchor   => $s->{subsection_anchor},
			gaid            => $s->{gaid},
			asid            => $s->{asid},
			load_items      => $s->{disp_diaries_int},
			separate_blog   => $s->{contents_separate},
			# 記事の表示設定
			disp_tmdate     => $s->{disp_write_date},
			disp_author     => $s->{disp_writer},
			disp_hatena_btn => $s->{disp_hatena_bicon},
			disp_twitter_btn=> $s->{disp_twitter_icon}
		}, $id);
		$ROBJ->notice("Blog create : %s : %s", $id, $s->{blog_name});

		# ブログの選択
		$self->set_and_select_blog($id);

		# ユーザー定義タグ
		{
			my $utag  = $h->{usertag_dir} . $id . '.txt';
			my $lines = $ROBJ->fread_lines($h->{auth_dir} . '#userdb.txt.cgi');
			if ($lines && @$lines) {
				&conv_code(@$lines);
				$self->save_usertag( $lines );
			}
		}

		# 対応テーマがあるときはそれを選択
		$s->{theme} =~ s/^satsuki/satsuki2/;
		if ($s->{template} eq 'satsuki' && $themes{ $s->{theme} }) {
			$self->save_theme({
				theme => 'satsuki2/' . $s->{theme}
			});
		}

		# ブログの記事とコメントの移行
		my $DB = $self->{DB};
		{
			my %com;
			my $coms = $DBv2->select("${id}_comment", {sort => 'pkey'});
			foreach(@$coms) {
				&conv_hash($_);
				my $apkey = $_->{diary_pkey};
				my $a = $com{$apkey} ||= [];
				$_->{text} =~ s/<br>/\n/g;
				push(@$a, $_);
			}

			my %tb;
			if ($h->{import_tb}) {
				my $tbs = $DBv2->select("${id}_tb", {
					sort => 'pkey',
					flag => {internal => 0}
				});
				foreach(@$tbs) {
					&conv_hash($_);
					my $apkey = $_->{diary_pkey};
					my $a = $tb{$apkey} ||= [];
					push(@$a, $_);
				}
			}
			
			my %opt;
			$opt{save_pkey}     = 1;
			$opt{save_com_pkey} = %tb ? 0 : 1;

			my $arts = $DBv2->select("${id}_diary", {sort => 'pkey'});
			$DB->begin();
			foreach(@$arts) {
				my $pkey = $_->{pkey};
				my $art = {
					pkey 	=> $pkey,
					year 	=> substr($_->{yyyymmdd}, 0, 4),
					mon 	=> substr($_->{yyyymmdd}, 4, 2),
					day 	=> substr($_->{yyyymmdd}, 6, 2),
					tm 	=> $_->{tm},
					tags 	=> $_->{category},
					title 	=> $_->{title},
					name 	=> $_->{name},
					text 	=> $_->{_text},

					com_ok 	=> $_->{allow_com},
					hcom_ok	=> $_->{allow_hcom},

					priority=> $_->{priority},
					upnode 	=> $_->{upnode},
					link_key=> $_->{link_key},

					ip	=> $_->{ip},
					host	=> $_->{host},
					agent	=> $_->{agent}
				};

				my $parser = $_->{parser};
				if ($self->{parsers}->{$parser}) {
					$art->{parser} = $parser;
				} else {
					# パーサーなし
					$art->{text} = $_->{text};
				}

				# 登録
				&conv_hash($art);
				$self->save_article($art, $com{$pkey}, $tb{$pkey}, \%opt);
			}
			$DB->commit();
			$ROBJ->notice("Import %d articles (find %d articles)", $opt{import_arts}, $opt{find_arts});

			# イベント処理
			if ($opt{import_arts}) {
				$self->import_events( \%opt );
			}
		}

		# 画像アルバムの移行
		my $src_dir = $ROBJ->get_filepath( $h->{image_dir} . $id . '/' );
		my $des_dir = $ROBJ->get_filepath( $self->blogimg_dir() );

		sub copy_dir {
			my ($ROBJ, $src, $des) = @_;
			$ROBJ->mkdir("$des");
			my $files = $ROBJ->search_files( $src, {dir=>1, all=>1} );
			my $c=0;
			foreach(@$files) {
				my $file = $src . $_;
				&conv_code($_);
				if (-d $file) {
					$c += &copy_dir($ROBJ, "$file", "$des$_");
				} else {
					$c += $ROBJ->_file_copy($file, "$des$_") ? 0 : 1;
				}
			}
			return $c;
		}
		my $c = &copy_dir($ROBJ, $src_dir, $des_dir) >> 1;
		if ($c) {
			$ROBJ->notice("Copy %d images(files)", $c);
		}
	}
	$self->set_and_select_blog('', 1);
	return 0;
}


1;
