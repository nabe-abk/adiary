#!/usr/bin/perl
use 5.8.1;
use strict;
###############################################################################
# Satsuki system - HTTP Server
#						Copyright (C)2018 nabe@abk
###############################################################################
# Last Update : 2018/09/xx
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
use Time::HiRes;	# for generate random string
use Image::Magick;	# load on main process for Windows EXE
use Encode::Locale;	# for get system locale / for Windows
#------------------------------------------------------------------------------
use Satsuki::Base ();
use Satsuki::AutoReload ();
use Satsuki::Timer ();
&Satsuki::AutoReload::save_lib();
###############################################################################
# setting
###############################################################################
my $SILENT_CGI   = 0;
my $SILENT_FILE  = 0;
my $SILENT_OTHER = 0;
my $IsWindows = ($^O eq 'MSWin32');

my $PORT    = $IsWindows ? 80 : 8888;
my $ITHREAD = $IsWindows;
my $PATH    = $ARGV[0];
my $TIMEOUT = 10;
my $MIME_FILE = '/etc/mime.types';
my $INDEX;  # = 'index.html';

my $SYS_CODE = $Satsuki::SYSTEM_CODING;
my $FS_CODE  = $IsWindows ? $Encode::Locale::ENCODING_LOCALE : undef;

# select() is thread block on Windows
my $SELECT_TIMEOUT = $IsWindows ? 0.01 : undef;
#------------------------------------------------------------------------------
my %DENY_DIRS;
my %MIME_TYPE = ( 
	html => 'text/html',
	htm  => 'text/html',
	text => 'text/plain',
	txt  => 'text/plain',
	css  => 'text/css',
	js   => 'application/javascript',
	png  => 'image/png',
	jpg  => 'image/jpeg',
	jpeg => 'image/jpeg'
);
my %DENY_EXTS = (cgi=>1, pl=>1, pm=>1);	# deny extensions
#------------------------------------------------------------------------------
# for CGI Deamon
#------------------------------------------------------------------------------
my $CGID_BUFSIZE = 0x1000000;		# 1MB
my $CGID_PROCESS = 3;
my $CGID_TIMEOUT = 3;
my $CGID_PORT;
my $CGID_KEY = &generate_random_string(64);	# shard key
my %CGID_ENV = (
	SERVER_NAME	=> 1,
	REQUEST_METHOD	=> 1,
	REQUEST_URI	=> 1,
	REMOTE_ADDR	=> 1,
	REMOTE_PORT	=> 1,
	PATH_INFO	=> 1,
	QUERY_STRING	=> 1,
	CONTENT_LENGTH	=> 1,
	CONTENT_TYPE	=> 1
);
my $CGID_HOST = '127.0.0.1';
my $CGID_SOCKADDR;
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
		my @c = split('', $key);
		while(@c) {
			my $k = shift(@c);
			if ($k eq 'h') { $help =1; next; }
			if ($k eq '?') { $help =1; next; }
			if ($k eq 'i') { $ITHREAD=1; next; }
			if ($k eq 'f') { $ITHREAD=0; next; }

			# silent
			if ($k eq 's' && $c[0] eq 'c') { shift(@c); $SILENT_CGI  = $SILENT_OTHER = 1; next; }
			if ($k eq 's' && $c[0] eq 'f') { shift(@c); $SILENT_FILE = $SILENT_OTHER = 1; next; }
			if ($k eq 's') { $SILENT_CGI = $SILENT_FILE = $SILENT_OTHER = 1; next; }

			# arg
			if ($k eq 'p') { $PORT         = int(shift(@ary)); next; }
			if ($k eq 't') { $TIMEOUT      = int(shift(@ary)); next; }
			if ($k eq 'd') { $CGID_PROCESS = int(shift(@ary)); next; }
			if ($k eq 'm') { $MIME_FILE    = shift(@ary); next; }
			if ($k eq 'c') { $FS_CODE      = shift(@ary); next; }
		}
	}
	if ($TIMEOUT < 1) { $TIMEOUT=1; }
	
	if ($help) {
		print <<HELP;
Usage: $0 [options] [output_xml_file]
Available options are:
  -p port	bind port (default:8888, windows:80)
  -t timeout	connection timeout second (default:10)
  -m mime_file	load mime types file name (default: /etc/mime.types)
  -d deamons	cgi deamons (default:5), set 0 for stable
  -c fs_code	set file system's code
  -f		use fork()
  -i 		use threads (ithreads)
  -s            silent mode
  -sc           silent mode for cgi  access
  -sf           silent mode for file access
  -\?|-h		view this help
HELP
		exit(0);
	}
}
###############################################################################
# start up
###############################################################################
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
$ENV{SCRIPT_NAME}     = $0;
$ENV{SERVER_NAME}     = 'localhost';
$ENV{SERVER_PORT}     = $PORT;
$ENV{SERVER_PROTOCOL} = 'HTTP/1.1';
$ENV{SERVER_SOFTWARE} = 'Satsuki';
$ENV{REQUEST_SCHEME}  = 'http';
$ENV{DOCUMENT_ROOT}   = Cwd::getcwd();
#------------------------------------------------------------------------------
# bind port
#------------------------------------------------------------------------------
my $srv;
{
	socket($srv, PF_INET, SOCK_STREAM, 0)				|| die "socket failed: $!";
	setsockopt($srv, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))	|| die "setsockopt failed: $!";
	bind($srv, sockaddr_in($PORT, INADDR_ANY))			|| die "bind port failed: $!";
	listen($srv, SOMAXCONN)						|| die "listen failed: $!";
}
print "Satsuki HTTP Server: Listen $PORT port, timeout $TIMEOUT sec, " . ($ITHREAD ? 'threads' : 'fork') . " mode\n";

