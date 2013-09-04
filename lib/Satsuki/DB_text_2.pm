use strict;
#-------------------------------------------------------------------------------
# Split from Satsuki::DB_text.pm for AUTOLOAD.
#-------------------------------------------------------------------------------
package Satsuki::DB_text;
use Satsuki::DB_text ();

our $filename_format;
our %index_cache;
###############################################################################
# ■データの挿入・削除
###############################################################################
#-------------------------------------------------------------------------------
# ●データの挿入
#------------------------------------------------------------------------------
sub insert {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($table, $h) = @_;
	$table =~ s/\W//g;

	my $db = $self->load_index($table, 1);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}
	# データの整合性チェック
	$h = $self->check_column_type($table, $h);
	if (!defined $h) {
		$self->edit_index_exit($table);
		return 0;	# error exit
	}

	my $pkey = $h->{pkey};
	if ($pkey<1) {	# pkeyが指定されていない
		$pkey = $h->{pkey} = ++( $self->{"$table.serial"} );	# pkey
	}

	# UNIQUEカラム制約の確認
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my $unique_hash = $self->load_unique_hash($table);
	foreach(@unique_cols) {
		my $v = $h->{$_};
		if ($v eq '' || !exists $unique_hash->{$_}->{$v}) { next; }
		# Error
		$self->edit_index_exit($table);
		$self->error("On '%s' table, duplicate key value violates unique constraint '%s'(value is '%s')", $table, $_, $v);
		return 0;
	}

	# カラム追加
	push(@$db, $h);			# add
	$self->add_unique_hash($table,$h);

	# 保存
	$self->write_rowfile($table, $h);
	my $r = $self->save_index($table);
	if ($r) { return 0; }	# 失敗

	# pkey書き換え
	if ($h->{pkey}>0 && $pkey>$self->{"$table.serial"}) {
		$self->{"$table.serial"} = $pkey;
	}

	return $pkey;		# 成功
}

