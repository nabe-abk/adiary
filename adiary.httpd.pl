#!/usr/bin/perl
use 5.14.0;
use strict;
our $VERSION  = '1.24';
our $SPEC_VER = '1.12';	# specification version for compatibility
################################################################################
# Satsuki system - HTTP Server
#					Copyright (C)2019-2026 nabe@abk
################################################################################
# Last Update : 2026/02/20
#
BEGIN {
	my $path = $0;
	$path =~ s|/[^/]*||;
	if ($path) { chdir($path); }
	unshift(@INC, './lib');
}
use Socket;
use Fcntl;
use threads;		# for ithreads
use POSIX;		# for waitpid(<pid>, WNOHANG);
use Cwd;		# for $ENV{DOCUMENT_ROOT}
use Time::HiRes;	# for ualarm() and generate random string
#-------------------------------------------------------------------------------
# Crypt patch for Windows
#-------------------------------------------------------------------------------
if (crypt('','$1$') eq '' || crypt('','$5$') eq '' || crypt('','$6$') eq ''){
	eval {
		require Crypt::glibc;
		*CORE::GLOBAL::crypt = *Crypt::glibc::crypt;
	};
};
#-------------------------------------------------------------------------------
# pre load modules
#-------------------------------------------------------------------------------
eval { require Image::Magick; };
eval { require Net::SSLeay;   };
################################################################################
# setting
################################################################################
my $IsWindows    = ($^O eq 'MSWin32');
my $SILENT_CGI   = 0;
my $SILENT_FILE  = 0;
my $SILENT_OTHER = 0;
my $OPEN_BROWSER = $IsWindows;
my $GENERATE_CONF= 1;

my $UNIX_SOCK;
my $PATH      = '/';
my $PORT      = $IsWindows ? 80 : 8888;
my $ITHREADS  = $IsWindows;
my $TIMEOUT   =  5;
my $TIMEOUT_BIN;
my $DEAMONS   = 10;
my $KEEPALIVE = 1;
my $BUFSIZE_u = '1M';	# 1MB
my $BUFSIZE;		# byte / set from $BUFSIZE_u
my $MIME_FILE = '/etc/mime.types';
my $INDEX     = 'index.html';
my $PID;
my $R_BITS;	# select socket bits

my $MAX_CGI_REQUESTS = 10000;

my $SYS_CODE = 'UTF-8';
my $FS_CODE;
my $PATH0;	# Remove last '/' from PATH
my $PATH0_len;	# $PATH0's length
#-------------------------------------------------------------------------------
if ($IsWindows) {
	require Encode::Locale;
	import  Encode::Locale;
	$FS_CODE = $Encode::Locale::ENCODING_LOCALE;
}

#-------------------------------------------------------------------------------
# Web Server data
#-------------------------------------------------------------------------------
my %DENY_DIRS;
my %MIME_TYPE = ( 
	html => 'text/html',
	htm  => 'text/html',
	text => 'text/plain',
	txt  => 'text/plain',
	md   => 'text/markdown',
	css  => 'text/css',
	js   => 'application/javascript',
	json => 'application/json',
	xml  => 'application/xml',
	gif  => 'image/gif',
	png  => 'image/png',
	jpg  => 'image/jpeg',
	jpeg => 'image/jpeg',
	webp => 'image/webp',
	m4a  => 'audio/mp4',
	mp4  => 'video/mp4',
	webm => 'video/webm',
	ico  => 'image/vnd.microsoft.icon'
);

