#------------------------------------------------------------------------------
# このスクリプトを実行することで自動的に最適化された Fcntl が生成されます。
# ローカルにFcntlを生成することで、CGI動作時の処理を少し高速されるかと思ったのですが、
# 誤差の範囲なので使わないほうがよいです。
#------------------------------------------------------------------------------
# ※mod_perl環境での使用はおすすめできません。
# ※外部から勝手に実行されることを防ぐため、実行属性はつけないでください。
#
use strict;
use Fcntl qw(:DEFAULT :flock);

our @vars = qw(
	O_RDONLY
	O_WRONLY
	O_RDWR
	O_CREAT
	O_EXCL
	O_CREAT
	O_TRUNC
	O_APPEND
	LOCK_SH
	LOCK_EX
	LOCK_UN
	LOCK_NB
	LOCK_MAND
	LOCK_UN
	LOCK_READ
	LOCK_WRITE
);

my $fh;
sysopen($fh, 'Fcntl.pm', O_CREAT | O_WRONLY | O_TRUNC);
print $fh <<HEADER;
# generate by $0
package Fcntl;
use strict;
use Satsuki::Exporter 'import';

HEADER
	print $fh 'our @EXPORT = qw(' . join(' ',@vars) .");\n\n";

{
	no strict 'refs';
	foreach(@vars) {
		print $fh "sub $_ { " . &{"Fcntl::$_"} . "; }\n";
	}
}
print $fh "\n1;\n";
close($fh);