#-------------------------------------------------------------------------------
# ●データの更新
#------------------------------------------------------------------------------
sub update_match {
	my $self = shift;
	my $table= shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $r = $self->load_index($table, 1);
	if (!defined $r) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}

	# updateの条件が式のときの前処理
	my %funcs;
	foreach (keys(%$h)) {
		if (ord($_) != 0x2a) { next; }		# "*column"
		my $v=$h->{$_};
		$v =~ s![^\w\+\-\*\/\%\(\)\|\&\~<>]!!g;
		if ($v =~ /\w\(/) {
			$self->error("expression error(not allow function). table=$table, $v");
			return 0;
		}
		$v =~ s/([A-Za-z_]\w*)/\$h->{$1}/g;
		my $func;
		eval "\$func=sub {my \$h=shift; return $v;}";
		# $ROBJ->debug("$v");
		if ($@) {
			$self->error("expression error. table=$table, $@");
			return 0;
		}
		delete $h->{$_};
		my $k=substr($_, 1);
		if ($k eq 'pkey') {
			$self->error("On '%s' table, disallow pkey update",$table);
			return 0;
		}
		$funcs{$k} = $func;
	}

	# データの整合性チェック
	$h = $self->check_column_type($table, $h, 'update mode flag=1');
	if (!defined $h) {
		$self->edit_index_exit($table);
		return 0;	# error exit
	}
	delete $h->{pkey};

	# マッチ条件のカラムを確認
	my ($func,$db,$in) = $self->load_and_generate_where($table, @_);
	if (!$func) {
		return 0;	# error exit
	}

	# 条件にマッチするカラムを書き換え
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my $unique_hash = $self->load_unique_hash($table);
	my $updates = 0;
	my @new_db = @$db;
	my @save_array;
	foreach(@new_db) {
		# マッチしない
		if (! &$func($_, $in)) { next; }

		# マッチした
		$updates++;
		$self->del_unique_hash($table, $_);

		# 保持情報書き換え
		my $row = $self->read_rowfile($table, $_);
		foreach my $k (keys(%$h)) {
			# replace
			$row->{$k} = $h->{$k};
		}
		foreach my $k (keys(%funcs)) {
			$row->{$k} = &{ $funcs{$k} }($row);
		}
		# save hash
		push(@save_array, $row);
		$_ = $row;

		# UNIQUE制約の確認
		foreach my $col (@unique_cols) {
			my $v = $row->{$col};
			if ($v eq '' || !exists $unique_hash->{$col}->{$v}) { next; }
			# 重複あり
			$self->edit_index_exit($table);
			$self->clear_unique_cache($table);
			$self->error("On '%s' table, duplicate key value violates unique constraint '%s'(value is '%s')", $table, $col, $_->{$col});
			return 0;
		}
		# UNIQUE hash の更新
		$self->add_unique_hash($table, $row);
	}

	# update実行
	if ($updates) {
		$self->{"$table.tbl"}=\@new_db;
		foreach(@save_array) {
			$self->write_rowfile($table, $_);
		}
		my $r = $self->save_index($table);	# 編集結果の保存
		if ($r) { return 0; }	# 失敗
	} elsif(! $self->{begin}) {
		$self->edit_index_exit($table);		# 編集処理の終了
	}

	return $updates;	# 成功
}
#-------------------------------------------------------------------------------
# ●データの削除
#------------------------------------------------------------------------------
sub delete_match {
	my $self = shift;
	my $table= shift;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $r = $self->load_index($table, 1);
	if (!defined $r) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 0;
	}

	# マッチ条件のカラムを確認
	my ($func,$db,$in) = $self->load_and_generate_where($table, @_);
	if (!$func) {
		return 0;	# error exit
	}

	my @newary;
	my $count;
	my $trace_ary = $self->load_trace_ary($table);
	foreach(@$db) {
		# マッチしない
		if (! &$func($_, $in)) {
			push(@newary, $_);
			next;
		}
		# 削除
		$self->delete_rowfile($table, $_);
		$count++;
		# UNIQUE制約のクリア
		$self->del_unique_hash($table, $_);
	}
	$self->{"$table.tbl"}=\@newary;
	$self->save_index($table);

	return $count;
}
###############################################################################
# ■テータの集計
###############################################################################
#------------------------------------------------------------------------------
# ●テーブルの情報を集計
#------------------------------------------------------------------------------
sub select_by_group {
	my ($self, $table, $h) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# group by
	my $group_col = $h->{group_by};
	$group_col =~ s/\W//g;

	my $sum_cols = ref($h->{sum_cols}) ? $h->{sum_cols} : ($h->{sum_cols} eq '' ? [] : [ $h->{sum_cols} ]);
	my $max_cols = ref($h->{max_cols}) ? $h->{max_cols} : ($h->{max_cols} eq '' ? [] : [ $h->{max_cols} ]);
	my $min_cols = ref($h->{min_cols}) ? $h->{min_cols} : ($h->{min_cols} eq '' ? [] : [ $h->{min_cols} ]);

	#---------------------------------------------
	# データロード条件
	#---------------------------------------------
	my %w = %$h;
	delete $w{sort};
	delete $w{sort_rev};
	delete $w{offset};
	delete $w{limit};
	delete $w{require_hits};

	my %cols = map {$_ => 1} ($group_col,@$sum_cols,@$max_cols,@$min_cols);
	delete $cols{''};
	$w{cols} = [ keys(%cols) ];

	#---------------------------------------------
	# データのロード
	#---------------------------------------------
	my $db = $self->select($table, \%w);

	#---------------------------------------------
	# グルーピングと集計処理
	#---------------------------------------------
	my %group;
	my %sum = map { $_=>{} } @$sum_cols;
	my %max = map { $_=>{} } @$max_cols;
	my %min = map { $_=>{} } @$min_cols;
	foreach my $x (@$db) {
		my $g = $x->{$group_col};
		$group{ $g } ++;

		foreach (@$sum_cols) {
			$sum{$_}->{$g} += $x->{$_};
		}
		foreach (@$max_cols) {
			my $y = $max{$_}->{$g};
			my $z = $x->{$_};
			$max{$_}->{$g} = ($y eq '') ? $z : ($y<$z ? $z : $y);
		}
		foreach (@$min_cols) {
			my $y = $min{$_}->{$g};
			my $z = $x->{$_};
			$min{$_}->{$g} = ($y eq '') ? $z : ($y>$z ? $z : $y);
		}
	}

	#---------------------------------------------
	# 結果を構成
	#---------------------------------------------
	my @newary;
	while(my ($k,$v) = each(%group)) {
		my %h;
		$h{$group_col} = $k;
		$h{_count}     = $v;
		foreach (@$sum_cols) {
			$h{"${_}_sum"} = $sum{$_}->{$k};
		}
		foreach (@$max_cols) {
			$h{"${_}_max"} = $max{$_}->{$k};
		}
		foreach (@$min_cols) {
			$h{"${_}_min"} = $min{$_}->{$k};
		}
		push(@newary, \%h);
	}

	#---------------------------------------------
	# ソート処理
	#---------------------------------------------
	my ($sort_func, $sort) = $self->generate_sort_func($table, $h);
	@newary = sort $sort_func @newary;

	return \@newary;
}