#------------------------------------------------------------------------------
# CGI Deamon
#------------------------------------------------------------------------------
if ($CGID_PROCESS > 0) {
	$CGID_PORT     = $PORT+1;
	$CGID_SOCKADDR = sockaddr_in($CGID_PORT, inet_aton($CGID_HOST));
	print "\tStart CGI Deamon: $CGID_PROCESS " . ($ITHREAD ? 'threads' : 'process') . ", $CGID_HOST:$CGID_PORT\n";
	&create_cgi_deamon($CGID_PROCESS);
}

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
if ($FS_CODE) {
	if ($FS_CODE =~ /utf-?8/i) { $FS_CODE='UTF-8'; }
	require Encode;
	print "\tSet file system coding: $FS_CODE\n";
}
if ($INDEX) {
	print "\tDirectory index: $INDEX\n";
}
($SILENT_CGI && $SILENT_FILE && $SILENT_OTHER) || print "\n";
###############################################################################
# main routine
###############################################################################
{
	local $SIG{CHLD};
	if (!$ITHREAD) {	# clear defunct process
		$SIG{CHLD} = sub {
			while(waitpid(-1, WNOHANG) > 0) {};
		};
	}

	my $rbits;
	&set_bit($rbits, $srv);
	while(1) {
		select(my $x = $rbits, undef, undef, $SELECT_TIMEOUT);
		if (!&check_bit($x, $srv)) { next; }
		&fork_or_crate_thread(\&accept_client, $srv);
	}
}
close($srv);
exit(0);

