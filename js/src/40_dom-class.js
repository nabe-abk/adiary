
//############################################################################
//■初期化処理
//############################################################################
var initfunc = [];
window.adiary_init = function(R) {
	for(var i=0; i<initfunc.length; i++)
		initfunc[i](R);
}

var jquery_hook_stop = false;
$(function(){
	var body = $('#body');
	body.append( $('<div>').attr('id', 'popup-image') );
	body.append( $('<div>').attr('id', 'popup-help').addClass('adiary-popup')  );
	body.append( $('<div>').attr('id', 'popup-com') .addClass('adiary-popup')  );
	adiary_init(body);

	//////////////////////////////////////////////////////////////////////
	//●自動でadiary初期化ルーチンが走るようにjQueryに細工する
	//////////////////////////////////////////////////////////////////////
	function hook_function(obj, args) {
		var R = $('<div>');
		for(var i=0; i<args.length; i++) {
			if (!args[i] instanceof jQuery) continue;
			if (typeof args[i] === 'string') continue;
			if (!('findx' in args[i])) continue;
			// hook ok
			adiary_init(args[i]);
		}
	}

	var hooking = false;
	var hooks = ['append', 'prepend', 'before', 'after', 'html', 'replaceWith'];
	function hook(name) {
		var func = $.fn[name];
		$.fn[name] = function() {	// closure
			if (jquery_hook_stop || hooking || this.attr('id') !== 'body' && !this.parents('#body').length)
				return func.apply(this, arguments);
			// hook処理
			hooking = true;
			var r = func.apply(this, arguments);
			// html かつ string の特別処理
			if (name === 'html' && arguments.length === 1 && typeof arguments[0] === 'string') {
				adiary_init(this);
			} else {
				hook_function(this, arguments);
			}
			hooking = false;
			return r;
		}
	}
	for(var i=0; i<hooks.length; i++) {
		hook(hooks[i]);
	}
});

//////////////////////////////////////////////////////////////////////////////
//●画像・ヘルプ・コメントのポップアップ
//////////////////////////////////////////////////////////////////////////////
function easy_popup(evt) {
	var obj = $(evt.target);
	var div = evt.data.div;
	var func= evt.data.func;
	var do_popup = function(evt) {
		if (div.is(":animated")) return;
		func(obj, div);
	  	div.css("left", (SP ? 0 : (evt.pageX +PopupOffsetX)));
	  	div.css("top" ,            evt.pageY +PopupOffsetY);
		div.showDelay();
	};

	var delay = obj.data('delay') != null ? obj.data('delay') : DefaultShowSpeed;
	delay = evt.data.delay != null ? evt.data.delay : delay;

	if (!delay) return do_popup(evt);
	obj.data('timer', setTimeout(function(){ do_popup(evt) }, delay));
}
function easy_popup_out(evt) {
	var obj = $(evt.target);
	var div = evt.data.div;
	if (obj.data('timer')) {
		clearTimeout( obj.data('timer') );
		obj.data('timer', null);
	}
	div.hide();
}

initfunc.push( function(R){
	var popup_img  = $('#popup-image');
	var popup_com  = $('#popup-com');
	var popup_help = $('#popup-help');
	var imgs  = R.findx(".js-popup-img");
	var coms  = R.findx(".js-popup-com");
	var helps = R.findx(".help[data-help]");
	var bhelps= R.findx(".btn-help[data-help]");

	imgs.removeAttr('title');
	imgs.mouseenter( {func: function(obj,div){
		var img = $('<img>');
		img.attr('src', obj.data('img-url'));
		img.addClass('popup-image');
		div.empty();
		div.append( img );
	}, div: popup_img}, easy_popup);

	coms.mouseenter( {func: function(obj,div){
		var num = obj.data('target');
		if (num == '' || num == 0) return div.empty();
		var com = $secure('#c' + num);
		if (!com.length) return div.empty();
		div.html( com.html() );
	}, div: popup_com}, easy_popup);

	var helpfunc = function(obj,div){
		var text = tag_esc_br( obj.data("help") );
		div.html( text );
	};
	 helps.mouseenter( {func: helpfunc, div: popup_help}, easy_popup);

	imgs  .mouseleave({div: popup_img }, easy_popup_out);
	coms  .mouseleave({div: popup_com }, easy_popup_out);
	helps .mouseleave({div: popup_help}, easy_popup_out);

	if (!SP) {
		bhelps.mouseenter( {func: helpfunc, div: popup_help}, easy_popup );
		bhelps.mouseleave({div: popup_help}, easy_popup_out);
	}
});

