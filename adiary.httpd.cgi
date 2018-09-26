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
use Time::Local;
use threads;	# for ithreads
use POSIX;	# for waitpid(<pid>, WNOHANG);
use Cwd;	# for $ENV{DOCUMENT_ROOT}
#------------------------------------------------------------------------------
use Satsuki::Base ();
use Satsuki::AutoReload ();
use Satsuki::Timer ();
#------------------------------------------------------------------------------
# default setting
#------------------------------------------------------------------------------
my $SILENT;
my $IsWindows = ($^O =~ /^MSWin/) ? 1 : 0;

my $PORT    = $IsWindows ? 80 : 8888;
my $ITHREAD = $IsWindows;
my $PATH    = $ARGV[0];
my $TIMEOUT = 10;
my $MIME_FILE = '/etc/mime.types';
my $INDEX;  #= 'index.html';
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
my %JanFeb2Mon = (
	Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	Jul => 7, Aug => 8, Sep => 9, Oct =>10, Nov =>11, Dec =>12
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
		foreach(split('', $key)) {
			if ($_ eq 'h') { $help =1; next; }
			if ($_ eq '?') { $help =1; next; }
			if ($_ eq 's') { $SILENT =1; next; }
			if ($_ eq 'i') { $ITHREAD=1; next; }
			if ($_ eq 'f') { $ITHREAD=0; next; }

			# arg
			if ($_ eq 'p') { $PORT    = int(shift(@ary)); next; }
			if ($_ eq 't') { $TIMEOUT = int(shift(@ary)); next; }
			if ($_ eq 'm') { $MIME_FILE = shift(@ary); next; }
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
  -f		use fork()
  -i 		use threads (ithreads)
  -s            silent mode
  -\?|-h		view this help
HELP
		exit(0);
	}
}
###############################################################################
# start up
###############################################################################
#------------------------------------------------------------------------------
# ENV setting
#------------------------------------------------------------------------------
if (!$IsWindows) {
	%ENV = ();
}
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
	listen($srv, 1000)						|| die "listen failed: $!";
}
print "Satsuki HTTP Server : Listen $PORT port, timeout $TIMEOUT sec, " . ($ITHREAD ? 'threads' : 'fork') . " mode\n";

