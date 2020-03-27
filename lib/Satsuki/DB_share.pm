use strict;
#-------------------------------------------------------------------------------
# データベースモジュール、共通ルーチン
#							(C)2020 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::DB_share;
our $VERSION = '1.10';

# use Satsuki::Exporter 'import';
use Exporter 'import';
our @EXPORT = qw(select_match_pkey1 select_match_limit1	select_match
		set_debug set_noerror debug warning error
		embed_timer_wrapper);

###############################################################################
# ■selectの拡張
###############################################################################
#------------------------------------------------------------------------------
# ●データの取得
#------------------------------------------------------------------------------
sub select_match_pkey1 {
	my $h = &select_match(@_, '*limit', 1, '*cols', 'pkey')->[0];
	return $h && $h->{pkey};
}
sub select_match_limit1 {
	return &select_match(@_, '*limit', 1)->[0];
}
sub select_match {
	my $self  = shift;
	my $table = shift;
	my %h;
	while(@_) {
		my $col = shift;
		my $val = shift;
		if ($col eq '*limit') { $h{limit}=$val; next; }
		if ($col eq '*cols' ) { $h{cols} =$val; next; }
		if ($col eq '*sort' ) { $h{sort} =$val; next; }
		if ($col eq '*NoError') { $h{NoError}=$val; next; }
		if (ord($col) == 0x2d) {	# == '-'
			$h{not_match}->{substr($col,1)}=$val;
			next;
		}
		# default
		$h{match}->{$col}=$val;
	}
	return $self->select($table, \%h);
}

###############################################################################
# ■エラー処理
###############################################################################
#------------------------------------------------------------------------------
# ●デバッグ処理
#------------------------------------------------------------------------------
sub set_debug {
	my ($self, $flag) = @_;
	my $r = $self->{DEBUG};
	$self->{DEBUG} = $flag || 1;
	return $r;
}
sub set_noerror {
	my ($self, $flag) = @_;
	my $r = $self->{NoError};
	$self->{NoError} = $flag;
	return $r;
}
sub debug {
	my ($self, $sql) = @_;
	if (!$self->{DEBUG}) { return; }
	$self->{ROBJ}->debug('['.$self->{_RDBMS}.'] '.$sql, 1);	# debug-safe
}
sub warning {
	my $self = shift;
	my $err  = shift;
	$self->{ROBJ}->warning('['.$self->{_RDBMS}.':WARNING] '.$err, @_);
}
sub error {
	my $self = shift;
	if ($self->can('error_hook')) {
		$self->error_hook(@_);
	}
	my $err = shift;
	if (!defined $err) { return; }
	if ($self->{NoError}) { 
		return $self->warning($err, @_);
	}
	$self->{ROBJ}->error('['.$self->{_RDBMS}.'] '.$err, @_);
}

###############################################################################
# ■時間計測ラッパー
###############################################################################
my @timer_functions = qw(new find_table select generate_pkey
 insert update_match delete_match select_by_group
 begin rollback commit create_table drop_table
 add_column drop_column add_index
);
#------------------------------------------------------------------------------
# ●ラッパーを仕込むルーチン
#------------------------------------------------------------------------------
sub embed_timer_wrapper {	# 処理時間計測の細工
	no strict 'refs';
	if (!defined $Satsuki::Timer::VERSION
	 && !defined $Satsuki::AutoReload::VERSION) { return; }

	my $pkg = shift;
	my $pkgcc = $pkg . '::';
	# "$pkg::"と書くと、それ自体がクラス参照になり動作しない
	foreach(@timer_functions) {
		my $org_func = $_;
		my $wrap_func = "_wrap_$_";
		if (!*{"$pkgcc$_"}{CODE} || *{"$pkgcc$wrap_func"}{CODE}) { next; }
		# ラッパーを仕込む
		*{"$pkgcc$wrap_func"} = *{"$pkgcc$_"}{CODE};
		*{"$pkgcc$_"} = sub {
			my $self = shift;
			my $timer = $self->{ROBJ}->{Timer};
			# 同じパッケージから呼び出されたときは、単に呼び出すのみ
			if ((caller)[0] eq $pkg || !$timer) {
				return $self->$wrap_func(@_);
			}
			my $t0 = $self->{timer_debug} && $timer->check('db');
			$timer->start('db');
			my @r; wantarray ? (@r=$self->$wrap_func(@_)) : ($r[0]=$self->$wrap_func(@_));
			my $t1 = $timer->stop('db');
			if ($self->{timer_debug}) {
				my @c = caller(0);
				my $x = int(($t1-$t0)*10000+0.5)/10;
				$self->{ROBJ}->debug("[DB] $org_func $_[0] : $x ms from $c[1] at $c[2]");	# debug-safe
			}
			return wantarray ? @r : $r[0];
		};
	}
}


1;
