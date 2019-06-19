#!/usr/local/bin/perl
require 5.004;
use strict;
#-------------------------------------------------------------------------------
# パーサー呼び出し
#							(C)2015 nabe@abk
#-------------------------------------------------------------------------------
package SatsukiApp::parser;
use Satsuki::AutoLoader;
#-------------------------------------------------------------------------------
our $VERSION = '1.00';
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my ($class, $ROBJ, $self) = @_;
	if (ref($self) ne 'HASH') { $self={}; }
	bless($self, $class);	# $self をこのクラスと関連付ける
	$self->{ROBJ}    = $ROBJ;	# root object save
	return $self;
}

###############################################################################
# ■メイン処理
###############################################################################
sub main {
	my $self  = shift;
	my $r = $self->_main(@_);
	my $ROBJ = $self->{ROBJ};

	foreach(@{$ROBJ->{Message}}, @{$ROBJ->{Errors}}) {
		print $_,"\n";
	}
	return $r;
}

sub _main {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	# パーサーのロード
	my $parser = $self->load_parser( $self->{parser_type} );
	if (! ref($parser)) {
		$ROBJ->message("Load parser '%s' failed", $parser);
		return ;
	}
	$parser->{section_hnum} = $self->{section_hnum};

	my $argv = $ROBJ->{ARGV};
	if (!@$argv) {
		print "$0 (file)\n";
		return ;
	}

	my $frame = $self->{format_skel};
	foreach(@$argv) {
		my $file = $_ . '.html';
		if ($_ =~ /^(.*?)\.\w+$/) {
			$file = $1 . '.html';
		}

		print "process: $_ to $file\n";

		# パーサーで処理
		my $text = $ROBJ->fread_lines( $_ );
		map { s/\r\n|\r/\n/g } @$text;
		$text = join('', @$text);

		my ($text, $text_s) = $parser->text_parser( $text );

		# パーサー内変数を埋め込む
		$ROBJ->{vars} = $parser->{vars_} || {};

		# フレームに埋め込む
		my $out = $ROBJ->call( $frame, $text );

		# 書き出し
		$ROBJ->fwrite_lines( $file, $out );
	}
}

#------------------------------------------------------------------------------
# ●parserのロード
#------------------------------------------------------------------------------
sub load_parser {
	my $self = shift;
	my $name = shift;
	if ($name =~ /\W/) { return; }
	return $self->{ROBJ}->call( '_parser/' . $name );
}

#------------------------------------------------------------------------------
# ●blog_dirを取得
#------------------------------------------------------------------------------
sub blog_dir {
	return '';
}
sub blogpub_dir {
	return '';
}
sub blogimg_dir {
	return '';
}