###############################################################################
# ■サブルーチン：ユニークカラムの処理
###############################################################################
#------------------------------------------------------------------------------
# ●unique hashのロード
#------------------------------------------------------------------------------
sub load_unique_hash {
	my $self  = shift;
	my $table = shift;

	# キャッシュを返す
	if ($index_cache{"$table.unique-cache"}) {
		return $index_cache{"$table.unique-cache"};
	}

	# UNIQUEカラム制約の確認
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	my ($line0, $line1, $line2);
	foreach(0..$#unique_cols) {
		my $col = $unique_cols[$_];
		$col =~ s/\W//g;
		$line0 .= "my \%h$_;";
		$line1 .= "\$h${_}{\$_->{'$col'}}=1;";
		$line2 .= "'$col'=>\\\%h$_,";
	}
	chop($line2);
	my $conv_hash_func = <<FUNC;
	sub {
		#  54646546
		my \$db = shift;
		$line0
		foreach(\@\$db) {
			$line1
		}
		return { $line2 };
	}
FUNC
	$conv_hash_func = $self->eval_and_cache($conv_hash_func);

	my $db = $self->{"$table.tbl"};
	my $unique_hash = &$conv_hash_func( $db );
	$index_cache{"$table.unique-cache"} = $unique_hash;
	return $unique_hash;
}

#------------------------------------------------------------------------------
# ●unique hashへの追加
#------------------------------------------------------------------------------
sub add_unique_hash {
	my $self  = shift;
	my ($table, $h) = @_;

	# hashロード
	my $unique_hash = $index_cache{"$table.unique-cache"};
	if (!$unique_hash) { return; }

	# 追加処理
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	foreach(@unique_cols) {
		$unique_hash->{ $_ }->{ $h->{$_} } = 1;
	}
}

#------------------------------------------------------------------------------
# ●unique hashの削除
#------------------------------------------------------------------------------
sub del_unique_hash {
	my $self  = shift;
	my ($table, $h) = @_;

	# hashロード
	my $unique_hash = $index_cache{"$table.unique-cache"};
	if (!$unique_hash) { return; }

	# 削除処理
	my @unique_cols = keys(%{ $self->{"$table.unique"} });
	foreach(@unique_cols) {
		delete $unique_hash->{ $_ }->{ $h->{$_} };
	}
}

