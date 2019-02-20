#!/usr/bin/perl
use 5.8.1;
use strict;
our $VERSION  = '1.04';
our $SPEC_VER = '1.00';	# specification version for compatibility
###############################################################################
# Satsuki system - HTTP Server
#						Copyright (C)2019 nabe@abk
###############################################################################
# Last Update : 2019/02/20
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
#------------------------------------------------------------------------------
# Crypt patch for Windows
#------------------------------------------------------------------------------
if (crypt('','$1$') eq '' || crypt('','$5$') eq '' || crypt('','$6$') eq ''){
	eval {
		require Crypt::glibc;
		*CORE::GLOBAL::crypt = *Crypt::glibc::crypt;
	};
};
#------------------------------------------------------------------------------
# pre load modules
#------------------------------------------------------------------------------
eval { require Image::Magick; };
eval { require Net::SSLeay;   };
###############################################################################
# setting
###############################################################################
my $IsWindows    = ($^O eq 'MSWin32');
my $SILENT_CGI   = 0;
my $SILENT_FILE  = 0;
my $SILENT_OTHER = 0;
my $OPEN_BROWSER = $IsWindows;
my $GENERATE_CONF= 1;

my $PORT      = $IsWindows ? 80 : 8888;
my $ITHREADS  = $IsWindows;
my $TIMEOUT   =  3;
my $DEAMONS   = 10;
my $KEEPALIVE = 1;
my $MIME_FILE = '/etc/mime.types';
my $INDEX     = 'index.html';
my $PID;
my $R_BITS;	# select socket bits

my $MAX_CGI_REQUESTS = 10000;

my $SYS_CODE;
my $FS_CODE;
#------------------------------------------------------------------------------
if ($IsWindows) {
	require Encode::Locale;
	import  Encode::Locale;
	$FS_CODE = $Encode::Locale::ENCODING_LOCALE;
}

#------------------------------------------------------------------------------
# Web Server data
#------------------------------------------------------------------------------
my %DENY_DIRS;
my %MIME_TYPE = ( 
	html => 'text/html',
	htm  => 'text/html',
	text => 'text/plain',
	txt  => 'text/plain',
	css  => 'text/css',
	js   => 'application/javascript',
	json => 'application/json',
	xml  => 'application/xml',
	png  => 'image/png',
	jpg  => 'image/jpeg',
	jpeg => 'image/jpeg',
	ico  => 'image/vnd.microsoft.icon'
);
my $DENY_EXTS_Reg = qr/\.(?:cgi|pl|pm)(?:$|\.)/;	# deny extensions regexp