//////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
  var prev;
  R.findx('.js-info[data-info], .js-info[data-url]').click( function(evt){
	if (evt.target == prev) return;	// 連続クリック防止
	prev=evt.target;

	var obj = $(evt.target);
	var div = $('<div>');
	var div2= $('<div>');	// 直接 div にクラスを設定すると表示が崩れる
	var text;
	div.attr('title', obj.data("title") || "Infomataion" );
	div2.addClass(obj.data("class"));
	div.empty();
	div.append(div2);
	if (obj.data('info')) {
		var text = tag_esc_br( obj.data("info") );
		div2.html( text );
		div.dialog({ width: DialogWidth, close: close_func });
		return;
	}
	var url = obj.data("url");
	div2.load( url, function(){
		div2.text( div2.text().replace(/\n*$/, "\n\n") );
		div.dialog({ width: DialogWidth, height: 320, close: close_func });
	});
  })
  function close_func(){
	prev = null;
  }
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム要素の全チェック
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
  R.findx('input.js-checked').click( function(evt){
	var obj = $(evt.target);
	var target = obj.data( 'target' );
	obj.rootfind(target).prop("checked", obj.is(":checked"));
  })
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム値の保存	※表示、非表示よりも前に処理すること
//////////////////////////////////////////////////////////////////////////////
var opt_dummy_value = "\e\f\e\f\b\n";
initfunc.push( function(R) {
	R.findx('input.js-save, select.js-save').each( function(idx, dom) {
		var obj = $(dom);
		var id  = obj.attr("id");
		if (!id) id = 'name=' + obj.attr("name");
		if (!id) return;

		var type = obj.attr('type');
		if (type && type.toLowerCase() == 'checkbox') {
			obj.change( function(evt){
				var obj = $(evt.target);
				Storage.set(id, obj.prop('checked') ? 1 : 0);
			});
			if ( Storage.defined(id) )
				obj.prop('checked', Storage.get(id) != 0 );
			return;
		}
		obj.change( function(evt){
			var obj = $(evt.target);
			if (obj.val() == opt_dummy_value) return;
			Storage.set(id, obj.val());
		});
		var val = Storage.get(id);
		if (! val) return;
		if (dom.tagName != 'SELECT') return obj.val( val );

		// selectで記録されいてる値がない時は追加する
		set_or_append_option( obj, val );
	});
});
function set_or_append_option(sel, val) {
	sel.val( val );
	if (sel.val() == val) return;

	var format = sel.data('format') || '%v';
	var text = format.replace(/%v/g, val);
	var opt  = $('<option>').attr('value', val).text( text );
	sel.append( opt );
	sel.val( val );
	sel.change();
}

//////////////////////////////////////////////////////////////////////////////
//●フォーム操作による、enable/disableの自動変更 (js-saveより後)
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	let objs = R.findx('input.js-enable, input.js-disable, select.js-enable, select.js-disable');
	function btn_evt(evt) {
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
			var obj = $($form[i]);
			var h   = obj.data('_jsdisable_list') || {};
			if (flag) h[id] = true;
			     else delete h[id];
			obj.data('_jsdisable_list', h);
			obj.prop('disabled', Object.keys(h).length ? disable : !disable);
		}
	}
	objs.change( btn_evt );
	objs.change();
});


//////////////////////////////////////////////////////////////////////////////
//●複数チェックボックスフォーム、全選択、submitチェック
//////////////////////////////////////////////////////////////////////////////
var confrim_button;
initfunc.push( function(R){
  R.findx('input.js-form-check, button.js-form-check').click( function(evt){
	var obj = $(evt.target);
	confrim_button = obj;
	var form = obj.parents('form.js-form-check');
	if (!form.length) return;
	form.data('confirm', obj.data('confirm') );
	form.data('focus',   obj.data('focus')   );
  })
});

initfunc.push( function(R){
  var confirmed;
  R.findx('form.js-form-check').submit( function(evt){
	var form = $(evt.target);
	var target = form.data('target');	// 配列
	var c = false;
	if (target) {
		c = form.rootfind( target + ":checked" ).length;
		if (!c) return false;	// ひとつもチェックされてない
	}

	// 確認メッセージがある？
	var confirm = form.data('confirm');
	if (!confirm) return true;
  	if (confirmed) { confirmed=false; return true; }

	// 確認ダイアログ
	if (c) confirm = confirm.replace("%c", c);
	var btn = confrim_button;
	confrim_button = false;
	my_confirm({
		html: confirm,
		focus: form.data('focus')
	}, function(flag) {
		if (!flag) return;
		confirmed = true;
		if (btn) return btn.click();
		form.submit();
	});
	return false;
  })
});

