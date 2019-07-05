//############################################################################
//■DOM要素への拡張機能の提供
//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●画像・ヘルプ・コメントのポップアップ
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
	const $popup_div = $('<div>').addClass('adiary-popup');
	this.$popup_div  = $popup_div;
	this.$body.append( $popup_div );
	const self = this;
	const func = function(evt){ self.popup(evt) }

	this.$body.on('mouseover', '.js-popup-img', {
		func: function($obj, $div) {
			const $img = $('<img>');
			$img.attr('src', $obj.data('img-url'));
			$div.empty();
			$div.attr('id', 'popup-image');
			$div.append( img );
		}
	}, func);
	$('.js-popup-img').removeAttr('title');	// remove title attr popup

	this.$body.on('mouseover', '.js-popup-com', {
		func: function($obj, $div){
			var num = $obj.data('target');
			if (num == '' || num == 0) return $div.empty();

			var $com = $secure('#c' + num);
			if (!$com.length) return $div.empty();

			$div.attr('id', 'popup-com');
			$div.html( $com.html() );
		}
	}, func);

	// btn-help はスマホでは無効にする
	const help = '.help[data-help]' + (SP ? '' : ', .btn-help[data-help]');
	this.$body.on('mouseover', help, {
		func: function($obj, $div){
			var text = self.tag_esc_br( $obj.data("help") );
			$div.attr('id', 'popup-help');
			$div.html( text );
		}
	}, func);
});

//////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
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
//●input[type="text"]などで enter による submit 停止
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
	this.$body.on('keypress', 'input.no-enter-submit, form.no-enter-submit input', function(evt){
		if (evt.which === 13) return false;
		return true;
	});
});

//////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
	const self=this;

	this.$body.on('focus', 'textarea', function(evt){
		var $obj = $(evt.target);
		$obj.data('_tab_stop', true);
	});

	this.$body.on('keydown', 'textarea', function(evt){
		var $obj = $(evt.target);
		if ($obj.prop('readonly') || $obj.prop('disabled')) return;

		// ESC key
		if (evt.keyCode == 27) return $obj.data('_tab_stop', true);

		// フォーカス直後のTABは遷移させる
		if ($obj.data('_tab_stop')) {
			$obj.data('_tab_stop', false);
			return;
		}
		if (evt.shiftKey || evt.keyCode != 9) return;

		evt.preventDefault();
		self.insert_to_textarea(evt.target, "\t");
	});
});

//////////////////////////////////////////////////////////////////////////////
//●file upload button （input type="file"を間接クリックする）
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
	this.$body.on('click', 'button.js-file-btn', function(evt) {
		const $obj = $(evt.target);
		const $tar = $obj.rootfind( $obj.data('target') );
		if (! $tar.length ) return;

		$tar.click();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム要素の全チェック
//////////////////////////////////////////////////////////////////////////////
adiary.init( function(){
	this.$body.on('click', 'input.js-checked', function(evt){
		var $obj = $(evt.target);
		var target = $obj.data( 'target' );
		$obj.rootfind(target).prop("checked", $obj.is(":checked"));
	});
});

//////////////////////////////////////////////////////////////////////////////
//●コンボボックス / <select class="js-combo">
//////////////////////////////////////////////////////////////////////////////
adiary.select_dummy_value = "\e\f\e\f\b\n";
adiary.init( function(){
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

adiary.val_for_select = function($sel, val) {
	$sel.val( val );
	if ($sel.val() == val) return;

	const format = $sel.data('format') || '%v';
	const text = format.replace(/%v/g, val);
	const $opt = $('<option>').attr('value', val).text( text );
	$sel.append( $opt );
	$sel.val( val );
	$sel.change();
}

