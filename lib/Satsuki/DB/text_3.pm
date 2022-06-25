use strict;
#-------------------------------------------------------------------------------
# Split from Satsuki::DB_text.pm for AUTOLOAD.
#-------------------------------------------------------------------------------
package Satsuki::DB::text;
use Satsuki::DB::share_3;
our $FileNameFormat;
our %IndexCache;
################################################################################
# ■テーブルの操作
################################################################################
#-------------------------------------------------------------------------------
# ●create table
#-------------------------------------------------------------------------------
sub create_table {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($table, $colums) = @_;
	$table =~ s/\W//g;
	if ($table eq '') { $self->error('Called create_table() with null table name'); return 9; }

	# テーブル構造の解析
	my %cols       = ('pkey'=>1);	# pkey : 先頭最初のカラム
	my %index_cols = ('pkey'=>1);
	my %int_cols   = ('pkey'=>1);
	my %float_cols;
	my %flag_cols;
	my %str_cols;
	my %unique_cols  = ('pkey'=>1);
	my %notnull_cols = ('pkey'=>1);
	my %default;
	foreach(@$colums) {
		my $col = $_->{name};
		$col =~ s/\W//g;
		if ($col eq '') { next; }

		if (exists $cols{$col}) {
			$self->error("Column %s is dupulicate or 'pkey' is not allow", $table, $col);
			return 10;
		}
		$cols{$col}=1;	# ここを書き換えたら add_column も変更すること
		if    ($_->{type} eq 'int')   { $int_cols  {$col}=1; }
		elsif ($_->{type} eq 'float') { $float_cols{$col}=1; }
		elsif ($_->{type} eq 'flag')  { $flag_cols {$col}=1; }
		elsif ($_->{type} eq 'text')  { $str_cols  {$col}=1; }
		elsif ($_->{type} eq 'ltext') { $str_cols  {$col}=1; }
		else {
			$self->error('Column "%s" have invalid type "%s"', $col, $_->{type});
			return 20;
		}
		if ($_->{unique})        { $unique_cols {$col}=1; }
		if ($_->{not_null})      { $notnull_cols{$col}=1; }
		if ($_->{default} ne '') { $default{$col} = $_->{default}; }

		# indexカラム？（UNIQUEカラムはindexにする）
		if ($_->{index} || $_->{index_tdb} || $_->{unique}) {
			$index_cols{$col}=1;
		}
	}

	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) {
		if (!$ROBJ->mkdir($dir)) { $self->error("mkdir '$dir' error : $!"); }
	}
	if ($table =~ /^\d/) {
		$self->error("To be a 'a-z' or '_' at the first character of a table name : '%s'", $table);
		return 30;
	}
	my $index = $dir . $self->{index_file};
	if (-e $index) {
		$self->error("'%s' table already exists", $table);
		return 40;
	}

	$self->{"$table.tbl"}     = [];			# table array ref
	$self->{"$table.cols"}    = \%cols;		# 全カラム名
	$self->{"$table.idx"}     = \%index_cols;	# indexカラム
	$self->{"$table.int"}     = \%int_cols;		# 整数カラム
	$self->{"$table.float"}   = \%float_cols;	# 数値カラム
	$self->{"$table.flag"}    = \%flag_cols;	# フラグ
	$self->{"$table.str"}     = \%str_cols;		# 文字列
	$self->{"$table.unique"}  = \%unique_cols;	# UNIQUE
	$self->{"$table.notnull"} = \%notnull_cols;	# NOT NULL
	$self->{"$table.default"} = \%default;		# Default
	$self->{"$table.serial"}  = 0;

	# index の保存
	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

#-------------------------------------------------------------------------------
# ●テーブルの削除
#-------------------------------------------------------------------------------
# 成功時は 0 が返る
sub drop_table {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $dir = $self->{dir} . $table . '/';
	if (!-e $dir) { return 1; }	# Not found

	my $files = $ROBJ->search_files($dir);
	my $flag = 0;
	foreach(@$files) {
		if (! unlink("$dir$_")) { $flag += 2; }
	}
	if (!rmdir($dir)) { $flag+=10000; }

	# キャッシュクリア
	$self->clear_cache($table);

	return $flag;
}

#-------------------------------------------------------------------------------
# ●index の再構築
#-------------------------------------------------------------------------------
sub index_rebuild {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	my $dir = $self->{dir} . $table . '/';
	my $index_backup_file = $dir . $self->{index_backup_file};
	if (!-r $index_backup_file) { return 1; }

	# バックアップの読み込み
	my $index_file_orig = $self->{index_file};
	$self->{index_file} = $self->{index_backup_file};
	my $db = $self->load_index($table);
	$self->{index_file} = $index_file_orig;

	# ファイルリスト取得
	my $files = $ROBJ->search_files($dir);
	my $ext   = $self->{ext};
	my @files = grep(/^\d+$ext$/, @$files);
	my @db;
	my $serial = 0;
	foreach(@files) {
		my $h = $ROBJ->fread_hash($dir . $_);
		push(@db, $h);
		if ($serial < $h->{pkey}) { $serial = $h->{pkey}; } 
	}

	# キャッシュをクリアする
	$self->clear_cache($table);

	$self->{"$table.serial"} = $serial +1;
	$self->{"$table.tbl"}    = \@db;
	$IndexCache{$table}     = \@db;
	$self->save_index($table, 1);	# force
}

