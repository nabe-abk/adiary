#-----------------------------------------------------------------------------
# install
#-----------------------------------------------------------------------------
sub {
use strict;
my $ECC_NAME = 'prime256v1';
#-----------------------------------------------------------------------------
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $ps   = $self->load_plgset($name);

	# ライブラリ
	require	Crypt::PK::ECC;
	sub base64urlsafe {
		my $table='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
		my $str = shift;
		my $ret = '';
		my ($i, $j, $x, $y);
		for($i=$x=0, $j=2; $i<length($str); $i++) {
			$x    = ($x<<8) + ord(substr($str,$i,1));
			$ret .= substr($table, ($x>>$j) & 0x3f, 1);
			if ($j != 6) { $j+=2; next; }
			$ret .= substr($table, $x & 0x3f, 1);
			$j    = 2;
		}
		if ($j != 2) { $ret .= substr($table, ($x<<(8-$j)) & 0x3f, 1); }
		return $ret;
	};

	# プライベートキー(１度のみ生成〕
	if (!$ps->{sprv}) {
		my $pk = Crypt::PK::ECC->new();
		$pk->generate_key($ECC_NAME);
		$self->update_plgset($name, 'spub', &base64urlsafe($pk->export_key_raw('public' )) );
		$self->update_plgset($name, 'sprv', &base64urlsafe($pk->export_key_raw('private')) );
	}

	# メッセージキー
	my $pk = Crypt::PK::ECC->new();
	$pk->generate_key($ECC_NAME);
	$self->update_plgset($name, 'mpub', &base64urlsafe($pk->export_key_raw('public' )) );
	$self->update_plgset($name, 'mprv', &base64urlsafe($pk->export_key_raw('private')) );

	return 0;
}