#------------------------------------------------------------------------------
# for RFC date
#------------------------------------------------------------------------------
my %JanFeb2Mon = (
	Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov =>10, Dec =>11
);
#------------------------------------------------------------------------------
# analyze @ARGV
#------------------------------------------------------------------------------
{
	my @ary = @ARGV;
	my $help;
	while(@ary) {
		my $key = shift(@ary);
		if (substr($key, 0, 1) ne '-') { $help=1; last; }
		$key = substr($key, 1);
		while($key ne '') {
			my $k = substr($key,0,1);
			my $k2= substr($key,0,2);
			$key  = substr($key,1);
			my $kx= substr($key,2);

			if ($k eq 'h') { $help =1; next; }
			if ($k eq '?') { $help =1; next; }
			if ($k eq 'n') { $OPEN_BROWSER=0; next; }
			if ($k eq 'i')                { $ITHREADS=1; next; }
			if ($k eq 'f' && $k2 ne 'fs') { $ITHREADS=0; next; }

			# keep-alive
			if ($k2 eq 'k0') { $key=$kx; $KEEPALIVE=0; next; }
			if ($k2 eq 'k1') { $key=$kx; $KEEPALIVE=1; next; }
			if ($k  eq 'k')  {           $KEEPALIVE=1; next; }

			# keep-alive
			if ($k2 eq 't0') { $key=$kx; $ENV{SatsukiTimer}=0; next; }
			if ($k2 eq 't1') { $key=$kx; $ENV{SatsukiTimer}=1; next; }

			# silent
			if ($k2 eq 'sc') { $key=$kx; $SILENT_CGI  = $SILENT_OTHER = 1; next; }
			if ($k2 eq 'sf') { $key=$kx; $SILENT_FILE = $SILENT_OTHER = 1; next; }
			if ($k  eq 's')  { $SILENT_CGI = $SILENT_FILE = $SILENT_OTHER = 1; next; }

			# arg
			if ($k2 eq 'fs' || $k2 eq 'mi') { $k=$k2; }
			if (index('ptdm',$k) < 0 && length($k)==1) {
				print "Unknown option : -$k\n";
				exit(-1);
			}
			my $val;
			if ($key =~ /^\d/) {
				$val=$key; $key='';
			} else {
				$val=shift(@ary);
			}
			if ($val eq '') {
				print "needs argument: -$k option\n";
				exit(-1);
			}
			# string argument
			if ($k eq 'mi') { $MIME_FILE = $val; next; }
			if ($k eq 'fs') { $FS_CODE   = $val; next; }

			# float argument
			if ($k eq 't') {
				if ($val !~ /^\d+(?:\.\d+)?$/) {
					print "Invalid argument: -$k option\n";
					exit(-1);
				}
			} elsif ($val !~ /^\d+$/) {
				print "Invalid argument: -$k option\n";
				exit(-1);
			}
			if ($k eq 'p') { $PORT    = $val; next; }
			if ($k eq 't') { $TIMEOUT = $val; next; }
			if ($k eq 'd') { $DEAMONS = $val; next; }
			if ($k eq 'm') { $MAX_CGI_REQUESTS = $val; next; }
			die("program error");
		}
	}
	if ($TIMEOUT < 0.001)	{ $TIMEOUT=0.001; }
	if ($DEAMONS < 1) 	{ $DEAMONS=1;     }
	if ($MAX_CGI_REQUESTS == 0)		{ $MAX_CGI_REQUESTS=10000000; }
	if ($MAX_CGI_REQUESTS > 10000000)	{ $MAX_CGI_REQUESTS=10000000; }
	if ($MAX_CGI_REQUESTS <      100)	{ $MAX_CGI_REQUESTS=100; }

	if ($help) {
		my $n = $IsWindows ? "  -n\t\tdo not open web browser\n" : '';
		print <<HELP;
Usage: $0 [options]
Available options are:
  -p port	bind port (default:8888, windows:80)
  -t timeout	connection timeout second (default:3, min:0.001)
  -d daemons	start daemons (default:10, min:1)
  -m max_req	maximum cgi requests per daemon (default:10000, min:100)
  -mi mime_file	load mime types file name (default: /etc/mime.types)
  -fs fs_code	set file system's code (charset)
  -f		use fork()
  -i		use threads (ithreads)
  -k, -k1	connection keep-alive enable (default)
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
###############################################################################
# start up
###############################################################################
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

#------------------------------------------------------------------------------
# safety (Do not run on CGI/HTTP SERVER)
#------------------------------------------------------------------------------
$ENV{SERVER_PROTOCOL} && die "Do not run on CGI/HTTP SERVER";
#------------------------------------------------------------------------------
# ENV setting
#------------------------------------------------------------------------------
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
{
	my $scr = $0;
	if ($IsWindows) {
		$scr =~ s|^\w+:||;
		$scr =~ s|\\|/|g;
	}
	$scr = ($scr =~ m|([^/]*)$|) ? "/$1" : $scr;
	$ENV{SCRIPT_NAME} = $scr;
}
#------------------------------------------------------------------------------
# windows port check
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# bind port
#------------------------------------------------------------------------------
my $srv;
{
	socket($srv, PF_INET, SOCK_STREAM, getprotobyname('tcp'))	|| die "socket failed: $!";
	setsockopt($srv, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))	|| die "setsockopt failed: $!";
	bind($srv, sockaddr_in($PORT, INADDR_ANY))			|| die "bind port failed: $!";
	listen($srv, SOMAXCONN)						|| die "listen failed: $!";
}
print	  "\tListen $PORT port, Timeout $TIMEOUT sec, Keep-Alive " . ($KEEPALIVE ? 'on' : 'off') . "\n"
	. "\tStart up daemon: $DEAMONS " . ($ITHREADS ? 'threads' : 'process')
	. ", Max cgi requests: $MAX_CGI_REQUESTS\n";

#------------------------------------------------------------------------------
# load mime types
#------------------------------------------------------------------------------
if ($MIME_FILE && -e $MIME_FILE) {
	print "\tLoad mime types: $MIME_FILE ";
	my $r = sysopen(my $fh, $MIME_FILE, O_RDONLY);
	if (!$r) {
		print "(error!)\n";
	} else {

		my $c=0;
		while(<$fh>) {
			chomp($_);
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

#------------------------------------------------------------------------------
# search deny directories
#------------------------------------------------------------------------------
{
	my @dirs = &search_dir_file('.htaccess');
	print "\tDeny dirs: " . join('/, ', @dirs) . "/\n";
	foreach(@dirs) {
		$DENY_DIRS{$_}=1;
	}
}

#------------------------------------------------------------------------------
# File system encode and directory index
#------------------------------------------------------------------------------
if ($FS_CODE) {
	if ($FS_CODE =~ /utf-?8/i) { $FS_CODE='UTF-8'; }
	require Encode;
	print "\tFile system coding: $FS_CODE\n";
}
if (0 && $INDEX) {
	print "\tDirectory index: $INDEX\n";
}

#------------------------------------------------------------------------------
($SILENT_CGI && $SILENT_FILE && $SILENT_OTHER) || print "\n";

$PID = $ITHREADS ? &thread_id() : $$;

###############################################################################
# auto generate default conf file
###############################################################################
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

###############################################################################
# main routine
###############################################################################
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
	}

	# open Browser on windows
	if ($IsWindows && $OPEN_BROWSER) {
		&open_browser_on_windows();
	}

	# main thread
	while(1) {
		sleep(2);
		$exit_daemons = $ITHREADS ? ($DEAMONS - $#{[ threads->list() ]} - 1) : $exit_daemons;
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
#------------------------------------------------------------------------------
my $CGI_REQUESTS=0;
sub daemon_main {
	my $srv = shift;
	my %bak = %ENV;
	my $cgi = 0;

	$PID = $ITHREADS ? &thread_id() : $$;
	$IsWindows && sleep(1);		# accept() blocking main thread on Windows

	&preload_satsuki_lib();

	while(1) {
		my $addr = accept(my $sock, $srv);
		if (!$addr) { next; }

		&accept_client($sock, $addr, \%bak);	# $r==-1 if cgi_reload
		if ($MAX_CGI_REQUESTS<$CGI_REQUESTS) { last; }
	}

	if ($ITHREADS) {
		threads->detach();
		if (!$IsWindows) { kill('SIGUSR1', $$); }
	}
}

#------------------------------------------------------------------------------
# fork() or create->thread()
#------------------------------------------------------------------------------
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

###############################################################################
# accept
###############################################################################
sub accept_client {
	my $sock = shift;
	my $addr = shift;
	my $bak  = shift;
	my($port, $ip_bin) = sockaddr_in($addr);
	my $ip   = inet_ntoa($ip_bin);
	binmode($sock);

	$ENV{REMOTE_ADDR} = $ip;
	$ENV{REMOTE_PORT} = $port;
	# print "[$PID] connection from $ip:$port\n";

	# set bit alarm emulation( use by select )
	$R_BITS='';
	&set_bit($R_BITS, $sock);

	my $state;
	my $flag=1;
	while($flag) {
		$state = &parse_request($sock);
		if (!$state || !$state->{keep_alive}) {
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

#------------------------------------------------------------------------------
# parse request
#------------------------------------------------------------------------------
sub parse_request {
	my $sock  = shift;
	my $state = { sock => $sock, type=>'    ' };

	#--------------------------------------------------
	# recieve HTTP Header
	#--------------------------------------------------
	my @header;
	{
		my $break;
		my $bad_req;

		local $SIG{ALRM} = sub { close($sock); $break=1; };
		&my_alarm( $TIMEOUT, $sock );

		my $first=1;
		while(1) {
			my $line = <$sock>;
			if (!defined $line)  {	# disconnect
				$break=1;
				last;
			}
			$line =~ s/[\r\n]//g;

			if ($first) {		# (example) HTTP/1.1 GET /
				$first = 0;
				$bad_req = &analyze_request($state, $line);
				if ($bad_req) { last; }
				next;
			}

			if ($line eq '') { last; }
			push(@header, $line);
		}

		&my_alarm(0);
		if ($break)   { return; }
		if ($bad_req) { return $state; }
	}

	#--------------------------------------------------
	# Analyze Header
	#--------------------------------------------------
	foreach(@header) {
		if ($_ !~ /^([^:]+):\s*(.*)/) { next; }
		my $key = $1;
		my $val = $2;

		if ($key eq 'If-Modified-Since') {
			$state->{if_modified} = $val;
			next;
		}
		if ($key eq 'Content-Length') {
			$ENV{CONTENT_LENGTH} = $val;
			next;
		}
		if ($key eq 'Content-Type') {
			$ENV{CONTENT_TYPE} = $val;
			next;
		}
		if ($KEEPALIVE && $key eq 'Connection' && ($val eq 'keep-alive' || $val eq 'Keep-Alive')) {
			$state->{req_keep_alive} = 1;
		}

		$key =~ s/-/_/g;
		$key =~ tr/a-z/A-Z/;
		$ENV{"HTTP_$key"} = $val;
	}

	#--------------------------------------------------
	# file read
	#--------------------------------------------------
	my $path = $state->{path};
	$state->{file} = $path;
	$state->{file} =~ s/\?.*//;	# cut query
	$state->{file} =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr(hex($1))/eg;
	my $r = &try_file_read($state);
	if ($r) {
		return $state;
	}

	#--------------------------------------------------
	# Exec CGI
	#--------------------------------------------------
	$ENV{SERVER_NAME}    = $ENV{HTTP_HOST};
	$ENV{SERVER_NAME}    =~ s/:\d+$//;
	$ENV{REQUEST_METHOD} = $state->{method};
	$ENV{REQUEST_URI}    = $path;
	{
		my $x = index($path, '?');
		if ($x>0) {
			$ENV{QUERY_STRING} = substr($path, $x+1);
			$path = substr($path, 0, $x);
		}
	}
	$ENV{PATH_INFO} = $path;

	$state->{type} = 'cgi ';
	$CGI_REQUESTS++;
	&exec_cgi($state);

	return $state;
}

#--------------------------------------------------
# Analyze Request
#--------------------------------------------------
sub analyze_request {
	my $state = shift;
	my $req   = shift;
	$state->{request} = $req;

	if ($req !~ m!^(GET|POST|HEAD) ([^\s]+) (?:HTTP/\d\.\d)?!) {
		&_400_bad_request($state);
		return 1;
	}

	my $method = $1;
	my $path   = $2;
	$state->{method} = $method;
	$state->{path}   = $path;
	if (substr($path,0,1) ne '/') {
		&_400_bad_request($state);
		return 2;
	}
	return 0;
}

#------------------------------------------------------------------------------
# try file read
#------------------------------------------------------------------------------
sub try_file_read {
	my $state = shift;
	my $file  = $state->{file};

	$file =~ s|/+|/|g;
	if ($file =~ m|/\.\./|) { return; }
	if ($INDEX && $file ne '/' && substr($file, -1) eq '/') {
		$file .= $INDEX;
	}
	$file = substr($file,1);	# /index.html to index.html

	#--------------------------------------------------
	# file system encode
	#--------------------------------------------------
	my $_file = $file;
	if ($FS_CODE && $FS_CODE ne $SYS_CODE) {
		Encode::from_to($_file, $SYS_CODE, $FS_CODE);
	}
	if (!-e $_file) { return; }

	#--------------------------------------------------
	# file request
	#--------------------------------------------------
	$state->{type} = 'file';
	if (!-r $_file
	 || $file =~ m|^\.ht|
	 || $file =~ m|/\.ht|
	 || $file =~ m|^([^/]+)/| && $DENY_DIRS{$1}
	 || $file =~ /$DENY_EXTS_Reg/) {
		&_403_forbidden($state);
		return 403;
	}

	#--------------------------------------------------
	# header
	#--------------------------------------------------
	my @st   = stat($_file);
	my $size = $st[7];
	my $lastmod = &rfc_date( $st[9] );
	my $header  = "Last-Modified: $lastmod\r\n";
	$header .= "Content-Length: $size\r\n";
	if ($file =~ /\.([\w\-]+)$/ && $MIME_TYPE{$1}) {
		$header .= "Content-Type: $MIME_TYPE{$1}\r\n";
	}
	if ($state->{if_modified} && $state->{if_modified} eq $lastmod) {
		&_304_not_modified($state, $header);
		return 304;
	}

	#--------------------------------------------------
	# read file
	#--------------------------------------------------
	sysopen(my $fh, $_file, O_RDONLY);
	my $r = sysread($fh, my $data, $size);
	if (!$fh || $r != $size) {
		&_403_forbidden($state);
		return 403;
	}
	close($fh);

	&_200_ok($state, $header, $data);
	return 200;
}

###############################################################################
# Exec CGI
###############################################################################
sub preload_satsuki_lib {
	require Satsuki::Base;
	require Satsuki::AutoReload;
	&Satsuki::AutoReload::save_lib();
	if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }

	$SYS_CODE = $Satsuki::SYSTEM_CODING;
}

sub exec_cgi {
	my $state = shift;
	my $cache = shift || 0;
	my $sock  = $state->{sock};

	my $ROBJ;
	eval {
		#--------------------------------------------------
		# connect stdout
		#--------------------------------------------------
		# local *STDIN;
		# open(STDIN,  '<&=', fileno($sock));
		# binmode(STDIN);

		local *STDOUT;
		open(STDOUT, '>&=', fileno($sock));
		binmode(STDOUT);

		#--------------------------------------------------
		# update check
		#--------------------------------------------------
		my $flag = &Satsuki::AutoReload::check_lib();
		if ($flag) {
			$Satsuki::Base::RELOAD = 1;	# if Base.pm compile error, force reload
			require Satsuki::Base;
			$Satsuki::Base::RELOAD = 0;
			$CGI_REQUESTS = 0x70000000;
		}

		#--------------------------------------------------
		# Timer start
		#--------------------------------------------------
		my $timer;
		if ($ENV{SatsukiTimer} ne '0' && $Satsuki::Timer::VERSION) {
			$timer = Satsuki::Timer->new();
			$timer->start();
		}

		#--------------------------------------------------
		# Initalize
		#--------------------------------------------------
		$ROBJ = Satsuki::Base->new();	# root object
		$ROBJ->{Timer} = $timer;
		$ROBJ->{AutoReload} = $flag;
		$ROBJ->{STDIN} = $sock;

		$ROBJ->init_for_httpd($state);

		if ($FS_CODE) {
			# file system's locale setting
			$ROBJ->set_fslocale($FS_CODE);
		}

		#--------------------------------------------------
		# main
		#--------------------------------------------------
		$ROBJ->start_up();
		$ROBJ->finish();
		close(STDIN);
		close(STDOUT);
	};
	binmode($sock);		# buffer clear
	$@ && !$ENV{SatsukiExit} && print STDERR "$@\n";	# debug-safe

	# Save LIB's modtime
	&Satsuki::AutoReload::save_lib();

	$state->{status} = $ROBJ->{Status};
	$state->{send}   = $ROBJ->{Send} || 0;
}

###############################################################################
# Response
###############################################################################
sub _200_ok {
	my $state = shift;
	$state->{status}     = 200;
	$state->{status_msg} = '200 OK';
	&send_response($state, @_);
}
sub _304_not_modified {
	my $state = shift;
	$state->{status}     = 304;
	$state->{status_msg} = '304 Not Modified';
	&send_response($state, @_);
}
sub _400_bad_request {
	my $state = shift;
	$state->{status}     = 400;
	$state->{status_msg} = '400 Bad Request';
	&send_response($state, @_);
}
sub _403_forbidden {
	my $state = shift;
	$state->{status}     = 403;
	$state->{status_msg} = '403 Forbidden';
	&send_response($state, @_);
}
sub _500_internal_server_error {
	my $state = shift;
	my $data  = shift;
	$state->{status}     = 500;
	$state->{status_msg} = '500 Internal Server Error';
	&send_response($state, '', $data);
}
sub send_response {
	my $state  = shift || {};
	my $status = $state->{status};
	my $header = shift || '';
	my $data   = shift || $state->{status_msg} . "\n";
	my $c_len  = length($data);
	my $sock   = $state->{sock};
	my $date   = &rfc_date( time() );

	if (index($header, 'Content-Length:')<0) {
		$header .= "Content-Length: $c_len\r\n";
	}
	$state->{keep_alive} = $state->{req_keep_alive} && $status<400;
	$header .= "Connection: " . ($state->{keep_alive} ? 'keep-alive' : 'close') . "\r\n";

	my $header = <<HEADER;
HTTP/1.1 $state->{status_msg}\r
Content-Type: text/plain\r
Date: $date\r
Server: $ENV{SERVER_SOFTWARE}\r
$header\r
HEADER
	print $sock $header;

	if ($state->{method} ne 'HEAD' && $status !~ /^304 /) {
		print $sock $data;
		$state->{send} = length($header) + $c_len;
	} else {
		$state->{send} = length($header);
	}
	binmode($sock);		# buffer clear
}

###############################################################################
# sub routine
###############################################################################
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

#------------------------------------------------------------------------------
# deny directories
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# deny directories
#------------------------------------------------------------------------------
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

#------------------------------------------------------------------------------
# alarm
#------------------------------------------------------------------------------
sub my_alarm {
	my $timeout = shift;
	if (!$IsWindows && !$ITHREADS) {
		return Time::HiRes::alarm($timeout);
	}
	# $IsWindows or $ITHREADS
	if ($timeout <= 0) { return; }

	my $sock = shift;
	my $r = select(my $x = $R_BITS, undef, undef, $timeout);

	if (!$r) {	# timeout
		&{ $SIG{ALRM} }();
	}
}

#------------------------------------------------------------------------------
# open Browser on windows
#------------------------------------------------------------------------------
sub open_browser_on_windows {
	if ($IsWindows && $OPEN_BROWSER) {
		my $url = 'http://' . $ENV{SERVER_NAME} . ($PORT==80 ? '' : ":$PORT");
		system("cmd.exe /c start $url?login_auto");
	}
}

#------------------------------------------------------------------------------
# debug output
#------------------------------------------------------------------------------
sub debug {
	my $str = shift;
	my ($sec, $usec) = Time::HiRes::gettimeofday();
	$usec = substr($sec,-2) . "." . substr("00000$usec",-6);
	print STDERR "$usec [$PID] $str\n";		# debug-safe
}