//////////////////////////////////////////////////////////////////////////////
//●select boxに選択肢追加（コンボボックス）
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R) {
	function append_form(evt) {
		var obj  = $(evt.target);
		var val  = obj.val();
		if (val != opt_dummy_value) return obj.data('default', val);
		obj.val( obj.data('default') );

		var tar  = $( obj.data('target') );
		var form = { title: tar.data('title') };
		form.elements = [{
			type: '*',
			html: tar
		}];
		tar.find('input').attr('name', 'data');
		form.callback = function(h){
			var data = h.data;
			if (data == '') {
				obj.val( opt_dummy_value );
				return obj.change();
			}
			set_or_append_option( obj, data );
		};
		form_dialog(form);
	}
	R.findx('select.js-combo').each( function(idx, dom) {
		var obj = $(dom);
		var opt = $('<option>').attr('value',opt_dummy_value).text( $('#ajs-other').text() );
		obj.append( opt );
		obj.data('default', obj.val());
		obj.change( append_form );
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム操作、クリック操作による表示・非表示の変更
//////////////////////////////////////////////////////////////////////////////
// 一般要素 + input type="checkbox", type="button"
// (例)
// <input type="button" value="ボタン" class="js-switch" data-target="xxx"
//  data-switch-speed="500" data-hide-val="表示する" data-show-val="非表示にする">
//  data-default="show/hide">
initfunc.push( function(R){
	function display_toggle(btn, init) {
		if (btn[0].tagName == 'A') return true;	// リンククリックは無視
		var type = btn[0].tagName == 'INPUT' && btn.attr('type').toLowerCase();
		var id = btn.data('target');
		if (!id) {
			// 子要素のクリックを拾うための処理
			btn = find_parent(btn, function(par){ return par.attr("data-target") });
			if (!btn) return;
			id = btn.data('target');
		}
		var target = btn.rootfind(id);
		if (!target.length || !target.is) return false;
		var speed  = btn.data('switch-speed');
		speed = (speed === undefined) ? DefaultShowSpeed : parseInt(speed);
		speed = init ? 0 : speed;

		// スイッチの状態を保存する
		var storage = btn.data('save') ? Storage : false;

		// 変更後の状態取得
		var flag;
		if (init && storage && storage.defined(id)) {
			flag = storage.getInt(id) ? true : false;
			if (type == 'checkbox' || type == 'radio') btn.prop("checked", flag);
		} else if (type == 'checkbox' || type == 'radio') {
			flag = btn.prop("checked");
		} else if (init && btn.data('default')) {
			flag = (btn.data('default') != 'hide');
		} else {
			flag = init ? !target.is(':hidden') : target.is(':hidden');
		}

		// 変更後の状態を設定
		if (flag) {
			btn.addClass('sw-show');
			btn.removeClass('sw-hide');
			if (init) target.show();
			     else target.show(speed);
			if (storage) storage.set(id, '1');

		} else {
			btn.addClass('sw-hide');
			btn.removeClass('sw-show');
			if (init) target.hide();
			     else target.hide(speed);
			if (storage) storage.set(id, '0');
		}
		if (type == 'button') {
			var val = flag ? btn.data('show-val') : btn.data('hide-val');
			if (val != undefined) btn.val( val );
		}

		if (init) {
			var dom = btn[0];
			if (dom.tagName == 'INPUT' || dom.tagName == 'BUTTON') return true;
			var span = $('<span>');
			span.addClass('ui-icon switch-icon');
			btn.prepend(span);
		}
		return true;
	}
	R.findx('.js-switch').each( function(idx,ele) {
		var obj = $(ele);
		var f = display_toggle(obj, true);	// initalize
		if (f) obj.click( function(evt){
			if (obj.attr('type') != "radio") return display_toggle($(evt.target), false);

			const name = obj.attr('name');
			$('input.js-switch[name=\"' + name + '"]').each(function(idx, dom){
				display_toggle($(dom), false);
			});
		});
	} );
});

//////////////////////////////////////////////////////////////////////////////
//●input[type="text"]などで enter による submit 停止
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('input.no-enter-submit, form.no-enter-submit input').keypress( function(ev){
		if (ev.which === 13) return false;
		return true;
	});
});

//////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
//////////////////////////////////////////////////////////////////////////////
var load_picker;
initfunc.push( function(R){
	var cp = R.findx('input.color-picker');
	if (!cp.length) return;

	cp.each(function(i,dom){
		var obj = $(dom);
		var box = $('<span>').addClass('colorbox');
		obj.before(box);
		var col = obj.val();
		if (col.match(/^#[\dA-Fa-f]{6}$/))
			box.css('background-color', col);
	});
	var initfunc = function(){
		cp.each(function(idx,dom){
			var obj = $(dom);
			obj.ColorPicker({
				onSubmit: function(hsb, hex, rgb, _el) {
					var el = $(_el);
					el.val('#' + hex);
					el.ColorPickerHide();
					var prev = el.prev();
					if (! prev.hasClass('colorbox')) return;
					prev.css('background-color', '#' + hex);
					obj.change();
				},
				onChange: function(hsb, hex, rgb) {
					var prev = obj.prev();
					if (! prev.hasClass('colorbox')) return;
					prev.css('background-color', '#' + hex);
					var func = obj.data('onChange');
					if (func) func(hsb, hex, rgb);
				}
			});
			$('.colorpicker').draggable({
				cancel: ".colorpicker_color, .colorpicker_hue, .colorpicker_submit, input, span"
			});
			obj.ColorPickerSetColor( obj.val() );
		});
		cp.on('keyup', function(evt){
			$(evt.target).ColorPickerSetColor(evt.target.value);
		});
		cp.on('keydown', function(evt){
			if (evt.keyCode != 27) return;
			$(evt.target).ColorPickerHide();
		});
	};

	if (cp.ColorPicker) return initfunc();
	if (load_picker) return load_picker.push(cp);
	load_picker = cp;

	// color pickerのロード
	var dir = ScriptDir + 'colorpicker/';
	prepend_css(dir + 'css/colorpicker.css');
	load_script(dir + "colorpicker.js", initfunc);
});

//////////////////////////////////////////////////////////////////////////////
//●input[type="text"], input[type="password"]の自由リサイズ
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('input').each( function(idx,dom){
		if (dom.type != 'text'
		 && dom.type != 'search'
		 && dom.type != 'tel'
		 && dom.type != 'url'
		 && dom.type != 'email'
		 && dom.type != 'password'
		) return;
		set_input_resize($(dom));
	} )

function set_input_resize(obj, flag) {
	if (obj.parents('.color-picker, .colorpicker').length) return;
	if (obj.hasClass('no-resize')) return;

	// 非表示要素は最初にhoverされた時に処理する
	if (!flag && obj.is(":hidden")) {
		var func = function(){
			obj.off('mouseenter', func);
			set_input_resize(obj, 1);
		};
		obj.on('mouseenter', func);
		return;
	}

	// テーマ側でのリサイズ機能の無効化手段なので必ず先に処理すること
	var span = $('<span>').addClass('resize-parts');
	if(span.css('display') == 'none') return;

	// 基準位置とする親オブジェクト探し
	var par = find_parent(obj, function(par){
		return par.css('display') == 'table-cell' || par.css('display') == 'block'
	});
	if (!par) return;
	if(par.css('display') == 'table-cell') {
		// テーブルセルの場合は、セル全体をdiv要素の中に移動する
		var cell  = par;
		var child = cell.contents();
		par = $('<div>').css('position', 'relative');
		child.each( function(idx,dom) {
			$(dom).detach();
			par.append(dom);
		});
		cell.append(par);
	} else {
		par.css('position', 'relative');
	}

	par.append(span);
	// append してからでないと span.width() が決まらないブラウザがある
	span.css("left", obj.position().left +  obj.outerWidth() - span.width());
	span.css("top",  obj.position().top );
	span.css("height", obj.outerHeight() );

	// 最小幅算出
	var width = obj.width();
	var min_width = parseInt(span.css("z-index")) % 1000;
	if (min_width < 16) min_width=16;
	if (min_width > width) min_width=width;
	span.mousedown( function(evt){ evt_mousedown(evt, obj, min_width) });
}

function evt_mousedown(evt, obj, min_width) {
	if (!obj.parents('.ui-dialog-content').length
	  && obj.parents('.ui-draggable, .ui-sortable-handle').length) return;

	var span = $(evt.target);
	var body = $('#body');
	span.data('drag-X', evt.pageX);
	span.data("obj-width", obj.width() );
	span.data("span-left", span.css('left') );

	var evt_mousemove = function(evt) {
		var offset = evt.pageX - parseInt(span.data('drag-X'));
		var width  = parseInt(span.data('obj-width')) + offset;
		if (width<min_width) {
			width  = min_width;
			offset = min_width - parseInt(span.data('obj-width'));
		}
		// 幅設定
		obj.width(width);
		span.css("left", parseInt(span.data('span-left')) + offset);
	};
	var evt_mouseup = function(evt) {
		body.unbind('mousemove', evt_mousemove);
		body.unbind('mouseup',   evt_mouseup);
	}

	// イベント登録
	body.mousemove( evt_mousemove );
	body.mouseup  ( evt_mouseup );
}
///
});

//////////////////////////////////////////////////////////////////////////////
//●input, textareaのフォーカスクラス設定  ※リサイズ設定より後に行うこと
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('form input, form textarea').each( function(idx,dom){
		if (dom.tagName != 'TEXTAREA'
		 && dom.type != 'text'
		 && dom.type != 'search'
		 && dom.type != 'tel'
		 && dom.type != 'url'
		 && dom.type != 'email'
		 && dom.type != 'password'
		) return;

		var obj = $(dom);
		// firefoxでなぜかうまく動かないバグ
		var par = find_parent(obj, function(par){ return par.css('display') == 'table-cell' });
		if (!par) return;

		obj.focus( function() {
			par.addClass('focus');
		});
		obj.blur ( function() {
			par.removeClass('focus');
		});
	} )
});

