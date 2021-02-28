//############################################################################
//■DOM要素への拡張機能の提供 / require initalize
//############################################################################
$$.dom_funcs = [];
$$.dom_init  = function(arg) {
	if (typeof(arg) == 'function')
		return this.dom_funcs.push(arg);

	const funcs = this.dom_funcs;
	const $obj  = arg ? arg : this.$body;
	for(var i=0; i<funcs.length; i++)
		funcs[i].call(this, $obj);
}
$$.init($$.dom_init);

//////////////////////////////////////////////////////////////////////////////
// ajax form
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R) {
	const self=this;
	const func = function($obj){
		$obj.find('.error').removeClass('error');

		const gen  = $obj.data('generator');
		const data = (typeof(gen) === 'function') ? gen($obj) : (function(){
			const $infile = $obj.find('input[type="file"]');
			return $infile.length ? (new FormData($obj[0])) : $obj.serialize();
		})();

		if ($obj.data('js-ajax-stop')) return;
		if ($('.ui-overlay').length)   return;	// dialog viewing
		$obj.data('js-ajax-stop', true);
		const $btns = $obj.find('button[type!="button"]');
		$btns.prop('disabled', true);

		self.send_ajax({
			data:	data,
			success: function(h) {
				const success = $obj.data('success');
				const url = $obj.data('url');
				if (typeof(success) === 'function') return success(h);
				if (typeof(success) === 'string' && success != '') {
					return self.show_dialog(success, function(){
						if (url) window.location = url;
					});
				}
				if (url) window.location = url;
			},
			error: function(h) {
				const error = $obj.data('error');
				if (typeof(error) === 'function') return error(h);

				if (!h || !h.errs) return;
				const e = h.errs;
				for(let k in e) {
					if (k == '_order') continue;

					// with number?
					const ma  = k.match(/^(.*)#(\d+)$/);
					const num = ma ? ma[2] : undefined;
					k = ma ? ma[1] : k;
					try {
						let $x = $obj.find('[name="' + k+ '"], [data-name="' + k + '"]');
						if (num) $x = $($x[num-1]);
						$x.addClass('error');
					} catch(e) {
						console.error(e);
					}
				}
			},
			error_callback: function(){
				const reject = $obj.data('reject');
				if (typeof(reject) === 'function') return reject();
			},
			complite: function(h) {
				$obj.data('js-ajax-stop', false);
				$btns.prop('disabled', false);
			}
		});
		return false;
	};

	$R.find('form.js-ajax').on('submit', function(evt) {
		const $obj = $(evt.target);
		const callback = function(){ func($obj) };

		const checker  = $obj.data('checker');
		if (typeof(checker) === 'function') {
			if (! checker($obj, callback)) return false;
		}
		if ($obj.hasClass('js-check-form')) {
			$obj.data('submit-func', func);
			return false;
		}
		func($obj);
		return false;
	});
});

//////////////////////////////////////////////////////////////////////////////
// フォーム値の保存	※表示、非表示よりも前に処理すること
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R) {
	const self = this;

	$R.findx('input.js-save, select.js-save').each( function(idx, dom) {
		const $obj = $(dom);
		const type = $obj[0].type;

		let id = type != 'radio' && $obj.attr("id");
		if (!id) id = 'name=' + $obj.attr("name");
		if (!id) return;

		if (type == 'checkbox') {
			$obj.change( function(evt){
				const $o = $(evt.target);
				self.Storage.set(id, $o.prop('checked') ? 1 : 0);
			});
			if ( self.Storage.defined(id) )
				$obj.prop('checked', self.Storage.get(id) != 0 );
			return;
		}
		if (type == 'radio') {
			const val = $obj.attr('value');
			$obj.change( function(evt){
				const $o = $(evt.target);
				self.Storage.set(id, val);
			});
			if ( self.Storage.defined(id) && val == self.Storage.get(id)) {
				$obj.prop('checked', 1);
			}
			return;
		}
		$obj.change( function(evt){
			var $o = $(evt.target);
			if ($o.val() == self.select_dummy_value) return;
			self.Storage.set(id, $o.val());
		});
		const val = self.Storage.get(id);
		if (! val) return;
		if (dom.tagName == 'SELECT')
			return self.val_for_select( $obj, val );
		
		return $obj.val( val );
	});
});

//////////////////////////////////////////////////////////////////////////////
// フォーム操作による、enable/disableの自動変更 (js-saveより後)
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	const $objs = $R.findx('input.js-enable, input.js-disable, select.js-enable, select.js-disable');

	let   init;
	const func = function(evt) {
		const $btn = $(evt.target);
		const $tar = $btn.rootfind( $btn.data('target') );

		const type = $btn[0].type;

		// radio button with data-state="0" or "1"
		if (type == 'radio') {
			if ($btn.prop("disabled") || !$btn.prop("checked")) return;
			let flag = $btn.data("state");
			if ($btn.hasClass('js-enable')) flag=!flag;
			$tar.prop('disabled', flag);
			return;
		}

		let flag;
		if (type == 'checkbox') {
			flag = !$btn.prop("disabled") && $btn.prop("checked");
		} else if (type == 'number' || $btn.data('type') == 'int') {
			var val = $btn.val();
			flag = val.length && val > 0;
		} else {
			flag = ! ($btn.val() + '').match(/^\s*$/);
		}

		// 変化してるか確認
		if (!init && $btn.data('_flag') === flag) return;
		$btn.data('_flag', flag);

		// disabled設定判別
		const counter = $btn.hasClass('js-disable') ? '_disable_c' :  '_enable_c';
		const add     = flag ? 1 : (init ? 0 : -1);
		$tar.each(function(idx,dom){
			const $obj = $(dom);
			$obj.data(counter, ($obj.data(counter) || 0) + add);

			const diff = ($obj.data('_disable_c') || 0) - ($obj.data('_enable_c') || 0)
				   + ($btn.hasClass('js-enable') ? 0.1 : 0);

			$obj.prop('disabled', diff>0);
		});
	}
	// regist
	$objs.change( func );
	init = true;
	$objs.change();
	init = false;
});