#------------------------------------------------------------------------------
# ●unique hash cacheのクリア
#------------------------------------------------------------------------------
sub clear_unique_cache {
	my ($self, $table) = @_;
	delete $index_cache{"$table.unique-cache"};
}

###############################################################################
# ■トランザクション
###############################################################################
# 大量の insert/update を高速化する目的で実装されている。
# ※insert/update/delete のみ対応。
sub begin {
	my $self = shift;
	if ($self->{begin}) {
		$self->warning("there is already a transaction in progress");
		return ;
	}
	$self->{begin} = 1;
	$self->{transaction} = {};
	$self->{trace} = {}
}
sub rollback {
	my $self = shift;
	if ($self->{begin}) {
		$self->warning("there is no transaction in progress");
		return ;
	}
	$self->{begin} = 0;
	# 編集破棄
	my $trans = $self->{transaction};
	foreach(keys(%$trans)) {
		$self->edit_index_exit($_);
		$self->clear_cache($_);

		# トランザクションlock を解く
		close($self->{"$_.lock-tr"});
		delete $self->{"$_.lock-tr"};
	}
	$self->{transaction}={};
	$self->{trace}={};
	return -1;
}
sub commit {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{begin}<0) {	# 途中でエラーがあった
		return $self->rollback();
	}
	$self->{begin} = 0;

	# 編集の書き込み
	my $trans = $self->{transaction};
	foreach my $table (keys(%$trans)) {
		# トランザクションを後追い処理
		my $trace = $self->load_trace_ary($table);
		my %write;
		my %del;
		foreach(@$trace) {
			if (ref($_)) { # write
				my $pkey = $_->{pkey};
				$write{$pkey}=$_;
				delete $del{$pkey};
			}
			# del
			$del{$_}=1;
			delete $write{$_};
		}
		# 書き込み処理
		foreach(values(%write)) {
			$self->write_rowfile($table, $_);
		}
		foreach(keys(%del)) {
			$self->delete_rowfile($table, $_);
		}

		# write block に変更可能ならば変更する
		# Non blocking。Windowsでは失敗する。
		$ROBJ->flock($self->{"$table.lock"}, Fcntl::LOCK_EX | Fcntl::LOCK_NB);
		$self->save_index($table);

		# トランザクションlock を解く
		close ($self->{"$table.lock-tr"});
		delete $self->{"$table.lock-tr"};
	}
	$self->{transaction}={};
	$self->{trace}={};
	return 0;
}
#------------------------------------------------------------------------------
# ●トランザクショントレース
#------------------------------------------------------------------------------
sub load_trace_ary {
	my ($self, $table) = @_;

	# トランザクションでない
	if (! $self->{transaction}->{$table}) { return '[load_trace_ary] error'; }

	if ($self->{trace}->{$table}) {
		return $self->{trace}->{$table};
	}
	return ($self->{trace}->{$table} = []);
}
###############################################################################
# ■update/検索関連サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●columnの型/not nullチェック
#------------------------------------------------------------------------------
sub check_column_type {
	my ($self, $table, $h, $update_flag) = @_;
	my $ROBJ = $self->{ROBJ};
	my $cols       = $self->{"$table.cols"};
	my $int_cols   = $self->{"$table.int"};
	my $float_cols = $self->{"$table.float"};
	my $flag_cols  = $self->{"$table.flag"};

	# 存在するカラム名をコピー
	my %new_hash;
	foreach (keys(%$h)) {
		if (! $cols->{$_}) {
			$self->error("On '%s' table, not exists '%s' column", $table, $_);
			return undef;
		}
		# 型の適用
		if ($h->{$_} eq '') {			# nullデータはそのまま
			$new_hash{$_} = undef;
		} elsif ($int_cols->{$_})  {
			$new_hash{$_} = int($h->{$_});
		} elsif ($float_cols->{$_}) {
			$new_hash{$_} = $h->{$_}+0;	# 数値化
		} elsif ($flag_cols->{$_}) {
			$new_hash{$_} = $h->{$_} ? 1 : 0;
		} else {	# 文字列はそのまま
			$new_hash{$_} = $h->{$_};
		}
	}
	# not null制約の確認
	my $notnull_cols = $self->{"$table.notnull"};
	my @check_columns_ary = $update_flag ? keys(%new_hash) : keys(%$notnull_cols);	# update or insert
	foreach (@check_columns_ary) {
		if (!$notnull_cols->{$_}) { next; }
		if (!$update_flag && $_ eq 'pkey') { next; }
		if (!defined $h->{$_}) {
			$self->error("On '%s' table, '%s' column is constrained not null", $table, $_);
			return undef;
		}
	}
	return \%new_hash;
}