#------------------------------------------------------------------------------
# fork() or create->thread()
#------------------------------------------------------------------------------
sub fork_or_crate_thread {
	my $func = shift;
	if ($ITHREAD) {
		my $thr = threads->create($func, @_);
		if (!defined $thr) { die "threads->create fail!"; }
		$thr->detach();
		return;
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
	my $sock;
	my $addr = accept($sock, $srv);
	if (!$addr) { return; }
	my($port, $ip_bin) = sockaddr_in($addr);
	my $ip   = inet_ntoa($ip_bin);
	binmode($sock);

	$ENV{REMOTE_ADDR} = $ip;
	$ENV{REMOTE_PORT} = $port;

	my $state = &parse_request($sock);
	close($sock);

	&output_connection_log($state);
}
sub output_connection_log {
	my $state = shift;
	if (!$state) {
		$SILENT_OTHER || print "[$$] connection close\n";
	} elsif ($state->{cgid}) {
		# print "[$$] connected to cgid\n";
	} else {
		if ($state->{type} eq 'file' && $SILENT_FILE
		 || $state->{type} ne 'file' && $SILENT_CGI) {
			return;
 		}
		my $byte = $state->{send};
		print "[$$] $state->{status} $state->{type} " . (' ' x (7-length($byte))) . "$byte " . $state->{request} . "\n";
	}
}

#------------------------------------------------------------------------------
# parse request
#------------------------------------------------------------------------------
sub parse_request {
	my $sock  = shift;
	my $state = { sock => $sock, type=>'    ' };
	# open(STDIN, '<&=', fileno($sock));

	#--------------------------------------------------
	# recieve HTTP Header
	#--------------------------------------------------
	my @header;
	my $body;
	my $timeout;
	{
		local $SIG{ALRM} = sub { close($sock); $timeout=1; };
		alarm( $TIMEOUT );

		my $first=1;
		while(1) {
			my $line = &read_sock_1line($sock);	# no buffered <$sock>
			if (!defined $line)  { return; }	# disconnect
			$line =~ s/[\r\n]//g;

			if ($first) {	# (example) HTTP/1.0 GET /
				# print "[$$] $line\n";
				$first = 0;
				my $err = &analyze_request($state, $line);
				if ($err) { return $state; }
				next;
			}

			if ($line eq '') { last; }
			push(@header, $line);
		}

		alarm(0);
	}
	if ($timeout) { return; }

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

		$key =~ s/-/_/g;
		$key =~ tr/a-z/A-Z/;
		$ENV{"HTTP_$key"} = $val;
	}

	#--------------------------------------------------
	# Analyze Request
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

	if ($CGID_PROCESS) {
		$state->{cgid} = 1;
		&connect_cgid($state);
	} else {
		$state->{type} = 'cgi ';
		&exec_cgi($state);
	}
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
	if ($INDEX ne '' && substr($file, -1) eq '/') {
		$file .= 'index.html';
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
	 || $file =~ m|^([^/]+)/| && $DENY_DIRS{$1}) {
		&_403_forbidden($state);
		return 403;
	}
	# deny extensions
	while($file =~ /\.([^\.]+)/g) {
		if (! $DENY_EXTS{$1}) { next; }
		&_403_forbidden($state);
		return 403;
	}

	#--------------------------------------------------
	# header
	#--------------------------------------------------
	my $size = -s $_file;
	my $lastmod = &rfc_date( (stat $_file)[9] );
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
my @CGI;
sub exec_cgi {
	my $state = shift;
	my $cache = shift || 0;
	my $sock  = $state->{sock};

	my $ROBJ;
	eval {
		#--------------------------------------------------
		# connect stdout
		#--------------------------------------------------
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
		}

		#--------------------------------------------------
		# Timer start
		#--------------------------------------------------
		if ($ENV{SatsukiTimer}) { require Satsuki::Timer; }
		my $timer;
		if (defined $Satsuki::Timer::VERSION) {
			$timer = Satsuki::Timer->new();
			$timer->start();
		}

		#--------------------------------------------------
		# Initalize
		#--------------------------------------------------
		$ROBJ = Satsuki::Base->new();	# root object
		$ROBJ->{Timer} = $timer;
		$ROBJ->{AutoReload} = $flag;

		$ROBJ->init_for_httpd($sock, undef, $cache);

		if ($FS_CODE) {
			# file system's locale setting
			$ROBJ->set_fslocale($FS_CODE);
		}

		#--------------------------------------------------
		# main
		#--------------------------------------------------
		$ROBJ->start_up();
		$ROBJ->finish();
	};
	# ライブラリのセーブ
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
	$state->{status_msg} = '400 Forbidden';
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
	if (index($header, 'Content-Type:')<0) {
		$header .= "Content-Type: text/plain\r\n";
	}
	my $header = <<HEADER;
HTTP/1.0 $state->{status_msg}\r
Date: $date\r
Server: $ENV{SERVER_SOFTWARE}\r
Connection: close\r
$header\r
HEADER
	print $sock $header;

	$state->{send} = 0;
	if ($state->{method} ne 'HEAD' && $status !~ /^304 /) {
		print $sock $data;
		$state->{send} = length($header) + $c_len;
	}
}

###############################################################################
# CGI Deamons : like FastCGI
###############################################################################
sub create_cgi_deamon {
	my $deamons = shift;
	my $cgid;

	socket($cgid, PF_INET, SOCK_STREAM, 0)				|| die "socket failed: $!";
	setsockopt($cgid, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))	|| die "setsockopt failed: $!";
	bind($cgid, $CGID_SOCKADDR)					|| die "bind port failed: $!";
	listen($cgid, SOMAXCONN)					|| die "listen failed: $!";

	foreach(my $i=0; $i<$deamons; $i++) {
		&fork_or_crate_thread(\&cgid_server, $cgid);
	}
}
sub cgid_server {
	my $srv = shift;
	my $rbits;
	&set_bit($rbits, $srv);
	my %bak = %ENV;
	$IsWindows && sleep(3);		# select is block main thread on Windows
	while(1) {
		my $r = select(my $x = $rbits, undef, undef, $SELECT_TIMEOUT);
		if (!&check_bit($x, $srv)) { next; }
		&accept_cgid_client($srv);
		%ENV = %bak;
	}
}

