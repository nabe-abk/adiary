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
	my $self = shift;
	$self->{FCGI_request} = shift;

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
	$self->{mod_rewrite}  = 1;

	$self->{myself}  = $path;
	$self->{myself2} = $path;

	my $port = int($ENV{SERVER_PORT});
	my $protocol = ($port == 443) ? 'https://' : 'http://';
	$self->{ServerURL} = $protocol . $ENV{SERVER_NAME} . (($port != 80 && $port != 443) ? ":$port" : '');
}

###############################################################################
# ■fork処理
###############################################################################
sub fork {
	my $self = shift;
	my $fcgi = $self->{FCGI_request};
	$fcgi && $fcgi->Detach();

	my $fork = fork();
	if ($fork) {
		# parent
		$fcgi && $fcgi->Attach();
		return $fork;
	}
	if (defined $fork) {
		# child
		close(STDIN);
		close(STDOUT);
		## close(STDERR);	# Error on FastCGI

		$self->{Shutdown} = 1;
	}
	return $fork;
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

sub check_lib {
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

sub check_cmd {
	my $self = shift;
	my $cmd  = shift;
	foreach(split(/:/, $ENV{PATH})) {
		if (-x "$_/$cmd") { return 1; }
	}
	return 0;
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