#------------------------------------------------------------------------------
# load mime types
#------------------------------------------------------------------------------
if ($MIME_FILE) {
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
if ($INDEX) {
	print "\tDirectory index: $INDEX\n";
}

$SILENT || print "\n";
###############################################################################
# main routine
###############################################################################
my $reload;
my $rbits;
&set_bit($rbits, $srv);
{
	local $SIG{CHLD};
	if (!$ITHREAD) {	# clear defunct process
		$SIG{CHLD} = sub {
			while(waitpid(-1, WNOHANG) > 0) {};
		};
	}
	while(1) {
		#--------------------------------------------------
		# select
		#--------------------------------------------------
		my $r = select(my $x = $rbits, undef, undef, undef);

		#--------------------------------------------------
		# accept
		#--------------------------------------------------
		if ($ITHREAD) {
			my $thr = threads->create(\&accept_client, $srv);
			$thr->detach();

		} else {
			my $pid = fork();
			if (!defined $pid) {
				die "Fork fail!!\n";
			}
			if (!$pid) {
				&accept_client($srv);
				exit();
			}
		}
	}
}
close($srv);
exit(0);

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

	if ($SILENT) { return; }

	 $state && print "[$$] $state->{status} $state->{type} " . substr("         $state->{send}", -8) . ' ' . $state->{request} . "\n";
	!$state && print "[$$] connection close\n";
}
sub parse_request {
	my $sock  = shift;
	my $state = { sock => $sock, type=>'    ' };
	# open(STDIN, '<&=', fileno($sock));

	#--------------------------------------------------
	# recieve HTTP Request Header
	#--------------------------------------------------
	my @header;
	my $body;
	my $timeout;
	{
		local $SIG{ALRM} = sub { close($sock); $timeout=1; };
		alarm( $TIMEOUT );

		while(1) {
			my $line = <$sock>;
			if (!defined $line)  { return; }	# disconnect
			$line =~ s/[\r\n]//g;
			if ($line eq '') { last; }
			push(@header, $line);
		}

		alarm(0);
	}
	if ($timeout) { return; }

	#--------------------------------------------------
	# Analyze Header
	#--------------------------------------------------
	my $req = shift(@header);
	$state->{request} = $req;
	# print "[$$] $req\n";

	my $clen;
	foreach(@header) {
		if ($_ !~ /^([^:]+):\s*(.*)/) { next; }
		my $key = $1;
		my $val = $2;

		if ($key eq 'If-Modified-Since') {
			$state->{if_modified} = &date2utc($val);
			next;
		}
		if ($key eq 'Content-Length') {
			$ENV{CONTENT_LENGTH} = $val;
			$clen = $val;
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
	if ($req !~ m!^(GET|POST|HEAD) ([^\s]+) (?:HTTP/\d\.\d)?!) {
		&_400_bad_request($state);
		return $state;
	}

	my $method = $1;
	my $path   = $2;
	$state->{method} = $method;
	$state->{path}   = $path;
	if (substr($path,0,1) ne '/') {
		&_400_bad_request($state);
		return $state;
	}

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
	$ENV{SERVER_NAME} = $ENV{HTTP_HOST};
	$ENV{SERVER_NAME} =~ s/:\d+$//;
	$ENV{REQUEST_METHOD} = $method;
	$ENV{REQUEST_URI} = $path;
	{
		my $x = index($path, '?');
		if ($x>0) {
			$ENV{QUERY_STRING} = substr($path, $x+1);
			$path = substr($path, 0, $x);
		}
	}
	$ENV{PATH_INFO} = $path;

	&exec_cgi($state);
	return $state;
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
	if (!-e $file) { return; }

	#--------------------------------------------------
	# file request
	#--------------------------------------------------
	$state->{type} = 'file';
	if (!-r $file
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
	my $size = -s $file;
	my $lastmod = (stat $file)[9];
	my $header  = "Last-Modified: " . &rfc_date($lastmod) . "\r\n";
	$header .= "Content-Length: $size\r\n";
	if ($file =~ /\.([\w\-]+)$/ && $MIME_TYPE{$1}) {
		$header .= "Content-Type: $MIME_TYPE{$1}\r\n";
	}
	if ($state->{if_modified} && $state->{if_modified} != $lastmod) {
		&_304_not_modified($state, $header);
		return 304;
	}

	#--------------------------------------------------
	# read file
	#--------------------------------------------------
	sysopen(my $fh, $file, O_RDONLY);
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
sub exec_cgi {
	my $state = shift;
	my $sock  = $state->{sock};
	$state->{type} = 'cgi ';

	my $ROBJ;
	eval {
		#--------------------------------------------------
		# connect stdout
		#--------------------------------------------------
		local *STDOUT;
		open( STDOUT, '>&=', fileno($sock));
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

		$ROBJ->init_for_httpd($state->{sock});

		#--------------------------------------------------
		# main
		#--------------------------------------------------
		$ROBJ->start_up();
		$ROBJ->finish();
	};
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

	print $sock "HTTP/1.0 $state->{status_msg}\r\n";
	print $sock <<HEADER;
Date: $date\r
Server: $ENV{SERVER_SOFTWARE}\r
Connection: close\r
HEADER
	if (index($header, 'Content-Length:')<0) {
		print $sock "Content-Length: $c_len\r\n";
	}
	if (index($header, 'Content-Type:')<0) {
		print $sock "Content-Type: text/plain\r\n";
	}
	print $sock "$header\r\n";

	$state->{send} = 0;
	if ($state->{method} ne 'HEAD' && $status !~ /^304 /) {
		print $sock $data;
		$state->{send} = $c_len;
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
# date to UTC
#------------------------------------------------------------------------------
# Sat, 11 Aug 2018 13:52:10 GMT
sub date2utc {
	my $date = shift;
	if ($date !~ /^\w\w\w, (\d+) (\w\w\w) (\d+) (\d\d):(\d\d):(\d\d) GMT/) {
		return;
	}
	my $tm;
	eval {
		$tm = timegm($6, $5, $4, $1, $JanFeb2Mon{$2}, $3 - 1900);
	};
	return $tm;
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

