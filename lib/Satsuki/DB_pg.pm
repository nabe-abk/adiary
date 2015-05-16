use strict;
#-------------------------------------------------------------------------------
# データベースプラグイン for PostgreSQL
#					(C)2006-03 nabe / ABK project
#-------------------------------------------------------------------------------
package Satsuki::DB_pg;
use Satsuki::AutoLoader;
use Satsuki::DB_share;
use DBI ();
our $VERSION = '1.00';
#-------------------------------------------------------------------------------
# データベースの接続属性 (DBI)
my $DB_attr = {AutoCommit => 1, RaiseError => 0, PrintError => 0};
#-------------------------------------------------------------------------------
# コネクションプール
my %Connection_pool;
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my $class = shift;
	my ($ROBJ, $database, $username, $password, $self) = @_;
	$self ||= {};
	bless($self, $class);
	$self->{ROBJ} = $ROBJ;	# root object save

	# 初期設定
	$self->{_RDBMS} = 'PostgreSQL';
	$self->{db_id}  = "pg.$database.";
	$self->{exist_tables_cache} = {};

	# コネクション pool 処理
	my $dbh;
	my $connect_id = $self->{connect_id} = "$database\e$username\e".$ROBJ->crypt_by_string($password);
	if ($self->{Pool}) {
		if (exists $Connection_pool{$connect_id}) {	# プールが存在したら
			$dbh = $Connection_pool{$connect_id};	# 取り出す
			if (! $dbh->ping) {
				$dbh = undef;
				delete $Connection_pool{$connect_id};
			}
			$dbh && $self->debug("pop from connection pool"); # debug-safe
			if (! $dbh->{AutoCommit}) { $dbh->rollback(); }
		}
	}
	# 接続
	if (! $dbh) {
		$dbh = DBI->connect("DBI:Pg:$database", $username, $password, $DB_attr);
		if (!$dbh) { $self->error('Connection faild'); return ; }
	}
	# プールする
	if ($self->{Pool}) {
		$Connection_pool{$connect_id} = $dbh;
	}
	# 初期設定
	$dbh->{pg_expand_array}=0;

	# 値保存
	$self->{dbh} = $dbh;
	return $self;
}
#------------------------------------------------------------------------------
# ●デストラクタ代わり
#------------------------------------------------------------------------------
sub Finish {
	my $self = shift;
	if ($self->{begin}) { $self->rollback(); }
	if (! $self->{Pool}) { $self->{dbh}->disconnect(); }
}

###############################################################################
# ■テーブルの操作
###############################################################################
#------------------------------------------------------------------------------
# ●テーブルの存在確認
#------------------------------------------------------------------------------
sub find_table {
	my ($self, $table) = @_;
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	# キャッシュの確認
	my $cache    = $self->{exist_tables_cache};
	my $cache_id = $self->{db_id} . $table;
	if ($cache->{$cache_id}) { return $cache->{$cache_id}; }

	# テーブルからの情報取得
	my $dbh = $self->{dbh};
	my $sql = "SELECT tablename FROM pg_tables WHERE tablename=? LIMIT 1";
	my $sth = $dbh->prepare($sql);
	$self->debug($sql);	# debug-safe
	$sth && $sth->execute($table);

	if (!$sth || !$sth->rows || $dbh->err) { return 0; }	# error
	return ($cache->{$cache_id} = 1);	# found
}

