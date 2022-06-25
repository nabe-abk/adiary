use strict;
#-------------------------------------------------------------------------------
# テキストデータベース
#						(C)2005-2022 nabe@abk
#-------------------------------------------------------------------------------
#
#■■■編集時の注意■■■
# 　値を返し、または変更するとき、内部ハッシュ配列 $db および
# その格納値であるハッシュリファレンスの実体を破壊されないようにすること。
#
package Satsuki::DB::text;
use Satsuki::AutoLoader;
use Satsuki::DB::share;

our $VERSION = '1.32';
our $FileNameFormat = "%05d";
our %IndexCache;
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;
	my ($ROBJ, $dir, $self) = @_;
	$self ||= {};
	bless($self, $class);	# $self をこのクラスと関連付ける

	if (!-e $dir) { $ROBJ->mkdir($dir); }
	$self->{ROBJ} = $ROBJ;
	$self->{dir}  = $dir;

	# ディフォルト値
	$self->{_RDBMS} = 'Text-DB';
	$self->{db_id}  = "$dir:";
	$self->{ext}  ||= ".dat";
	$self->{index_file}  = "#index" . $self->{ext};
	$self->{index_backup_file} = "#index.backup" . $self->{ext};

	return $self;
}

################################################################################
# ■テーブルの操作
################################################################################
#-------------------------------------------------------------------------------
# ●テーブルの存在確認
#-------------------------------------------------------------------------------
sub find_table {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $table = shift;
	if ($table =~ /\W/) { return 0; }	# Not Found(error)

	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		if (-e "$dir$self->{index_backup_file}") { return 1; }	# Found
		return 0;	# Not found
	}
	return 1;
}