#------------------------------------------------------------------------------
# ●条件節カラムの解析と必要データのロード
#------------------------------------------------------------------------------
sub load_and_generate_where {
	my $self = shift;
	my $table = shift;
	my $ROBJ = $self->{ROBJ};

	# ハッシュ引数を書き換え
	if ($#_ == 0 && ref($_[0]) eq 'HASH') {
		my $h = shift;
		foreach(sort(keys(%$h))) {
			push(@_, $_);
			push(@_, $h->{$_});
		}
	}

	# 条件節に必要なカラムの確認
	if (!exists $self->{"$table.idx"}) {
		$self->load_index($table);
	}
	my $cols = $self->{"$table.cols"};
	my $idx  = $self->{"$table.idx"};
	my $str  = $self->{"$table.str"};

	# 条件節分析
	my $load_all;
	my @cond;
	my %in;
	while(@_) {
		my $col = shift;
		my $val = shift;
		my $not = 0;
		if (!defined $col) { last; }
		# 負論理？
		if (substr($col,0,1) eq '-') {
			$col = substr($col,1);
			$not = 1;
		}
		# 正しいカラムか？
		if (! $cols->{$col}) {
			$self->edit_index_exit($table);
			$self->error("On '%s' table, not exists '%s' column", $table, $col);
			return (undef,undef,undef);
		}
		if (! $idx->{$col}) { $load_all=1; }	# index以外を参照してる

		# 関数の生成
		if (ref($val) eq 'ARRAY') {
			# 複数マッチ
			$in{$col} = { map {$_=>1} @$val };
			push(@cond, ($not ? '!' : '') . "exists\$in->{$col}->{\$h->{$col}}");
			next;
		}
		if ($str->{$col}) {
			# 文字列カラム
			$val =~ s/([\\'])/\\$1/g;
			push(@cond, $not ? "\$h->{$col}ne'$val'" : "\$h->{$col}eq'$val'");
			next;
		}
		{
			# 数値カラム
			$val += 0;
			push(@cond, $not ? "\$h->{$col}!=$val" : "\$h->{$col}==$val");
			next;
		}
	}
	# 条件関数のコンパイル
	my $func;
	if (@cond) {
		my $cond = join('&&', @cond);
		$func = "sub { my (\$h,\$in)=\@_; return $cond; }";
		$func = $self->eval_and_cache($func);
	} else {
		$func = sub { return 1; };
	}

	# 条件節に必要なカラムの確認
	if ($load_all) { $self->load_all($table); }
	return ($func, $self->{"$table.tbl"}, \%in);
}

###############################################################################
# ■サブルーチン
###############################################################################
#-------------------------------------------------------------------------------
# ●pkeyの生成
#------------------------------------------------------------------------------
sub generate_pkey {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	if ($self->{begin}) {
		# トランザクション中？
		my $db = $self->load_index($table, 1);
		if (!defined $db) {
			$self->edit_index_exit($table);
			$self->error("Can't find '%s' table", $table);
			return 0;
		}
		return ++( $self->{"$table.serial"} )
	}

	# 編集準備
	my $dir   = $ROBJ->get_filepath( $self->{dir} . $table . '/' );
	my $index = $dir . $self->{index_file};
	if (!-e $index && -e $dir) { $self->index_rebuild( $table ); }

	# indexをopenしてlockをかける
	my $fh;
	if ( !sysopen($fh, $index, Fcntl::O_RDWR) ) {
		return 0;
	}
	$ROBJ->write_lock($fh);
	binmode($fh);

	# データを読み出し
	my $version = <$fh>;
	my $random  = <$fh>;
	my $serial  = <$fh>;

	# 次の値
	my $fail;
	$serial =~ s/[\r\n]//g;
	my $nextval = $serial+1;
	my $datalen = length($serial);
	if ($datalen < length($nextval)) { $fail=1; }	# データサイズ増加
	# サイズ増加は、indexファイル生成時シリアル値の頭「00」をつけて回避している

	# 書き換え準備
	my $nextval_str = substr(('0' x $datalen) . $nextval, -$datalen);
	if (length($nextval_str) != $datalen) { $fail=1; }	# 失敗
	# 書き換え
	if (!seek($fh, length($version)+length($random), 0)) { $fail=1; }
	if (!$fail) {
		if (syswrite($fh, $nextval_str, $datalen) != $datalen) { $fail=1; }
	}
	close($fh);
	if ($fail) { return 0; }	# 失敗

	$self->{"$table.serial"} = $nextval;
	return $nextval;
}

#------------------------------------------------------------------------------
# ●index のセーブ
#------------------------------------------------------------------------------
sub save_index {
	my $self    = shift;
	my $ROBJ    = $self->{ROBJ};
	my ($table, $force) = @_;

	# トランザクション中は書き込まない。
	if (!$force && $self->{begin}) {
		$self->{transaction}->{$table}=1;
		return 0;
	}

	my $db        = $self->{"$table.tbl"};			# table array ref
	my $idx_cols  = $self->{"$table.idx"};			# index array ref
	my $idx_only  = $self->{"$table.index_only"};		# index only flag
	my $serial    = int($self->{"$table.serial"});		# serial

	my @lines;
	# 1行目 = DBファイルのVersion番号
	push(@lines, "4\n");
	# 2行目 = ランダム値
	push(@lines, "R" . $ROBJ->{TM} . rand(1) . "\n");	# random signature
	# 3行目 = シリアル値（現在の最大値）
	# 	★★★仕様変更字は generate_pkey も編集のこと★★★
	push(@lines, "00000$serial\n");	# 00付加必須
	# 4行目 = 全カラム名
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.cols"} }))). "\n");
	# 5行目 = 整数カラム名
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.int"}  }))). "\n");
	# 6行目 = 数値カラム名
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.float"} }))). "\n");
	# 7行目 = flagカラム名
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.flag"}  }))). "\n");
	# 8行目 = 文字列カラム
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.str"}   }))). "\n");
	# 9行目 = UNIQUEカラム
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.unique"}  }))). "\n");
	#10行目 = NOT NULLカラム
	push(@lines, join("\t", sort(keys(%{ $self->{"$table.notnull"} }))). "\n");

	# pkeyの昇順に全データを並べる
	my @newary = sort { $a->{pkey} <=> $b->{pkey} } @$db;
	$self->{"$table.tbl"} = \@newary;	# 内部保持を書き換え
	$index_cache{$table}  = \@newary;	# indexキャッシュ

	# indexカラムを並べる
	my @idx_cols;
	{
		my %h = %$idx_cols;
		delete $h{pkey};
		@idx_cols = ('pkey', sort(keys(%h)));
	}
	# 10行目 = indexカラム名
	push(@lines, join("\t", @idx_cols) . "\n");

	#--------------------------------------
	# 行合成関数を生成
	#--------------------------------------
	my $hash2line='';
	foreach(@idx_cols) {
		$_ =~ s/\W//g;
		$hash2line.="\$h->{$_}\0";
	}
	chop($hash2line);

	# TAB, 改行をspace１個に
	my $line_func=<<FUNC;
	sub {
		my (\$ary,\$h) = \@_;
		my \$s = "$hash2line";
		\$s =~ tr/\t\n/  /;
		\$s =~ tr/\0/\t/;
		push(\@\$ary, \$s."\n");
	}
FUNC
	$line_func = $self->eval_and_cache($line_func);
	foreach(@newary) {
		&$line_func(\@lines, $_);
	}

	#--------------------------------------
	# save
	#--------------------------------------
	my $dir   = $self->{dir} . $table . '/';
	my $index = $dir . $self->{index_file};
	# unlock
	my $r;
	if (exists $self->{"$table.lock"}) {
		$r = $ROBJ->fedit_writelines($index, $self->{"$table.lock"}, \@lines);
		delete $self->{"$table.lock"};
	} else {
		$ROBJ->fwrite_lines($index, \@lines);
	}
	# 失敗
	if ($r) { $self->clear_cache($table); return $r; }

	# キャッシュ更新
	$index_cache{$table} = $self->{"$table.tbl"};
	return 0;
}

#------------------------------------------------------------------------------
# ●index編集の破棄
#------------------------------------------------------------------------------
sub edit_index_exit {
	my ($self, $table) = @_;
	if ($self->{begin}) {
		# トランザクション中は書き込まない。
		$self->{begin}=-1;	# エラー発生と見なす
		return 0;
	}
	if (defined $self->{"$table.lock"}) {
		my $index_file = $self->{dir} . $table . '/' . $self->{index_file};
		$self->{ROBJ}->fedit_exit($index_file, $self->{"$table.lock"});
		delete $self->{"$table.lock"};
	}
	# キャッシュの削除
	$self->clear_cache($table);
}

#-------------------------------------------------------------------------------
# ●１カラムのデータを保存
#------------------------------------------------------------------------------
sub write_rowfile {
	my $self = shift;
	my ($table, $h) = @_;

	# トランザクション
	if ($self->{begin}) {
		my $ary = $self->load_trace_ary($table);
		push(@$ary, $h);	# hash
		$h->{'*'}=1;		# ロード済フラグ設定
		return 0;
	}

	# ハッシュ保存
	my $ROBJ = $self->{ROBJ};
	my $ext  = $self->{ext};
	my $dir  = $self->{dir} . $table . '/';

	delete $h->{'*'};	# ロード済フラグ
	my $r = $ROBJ->fwrite_hash($dir . sprintf($filename_format, $h->{pkey}). $ext, $h);
	$h->{'*'}=1;		# ロード済フラグ再設定
	return $r;
}

#-------------------------------------------------------------------------------
# ●１カラムのデータロード
#------------------------------------------------------------------------------
sub delete_rowfile {
	my $self = shift;
	my ($table, $pkey) = @_;
	if (ref $pkey) { $pkey=$pkey->{pkey}; }

	# トランザクション
	if ($self->{begin}) {
		my $ary = $self->load_trace_ary($table);
		push(@$ary, $pkey);	# 数値
		return 0;
	}

	my $ROBJ = $self->{ROBJ};
	my $ext  = $self->{ext};
	my $dir  = $self->{dir} . $table . '/';
	return $ROBJ->file_delete($dir . sprintf($filename_format, $pkey). $ext);
}

#------------------------------------------------------------------------------
# ●キャッシュの消去
#------------------------------------------------------------------------------
sub clear_cache {
	my $self  = shift;
	my $table = shift;
	# index の予備を保存
	delete $self->{"$table.tbl"};
	delete $self->{"$table.load_all"};
	delete $index_cache{$table};
	delete $index_cache{"$table.rand"};
	delete $index_cache{"$table.load_all"};
	delete $index_cache{"$table.unique-cache"};
}

###############################################################################
# ●タイマーの仕込み
###############################################################################
&embed_timer_wrapper(__PACKAGE__);

1;
