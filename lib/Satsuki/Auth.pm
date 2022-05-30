use strict;
#-------------------------------------------------------------------------------
package Satsuki::Auth;
use Satsuki::AutoLoader;
our $VERSION = '2.41';
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $class = shift;
	my $self  = bless({ROBJ => shift}, $class);

	my $db = shift;
	$self->{DB} = $db;	# DBモジュール
	
	# ディフォルト値
	$self->{table} = "_user";
	$self->{extcol} = [];
	$self->{uid_max_length}  = 16;
	$self->{uid_lower_rule}  = 1;
	$self->{uid_underscore}  = 1;
	$self->{name_max_length} = 30;
	$self->{name_notag}      = 1;

	$self->{disallow_num_pass}=1;
	$self->{pass_min} = 4;
	$self->{expires}  = 180*86400;	# 180days

	$self->{sessions}    = 1;
	$self->{all_logout}  = 0;
	$self->{start_up}    = 0;
	$self->{exists_admin}= -1;	# 初期値は-1

	$self->{fail_count}  = 15;
	$self->{fail_minute} = 10;
	
	$self->{logtext_max} = 128;	# ログ１要素あたりの最大文字数
	return $self;
}

1;
