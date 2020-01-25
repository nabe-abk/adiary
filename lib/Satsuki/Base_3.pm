use strict;
#------------------------------------------------------------------------------
# Split from Base.pm for AutoLoader
#------------------------------------------------------------------------------
use Satsuki::Base ();
use Satsuki::Base_2 ();
package Satsuki::Base;
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
	my $self  = shift;
	$self->{HTTPD_state} = shift;
	my $path  = shift || '/';

	$self->{CGI_cache}= 1;
	$self->{HTTPD}    = 1;
	$self->{CGI_mode} = 'httpd';

	$self->{Initialized_path} = 1;
	$self->{Basepath}     = $path;
	$self->{Mod_rewrite}  = 1;

	$self->{myself}  = $path;
	$self->{myself2} = $path;

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
	return -r $file;
}

sub write_check {
	my ($self, $file) = @_;
	return -w $file;
}

sub lib_check {
	my ($self, $lib) = @_;
	my $pm = $lib;
	$pm =~ tr|::|/|;
	eval { require "$pm.pm"; };
	if ($@) { return 0; }
	my $ver;
	{
		no strict "refs";
		$ver = ${$lib . '::VERSION'};
	}
	return $ver ? $ver : '?.??';
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