//////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	var $ta = R.findx('textarea');

	$ta.focus( function(evt){
		var $obj = $(evt.target);
		$obj.data('_tab_stop', true);
	});
	$ta.keydown( function(evt){
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
		insert_to_textarea(evt.target, "\t");
	});
});

//////////////////////////////////////////////////////////////////////////////
//●file upload button
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('button[data-target]').click( function(evt){
		var $obj = $(evt.target);
		var $tar = $obj.rootfind( $obj.data('target') );
		if (! $tar.length ) return;

		$tar.click();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●なんでもsubmitボタン
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('.js-submit').click( function(evt){
		var form = $(evt.target).parents('form');
		$(form[0]).submit();
	});
});

//////////////////////////////////////////////////////////////////////////////
//●accordion機能
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	const obj = R.findx('.js-accordion');
	if (!obj.length) return;

	obj.find("h3").each(function(idx,dom) {
		var $obj = $(dom);
		var $div = $(dom).next();
		if ($div[0].tagName != "DIV") return;
		$div.hide();
		$obj.click(function(evt){
			$div.toggle( DefaultShowSpeed );
		});
	});
});

//////////////////////////////////////////////////////////////////////////////
//●FormDataが使用できないブラウザで、ファイルアップ部分を無効にする
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	if (window.FormData) return;
	R.findx('.js-fileup').prop('disabled', true);
});

