use strict;
#-------------------------------------------------------------------------------
# 更新されたライブラリの自動リロード
#						(C)2013-2020 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::AutoReload;
our $VERSION = '1.12';
#-------------------------------------------------------------------------------
my $Satsuki_pkg = 'Satsuki';
my $CheckTime;
my %Libs;
my @Packages;
#-------------------------------------------------------------------------------
my $MyPkg = __PACKAGE__ . '.pm';
$MyPkg =~ s|::|/|g;
################################################################################
# ●ライブラリの情報保存
################################################################################
sub save_lib {
	if ($ENV{SatsukiReloadStop}) { return; }
	while (my ($pkg, $file) = each(%INC)) {
		if (exists $Libs{$file}) { next; }
		if (index($pkg, $Satsuki_pkg) != 0) {
			$Libs{$file} = 0;
			next;
		}
		$Libs{$file} = (stat($file)) [9];
		push(@Packages, $pkg);
	}
}

################################################################################
# ●更新されたモジュールをアンロードする
################################################################################
sub check_lib {
	my $tm = time();
	if ($CheckTime == $tm) { return ; }
	$CheckTime = $tm;

	my $flag = shift || $Satsuki::Base::RELOAD;
	if (!$flag) {
		if ($ENV{SatsukiReloadStop}) { return; }
		while(my ($file,$tm) = each(%Libs)) {
			if (!$tm || $tm == (stat($file))[9]) { next; }
			$flag=1;
			last;
		}
		if (!$flag) { return 0; }
	}

	# 更新されたものがあれば、ロード済パッケージをすべてアンロード
	foreach(@Packages) {
		if ($_ eq $MyPkg)       { next; }
		delete $INC{$_};
		if ($_ =~ /_\d+\.pm$/i) { next; }	# _2.pm _3.pm 等は無視
		# 名前空間からすべて除去
		&unload($_);
	}
	undef %Libs;
	undef @Packages;

	# 自分自身をリロード（unloadは危険なのでしない）
	delete $INC{$MyPkg};
	require $MyPkg;

	return 1;
}

#-------------------------------------------------------------------------------
# ●指定されたパッケージをアンロードする
#-------------------------------------------------------------------------------
sub unload {
	no strict 'refs';

	my $pkg = shift;
	$pkg =~ s/\.pm$//;
	$pkg =~ s[/][::]g;
	my $names = \%{ $pkg . '::' };
	# パッケージの名前空間からすべて除去
	foreach(keys(%$names)) {
		substr($_,-2) eq '::' && next;
		if (ref($names->{$_})) {
			delete $names->{$_};
		} else {
			undef  $names->{$_};	# スカラ変数用（参照エラー防止）
		}
	}
}

1;