//////////////////////////////////////////////////////////////////////////////
// フォーム操作、クリック操作による表示・非表示の変更
//////////////////////////////////////////////////////////////////////////////
// 一般要素 + input type="checkbox", type="button"
// (例)
// <input type="button" value="ボタン" class="js-switch"  data-target="xxx"
//  data-delay="300"
//  data-hide-val="表示する" data-show-val="非表示にする" data-negative="1">
//
$$.toggle = function() {
	const arg = Array.from(arguments);
	arg.unshift(false);
	return this._toggle.apply(this, arg);
}
$$.toggle_init = function() {
	const arg = Array.from(arguments);
	arg.unshift(true);
	return this._toggle.apply(this, arg);
}
$$._toggle = function(init, $obj) {
	if ($obj[0].tagName == 'A')
		return true;	// リンククリックそのまま（falseにするとリンクが飛べない）

	// append switch icon
	if (init && $obj[0].tagName != 'INPUT' && $obj[0].tagName != 'BUTTON') {
		const span = $('<span>');
		span.addClass('ui-icon switch-icon');
		$obj.prepend(span).addClass('sw-show');
	}

	const type = $obj[0].tagName == 'INPUT' && $obj[0].type;
	let   tar  = $obj.data('target');
	if (!tar) {
		// 子要素のクリックを拾う
		$obj = $obj.parents(".js-switch").first();
		if (!$obj.length) return;
		tar = $obj.data('target');
	}
	const $target = $obj.rootfind(tar);
	if (!$target.length) return false;

	// スイッチの状態を保存する	ex)タグリスト(tree)
	const storage = $obj.existsData('save') ? this.Storage : null;

	// 変更後の状態取得
	const id = $obj.attr('id') || $obj.attr('name') || tar;
	let flag;
	if (init && storage && storage.defined(id)) {
		flag = storage.getInt(id) ? true : false;
		if (type == 'checkbox' || type == 'radio') $obj.prop("checked", flag);
	} else if (type == 'checkbox' || type == 'radio') {
		flag = $obj.prop("checked");
	} else {
		flag = init ? !$target.is(':hidden') : $target.is(':hidden');
	}
	if ($obj.data('negative')) flag = !flag;

	// show speed
	let delay = $obj.data('delay');
	if (delay === undefined || delay === '') delay = this.DefaultShowSpeed;

	// first mode
	if (delay==0 && $obj.data('first')) {
		const css_id = '--css--' + id.replace(/[^\w\-]/g, '-');
		let   $css   = $('#' + css_id);
		if (!$css.length) {
			$css = $('<style>').attr('id', css_id);
			$('head').append($css);
		}
		$css.text( flag ? '' : tar + '{ display: none; }' );
		return true;
	}

	// set state
	if (flag) {
		$obj.addClass('sw-show');
		$obj.removeClass('sw-hide');
		if (init) $target.show();
		     else $target.show(delay);
		if (storage) storage.set(id, '1');

	} else {
		$obj.addClass('sw-hide');
		$obj.removeClass('sw-show');
		if (init) $target.hide();
		     else $target.hide(delay);
		if (storage) storage.set(id, '0');
	}
	if (type == 'button') {
		const val = flag ? $obj.data('show-val') : $obj.data('hide-val');
		if (val != undefined) $obj.val( val );
	}
	return true;
}

//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	const self = this;

	const func = function(evt){
		const $obj = $(evt.target);
		if ($obj[0].type != "radio")
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
			$obj.on(dom.tagName == 'INPUT' ? 'change' : 'click', func);
	} );
});

//////////////////////////////////////////////////////////////////////////////
// フォームsubmitチェック
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	let confirmed;
	const self=this;

	$R.findx('button.js-check-form').on('click', function(evt){
		const $obj  = $(evt.target);
		const $form = $obj.parents('form.js-check-form');
		if (!$form.length) return;
		$form.data('confirm', $obj.data('confirm') );
		$form.data('focus',   $obj.data('focus')   );
		$form.data('button',  $obj);
	});

	$R.findx('form.js-check-form').on('submit', function(evt){
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

			const func = $form.data('submit-func');
			if (typeof(func) == 'function')
				return func($form);
			$form.submit();
		});
		return false;
	});
});

//////////////////////////////////////////////////////////////////////////////
// accordion機能
//////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	const $accordion = $R.findx('.js-accordion');
	if (!$accordion.length) return;
	$accordion.adiaryAccordion();
});

