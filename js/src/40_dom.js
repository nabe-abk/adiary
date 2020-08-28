//############################################################################
//■DOM要素への拡張機能の提供
//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●popup-help
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const $popup_div = $('<div>').addClass('popup-block');
	this.$popup_div  = $popup_div;
	this.$body.append( $popup_div );
	const self = this;

	// btn-help はスマホでは無効にする
	const help = '.help[data-help]' + (this.SP ? '' : ', .btn-help[data-help]');
	this.$body.on('mouseover', help, {
		func: function($obj, $div){
			var text = self.tag_esc_br( $obj.data("help") );
			$div.addClass('popup popup-help');
			$div.html( text );
		}
	}, function(evt){ self.popup(evt) });
});

//////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	let prev;
	const self=this;
	this.$body.on('click', '.js-info[data-info], .js-info[data-url]', function(evt){

		if (evt.target == prev) return;	// 連続クリック防止
		prev = evt.target;

		const $obj = $(evt.target);
		const $div = $('<div>');
		const $div2= $('<div>');	// 直接 div にクラスを設定すると表示が崩れる

		$div.attr('title', $obj.data("title") || "Infomataion" );
		$div2.addClass($obj.data("class"));
		$div.empty();
		$div.append($div2);
		if ($obj.data('info')) {
			const text = self.tag_esc_br( $obj.data("info") );
			$div2.html( text );
			$div.adiaryDialog({ width: self.DialogWidth, close: close_func });
			return;
		}
		var url = $obj.data("url");
		$div2.load( url, function(){
			$div2.text( $div2.text().replace(/\n*$/, "\n\n") );
			$div.adiaryDialog({ width: self.DialogWidth, height: 320, close: close_func });
		});
	});
	function close_func() {
		prev = null;
	}
});

//////////////////////////////////////////////////////////////////////////////
//●ボタンでリンク
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	this.$body.on('click', 'button[data-href]', function(evt){
		location.href = $(evt.target).data('href');
	});
});

//////////////////////////////////////////////////////////////////////////////
//●ボタンで値設定
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	this.$body.on('click', 'button.js-set-value[data-target]', function(evt){
		const $btn = $(evt.target);
		$($btn.data('target')).val( $btn.attr('value') );
	});
});

//////////////////////////////////////////////////////////////////////////////
//●input[type="text"]などで enter による submit 停止
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	this.$body.on('keypress', 'input.no-enter-submit, form.no-enter-submit input', function(evt){
		if (evt.which === 13) return false;
		return true;
	});
});

//////////////////////////////////////////////////////////////////////////////
//●file upload button （input type="file"を間接クリックする）
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	this.$body.on('click', 'button.js-file-btn', function(evt) {
		const $obj = $(evt.target);
		const $tar = $obj.rootfind( $obj.data('target') );
		if (! $tar.length ) return;

		if ($tar.data('target') && !$tar.data('-regist-change-evt')) {
			$tar.data('-regist-change-evt', true);
			$tar.on('change', function(evt){
				const $span = $tar.rootfind( $tar.data('target') );
				const file  = $tar.val().replace(/^.*?([^\\\/]*)$/, "$1");
				$span.text( file );
			})
		}
		$tar.click();
	});
});
//////////////////////////////////////////////////////////////////////////////
//●file reset button
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	this.$body.on('click', 'button.js-reset-btn', function(evt) {
		const $obj = $(evt.target);
		const $tar = $obj.rootfind( $obj.data('target') );
		if (!$tar.length || $tar.val()=='') return;
		$tar.val('').change();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム要素の全チェック
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	this.$body.on('change', 'input.js-checked', function(evt){
		const $obj = $(evt.target);
		const target = $obj.data( 'target' );
		$obj.rootfind(target).prop("checked", $obj.is(":checked"));
	});
});

//////////////////////////////////////////////////////////////////////////////
//●値変更でフォーム送信
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	this.$body.on('change', '.js-on-change-submit', function(evt){
		const $obj = $(evt.target);
		$obj.parentsOne('form').submit();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●テーブルの行選択
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	this.$body.on('click', 'tbody.js-line-checked', function(evt){
		const $obj = $(evt.target);
		const $pars= $obj.parents('tr');
		if ($pars.add($obj).filter('a,input,button,label,.line-checked-cancel').length) return;

		const $tr  = $pars.last();
		const $inp = $tr.find('input[type="checkbox"],input[type="radio"]');
		$inp.first().click();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●コンボボックス / <select class="js-combo">
//////////////////////////////////////////////////////////////////////////////
$$.select_dummy_value = "\e\f\e\f\b\n";
$$.init( function(){
	const self = this;
	const dummy_val = this.select_dummy_value;

	const func = function(evt) {
		const $obj = $(evt.target);
		const val  = $obj.val();
		if (val != dummy_val)
			return $obj.data('default', val);
		$obj.val( $obj.data('default') );

		const $target = $( $obj.data('target') );
		$target.find('input').attr('name', 'data');

		self.form_dialog({
			title: $target.data('title'),
			elements: [
				{ type: '*', html: $target }
			],
			callback: function(h) {
				var data = h.data;
				if (data == '') {
					$obj.val( dummy_val );
					return $obj.change();
				}
				self.val_for_select( $obj, data );
			}
		});
	}

	// initalize
	this.$body.on('focus', 'select.js-combo', function(evt){
		const $obj = $(evt.target);
		if ($obj.data('init-combo')) return;
		$obj.data('init-combo',  true);

		$obj.data('default', $obj.val() );
		const $opt = $('<option>').attr('value', dummy_val).text( self.msg('other') );
		$obj.append( $opt );
		$obj.change( func );
	});
})

$$.val_for_select = function($sel, val) {
	$sel.val( val );
	if ($sel.val() == val) return;

	const format = $sel.data('format') || '%v';
	const text = format.replace(/%v/g, val);
	const $opt = $('<option>').attr('value', val).text( text );
	$sel.append( $opt );
	$sel.val( val );
	$sel.change();
}