#------------------------------------------------------------------------------
# accept cgid client
#------------------------------------------------------------------------------
sub accept_cgid_client {
	my $srv = shift;

	my $sock;
	my $addr = accept($sock, $srv);
	if (!$addr) { return; }
	my($port, $ip_bin) = sockaddr_in($addr);
	my $ip   = inet_ntoa($ip_bin);
	binmode($sock);

	my $state = &cgid_run_cgi($sock);
	close($sock);

	if ($state) {
		&output_connection_log($state);
	}
}
#------------------------------------------------------------------------------
# run cgi
#------------------------------------------------------------------------------
sub cgid_run_cgi {
	my $sock = shift;

	#--------------------------------------------------
	# recieve HTTP Header
	#--------------------------------------------------
	my @header;
	my $timeout;
	{
		local $SIG{ALRM} = sub { close($sock); $timeout=1; };
		alarm( $CGID_TIMEOUT );

		my $first=1;
		while(1) {
			my $line = &read_sock_1line($sock);	# no buffered <$sock>
			if (!defined $line)  { return; }	# disconnect
			chomp($line);
			if ($line eq '') { last; }
			push(@header, $line);
		}
		alarm(0);
	}
	if ($timeout) { return; }

	#--------------------------------------------------
	# check shard key
	#--------------------------------------------------
	my $key = shift(@header);
	if ($key ne $CGID_KEY) { return; }

	#--------------------------------------------------
	# setting ENV
	#--------------------------------------------------
	my $state = { sock => $sock };
	foreach(@header) {
		my $x = index($_, ':');			# split "HTTP_SERVER:localhost"
		my $k = substr($_, 0, $x);
		my $v = substr($_, $x+1);
		if ($k eq 'REQUEST') {
			$state->{request} = $v;
			next;
		}
		if ($CGID_ENV{$k} || $k =~ /^HTTP_/) {	# security check
			$ENV{$k} = $v;
		}
	}
	
	#--------------------------------------------------
	# exec CGI
	#--------------------------------------------------
	$state->{type} = 'cgid';
	&exec_cgi($state, 1);

	return $state;
}

#------------------------------------------------------------------------------
# connect to cgid
#------------------------------------------------------------------------------
sub connect_cgid {
	my $state = shift;

	my $cgi;
	socket($cgi, PF_INET, SOCK_STREAM, 0) || die "socket failed: $!";
	{
		local $SIG{ALRM} = sub { close($cgi); };
		alarm( $CGID_TIMEOUT );
		my $r = connect($cgi, $CGID_SOCKADDR);
		alarm(0);
		$r || die "Can't connect CGId server";
	
	}
	binmode($cgi);

	my $header = "$CGID_KEY\n";
	foreach(keys(%ENV)) {
		if (!$CGID_ENV{$_} && $_ !~ /^HTTP_/) { next; }
		$header .= "$_:$ENV{$_}\n";
	}
	$header .= "REQUEST:$state->{request}\n\n";
	syswrite($cgi, $header, length($header));

	&data_relay($state->{sock}, $cgi, $CGID_BUFSIZE);
	return 0;
}

sub data_relay {
	my $sock1 = shift;
	my $sock2 = shift;
	my $bufsize = shift || 0x100000;	# 256KB

	my $rbits = '';
	&set_bit($rbits, $sock1);
	&set_bit($rbits, $sock2);
	while(1) {
		select(my $x = $rbits, undef, undef, undef);

		if (&check_bit($x, $sock1)) {
			my $data;
			recv($sock1, $data, $bufsize, 0);
			if ($data eq '') { last; }
			syswrite($sock2, $data, length($data));
		}
		if (&check_bit($x, $sock2)) {
			my $data;
			recv($sock2, $data, $bufsize, 0);
			if ($data eq '') { last; }
			syswrite($sock1, $data, length($data));
		}
	}
}

###############################################################################
# sub routine
###############################################################################
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
# no buffered read <$sock>
#------------------------------------------------------------------------------
sub read_sock_1line {
	my $sock = shift;
	my $line = '';
	my $c;
	while($c ne "\n") {
		if (sysread($sock, $c, 1) != 1) { return; }
		$line .= $c;
	}
	return $line;
}

#------------------------------------------------------------------------------
# deny directories
#------------------------------------------------------------------------------
sub generate_random_string {
	my $_SALT = 'xL6R.JAX38tUanpyFfjZGQ49YceKqs2NOiwB/ubhHEMzo7kSC5VDPWrm1vgT0lId';
	my $len = int(shift) || 32;
	my $str = '';
	my ($sec, $msec) = Time::HiRes::gettimeofday();
	foreach(1..$len) {
		$str .= substr($_SALT, (int(rand(0x1000000) * $msec)>>8) & 0x3f, 1);
	}
	return $str;
}