//////////////////////////////////////////////////////////////////////////////
//●要素の位置を変更する
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('[data-move]').each(function(idx,dom) {
		var obj = $(dom);
		obj.detach();
		var target = obj.rootfind(obj.data('move'));
		var type   = obj.data('move-type');
		     if (type == 'prepend') target.prepend(obj);
		else if (type == 'append')  target.append (obj);
		else if (type == 'before')  target.before(obj);
					else target.after(obj);
	});
});

//////////////////////////////////////////////////////////////////////////////
//●bodyにクラスを追加する
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('[data-body-class]').each(function(idx,dom) {
		var cls = $(dom).data('body-class');
		$('#body').addClass(cls);
	});
});

//////////////////////////////////////////////////////////////////////////////
//●スマホ用の処理。hover代わり
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	var ary = R.findx('.js-alt-hover li ul').parent();
	ary.addClass('node');
	ary = ary.children('a');
	ary.click(function(evt) {
		var obj = $(evt.target).parent();
		if (obj.hasClass('open')) {
			obj.removeClass('open');
			obj.find('.open').removeClass('open')
		} else
			obj.addClass('open');
		// リンクを飛ぶ処理をキャンセル
		evt.preventDefault();
	});
	ary.dblclick(function(evt) {
		location.href = $(evt.target).attr('href');
	});
	// タブルタップでリンクを開く
	R.findx('.js-alt-hover li a').on('mydbltap', function(evt) {
		location.href = $(evt.target).attr('href');
	});
});

//////////////////////////////////////////////////////////////////////////////
//●スマホ用のDnDエミュレーション登録
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('.treebox').dndEmulation();
});


//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●要素の幅を中身を参照して自動設定する
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.findx('.js-ddmenu-free-item-width').each(function(idx,dom) {
		var ch = $(dom).children('ul').children();
		for(var i=0; i<ch.length; i++) {
			var li = $(ch[i]);
			var a  = li.children('a');
			a.css('display', 'inline-block');
			var w = Math.ceil( a.outerWidth() );
			li.width( w );
			a.css('display', 'block');
		}
	});
	R.findx('.js-auto-width').each(function(idx,dom) {
		var obj = $(dom);
		var ch = obj.children();
		var width = 0;
		for(var i=0; i<ch.length; i++) {
			width += Math.ceil( $(ch[i]).outerWidth() );
		}
		width += 1;
		obj.width(width);
	});
});

