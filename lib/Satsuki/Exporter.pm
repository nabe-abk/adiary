use strict;
#-------------------------------------------------------------------------------
# 軽量なExporter
#					(C)2013 nabe / ABK project
#-------------------------------------------------------------------------------
# 動作するのは @EXPORT と @EXPORT_OK のみ。
# タグや複雑なエクスポートはできない。
#
# 標準のExporterの@EXPORTに、&funcname ではなく funcname だけ与えれば
# Exporter::Heavy がロードされず、ほぼ誤差の範囲なのでボツになった。
#
package Satsuki::Exporter;
our $VERSION = '1.00';

#------------------------------------------------------------------------------
# ●import本体
#------------------------------------------------------------------------------
sub import {
	no strict 'refs';

	my $spkg = shift;
	my $dpkg = (caller(0))[0];
	if ($spkg eq __PACKAGE__) {
		foreach(@_) {
			*{"$dpkg\::$_"} = *{"$spkg\::$_"}{CODE};
		}
		return;
	}

	my %exp = map { $_ => 1 } @{"$spkg\::EXPORT"};
	my %ok  = map { $_ => 1 } @{"$spkg\::EXPORT_OK"};

	foreach(@_) {
		if (exists $exp{$_} || exists $ok{$_}) { next; }
		&die("[Exporter] '$_' is not found");
	}

	my @ary = @_ || keys(%exp);
	foreach(@ary) {
		my $type;
		my $x = substr($_,0,1);
		   if ($x eq '$') { $type='SCALAR'; }
		elsif ($x eq '@') { $type='ARRAY'; }
		elsif ($x eq '%') { $type='HASH'; }
		elsif ($x eq '&') { $type='CODE'; }
		else {
			if ($x eq '*') { $_ = substr($_,1); }
			*{"$dpkg\::$_"} = *{"$spkg\::$_"};
			next;
		}
		$_ = substr($_,1);
		*{"$dpkg\::$_"} = *{"$spkg\::$_"}{$type};
	}
}

#------------------------------------------------------------------------------
# ●die
#------------------------------------------------------------------------------
sub die {
	my $str = shift;
	my @c = caller(1);
	die "[Exporter] $str from $c[1] line $c[2]"
}

1;