###############################################################################
# ■データの検索
###############################################################################
sub select {
	my ($self, $table, $h) = @_;
	my $dbh  = $self->{dbh};
	my $ROBJ = $self->{ROBJ};
	$table =~ s/\W//g;

	#---------------------------------------------
	# マッチング条件の処理
	#---------------------------------------------
	my ($where, $ary) = $self->generate_select_where($h);

	#---------------------------------------------
	# 該当件数を記録
	#---------------------------------------------
	my $hits;
	if ($h->{require_hits}) {
		my $sql = "SELECT count(*) FROM $table$where";
		my $sth = $dbh->prepare($sql);
		$self->debug($sql);	# debug-safe
		$sth && $sth->execute(@$ary);
		if (!$sth || $dbh->err) {
			$self->error($sql);
			$self->error($dbh->errstr);
			return [];
		}
		$hits = $sth->fetchrow_array;
		$sth->finish();
	}

	#---------------------------------------------
	# SQLを構成
	#---------------------------------------------
	# 取得するカラム
	my $cols = "*";
	my $select_cols = (!exists$h->{cols} || ref($h->{cols})) ? $h->{cols} : [ $h->{cols} ];
	if (ref($select_cols)) {
		foreach(@$select_cols) { $_ =~ s/\W//g; }
		$cols = join(',', @$select_cols);
	}
	# SQL
	my $sql = "SELECT $cols FROM $table$where";

	#---------------------------------------------
	# ソート処理
	#---------------------------------------------
	$sql .= $self->generate_order_by($h);

	#---------------------------------------------
	# limit and offset
	#---------------------------------------------
	my $offset = int($h->{offset});
	my $limit;
	if ($h->{limit} ne '') { $limit = int($h->{limit}); }
	if ($offset > 0)  { $sql .= ' OFFSET ' . $offset; }
	if ($limit ne '') { $sql .= ' LIMIT '  . $limit;  }

	#---------------------------------------------
	# Do SQL
	#---------------------------------------------
	my $sth = $dbh->prepare($sql);
	$self->debug($sql);	# debug-safe
	$sth && $sth->execute(@$ary);
	if (!$sth || $dbh->err) {
		$self->error($sql);
		$self->error($dbh->errstr);
		return [];
	}

	my $r = $sth->fetchall_arrayref({});
	return wantarray ? ($r,$hits) : $r;
}


###############################################################################
# ■サブルーチン
###############################################################################
#------------------------------------------------------------------------------
# ●whereの生成
#------------------------------------------------------------------------------
sub generate_select_where {
	my ($self, $h) = @_;

	my $where;
	my @ary;
	while(my ($k,$v) = each(%{ $h->{match} })) {
		$k =~ s/\W//g;
		if ($v eq '') {
			$where .= " AND $k IS NULL";
			next;
		}
		if (ref($v) ne 'ARRAY') {
			$where .= " AND $k=?";
			push(@ary, $v);
			next;
		}
		# 値が配列のとき
		my $w = '?,' x ($#$v+1);
		chop($w);
		if ($w eq '') { 
			$where .= " AND false";
			next;
		}
		$where .= " AND $k in ($w)";
		push(@ary, @$v);
	}
	while(my ($k,$v) = each(%{ $h->{not_match} })) {
		$k =~ s/\W//g;
		if ($v eq '') {
			$where .= " AND $k IS NOT NULL";
			next;
		}
		if (ref($v) ne 'ARRAY') {
			$where .= " AND $k!=?";
			push(@ary, $v);
			next;
		}
		# 値が配列のとき
		my $w = '?,' x ($#$v+1);
		chop($w);
		if ($w eq '') { next; }
		$where .= " AND $k not in ($w)";
		push(@ary, @$v);
	}
	while(my ($k,$v) = each(%{ $h->{min} })) {
		$k =~ s/\W//g;
		$where .= " AND $k>=?";
		push(@ary, $v);
	}
	while(my ($k,$v) = each(%{ $h->{max} })) {
		$k =~ s/\W//g;
		$where .= " AND $k<=?";
		push(@ary, $v);
	}
	while(my ($k,$v) = each(%{ $h->{gt} })) {
		$k =~ s/\W//g;
		$where .= " AND $k>?";
		push(@ary, $v);
	}
	while(my ($k,$v) = each(%{ $h->{lt} })) {
		$k =~ s/\W//g;
		$where .= " AND $k<?";
		push(@ary, $v);
	}
	while(my ($k,$v) = each(%{ $h->{flag} })) {
		$k =~ s/\W//g;
		if ($v) { $where .= " AND $k"; next; }
		$where .= " AND NOT $k";
	}
	foreach(@{ $h->{is_null} }) {
		$_ =~ s/\W//g;
		$where .= " AND $_ IS NULL";
	}
	foreach(@{ $h->{not_null} }) {
		$_ =~ s/\W//g;
		$where .= " AND $_ IS NOT NULL";
	}
	if ($h->{search_cols}) {
		my $words = $h->{search_words};
		my $ilike = ($self->{alt_ilike} ? $self->{alt_ilike} : 'ILIKE');
		foreach my $word (@$words) {
			my $w = $word;
			if (! $self->{alt_ilike}) {
				$w =~ s/([\\%_])/\\$1/g;
				$w = "%$w%";
			}
			my @x;
			foreach (@{ $h->{search_cols} }) {
				push(@x, "$_ $ilike ?");
				push(@ary, $w);
			}
			$where .= " AND (" . join(' OR ', @x) . ")";
		}
	}
	if ($h->{RDB_where} ne '') { # RDBMS専用、where直指定
		my $add = $h->{RDB_where};
		$add =~ s/[\\;\x80-\xff]//g;
		my $c = ($add =~ tr/'/'/);	# 'の数を数える
		if ($c & 1)	{		# 奇数ならすべて除去
			$add =~ s/'//g;
		}
		$where .= ' AND '.$add;
	}

	if ($where) { $where = ' WHERE' . substr($where, 4); }

	return ($where, \@ary);
}

#------------------------------------------------------------------------------
# ●ORDER BYの生成
#------------------------------------------------------------------------------
sub generate_order_by {
	my ($self, $h) = @_;
	my $sort = ref($h->{sort}    ) ? $h->{sort}     : [ $h->{sort}     ];
	my $rev  = ref($h->{sort_rev}) ? $h->{sort_rev} : [ $h->{sort_rev} ];
	my $sql='';
	foreach(0..$#$sort) {
		my $col = $sort->[$_];
		$col =~ s/\W//g;
		if ($col eq '') { next; }
		$sql .= $col . ($rev->[$_]?' DESC':'') . ',';
	}
	chop($sql);
	if ($sql) {
		$sql = ' ORDER BY ' . $sql;
	}
	return $sql
}

#------------------------------------------------------------------------------
# ●エラーフック
#------------------------------------------------------------------------------
# $self->error in DB_share.pm から呼ばれる
sub error_hook {
	my $self = shift;
	if ($self->{begin}) {
		$self->{begin}=-1;	# error
	}
}

###############################################################################
# ●タイマーの仕込み
###############################################################################
&embed_timer_wrapper(__PACKAGE__);

1;