################################################################################
# ■オプショナル関数
################################################################################
#-------------------------------------------------------------------------------
# ●カラムの追加
#-------------------------------------------------------------------------------
sub add_column {
	my ($self, $table, $h) = @_;
	my $ROBJ = $self->{ROBJ};

	# テーブルindex のロード
	$table =~ s/\W//g;
	my $db = $self->load_index($table, 1);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 7;
	}

	my $col = $h->{name};
	$col =~ s/\W//g;
	if ($col eq '') { return 8; }

	# カラム名の確認
	my $cols = $self->{"$table.cols"};
	if ($cols->{$col}) {	# 同じ名前のカラムがある
		$self->edit_index_exit($table);
		$self->error("'%s' is already exists in relation '%s'", $col, $table);
		return 8;
	}
	# テーブル情報の書き換え
	if    ($h->{type} eq 'int')   { $self->{"$table.int"}  ->{$col}=1; }
	elsif ($h->{type} eq 'float') { $self->{"$table.float"}->{$col}=1; }
	elsif ($h->{type} eq 'flag')  { $self->{"$table.flag"} ->{$col}=1; }
	elsif ($h->{type} eq 'text')  { $self->{"$table.str"}  ->{$col}=1; }
	elsif ($h->{type} eq 'ltext') { $self->{"$table.str"}  ->{$col}=1; }
	else {
		$self->error('Column "%s" have invalid type "%s"', $col, $h->{type});
		return 10;
	}
	$self->{"$table.cols"}->{$col}=1;
	if ($h->{unique})  { $self->{"$table.unique"} ->{$col}=1; }	# UNIQUE
	if ($h->{notnull}) { $self->{"$table.notnull"}->{$col}=1; }	# NOT NULL
	if ($h->{index} || $h->{unique}) { $self->{"$table.idx"}->{$col}=1; }

	# index の保存
	$self->save_index($table);
	$self->save_backup_index($table);
	# キャッシュクリア
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# ●カラムの削除
#-------------------------------------------------------------------------------
sub drop_column {
	my ($self, $table, $column) = @_;
	my $ROBJ = $self->{ROBJ};
	$table  =~ s/\W//g;
	$column =~ s/\W//g;
	if ($table eq '' || $column eq '') { return 7; }

	# テーブルindex のロード
	$table =~ s/\W//g;
	my $db = $self->load_index($table, 1);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 8;
	}
	if (! $self->{"$table.cols"}->{$column}) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' column in relation '%s'", $column, $table);
		return 9;
	}
	# テーブル情報の書き換え
	delete $self->{"$table.cols"}->{$column};
	delete $self->{"$table.int"}->{$column};
	delete $self->{"$table.float"}->{$column};
	delete $self->{"$table.flag"}->{$column};
	delete $self->{"$table.str"}->{$column};
	delete $self->{"$table.unique"}->{$column};
	delete $self->{"$table.notnull"}->{$column};
	delete $self->{"$table.idx"}->{$column};

	# 削除カラムのデータ消去
	$self->load_allrow($table);
	my $all = $self->{"$table.tbl"};
	foreach(@$all) {
		if ($_->{$column} eq '') { next; }

		delete $_->{$column};
		$self->write_rowfile($table, $_);
	}

	# index の保存
	$self->save_index($table);
	$self->save_backup_index($table);
	# キャッシュクリア
	$self->clear_cache($table);

	return 0;
}

#-------------------------------------------------------------------------------
# ●インデックスの追加
#-------------------------------------------------------------------------------
sub add_index {
	my ($self, $table, $column) = @_;
	my $ROBJ = $self->{ROBJ};

	# テーブルindex のロード
	$table =~ s/\W//g;
	my $db = $self->load_index($table, 1);
	if (!defined $db) {
		$self->edit_index_exit($table);
		$self->error("Can't find '%s' table", $table);
		return 9;
	}

	# テーブル情報の書き換え
	my $cols = $self->{"$table.cols"};
	my $idx  = $self->{"$table.idx"};
	if (! grep { $_ eq $column } @$cols) {	# カラムが存在しない
		$self->edit_index_exit($table);
		$self->error("On '%s' table, not exists '%s' column", $table, $column);
		return 8;
	}
	if (! grep { $_ eq $column } @$idx) {	# index に追加
		push(@$idx, $column);
		my $dir     = $self->{dir} . $table . '/';
		my $ext = $self->{ext};
		$self->load_allrow($table);
	}
	# index の保存
	$self->save_index($table);
	$self->save_backup_index($table);

	return 0;
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●バックアップファイルの書き換え
#-------------------------------------------------------------------------------
sub save_backup_index {
	my $self  = shift;
	my $table = shift;
	# index の予備を保存
	my $index_file_orig = $self->{index_file};
	$self->{index_file} = $self->{index_backup_file};
	local ($self->{"$table.tbl"}) = [];
	$self->save_index($table, 1);
	$self->{index_file} = $index_file_orig;
	return 0;
}

################################################################################
# ●タイマーの仕込み
################################################################################
&embed_timer_wrapper(__PACKAGE__);

1;
