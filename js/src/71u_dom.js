//////////////////////////////////////////////////////////////////////////////
//●画像・コメントのポップアップ
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
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
});

//////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
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
//【スマホ】ドロップダウンメニューでの hover の代わり
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	function open_link(evt) {
		location.href = $(evt.target).attr('href');
	}

	this.$body.on('click', '.js-alt-hover li > a', function(evt) {
		const $obj = $(evt.target).parent();
		if (!$obj.children('ul').length) return true;

		if ($obj.hasClass('open')) {
			$obj.removeClass('open');
			$obj.find('.open').removeClass('open')
		} else {
			$obj.addClass('open');
		}
		// リンクをキャンセル。"return false" ではダブルクリックイベントが発生しない
		evt.preventDefault();

		// dbltapイベントを登録
		if ($obj.data('_reg_dbltap')) return;
		$obj.data('_reg_dbltap', true);
		$obj.on('dblclick', open_link);
		$obj.on('mydbltap', open_link);
	});
});

//////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
//////////////////////////////////////////////////////////////////////////////
$$._load_picker = false;
$$.dom_init( function($R){
	const $cp = $R.findx('input.color-picker');
	if (!$cp.length) return;

	$cp.each(function(i,dom){
		const $obj = $(dom);
		const $box = $('<span>').addClass('colorbox');
		$obj.before($box);
		const color = $obj.val();
		if (color.match(/^#[\dA-Fa-f]{6}$/))
			$box.css('background-color', color);
	});

	// color pickerのロード
	var dir = this.ScriptDir + 'colorpicker/';
	this.prepend_css(dir + 'css/colorpicker.css');
	this.load_script(dir + "colorpicker.js", function(){

		$cp.each(function(idx,dom){
			var $obj = $(dom);
			$obj.ColorPicker({
				onSubmit: function(hsb, hex, rgb, _el) {
					var $el = $(_el);
					$el.val('#' + hex);
					$el.ColorPickerHide();
					var $prev = $el.prev();
					if (! $prev.hasClass('colorbox')) return;
					$prev.css('background-color', '#' + hex);
					$obj.change();
				},
				onChange: function(hsb, hex, rgb) {
					var $prev = $obj.prev();
					if (! $prev.hasClass('colorbox')) return;
					$prev.css('background-color', '#' + hex);
					var func = $obj.data('onChange');
					if (func) func(hsb, hex, rgb);
				}
			});
			$obj.ColorPickerSetColor( $obj.val() );
		});
		$cp.on('keyup', function(evt){
			$(evt.target).ColorPickerSetColor(evt.target.value);
		});
		$cp.on('keydown', function(evt){
			if (evt.keyCode != 27) return;
			$(evt.target).ColorPickerHide();
		});

		// if loaded jQuery UI, color picker draggable
		$R.rootfind('.colorpicker').adiaryDraggable({
			cancel: ".colorpicker_color, .colorpicker_hue, .colorpicker_submit, input, span"
		})
	});
});

//////////////////////////////////////////////////////////////////////////////
//●【スマホ】DnDエミュレーション登録
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	$R.findx('.treebox').dndEmulation();
});


