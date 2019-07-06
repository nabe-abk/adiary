//############################################################################
//■DOM要素への拡張機能の提供 / require initalize
//############################################################################
adiary.dom_funcs = [];
adiary.dom_init  = function(arg) {
	if (typeof(arg) == 'function')
		return this.dom_funcs.push(arg);

	const funcs = this.dom_funcs;
	const $obj  = arg ? arg : this.$body;
	for(var i=0; i<funcs.length; i++)
		funcs[i].call(this, $obj);
}
adiary.init(adiary.dom_init);

//////////////////////////////////////////////////////////////////////////////
//●フォーム値の保存	※表示、非表示よりも前に処理すること
//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R) {
	const self = this;

	$R.findx('input.js-save, select.js-save').each( function(idx, dom) {
		const $obj = $(dom);
		let   id   = $obj.attr("id");
		if (!id) id = 'name=' + $obj.attr("name");
		if (!id) return;

		const type = $obj.attr('type');
		if (type && type.toLowerCase() == 'checkbox') {
			$obj.change( function(evt){
				const $o = $(evt.target);
				Storage.set(id, $o.prop('checked') ? 1 : 0);
			});
			if ( Storage.defined(id) )
				$obj.prop('checked', Storage.get(id) != 0 );
			return;
		}
		$obj.change( function(evt){
			var $o = $(evt.target);
			if ($o.val() == self.select_dummy_value) return;
			Storage.set(id, $o.val());
		});
		const val = Storage.get(id);
		if (! val) return;
		if (dom.tagName == 'SELECT')
			return self.val_for_select( $obj, val );
		
		return $obj.val( val );
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム操作による、enable/disableの自動変更 (js-saveより後)
//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R){
	const $objs = $R.findx('input.js-enable, input.js-disable, select.js-enable, select.js-disable');

	const func = function(evt) {
		let $btn = $(evt.target);
		let $form = $btn.rootfind( $btn.data('target') );

		var id;
		var flag;
		var type=$btn.attr('type');
		if (type) type = type.toLowerCase();
		if (type == 'checkbox') {
			flag = $btn.prop("checked");
		} else if (type == 'radio') {
			if (! $btn.prop("checked")) return;
			flag = $btn.data("state");
			id   = 'name:' + $btn.attr('name');
		} else if (type == 'number' || $btn.data('type') == 'int') {
			var val = $btn.val();
			flag = val.length && val > 0;
		} else {
			flag = ! ($btn.val() + '').match(/^\s*$/);
		}
		// id設定
		if (!id) {
			id = $btn.attr('id') ? $btn.attr('id') : 'name:' + $btn.attr('name');
			if (!id) id = $btn.data('gen-id');
			if (!id) {
				id = 'js-generate-' + Math.floor( Math.random()*0x80000000 );
				$btn.data('gen-id', id);
			}
		}

		// disabled設定判別
		const disable = $btn.hasClass('js-disable');
		for(var i=0; i<$form.length; i++) {
			var $obj = $($form[i]);
			var h    = $obj.data('_jsdisable_list') || {};
			if (flag) h[id] = true;
			     else delete h[id];
			$obj.data('_jsdisable_list', h);
			$obj.prop('disabled', Object.keys(h).length ? disable : !disable);
		}
	}
	// regist
	$objs.change( func );
	$objs.change();
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム操作、クリック操作による表示・非表示の変更
//////////////////////////////////////////////////////////////////////////////
// 一般要素 + input type="checkbox", type="button"
// (例)
// <input type="button" value="ボタン" class="js-switch"  data-target="xxx"
//  data-hide-val="表示する" data-show-val="非表示にする" data-default="show/hide">
//
adiary.toggle = function() {
	const arg = Array.from(arguments);
	arg.unshift(false);
	return this._toggle.apply(this, arg);
}
adiary.toggle_init = function() {
	const arg = Array.from(arguments);
	arg.unshift(true);
	return this._toggle.apply(this, arg);
}
adiary._toggle = function(init, $obj) {
	if ($obj[0].tagName == 'A')
		return true;	// リンククリックそのまま（falseにするとリンクが飛べない）

	const type = $obj[0].tagName == 'INPUT' && $obj.attr('type').toLowerCase();
	let     id = $obj.data('target');
	if (!id) {
		// 子要素のクリックを拾う
		$obj = $obj.parents("[data-target]").first();
		if (!$obj.length) return;
		id = $obj.data('target');
	}

	const $target = $obj.rootfind(id);
	if (!$target.length) return false;

	// スイッチの状態を保存する	ex)タグリスト(tree)
	const storage = $obj.myhasData('save') ? Storage : null;

	// 変更後の状態取得
	var flag;
	if (init && storage && storage.defined(id)) {
		flag = storage.getInt(id) ? true : false;
		if (type == 'checkbox' || type == 'radio') $obj.prop("checked", flag);
	} else if (type == 'checkbox' || type == 'radio') {
		flag = $obj.prop("checked");
	} else if (init && $obj.data('default')) {
		flag = ($obj.data('default') != 'hide');
	} else {
		flag = init ? !$target.is(':hidden') : $target.is(':hidden');
	}

	// 変更後の状態を設定
	if (flag) {
		$obj.addClass('sw-show');
		$obj.removeClass('sw-hide');
		if (init) $target.show();
		     else $target.showDelay();
		if (storage) storage.set(id, '1');

	} else {
		$obj.addClass('sw-hide');
		$obj.removeClass('sw-show');
		if (init) $target.hide();
		     else $target.hideDelay();
		if (storage) storage.set(id, '0');
	}
	if (type == 'button') {
		var val = flag ? $obj.data('show-val') : $obj.data('hide-val');
		if (val != undefined) $obj.val( val );
	}

	if (init) {
		var dom = $obj[0];
		if (dom.tagName == 'INPUT' || dom.tagName == 'BUTTON') return true;
		var span = $('<span>');
		span.addClass('ui-icon switch-icon');
		$obj.prepend(span);
	}
	return true;
}

//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R){
	const self = this;

	const func = function(evt){
		const $obj = $(evt.target);
		if ($obj.attr('type') != "radio")
			return self.toggle($obj);

		const name = $obj.attr('name');
		$('input.js-switch[name=\"' + name + '"]').each(function(idx, dom){
			self.toggle($(dom));
		});
	}

	$R.findx('.js-switch').each( function(idx,dom) {
		var $obj = $(dom);
		var f = self.toggle_init($obj);
		if (f) 	// initalize success
			$obj.on('click', func);
	} );
});

