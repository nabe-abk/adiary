#-----------------------------------------------------------------------------
# 最近のコメント生成モジュール
#-----------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $num = $self->load_plgset($name, 'displays') || 5;
	my $ary = $DB->select("${blogid}_com",{
		flag     => { enable => 1 },
		cols     => [ 'name','id','tm','num','a_pkey','a_yyyymmdd','a_title','a_elink_key' ],
		sort     => 'tm',
		sort_rev => 1,
		limit    => $num
	});

	foreach(@$ary) {
		my $ymd = $_->{a_yyyymmdd};
		$_->{year} = substr($ymd, 0, 4);
		$_->{mon}  = substr($ymd, 4, 2);
		$_->{day}  = substr($ymd, 6, 2);
	}

	# スケルトンの実行と保存
	$self->update_plgset($name, 'html', $ROBJ->call('_format/recent_comment', $name, $ary));

	return 0;
}