#-------------------------------------------------------------------------------
# for RFC date
#-------------------------------------------------------------------------------
my %JanFeb2Mon = (
	Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov =>10, Dec =>11
);
#-------------------------------------------------------------------------------
# analyze @ARGV
#-------------------------------------------------------------------------------
my %SIZE_UNIT = ('K' => 1024, 'M' => 1024*1024, 'G' => 1024*1024*1024);
{
	my @ary = @ARGV;
	my $path_arg;
	my $help;
	while(@ary) {
		my $key = shift(@ary);
		if (substr($key, 0, 1) ne '-') {
			if ($path_arg) { $help=1; last; }
			$PATH = $key;
			$path_arg = 1;
			next;
		}
		$key = substr($key, 1);
		while($key ne '') {
			my $k = substr($key,0,1);
			my $k2= substr($key,0,2);
			my $kx= substr($key,1);
			my $ky= substr($key,2);

			if ($k eq 'h') { $key=$kx; $help=1; next; }
			if ($k eq '?') { $key=$kx; $help=1; next; }
			if ($k eq 'n') { $key=$kx; $OPEN_BROWSER=0; next; }
			if ($k eq 'i') { $key=$kx; $ITHREADS=1; next; }
			if ($k eq 'f') { $key=$kx; $ITHREADS=0; next; }

			# keep-alive
			if ($k2 eq 'k0') { $key=$ky; $KEEPALIVE=0; next; }
			if ($k2 eq 'k1') { $key=$ky; $KEEPALIVE=1; next; }

			# SatsukiTimer
			if ($k2 eq 't0') { $key=$ky; $ENV{SatsukiTimer}=0; next; }
			if ($k2 eq 't1') { $key=$ky; $ENV{SatsukiTimer}=1; next; }

			# silent
			if ($k2 eq 'sc') { $key=$ky; $SILENT_CGI  = $SILENT_OTHER = 1; next; }
			if ($k2 eq 'sf') { $key=$ky; $SILENT_FILE = $SILENT_OTHER = 1; next; }
			if ($k  eq 's')  { $key=$kx; $SILENT_CGI  = $SILENT_FILE = $SILENT_OTHER = 1; next; }

			# system code
			if ($k2 eq 'cs') { $key=$ky; $SYS_CODE = shift(@ary); next; }

			#---------------------------------------------
			# option with argument
			#---------------------------------------------
			my $val;
			if ($key =~ /^(?:[ptdmecbu])(.*)/) {
				$key = '';
				$val = $1 ne '' ? $1 : shift(@ary);
				if ($val eq '') {
					print STDERR "needs argument: -$k option\n";	# debug-safe
					exit(-1);
				}
			}
			# string argument
			if ($k eq 'e') { $MIME_FILE = $val; next; }
			if ($k eq 'c') { $FS_CODE   = $val; next; }
			if ($k eq 'u') { $UNIX_SOCK = $val; next; }

			#---------------------------------------------
			# size argument
			#---------------------------------------------
			if ($k eq 'b' && $val !~ /^(\d+)(?:([GMK])B?)?$/) {
				print STDERR "Invalid argument: -$k option >>$val\n";	# debug-safe
				exit(-1);
			}
			my $unit = $1 . ($2 ne '' ? $2 : 'K');
			if ($k eq 'b') { $BUFSIZE_u = $unit; next; }

			#---------------------------------------------
			# float argument
			#---------------------------------------------
			if ($k eq 't' && $val !~ /^\d+(?:\.\d+)?$/) {
				print STDERR "Invalid argument: -$k option >>$val\n";	# debug-safe
				exit(-1);
			}
			if ($k eq 't') { $TIMEOUT = $val+0; next; }

			#---------------------------------------------
			# integer argument
			#---------------------------------------------
			if ($k =~ /^[pdm]$/ && $val !~ /^\d+$/) {
				print STDERR "Invalid argument: -$k option >>$val\n";	# debug-safe
				exit(-1);
			}
			if ($k eq 'p') { $PORT    = $val; next; }
			if ($k eq 'd') { $DEAMONS = $val; next; }
			if ($k eq 'm') { $MAX_CGI_REQUESTS = $val; next; }

			#---------------------------------------------
			# Unknown
			#---------------------------------------------
			print STDERR "Unknown option : -$k\n";	# debug-safe
			exit(-1);
		}
	}
	if ($TIMEOUT < 0.001)	{ $TIMEOUT=0.001; }
	if ($DEAMONS < 1) 	{ $DEAMONS=1;     }
	if ($MAX_CGI_REQUESTS == 0)		{ $MAX_CGI_REQUESTS=10000000; }
	if ($MAX_CGI_REQUESTS > 10000000)	{ $MAX_CGI_REQUESTS=10000000; }
	if ($MAX_CGI_REQUESTS <      100)	{ $MAX_CGI_REQUESTS=100; }

	if ($BUFSIZE_u =~ /^(.*)(\w)$/) { $BUFSIZE = $1*$SIZE_UNIT{$2}; }
	if ($BUFSIZE < 65536) { $BUFSIZE_u='64K'; $BUFSIZE = 65536; }

	if ($help) {
		my $n = $IsWindows ? "  -n\t\tdo not open web browser\n" : '';
		print <<HELP;
Satsuki HTTP Server - Version $VERSION

Usage: $0 [options] [path]
Available options are:
  path		working web path (default:/)
  -p port	bind port (default:8888, windows:80)
  -t timeout	connection timeout second (default:3, min:0.001)
  -d daemons	start daemons (default:10, min:1)
  -m max_req	maximum cgi requests per daemon (default:10000, min:100)
  -e mime_file	load mime types file name (default: /etc/mime.types)
  -c  fs_code	set file system's character code (default is auto)
  -cs sys_code	set cgi  system's character code (default: UTF-8)
  -b bufsize	buffer size [KB] (default:1024 = 1M, min:64)
  -u filename	UNIX domain socket mode
  -f		use fork()
  -i		use threads (ithreads)
  -k1		connection keep-alive enable (default)
  -k0		connection keep-alive disable
  -t0		set ENV SatsukiTimer=0
  -t1		set ENV SatsukiTimer=1
  -s		silent mode
  -sc		silent mode for cgi  access
  -sf		silent mode for file access
$n  -?|-h		view this help
HELP
		exit(0);
	}
}
################################################################################
# start up
################################################################################
print "Satsuki HTTP Server - Version $VERSION\n";
if ($0 =~ /\.exe$/i) {
	my $pl = $0;
	$pl =~ s/\.exe/.httpd.pl/;
	if (sysopen(my $fh, $pl, O_RDONLY)) {
		my $pl_ver=0;
		while(<$fh>) {
			if ($_ !~ /\$SPEC_VER\s*=\s*[\"\']?(\d+\.\d+)/) { next; }
			$pl_ver = $1;
			last;
		}
		close($fh);
		if ($SPEC_VER ne $pl_ver) {
			print STDERR "*** adiary.httpd.pl's specification version $pl_ver mismatch!!\n";	# debug-safe
			print STDERR "*** Please update '$0'\n";						# debug-safe
			print STDERR "\n<<push any key for exit>>";						# debug-safe
			my $key = <STDIN>;
			exit(-1);
		}
	}
}

#-------------------------------------------------------------------------------
# safety (Do not run on CGI/HTTP SERVER)
#-------------------------------------------------------------------------------
$ENV{SERVER_PROTOCOL} && die "Do not run on CGI/HTTP SERVER";
#-------------------------------------------------------------------------------
# ENV setting
#-------------------------------------------------------------------------------
if (!$IsWindows) {
	foreach(keys(%ENV)) {
		if ($_ =~ /^Satsuki/) { next; }
		delete $ENV{$_};
	}
}
$ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
$ENV{SERVER_NAME}     = 'localhost';
$ENV{SERVER_PORT}     = $PORT;
$ENV{SERVER_PROTOCOL} = 'HTTP/1.1';
$ENV{SERVER_SOFTWARE} = 'Satsuki';
$ENV{REQUEST_SCHEME}  = 'http';
$ENV{DOCUMENT_ROOT}   = Cwd::getcwd();

#-------------------------------------------------------------------------------
# windows port check
#-------------------------------------------------------------------------------
if ($IsWindows) {
	my $sock;
	socket($sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
	my $addr = sockaddr_in($PORT, inet_aton('localhost'));
	my $r = connect($sock, $addr);
	close($sock);

	if ($r) {
		&open_browser_on_windows();
		die "bind port $PORT failed: Address already in use";
	}
}

#-------------------------------------------------------------------------------
# bind port
#-------------------------------------------------------------------------------
my $srv;
if ($UNIX_SOCK ne '') {
	socket($srv, AF_UNIX, SOCK_STREAM, 0)		|| die "socket failed: $!";
	if (-S $UNIX_SOCK) {
		unlink($UNIX_SOCK);
	}
	bind($srv, pack_sockaddr_un($UNIX_SOCK))	|| die "bind port failed: $!";
	listen($srv, SOMAXCONN)				|| die "listen failed: $!";

	chmod(0777, $UNIX_SOCK);
	$PORT=0;

	print	"\tUNIX domain socket: $UNIX_SOCK\n"

} else {
	socket($srv, PF_INET, SOCK_STREAM, getprotobyname('tcp'))	|| die "socket failed: $!";
	setsockopt($srv, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))	|| die "setsockopt failed: $!";
	bind($srv, sockaddr_in($PORT, INADDR_ANY))			|| die "bind port failed: $!";
	listen($srv, SOMAXCONN)						|| die "listen failed: $!";
}

print(
	($PORT ? "\tListen $PORT port," : "\tNo Listen port,")
		. " Timeout $TIMEOUT sec,"
		. " Buffer ${BUFSIZE_u}B,"
		. " Keep-Alive " . ($KEEPALIVE ? 'on' : 'off') . "\n"
	. "\tStart up daemon: $DEAMONS " . ($ITHREADS ? 'threads' : 'process')
	. ", Max cgi requests: $MAX_CGI_REQUESTS\n"
);

#-------------------------------------------------------------------------------
# set TIMEOUT_BIN
#-------------------------------------------------------------------------------
if (1) {
	my $sec  = int($TIMEOUT);
	my $usec = ($TIMEOUT - $sec) * 1_000_000;
	$TIMEOUT_BIN = pack('l!l!', $sec, $usec);
}

#-------------------------------------------------------------------------------
# load mime types
#-------------------------------------------------------------------------------
if ($MIME_FILE && -e $MIME_FILE) {
	print "\tLoad mime types: $MIME_FILE ";
	my $r = sysopen(my $fh, $MIME_FILE, O_RDONLY);
	if (!$r) {
		print "(error!)\n";
	} else {

		my $c=0;
		while(<$fh>) {
			chomp($_);
			$_ =~ s/#.*//;
			my ($type, @ary) = split(/\s+/, $_);
			if ($type eq '' || !@ary) { next; }
			foreach(@ary) {
				$MIME_TYPE{$_} = $type;
				$c++;
			}
		}
		print "(load $c extensions)\n";
	}
	close($fh);
}

#-------------------------------------------------------------------------------
# search deny directories
#-------------------------------------------------------------------------------
{
	my @dirs = &search_dir_file('.htaccess');
	if (-r '.git') { push(@dirs, '.git'); }

	print "\tDeny dirs: " . join('/, ', @dirs) . "/\n";
	foreach(@dirs) {
		$DENY_DIRS{$_}=1;
	}
}

#-------------------------------------------------------------------------------
# file system encode
#-------------------------------------------------------------------------------
if ($FS_CODE) {
	require Encode;

	my $enc = Encode::find_encoding($FS_CODE);
	if (!$enc) {
		print STDERR "Unknown file system code: $FS_CODE\n";	# debug-safe
		exit(-1);
	}
	$FS_CODE = $enc->mime_name || $enc->name;

	my $enc2 = Encode::find_encoding($SYS_CODE);
	if (!$enc2) {
		print STDERR "Unknown cgi system code: $SYS_CODE\n";	# debug-safe
		exit(-1);
	}
	$SYS_CODE = $enc2->mime_name || $enc2->name;
	print "\tFile system code: $FS_CODE (cgi system is $SYS_CODE)\n";
}

#-------------------------------------------------------------------------------
# PATH and SCRIPT_NAME
#-------------------------------------------------------------------------------
{
	$PATH .= '/';
	$PATH  =~ s|//|/|g;
	$PATH0 = $PATH;
	$PATH0 =~ s|/$||;
	$PATH0_len = length($PATH0);
	print "\tWeb working path: $PATH\n";

	## SCRIPT_NAME
	my $scr = $0;
	if ($IsWindows) {
		$scr =~ s|^\w+:||;
		$scr =~ s|\\|/|g;
	}
	$scr = ($scr =~ m|([^/]*)$|) ? "$PATH$1" : $scr;
	$ENV{SCRIPT_NAME} = $scr;
}

#-------------------------------------------------------------------------------
($SILENT_CGI && $SILENT_FILE && $SILENT_OTHER) || print "\n";

$PID = $ITHREADS ? &thread_id() : $$;

################################################################################
# auto generate default conf file
################################################################################
if ($GENERATE_CONF) {
	my $cmd = $0;
	if ($IsWindows) { $cmd =~ tr|\\|/|; }
	if ($cmd =~ m|/([^/\.]*)[^/]*$|) {
		my $conf   = $1 . '.conf.cgi';
		my $sample = $conf . '.sample';
		if (!-e $conf && -r $sample) {
			print "Auto generate: '$conf' from '$sample'\n\n";
			require File::Copy;
			File::Copy::copy($sample, $conf);
		}
	}
}

################################################################################
# main routine
################################################################################
{
	$SIG{USR1} = sub {};	# wake up for main process

	# prefork / create_threads
	for(my $i=0; $i<$DEAMONS; $i++) {
		&fork_or_crate_thread(\&daemon_main, $srv);
	}

	# clear defunct process on fork()
	my $exit_daemons = 0;
	if (!$ITHREADS) {
		$SIG{CHLD} = sub {
			while(waitpid(-1, WNOHANG) > 0) {
				$exit_daemons++;
			};
		};
	} else {
		$SIG{CHLD} = 'IGNORE';
	}

	# open Browser on windows
	if ($PORT && $IsWindows && $OPEN_BROWSER) {
		&open_browser_on_windows();
	}

	# main thread
	while(1) {
		sleep(3);
		$exit_daemons = $ITHREADS ? ($DEAMONS - scalar(threads->list())) : $exit_daemons;
		if (!$exit_daemons) { next; }

		# Restart dead daemons
		## print STDERR "Restart daemons $exit_daemons\n";
		my $x = $exit_daemons;
		for(my $i=0; $i<$x; $i++) {
			&fork_or_crate_thread(\&daemon_main, $srv);
		}
		$exit_daemons -= $x;
	}
}
close($srv);
exit(0);
#-------------------------------------------------------------------------------
my $CGI_REQUESTS=0;
sub daemon_main {
	my $srv = shift;
	my %bak = %ENV;
	my $cgi = 0;

	if (!$ITHREADS) {	# for fock() in CGI
		$SIG{CHLD} = 'IGNORE';
	}

	$PID = $ITHREADS ? &thread_id() : $$;
	$IsWindows && sleep(1);		# accept() blocking main thread on Windows

	&preload_satsuki_lib();

	while(1) {
		my $addr = accept(my $sock, $srv);
		if (!$addr) { next; }

		my $st = &accept_client($sock, $addr, \%bak);	# $r==-1 if cgi_reload

		if ($st->{shutdown}) {
			print "$$ shutdown\n";
			last;
		}
		if ($MAX_CGI_REQUESTS<$CGI_REQUESTS) { last; }
	}

	if ($ITHREADS) {
		threads->detach();
		if (!$IsWindows) { kill('SIGUSR1', $$); }
	}
}

#-------------------------------------------------------------------------------
# fork() or create->thread()
#-------------------------------------------------------------------------------
sub fork_or_crate_thread {
	my $func = shift;
	if ($ITHREADS) {
		my $thr = threads->create($func, @_);
		if (!defined $thr) { die "threads->create fail!"; }
		return $thr;
	}
	# fork
	my $pid = fork();
	if (!defined $pid) {
		die "fork() fail!";
	}
	if (!$pid) {
		&$func(@_);
		exit();
	}
}

################################################################################
# accept
################################################################################
sub accept_client {
	my $sock = shift;
	my $addr = shift;
	my $bak  = shift;
	binmode($sock);
	setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, $TIMEOUT_BIN);	# invalid on windows

	if ($PORT) {
		my ($port, $ip_bin) = sockaddr_in($addr);
		$ENV{REMOTE_ADDR} = inet_ntoa($ip_bin);
		$ENV{REMOTE_PORT} = $port;
		# print "[$PID] connection from $ip:$port\n";
	} else {
		# $ENV{REMOTE_ADDR} = '0.0.0.0';
		# $ENV{REMOTE_PORT} = 0;
	}

	# set bit alarm emulation( use by select )
	$R_BITS='';
	&set_bit($R_BITS, $sock);

	my $state;
	my $flag=1;
	while($flag) {
		$state = &parse_request($sock);
		if (!$state || !$state->{keep_alive} || $state->{shutdown}) {
			close($sock);
			$flag = 0;
		}
		&output_connection_log($state);
		%ENV = %$bak;
	}
	return $state;
}
sub output_connection_log {
	my $state = shift;
	if (!$state) {
		$SILENT_OTHER || print "[$PID] connection close\n";
	} else {
		if ($state->{type} eq 'file' && $SILENT_FILE
		 || $state->{type} eq 'cgi ' && $SILENT_CGI) {
			return;
 		}
		my $byte = $state->{send};
		print "[$PID] $state->{status} $state->{type} " . (' ' x (7-length($byte))) . "$byte " . $state->{request} . "\n";
	}
}

#-------------------------------------------------------------------------------
# parse request
#-------------------------------------------------------------------------------
sub parse_request {
	my $sock  = shift;
	my $state = { sock => $sock, type=>'    ' };

	#---------------------------------------------------
	# recieve HTTP Header
	#---------------------------------------------------
	my @header;
	{
		if ($IsWindows) {
			my $r = select(my $x = $R_BITS, undef, undef, $TIMEOUT);
			if (!$r) { return; }
		}

		my $first=1;
		while(1) {
			my $line = <$sock>;
			if (!defined $line) { return; }	# disconnect

			$line =~ s/[\r\n]//g;

			if ($first) {		# (example) HTTP/1.1 GET /
				$first = 0;
				my $bad_req = &analyze_request($state, $line);
				if ($bad_req) {
					return $state;
				}
				next;
			}

			if ($line eq '') { last; }
			push(@header, $line);
		}
	}

	#---------------------------------------------------
	# Analyze Header
	#---------------------------------------------------
	foreach(@header) {
		if ($_ !~ /^([\w\-]+):\s*(.*)/) {
			&_400_bad_request($state);
			return $state;
		}
		my $key = $1;
		my $val = $2;
		$key =~ tr/a-z/A-Z/;

		if ($key eq 'IF-MODIFIED-SINCE') {
			$state->{if_modified} = $val;
			next;
		}
		if ($key eq 'CONTENT-LENGTH') {
			$ENV{CONTENT_LENGTH} = $val;
			next;
		}
		if ($key eq 'CONTENT-TYPE') {
			$ENV{CONTENT_TYPE} = $val;
			next;
		}
		if ($KEEPALIVE && $key eq 'CONNECTION') {
			$val =~ tr/A-Z/a-z/;
			if ($val eq 'keep-alive') {
				$state->{keep_alive} = 1;
			}
		}

		$key =~ s/-/_/g;
		$ENV{"HTTP_$key"} = $val;
	}
	#---------------------------------------------------
	# Header check
	#---------------------------------------------------
	if ($ENV{HTTP_HOST} eq '' || $ENV{HTTP_HOST} !~ m/^[\w-]+(\.[\w\-]+)*(:\d+)?$/) {
		&_400_bad_request($state);
		return $state;
	}

	#---------------------------------------------------
	# file read
	#---------------------------------------------------
	my $path = $state->{path};
	{
		my $file = $path;
		$file =~ s/\?.*//;	# cut query
		$file =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;

		if ($PATH0_len) {
			if (substr($file, 0, $PATH0_len) ne $PATH0) {
				&_404_not_found($state);
				return $state;
			}
			$file = substr($file, $PATH0_len);
		}

		my $r = &try_file_read($state, $file);
		if ($r) {
			return $state;
		}
	}

	#---------------------------------------------------
	# Exec CGI
	#---------------------------------------------------
	$ENV{SERVER_NAME}    = $ENV{HTTP_HOST};
	$ENV{SERVER_NAME}    =~ s/:\d+$//;
	$ENV{REQUEST_METHOD} = $state->{method};
	$ENV{REQUEST_URI}    = $state->{path};
	{
		my $x = index($path, '?');
		if ($x>0) {
			$ENV{QUERY_STRING} = substr($path, $x+1);
			$path = substr($path, 0, $x);
		}
	}
	$path =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
	$ENV{PATH_INFO} = $PATH0_len ? substr($path, $PATH0_len) : $path;

	$state->{type} = 'cgi ';
	$CGI_REQUESTS++;
	&exec_cgi($state);

	return $state;
}

#-------------------------------------------------
# Analyze Request
#-------------------------------------------------
sub analyze_request {
	my $state = shift;
	my $req   = shift;
	$state->{request} = $req;

	if ($req !~ m!^(GET|POST|HEAD) ([^\s]+) HTTP/(\d\.\d)!) {
		&_400_bad_request($state);
		return 1;
	}
	my $path = $2;
	$state->{method}  = $1;
	$state->{path}    = $path;
	$state->{version} = $3;

	if (substr($path,0,1) ne '/' || $state->{version}<1.0) {
		&_400_bad_request($state);
		return 2;
	}
	return 0;
}

#-------------------------------------------------------------------------------
# try file read
#-------------------------------------------------------------------------------
sub try_file_read {
	my $state = shift;
	my $file  = shift;

	$file =~ s|/+|/|g;
	$file =~ s|\?.*||;
	if ($file =~ m|/\.\./|) { return; }
	if ($INDEX && $file ne '/' && substr($file, -1) eq '/') {
		$file .= $INDEX;
	}

	#---------------------------------------------------
	# file system encode
	#---------------------------------------------------
	my $_file = substr($file,1);	# /index.html to index.html

	if ($FS_CODE && $FS_CODE ne $SYS_CODE) {
		Encode::from_to($_file, $SYS_CODE, $FS_CODE);
	}
	if (!-e $_file) {
		if ($file ne '/favicon.ico') { return; }
		$state->{type} = 'file';
		return &_404_not_found($state);
	}
	if ($file =~ m|^/[^/]*$|) {	# ignore current dir files
		return;
	}

	#---------------------------------------------------
	# file request
	#---------------------------------------------------
	$state->{type} = 'file';
	if (!-r $_file
	 || $file =~ m|/\.ht|
	 || $file =~ m|^/([^/]+)/| && $DENY_DIRS{$1}) {
		return &_403_forbidden($state);
	}

	#---------------------------------------------------
	# header
	#---------------------------------------------------
	my @st   = stat($_file);
	my $size = $st[7];
	my $lastmod = &rfc_date( $st[9] );
	my $header  = "Last-Modified: $lastmod\r\n";
	$header .= "Content-Length: $size\r\n";
	if ($file =~ /\.([\w\-]+)$/) {
		my $ext = $1;
		$ext =~ tr/A-Z/a-z/;
		if ($MIME_TYPE{$ext}) {
			$header .= "Content-Type: $MIME_TYPE{$ext}\r\n";
		}
	}
	if ($state->{if_modified} && $state->{if_modified} eq $lastmod) {
		return &_304_not_modified($state, $header);
	}

	#---------------------------------------------------
	# read file
	#---------------------------------------------------
	$state->{length} = $size;

	return &_200_ok($state, $header, sub {
		my $sock = shift;
		sysopen(my $fh, $_file, O_RDONLY);

		my $remain = $size;
		while(0 < $remain) {
			my $byte = ($BUFSIZE < $remain ? $BUFSIZE : $remain);

			my $r = sysread($fh, my $data, $byte);
			if (!$fh || $r != $byte) {
				# fatal error
				$state->{keep_alive} = 0;
			}
			print $sock $data;
			$remain -= $byte;
		}
		close($fh);
	});
}

################################################################################
# Exec CGI
################################################################################
sub preload_satsuki_lib {
	require Satsuki::Base;
	require Satsuki::AutoReload;
	&Satsuki::AutoReload::save_lib();
	if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
}

sub exec_cgi {
	my $state = shift;
	my $cache = shift || 0;
	my $sock  = $state->{sock};

	my $ROBJ;
	eval {
		#-----------------------------------------------------
		# connect stdout
		#-----------------------------------------------------
		# local *STDIN;
		# open(STDIN,  '<&=', fileno($sock));
		# binmode(STDIN);

		local *STDOUT;
		open(STDOUT, '>&=', fileno($sock));
		binmode(STDOUT);

		#-----------------------------------------------------
		# update check
		#-----------------------------------------------------
		my $flag = &Satsuki::AutoReload::check_lib();
		if ($flag) {
			$Satsuki::Base::RELOAD = 1;	# if Base.pm compile error, force reload
			require Satsuki::Base;
			$Satsuki::Base::RELOAD = 0;
			$CGI_REQUESTS = 0x70000000;
		}

		#-----------------------------------------------------
		# Timer start
		#-----------------------------------------------------
		my $timer;
		if ($ENV{SatsukiTimer} ne '0' && $Satsuki::Timer::VERSION) {
			$timer = Satsuki::Timer->new();
			$timer->start();
		}

		#-----------------------------------------------------
		# Initalize
		#-----------------------------------------------------
		$ROBJ = Satsuki::Base->new();	# root object
		$ROBJ->{Timer} = $timer;
		$ROBJ->{AutoReload} = $flag;
		$ROBJ->{STDIN}      = $sock;

		$ROBJ->init_for_httpd($state, $PATH);

		if ($FS_CODE) {
			# file system's locale setting
			$ROBJ->set_fslocale($FS_CODE);
		}

		#-----------------------------------------------------
		# main
		#-----------------------------------------------------
		$ROBJ->start_up();
		$ROBJ->finish();
		close(STDOUT);
	};
	binmode($sock);		# buffer clear
	$@ && !$ENV{SatsukiExit} && print STDERR "$@\n";	# debug-safe

	# Save LIB's modtime
	&Satsuki::AutoReload::save_lib();

	$state->{status}   = $ROBJ->{Status};
	$state->{send}     = $ROBJ->{Send} || 0;
	$state->{shutdown} = $ROBJ->{Shutdown};
}

################################################################################
# Response
################################################################################
sub _200_ok {
	my $state = shift;
	$state->{status}     = 200;
	$state->{status_msg} = '200 OK';
	return &send_response($state, @_);
}
sub _304_not_modified {
	my $state = shift;
	$state->{status}     = 304;
	$state->{status_msg} = '304 Not Modified';
	return &send_response($state, @_);
}
sub _400_bad_request {
	my $state = shift;
	$state->{status}     = 400;
	$state->{status_msg} = '400 Bad Request';
	return &send_response($state, @_);
}
sub _403_forbidden {
	my $state = shift;
	$state->{status}     = 403;
	$state->{status_msg} = '403 Forbidden';
	return &send_response($state, @_);
}
sub _404_not_found {
	my $state = shift;
	$state->{status}     = 404;
	$state->{status_msg} = '404 Not Found';
	return &send_response($state, @_);
}
sub _500_internal_server_error {
	my $state = shift;
	my $data  = shift;
	$state->{status}     = 500;
	$state->{status_msg} = '500 Internal Server Error';
	return &send_response($state, '', $data);
}
sub send_response {
	my $state  = shift || {};
	my $status = $state->{status};
	my $header = shift || '';
	my $data   = shift || $state->{status_msg} . "\n";
	my $c_len  = $state->{length} || length($data);
	my $sock   = $state->{sock};
	my $date   = &rfc_date( time() );

	if (399 < $status) {
		$header .= "Content-Type: text/plain\r\n";
	}
	if (index($header, 'Content-Length:')<0) {
		$header .= "Content-Length: $c_len\r\n";
	}
	$header .= "Connection: " . ($state->{keep_alive} ? 'keep-alive' : 'close') . "\r\n";

	my $header = <<HEADER;
HTTP/1.1 $state->{status_msg}\r
Date: $date\r
Server: $ENV{SERVER_SOFTWARE}\r
$header\r
HEADER
	print $sock $header;

	if ($state->{method} ne 'HEAD' && $status !~ /^304 /) {
		if (ref($data) eq 'CODE') {
			&$data($sock);
		} else {
			print $sock $data;
		}
		$state->{send} = length($header) + $c_len;
	} else {
		$state->{send} = length($header);
	}
	binmode($sock);		# buffer clear
	return $status;
}

################################################################################
# sub routine
################################################################################
sub thread_id	{ return sprintf("%02d", threads->tid); }
sub set_bit	{ vec($_[0], fileno($_[1]), 1) = 1; }
sub reset_bit	{ vec($_[0], fileno($_[1]), 1) = 0; }
sub check_bit   { vec($_[0], fileno($_[1]), 1); }
sub rfc_date {
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(shift);

	my($wd, $mn);
	$wd = substr('SunMonTueWedThuFriSat',$wday*3,3);
	$mn = substr('JanFebMarAprMayJunJulAugSepOctNovDec',$mon*3,3);

	return sprintf("$wd, %02d $mn %04d %02d:%02d:%02d GMT"
		, $mday, $year+1900, $hour, $min, $sec);
}

#-------------------------------------------------------------------------------
# deny directories
#-------------------------------------------------------------------------------
sub search_dir_file {
	my $file = shift || '.htaccess';
	opendir(my $fh, './') || return [];

	my @ary;
	foreach(readdir($fh)) {
		if ($_ eq '.' || $_ eq '..' )  { next; }
		if (!-d $_) { next; }
		if (-e "$_/$file") {
			push(@ary, $_);
		}
	}
	closedir($fh);
	return @ary;
}

#-------------------------------------------------------------------------------
# deny directories
#-------------------------------------------------------------------------------
sub generate_random_string {
	my $_SALT = 'xL6R.JAX38tUanpyFfjZGQ49YceKqs2NOiwB/ubhHEMzo7kSC5VDPWrm1vgT0lId';
	my $len = int(shift) || 32;
	my $str = '';
	my ($sec, $usec) = Time::HiRes::gettimeofday();
	foreach(1..$len) {
		$str .= substr($_SALT, (int(rand(0x1000000) * $usec)>>8) & 0x3f, 1);
	}
	return $str;
}

#-------------------------------------------------------------------------------
# open Browser on windows
#-------------------------------------------------------------------------------
sub open_browser_on_windows {
	if ($IsWindows && $OPEN_BROWSER) {
		my $url = 'http://' . $ENV{SERVER_NAME} . ($PORT==80 ? '' : ":$PORT");
		system("cmd.exe /c start $url?login_auto");
	}
}

#-------------------------------------------------------------------------------
# debug output
#-------------------------------------------------------------------------------
sub debug {
	my $str = shift;
	my ($sec, $usec) = Time::HiRes::gettimeofday();
	$usec = substr($sec,-2) . "." . substr("00000$usec",-6);
	print STDERR "$usec [$PID] $str\n";		# debug-safe
}