//////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
//////////////////////////////////////////////////////////////////////////////
adiary._load_picker = false;
adiary.dom_init( function($R){
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
//●フォームsubmitチェック
//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R){
	let confirmed;
	const self=this;

	$R.findx('button.js-form-check').on('click', function(evt){
		const $obj  = $(evt.target);
		const $form = $obj.parents('form.js-form-check');
		if (!$form.length) return;
		$form.data('confirm', $obj.data('confirm') );
		$form.data('focus',   $obj.data('focus')   );
		$form.data('button',  $obj);
	});

	$R.findx('form.js-form-check').on('submit', function(evt){
		const $form  = $(evt.target);
		const target = $form.data('target');
		let count=0;
		if (target) {
			count = $form.rootfind( target + ":checked" ).length;
			if (!count) return false;	// ひとつもチェックされてない
		}

		// 確認メッセージがある？
		var confirm = $form.data('confirm');
		if (!confirm) return true;
  		if (confirmed) {
  			confirmed = false;
  			return true;
  		}

		// 確認ダイアログ
		confirm = confirm.replace("%c", count);
		self.confirm({
			html: confirm,
			focus: $form.data('focus')
		}, function(flag) {
			if (!flag) return;
			confirmed = true;
			if ($form.data('button')) return $form.data('button').click();
			$form.submit();
		});
		return false;
	});
});

//////////////////////////////////////////////////////////////////////////////
//●accordion機能
//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R){
	const $accordion = $R.findx('.js-accordion');
	if (!$accordion.length) return;
	$accordion.adiaryAccordion();
});

//////////////////////////////////////////////////////////////////////////////
//●【スマホ】DnDエミュレーション登録
//////////////////////////////////////////////////////////////////////////////
adiary.dom_init( function($R){
	$R.findx('.treebox').dndEmulation();
});

