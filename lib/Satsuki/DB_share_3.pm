use strict;
#------------------------------------------------------------------------------
# データベースモジュール、共通ルーチン
#					(C)2005-2009 nabe / ABK project
#------------------------------------------------------------------------------
package Satsuki::DB_share_3;
our $VERSION = '1.00';
our @ISA    = qw(Exporter);
our @EXPORT = qw(&get_options &create_table_wrapper);
###############################################################################
# ■オプショナル関数情報
###############################################################################
my @optional_methods = qw(add_column drop_column add_index load_dbh);

sub get_options {
	my $self=shift;
	my %h;
	foreach(@optional_methods) {
		if ($self->can($_)) { $h{$_}=1; }
	}
	return \%h;
}

###############################################################################
# ■拡張
###############################################################################
#------------------------------------------------------------------------------
# ●create tableのラッパー
#------------------------------------------------------------------------------
sub create_table_wrapper {
	my $self = shift;
	my ($table, $ci, $ext) = @_;
	my %cols;
	foreach(@{$ci->{flag}})    { $cols{$_} = {name => $_, type => 'flag'}; }	# 整数カラム
	foreach(@{$ci->{text}})    { $cols{$_} = {name => $_, type => 'text'}; }	# テキスト
	foreach(@{$ci->{ltext}})   { $cols{$_} = {name => $_, type => 'ltext'};}	# 大きいテキスト
	foreach(@{$ci->{int}})     { $cols{$_} = {name => $_, type => 'int'};  }	# 整数カラム
	foreach(@{$ci->{float}})   { $cols{$_} = {name => $_, type => 'float'};}	# 少数カラム
	foreach(@{$ci->{idx}})     { $cols{$_}->{index}    = 1; }			# indexカラム
	foreach(@{$ci->{idx_tdb}}) { $cols{$_}->{index_tdb}= 1; }			# index_tdbカラム
	foreach(@{$ci->{unique}})  { $cols{$_}->{unique}   = 1; }			# uniqueカラム
	foreach(@{$ci->{notnull}}) { $cols{$_}->{not_null} = 1; }			# NOT NULLeカラム
	while(my ($k, $v) = each(%{ $ci->{ref} })) {			# 外部キー
		$cols{$k}->{ref_pkey} = $v;
	}
	my @cols;
	while(my ($k,$v) = each(%cols)) { push(@cols, $v); }
	foreach (@{$ext || []}) {	# 追加カラム
		push(@cols, $_);
	}

	return $self->create_table("$table", \@cols);	# テーブルの作成
}

1;
