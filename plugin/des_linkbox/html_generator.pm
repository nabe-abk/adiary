#-------------------------------------------------------------------------------
# linkボックスモジュールのHTML生成ルーチン
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $id   = $self->plugin_name_id($name);
	my $set  = $self->load_plgset($name);

	my $title = $set->{title} || 'link list';
	my $html = <<HTML;
<!--Links======================================-->
<div class="hatena-module side-link-list" data-module-name="$name" id="$id">
<div class="hatena-moduletitle">$title</div>
<div class="hatena-modulebody">
<ul class="hatena-section">
HTML


	foreach(split('\n', $set->{elements})) {
		my ($text,$url) = split(/\t/, $_, 2);
		if ($url ne '') {
			$html .= <<HTML;
<li><a href="$url">$text</a></li>
HTML
		} else {
			$html .= "<li>$text</li>";
		}
	}

	$html .= <<HTML;
</ul>
</div> <!-- hatena-modulebody -->
</div> <!-- hatena-module -->
HTML
	return $html;
}

