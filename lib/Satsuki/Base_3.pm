use strict;
#------------------------------------------------------------------------------
# Split from Base.pm for AutoLoader
#------------------------------------------------------------------------------
use Satsuki::Base ();
use Satsuki::Base_2 ();
package Satsuki::Base;
###############################################################################
# ■mod_perl用スタートアップ（new から呼ばれる）
###############################################################################
sub init_for_mod_perl {
	my $self = shift;
	my $ver  = $ENV{MOD_PERL_API_VERSION};
	$self->{CGI_cache} = 1;
	$self->{Mod_perl}  = $ver || 1;
	$self->{CGI_mode}  = "mod_perl$ver";

	# 擬似的なカレントディレクトリを抽出（設定）
	# ・mod_perl2 + thread 環境では、カレントディレクトリが変更できないため必須
	# ・ファイルキャッシュを絶対パスで管理するため、mod_perl環境では必須
	$self->{WD} = substr($0, 0, rindex($0, '/')+1); # カレントdir
}

###############################################################################
# ■SpeedyCGI用のスタートアップ
###############################################################################
sub init_for_speedycgi {
	my $self = shift;
	$self->{CGI_cache} = 1;
	$self->{SpeedyCGI} = 1;
	$self->{CGI_mode}  = 'SpeedyCGI';
}

###############################################################################
# ■FastCGI用のスタートアップ
###############################################################################
sub init_for_fastcgi {
	my ($self, $req, $sock) = @_;
	if (!$req->IsFastCGI()) { return ; }	# フラグ確認

	$self->{CGI_cache}= 1;
	$self->{FastCGI}  = 1;
	$self->{CGI_mode} = 'FastCGI';
}

###############################################################################
# ■httpd用のスタートアップ
###############################################################################
sub init_for_httpd {
	my $self = shift;
	my $path = shift || '/';

	$self->{CGI_cache}= 1;
	$self->{HTTPD}    = 1;
	$self->{CGI_mode} = 'httpd';

	$self->{Initialized_path} = 1;
	$self->{Basepath}     = $path;
	$self->{Mod_rewrite}  = 1;
	$self->{Request_base} = $path;

	$self->{Myself}  = $path;
	$self->{Myself2} = $path;

	my $port = int($ENV{SERVER_PORT});
	my $protocol = ($port == 443) ? 'https://' : 'http://';
	$self->{Server_url} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
}

###############################################################################
# ■システムチェック用ルーチン
###############################################################################
sub get_system_info {
	my ($self) = @_;
	my %h;
	my $v = $];
	$v =~ s/(\d+)\.(\d\d\d)(\d\d\d)/$1.'.'. ($2+0).'.'.($3+0)/e;
	$h{perl_version} = $v;
	$h{perl_cmd}     = $^X;
	return \%h;
}

sub read_check {
	my ($self, $file) = @_;
	return (-r $self->get_filepath($file));
}

sub write_check {
	my ($self, $file) = @_;
	return (-w $self->get_filepath($file));
}

sub lib_check {
	my ($self, $lib) = @_;
	$lib =~ s|::|/|g;
	eval { require "$lib.pm"; };
	return !$@ ? 1 : 0;
}


###############################################################################
# ■データダンプ
###############################################################################
sub dump_all {
	my $self = shift;
	my $data = shift;
	my $tab  = shift || '  ';
	my $br   = shift || "\n";
	my $sp   = shift || '';
	my $ret = '';
	if (ref($data) eq 'HASH') {
		foreach(sort(keys(%$data))) {
			my $k = $_;
			my $v = $data->{$_};
			if (ref($v) eq 'ARRAY') {
				$ret .= "$sp$k=[$br";
				$ret .= $self->dump_all($v, $tab, $br, "$tab$sp");
				$ret .= "$sp]$br";
				next;
			}
			if (ref($v) eq 'HASH') {
				$ret .= "$sp$k={$br";
				$ret .= $self->dump_all($v, $tab, $br, "$tab$sp");
				$ret .= "$sp}$br";
				next;
			}
			$ret .= "$sp$k=$v$br";
		}
	} else {
		foreach(@$data) {
			if (ref($_) eq 'ARRAY') {
				$ret .= "$sp\[$br";
				$ret .= $self->dump_all($_, $tab, $br, "$tab$sp");
				$ret .= "$sp]$br";
				next;
			}
			if (ref($_) eq 'HASH') {
				$ret .= "$sp\{$br";
				$ret .= $self->dump_all($_, $tab, $br, "$tab$sp");
				$ret .= "$sp}$br";
				next;
			}
			$ret .= "$sp$_$br";
		}
	}
	return $ret;
}

1;