################################################################################
# ■データの検索
################################################################################
# called by select method in DB_share.
sub select {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};

	$table =~ s/\W//g;
	my $require_hits = wantarray;

	my $db = $self->load_index($table, undef, $h->{NoError});	# table array ref
	if ($#$db < 0) { return []; }

	#-----------------------------------------------------------------------
	# 全文データロードの準備
	#-----------------------------------------------------------------------
	my $dir = $self->{dir} . $table . '/';
	my $ext = $self->{ext};

	# カラム情報のロード
	my $index_cols  = $self->{"$table.idx"};
	my $exists_cols = $self->{"$table.cols"};

	#-----------------------------------------------------------------------
	# 選択カラムが正しいか？
	#-----------------------------------------------------------------------
	my $sel_cols = $h->{cols};
	if ($sel_cols) {
		$sel_cols = ref($sel_cols) ? $sel_cols : [ $sel_cols ];
		if (my @ary = grep { !$exists_cols->{$_} } @$sel_cols) {
			foreach(@ary) {
				$self->error("Select column '$_' is not exists");
			}
			return [];
		}
	}

	#-----------------------------------------------------------------------
	# マッチング条件の処理
	#-----------------------------------------------------------------------
	my @match    = sort( keys(%{ $h->{match}     }) );
	my @not_match= sort( keys(%{ $h->{not_match} }) );
	my @min      = sort( keys(%{ $h->{min}       }) );
	my @max      = sort( keys(%{ $h->{max}       }) );
	my @gt       = sort( keys(%{ $h->{gt}        }) );
	my @lt       = sort( keys(%{ $h->{lt}        }) );
	my @flag     = sort( keys(%{ $h->{flag}      }) );
	my $is_null  = $h->{is_null}      || [];
	my $not_null = $h->{not_null}     || [];
	my $s_cols   = $h->{search_cols}  || [];
	my $s_match  = $h->{search_match} || [];
	my $s_equal  = $h->{search_equal} || [];

	my @target_cols_L1 = (
		@match, @not_match, @min, @max, @gt, @lt, @flag,
		@$is_null, @$not_null
	);
	my @target_cols_L2 = (@$s_cols, @$s_match, @$s_equal);
	my @target_cols    = (@target_cols_L1, @target_cols_L2);

	#-----------------------------------------------------------------------
	# limit設定あり？
	#-----------------------------------------------------------------------
	my $limit_state;
	if (!$require_hits && $h->{limit} ne '') {
		$limit_state = int($h->{limit}) -1 + int($h->{offset});
	}

	#-----------------------------------------------------------------------
	# sort対象の確認
	#-----------------------------------------------------------------------
	my ($sort_func, $sort) = $self->generate_sort_func($table, $h);
	my $sort_state;
	if (@$sort) {
		if (my @ary = grep { !$exists_cols->{$_} } @$sort) {
			foreach(@ary) {
				$self->error("Sort column '$_' is not exists");
			}
			return [];
		}
		# $sort_state
		#   bit 0	ソートが必要
		#   bit 1	リミットあり
		#   bit 2	ソートに必要なデータはロード済
		$sort_state = 1;
		if (defined $limit_state) { $sort_state |= 2; }
		if (! grep{!$index_cols->{$_}} @$sort) {
			$sort_state |= 4;
		}
	}

	#-----------------------------------------------------------------------
	# 抽出処理
	#-----------------------------------------------------------------------
	my $load_all_data = $self->{"$table.load_all"};
	my $copy_flag;
	if (@target_cols) {
		if (my @ary = grep { !$exists_cols->{$_} } @target_cols) {
			foreach(@ary) {
				$self->error("Search column '$_' is not exists");
			}
			return [];
		}
		#---------------------------------------------------------------
		# リミットとロード処理
		#---------------------------------------------------------------
		my $limit;
		my $do_load_L1 = '';
		my $do_load_L2 = '';

		if (!$load_all_data && grep {! $index_cols->{$_}} @target_cols) {
			# index外カラムの参照
			$load_all_data = 1;
			if ($sort_state == 7) {
				# limit値がある and indexのみでソート可能
				$do_load_L1 = 1;	# ファイル順次読み込み
				$db = [sort $sort_func @$db];
				$sort_state = 0;
				$limit = $limit_state;
			} else {
				# 全ロードする（キャッシュ環境ではキャッシュが効く）
				$sort_state |= 4;
				$db = $self->load_allrow($table);
			}
		}
		if ($do_load_L1 && !(grep {! $index_cols->{$_}} @target_cols_L1)) {
			$do_load_L1 = '';
			$do_load_L2 = 1;
		}

		#---------------------------------------------------------------
		# Level-1 検索条件
		#---------------------------------------------------------------
		my $cond_L1='';
		my %match_h;
		my %not_match_h;
		if (@target_cols_L1) {
			my @cond;
			my $str = $self->{"$table.str"};
			foreach (@match) {
				my $v = $h->{match}->{$_};
				if (ref($v) eq 'ARRAY') {
					$match_h{$_} = { map {$_=>1} @$v };
					push(@cond, "exists\$match_h->{$_}->{\$_->{$_}}");
					next;
				}
				if ($str->{$_} || $v eq '') {	# $v eq '' はnullデータ
					# 文字カラム
					$v =~ s/([\\'])/\\$1/g;
					push(@cond, "\$_->{$_}eq'$v'");
					next;
				}
				{
					# 数値カラム
					$v += 0;
					if ($v ne $h->{match}->{$_}) { $self->error("'$v' ($_ column) is not number"); return []; }
					push(@cond, "\$_->{$_}==$v");
					next;
				}
			}
			foreach (@not_match) {
				my $v = $h->{not_match}->{$_};
				if (ref($v) eq 'ARRAY') {
					$not_match_h{$_} = { map {$_=>1} @$v };
					push(@cond, "!exists\$not_match_h->{$_}->{\$_->{$_}}");
					next;
				}
				if ($str->{$_} || $v eq '') {	# $v eq '' はnullデータ
					$v =~ s/([\\'])/\\$1/g;
					push(@cond, "\$_->{$_}ne'$v'");
					next;
				}
				{
					$v += 0;
					if ($v ne $h->{not_match}->{$_}) { $self->error("'$v' ($_ column) is not number"); return []; }
					push(@cond, "\$_->{$_}!=$v");
					next;
				}
			}
			foreach (@flag) {
				my $v = $h->{flag}->{$_};
				if ($v ne '0' && $v ne '1') { $self->error("'$v' ($_ column) is not flag(allowd '1' or '0')"); return []; }
				push(@cond, "\$_->{$_}==$v");
			}
			foreach (@min) {
				my $v = $h->{min}->{$_} + 0;
				if ($v != $h->{min}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}>=$v");
			}
			foreach (@max) {
				my $v = $h->{max}->{$_} + 0;
				if ($v != $h->{max}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}<=$v");
			}
			foreach (@gt) {
				my $v = $h->{gt}->{$_} + 0;
				if ($v != $h->{gt}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}>$v");
			}
			foreach (@lt) {
				my $v = $h->{lt}->{$_} + 0;
				if ($v != $h->{lt}->{$_}) { $self->error("'$v' ($_ column) is not numeric"); return []; }
				push(@cond, "\$_->{$_}<$v");
			}
			foreach (@$is_null) {
				push(@cond, "\$_->{$_}eq''");
			}
			foreach (@$not_null) {
				push(@cond, "\$_->{$_}ne''");
			}

			$cond_L1 = 'if (!(' . join(' && ', @cond) . ')) { next; }';
			$self->debug("select '$table' where L1: $cond_L1");	# debug-safe
		}

		#---------------------------------------------------------------
		# Level-2 検索条件（文字列検索）
		#---------------------------------------------------------------
		my $cond_L2='';
		if (@target_cols_L2) {
			my $words = $h->{search_words} || [];
			my $not   = $h->{search_not}   || [];
			my $cols  = $h->{search_cols}  || [];
			my $match = $h->{search_match} || [];
			my $equal = $h->{search_equal} || [];

			# 検索の準備
			my @cond;
			foreach(@$words) {
				my $x = $_ =~ s/([\\\"])/\\$1/rg;
				my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

				my @ary;
				foreach (@$equal) {
					push(@ary, "\$_->{$_} eq \"$x\"");
				}
				foreach (@$cols) {
					push(@ary, "\$_->{$_} =~ /$r/i");
				}
				foreach (@$match) {
					push(@ary, "\$_->{$_} =~ /^$r\$/i");
				}
				push(@cond, '(' . join(' || ', @ary) . ')');
			}

			my @not_words_reg;
			foreach(@$not) {
				my $x = $_ =~ s/([\\\"])/\\$1/rg;
				my $r = $_ =~ s/([^0-9A-Za-z\x80-\xff])/"\\x" . unpack('H2',$1)/reg;

				my @ary;
				foreach (@$equal) {
					push(@ary, "\$_->{$_} ne \"$x\"");
				}
				foreach (@$cols) {
					push(@ary, "\$_->{$_} !~ /$r/i");
				}
				foreach (@$match) {
					push(@ary, "\$_->{$_} !~ /^$r\$/i");
				}
				push(@cond, join(' && ', @ary));
			}

			$cond_L2 = 'if (!(' . join(' && ', @cond) . ')) { next; }';
			$self->debug("select '$table' where L1: $cond_L2");	# debug-safe
		}

		#---------------------------------------------------------------
		# 検索関数生成
		#---------------------------------------------------------------

		if ($do_load_L1 || $do_load_L2) {
			$dir =~ s/\\\'//g;
			$ext =~ s/\\\'//g;
			my $load = "\$_ = \$self->read_rowfile('$table', \$_);";
			if ($do_load_L1) { $do_load_L1 = $load; }
				else     { $do_load_L2 = $load; }
		}
		if ($limit) {
			$limit = "if(\$#newary >= $limit) { last; }";
		}
		my $func=<<FUNCTION_TEXT;
		sub {
			my (\$self, \$db, \$match_h, \$not_match_h) = \@_;
			my \@newary;
			foreach(\@\$db) {
				$do_load_L1
				$cond_L1
				$do_load_L2
				$cond_L2
				push(\@newary, \$_);
				$limit
			}
			return \\\@newary;
		}
FUNCTION_TEXT
		## $ROBJ->debug("[$table]" . $func =~ s/\t/　　/rg);

		# 検索関数のコンパイルと実行
		$func = $self->eval_and_cache($func);
		$db = &$func($self, $db, \%match_h, \%not_match_h);

	} else {
		# 内部データを破壊しないためのコピー生成
		my @newary = @$db;
		$db = \@newary;
	}
	if ($#$db < 0) { return []; }

	#-----------------------------------------------------------------------
	# まだソートされてなければソートする
	#-----------------------------------------------------------------------
	if ($sort_state) {
		if (!$load_all_data && !($sort_state & 4)) {
			$load_all_data = 1;
			$db = [ map { $self->read_rowfile($table, $_) } @$db ];
		}
		$db = [sort $sort_func @$db];
	}

	#-----------------------------------------------------------------------
	# 該当件数を記録
	#-----------------------------------------------------------------------
	my $hits = $#$db +1;

	#-----------------------------------------------------------------------
	# limit and offset
	#-----------------------------------------------------------------------
	if ($h->{offset} ne '') {
		splice(@$db, 0, $h->{offset});
	}
	if ($h->{limit} ne '') {
		splice(@$db, int($h->{limit}));
	}

	#-----------------------------------------------------------------------
	# all data load? / index 外のカラムが必要?
	#-----------------------------------------------------------------------
	if (!$load_all_data) {
		my $cols = $sel_cols;
		if (!$cols) { $cols = [ keys(%$exists_cols) ]; }
		if (grep { !$index_cols->{$_} } @$cols) {
			foreach(@$db) {
				$_ = $self->read_rowfile($table, $_);
			}
		}
	}

	#-----------------------------------------------------------------------
	# コピー生成
	#-----------------------------------------------------------------------
	# 各配列要素の hashref を破壊しないためコピー生成
	if ($sel_cols) {
		my $func='sub { my $db = shift; foreach(@$db) {';
		$func .= '$_ = {';
		foreach(@$sel_cols) {
			$func .= "$_=>\$_->{$_},"
		}
		chop($func);
		$func .= '}}}';
		$func = $self->eval_and_cache($func);
		&$func($db);
	} else {
		foreach(@$db) {
			my %h = %$_;
			$_ = \%h;
			delete $h{'*'};		# loaded flag
		}
	}

	return $require_hits ? ($db,$hits) : $db;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●index のロード
#-------------------------------------------------------------------------------
sub load_index {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my ($table, $edit_flag, $NoError) = @_;
	if (! $edit_flag && defined $self->{"$table.tbl"}) {
		return $self->{"$table.tbl"};
	}
	$self->debug("load index on '$table' table".($edit_flag ? ' (edit)':''));	# debug-safe

	# ロード準備
	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	if (!-e $index) {
		if (-e $dir) { $self->index_rebuild( $table ); }
		else {
			$self->error("Table '$table' not found!");
			return;
		}
	}

	# ロード
	my ($fh, $lines);
	if ($edit_flag) {
		# 編集モード
		my $flags={};
		if ($self->{begin}) {
			# 既にトランザクション処理をしてる
			if ($self->{transaction}->{$table}) {
				return $self->{"$table.tbl"};
			}
			# トランザクションは bakupfile を write_lock する
			my $fh = $ROBJ->file_lock($dir . $self->{index_backup_file}, 'write_lock_nb' );
			if (!$fh) {
				# 別のトランザクションが既に lock していたらエラー終了
				# ※「開放待ち」はデッドロックの可能性があるので終了する
				return undef;
			}
			$self->{"$table.lock-tr"} = $fh;
			$self->{transaction}->{$table}=1;
			# indexファイルは編集されないようにReadlock（読み込みはブロックしない）
			$flags->{ReadLock}=1;
		}
		($fh, $lines) = $ROBJ->fedit_readlines($index, $flags);
		if ($#$lines < 0) {
			$ROBJ->fedit_exit($fh);
			delete $self->{transaction}->{$table};
			return undef;
		}
		$self->{"$table.lock"} = $fh;
	} else {
		$lines = $ROBJ->fread_lines_cached($index, {NoError => $NoError});
		if ($#$lines < 0) { return undef; }
	}

	# 改行コード除去
	# map { s/[\r\n]//g; } @$lines;
	map { chop($_) } @$lines;	# 正規表現よりchompよりchopが速い

	# データ解析
	# 1行目 = DBファイルのVersion番号
	my $version = $self->{"$table.version"} = int(shift(@$lines));	# Version
	# 2行目 = ランダム値
	my $random;
	if ($version > 3) {	# Ver4以降のみ存在
		$random = $self->{"$table.rand"} = shift(@$lines);
	} else {		# last modofied で代用
		$random = $ROBJ->get_lastmodified($index);
		shift(@$lines);	# index only flagを読み捨て
	}
	# 3行目 = シリアル値
	$self->{"$table.serial"} = int(shift(@$lines));
	# 4行目 = 全カラム名
	my @allcols = split(/\t/, shift(@$lines));
	$self->{"$table.cols"} = { map { $_ => 1} @allcols };
	# 5行目 = 数値カラム名
	$self->{"$table.int"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	# 6行目 = floatカラム名
	if ($version > 3) {	# Ver4以降のみ存在
		$self->{"$table.float"}= { map { $_ => 1} split(/\t/, shift(@$lines)) };
	} else {
		$self->{"$table.float"} = {};
	}
	# 7行目 = flagカラム名
	$self->{"$table.flag"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	if ($version > 3) {	# Ver4以降のみ存在
		# 8行目 = 文字列カラム
		$self->{"$table.str"}     = { map { $_ => 1} split(/\t/, shift(@$lines)) };
		# 9行目 = UNQUEカラム
		$self->{"$table.unique"}  = { map { $_ => 1} split(/\t/, shift(@$lines)) };
		#10行目 = NOT NULLカラム
		$self->{"$table.notnull"} = { map { $_ => 1} split(/\t/, shift(@$lines)) };
	} else {
		my %cols = %{ $self->{"$table.cols"} };
		map { delete $cols{$_} } (keys(%{$self->{"$table.int"}}), keys(%{$self->{"$table.flag"}}) );
		$self->{"$table.str"}     = \%cols;
		$self->{"$table.unique"}  = { pkey=>1 };
		$self->{"$table.notnull"} = { pkey=>1 };
	}
	if ($version > 4) {	# Ver5以降のみ存在
		#11行目 = defaultカラム
		my @ary  = split(/\t/, shift(@$lines));
		$self->{"$table.default"} = { map { $_ => shift(@ary) } @allcols };
	}
	# 12行目 = indexカラム名
	my @idx_cols = split(/\t/, shift(@$lines));
	$self->{"$table.idx"} = { map { $_ => 1} @idx_cols };

	# キャッシュの確認。ランダム値を見て書き換えを検出する。
	if ($IndexCache{"$table.rand"} eq $random) {
		$self->{"$table.load_all"} = $IndexCache{"$table.load_all"};
		return ($self->{"$table.tbl"} = $IndexCache{$table});
	}
	# キャッシュを消す
	if( exists($IndexCache{$table}) ) { $self->clear_cache($table); }

	my $parse_func='sub{return{';
	foreach (0..$#idx_cols) {
		my $col=$idx_cols[$_];
		$col =~ s/\W//g;
		$parse_func.="$col=>\$_[$_],";
	}
	chop($parse_func);
	$parse_func.='}}';
	$parse_func = $self->eval_and_cache($parse_func);

	### 【メモ】全体を関数化するよりこの方が速い
	### $ROBJ->{Timer}->start('x2');
	foreach(@$lines) {
		$_ = &$parse_func(split("\t", $_));
	}
	### $ROBJ->debug("[$table] " . $#$lines . " lines parse = ".int($ROBJ->{Timer}->stop('x2')*10000+0.5)/10 ."ms");

	$self->{"$table.tbl"} = $lines;		# table 内容保存
	$IndexCache{$table}  = $lines;		# キャッシュ保存
	$IndexCache{"$table.rand"} = $random;
	return $lines;
}

#-------------------------------------------------------------------------------
# ●１カラムのデータロード
#-------------------------------------------------------------------------------
sub read_rowfile {
	my $self = shift;
	my ($table, $h) = @_;
	if ($h->{'*'}) { return $h; }	# ロード済
	my $ROBJ = $self->{ROBJ};

	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	my $h = $ROBJ->fread_hash_cached($dir . sprintf($FileNameFormat, $h->{pkey}). $ext);
	$h->{'*'}=1;	# ロード済フラグ
	return $h;
}

#-------------------------------------------------------------------------------
# ●全データのロード
#-------------------------------------------------------------------------------
sub load_allrow {
	my $self = shift;
	my $table = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{"$table.load_all"}) { return $self->{"$table.tbl"}; }

	$self->debug("load all data on '$table' table");	# debug-safe
	my $ext = $self->{ext};
	my $dir = $self->{dir} . $table . '/';
	$self->{"$table.tbl"} = [ map { $self->read_rowfile($table, $_) } @{$self->{"$table.tbl"}} ];
	$self->{"$table.load_all"} = 1;
	$IndexCache{"$table.load_all"} = 1;
	return ($IndexCache{$table} = $self->{"$table.tbl"});
}

#-------------------------------------------------------------------------------
# ●文字列型かチェックする
#-------------------------------------------------------------------------------
sub check_type_str {
	my ($self, $table, $column) = @_;
	if (!exists $self->{"$table.tbl"}) {
		$self->error("%s table not found!", $table);
	}
	return $self->{"$table.str"}->{$column};
}

#-------------------------------------------------------------------------------
# ●Sort関数の生成 (ORDER BY)
#-------------------------------------------------------------------------------
sub generate_sort_func {
	my ($self, $table, $h) = @_;
	my $sort = ref($h->{sort}    ) ? $h->{sort}     : ($h->{sort}     eq '' ? [] : [ $h->{sort}     ]);
	my $rev  = ref($h->{sort_rev}) ? $h->{sort_rev} : ($h->{sort_rev} eq '' ? [] : [ $h->{sort_rev} ]);
	my $cols   = $self->{"$table.cols"};
	my $is_str = $self->{"$table.str"};
	my @cond;
	foreach(0..$#$sort) {
		my $col = $sort->[$_];
		my $rev = $rev->[$_];
		if (ord($col) == 0x2d) {	# '-colname'
			$col = $sort->[$_] = substr($col, 1);
			$rev = 1;
		}
		$col =~ s/\W//g;
		if ($col eq '') { next; }

		my $op = $is_str->{$col} ? 'cmp' : '<=>';
		push(@cond, $rev ? "\$b->{$col}$op\$a->{$col}" : "\$a->{$col}$op\$b->{$col}");
	}
	my $func = sub { 1; };
	if (@cond) {
		$func = 'sub{'. join('||',@cond) .'}';
		$func = $self->eval_and_cache($func);
	}

	return wantarray ? ($func, $sort) : $func;
}

#-------------------------------------------------------------------------------
# ●evalキャッシュ
#-------------------------------------------------------------------------------
my %function_cache;
sub eval_and_cache {
	my $self=shift;
	my $functext=shift;
	if (exists $function_cache{$functext}) {
		return $function_cache{$functext};
	}
	# function compile
	my $func;
	eval "\$func=$functext";
	if ($@) { die "[DB_text/eval_and_cache] $@"; }
	return ($function_cache{$functext} = $func);
}

################################################################################
# ●タイマーの仕込み
################################################################################
&embed_timer_wrapper(__PACKAGE__);

1;

