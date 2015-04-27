use strict;
#-------------------------------------------------------------------------------
# adiary_6.pm (C)2014 nabe@abk
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
use SatsukiApp::adiary_3 ();
use SatsukiApp::adiary_4 ();
use SatsukiApp::adiary_5 ();
package SatsukiApp::adiary;
###############################################################################
# ■ワンライナーなサブルーチン等
###############################################################################
my @update_versions = (
	{ ver => 2.93, func => 'sys_update_293', rebuild=>1, plugin=>1 },
	{ ver => 2.94, func => 'sys_update_294' },
);
#------------------------------------------------------------------------------
# ●システムアップデート
#------------------------------------------------------------------------------
sub system_update {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	if (!$auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 5; }

	my $cur_blogid = $self->{blogid};
	my $blogs = $self->load_all_blogid();

	my %opt;
	my $cur = $self->{sys}->{VERSION};
	foreach my $h (@update_versions) {
		if ($cur >= $h->{ver}) { next; }
		$ROBJ->message("System update for Ver %s", $h->{ver});
		$opt{rebuild} ||= $h->{rebuild};	# 全記事再構築
		$opt{plugin}  ||= $h->{plugin};		# プラグイン更新

		my $func = $h->{func};
		if ($func) {
			$self->$func($blogs);
		}
		$cur = $h->{ver};
	}
	$self->set_and_select_blog($cur_blogid);

	# 再構築？
	if ($opt{rebuild}) {
		$ROBJ->message("Rebuild all blogs");
		$self->rebuild_all_blogs();
	}
	# プラグイン再インストール
	if ($opt{plugin}) {
		$ROBJ->message("Reinstall all plugins");
		$self->reinstall_all_plugins();
	}

	$self->update_sysdat('VERSION', $cur);
	return 0;
}

#------------------------------------------------------------------------------
# ●システムアップデート for Ver2.93
#------------------------------------------------------------------------------
sub sys_update_293 {
	my $self  = shift;
	my $blogs = shift;
	my $ROBJ = $self->{ROBJ};
	foreach(@$blogs) {
		$self->update_blogset($_, 'http_rel');
		$self->update_blogset($_, 'image_rel');
		$self->update_blogset($_, 'image_data', 'lightbox=%k');
	}
}

#------------------------------------------------------------------------------
# ●システムアップデート for Ver2.94
#------------------------------------------------------------------------------
sub sys_update_294 {
	my $self  = shift;
	my $blogs = shift;
	my $ROBJ = $self->{ROBJ};
	foreach(@$blogs) {
		$self->set_and_select_blog( $_ );
		#
		my $dir  = $ROBJ->get_filepath( $self->{blogpub_dir} );
		my $file = $dir . 'usercss.css';
		if (-r $file) {
			my $lines = $ROBJ->fread_lines( $file );
			my $css = join('', @$lines);
			$self->save_usercss( $css );
			unlink( $file );
		}
	}
}

###############################################################################
# ■Version2 to 3 移行ルーチン
###############################################################################
sub parse_adiary_conf_cgi {
	my $self = shift;
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	my %h;
	my $lines = $ROBJ->fread_lines( $file );
	
	
	
	
	
	
	
	
	
	
	
	
	
	
}

1;
