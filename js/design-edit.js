//############################################################################
// adiaryデザイン編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';
//////////////////////////////////////////////////////////////////////////////
// ●モジュール情報のロード
//////////////////////////////////////////////////////////////////////////////
var $f;
var $fsec;
$(function(){
	var iframe = $('#iframe');
	var module_data_id   = '#design-modules-data';
	var module_selector  = '[data-module-name]';
	var not_sortable     = ':not([data-fix])';

	var btn_save = $('#save-btn');
	var btn_close_title   = $('#btn-close').text()   || 'delete';
	var btn_setting_title = $('#btn-setting').text() || 'setting';
	var btn_cssset_title  = $('#btn-css-setting').text() || 'design setting';

	var modules = [];	// 各モジュールを取得し保存
	var mod_list= [];
	var data = $secure(module_data_id);
	data.children(module_selector).each( function(idx,_obj){
		var obj  = $(_obj);
		var name = obj.data('module-name');
		obj.detach();
		if (name.match(/[^\w\-]/)) return;
		modules[name] = obj;
		mod_list.push(name);
	});

//////////////////////////////////////////////////////////////////////////////
// ●iframeの自動リサイズ
//////////////////////////////////////////////////////////////////////////////
	var body = $('#body');
	iframe_resize();
	$(window).resize( iframe_resize );
	function iframe_resize() {
		var h = body.height() - iframe.position().top;
		$('#debug-msg').html(body.height() + ' / ' + iframe.position().top);
		iframe.css('height', h);
	}


//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
iframe.on('load', function(){
	var if_cw = iframe[0].contentWindow;
	    $f    = iframe[0].contentWindow.$;		// global
	    $fsec = iframe[0].contentWindow.$secure;	// global
	var side_a = $fsec('#side-a');
	var side_b = $fsec('#side-b');
	var f_main = $fsec('#main-first');
	var f_head = $fsec('#header');

	// フレーム内check
	if ($f('#body').hasClass('system-mode')) {
		btn_save.prop('disabled', true);
		return;
	}
	btn_save.prop('disabled', false);

	// モジュールにボタン追加
	$f(module_selector).each( function(idx,obj){
		init_module( $(obj) );
	});

	// sortable設定
	side_a.addClass('connectedSortable');
	side_b.addClass('connectedSortable');
	var selector = '>' + module_selector + not_sortable;
	side_a.sortable({ items: selector, connectWith: ".connectedSortable" });
	side_b.sortable({ items: selector, connectWith: ".connectedSortable" });
	f_main.sortable({ items: selector + ', #article, #articles' });
	f_head.sortable({ items: selector });

	// 記事本体
	var artbody = $f('#article-body>div.body');
	var arthead = artbody.children('div.body-header');
	var artfoot = artbody.children('div.body-footer');
	var artmain = artbody.children('div.body-main');
	artfoot.sortable({ items: selector });
	if (artmain.height() > 300)
		artmain.css({
			'height':	'300px',
			'overflow-y':	'hidden',
			'margin-bottom':'12px',
			'border-bottom':'2px dashed #900'
		});
	// コメント欄
	var combody = $f('#com>div.commentbody');
	var comview = combody.children('div.comemntview');
	comview.hide(0);

	// iframe内のリンク書き換え
	$f('a').each(function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (!url) return;

		// if (url.substr(0, if_cw.Vmyself.length) != if_cw.Vmyself
		//  || url.indexOf('?&')<0 && 0<url.indexOf('?')) {
			obj.attr('target', '_top');
		//}
	});

//////////////////////////////////////////////////////////////////////////////
// ●要素タイプの選択
//////////////////////////////////////////////////////////////////////////////
var mod_type = $('#module-type');
mod_type.change(function(evt){
	var type = $(evt.target).val();
	var sel  = $('#add-module').empty();
	sel.append( $('<option>')
		.val('').text( $('#msg-append-module-select').text() )
	);
	for(var i=0; i<mod_list.length; i++) {
		var name = mod_list[i];
		var mod = modules[name];
		if (mod.data('type').indexOf(type)<0) continue;
		// 
		var id = mod.children().attr('id');
		if (id) {
			if ($f('#' + id).data('fix')) continue;	// 固定要素は無視
		} else {
			if ($f('[data-module-name="' + name + '"]').data('fix')) continue;
		}

		// 追加
		sel.append( $('<option>')
			.attr('value', name)
			.text(mod.attr('title'))
		);
	}
});
mod_type.change();

//////////////////////////////////////////////////////////////////////////////
// ●要素を追加する
//////////////////////////////////////////////////////////////////////////////
$('#add-module').change(function(evt){
	var _this = $(evt.target)
	var name = _this.val();
	if (name == '') return;
	_this.val('');

	var mod = modules[ name ];
	if (! mod.length) return;
	var obj = mod.children().clone(true);
	obj.data('module-name', name);
	obj.attr('data-module-name', name);

	var id = obj.attr('id');
	if (id != '' && $f('#' + id).length) {	// 同じidが既に存在する、↓同じモジュール名が存在する
		show_error( '#msg-duplicate-id', {
			n: mod.attr('title') || name
		});
		return false;
	}

	// data-id to id
	obj.find('*[data-id]').each(function(){
		var el = $(this);
		$(el).attr('id', el.data('id'));
	});

	// 多重インストールが許可されている場合、エイリアスを作る
	if (!id) {
		name = obj.data('module-name');
		for(var i=1; i<9999; i++) {
			var name2 = name + ',' + i.toString();
			if ($f('*[data-module-name="'+ name2 +'"]').length) continue;
			break;
		}
		obj.data('module-name', name2);
		obj.attr('data-module-name', name2);	// 必須
		name = name2;
		var id = name.replace(/_/g, '-').replace(',', '');
		obj.attr('id', id);			// 個別CSS適用のための細工
	}

	// モジュール初期化
	init_module(obj);

	// 追加
	var type = mod_type.val();
	if (type == 'header') {
		f_head.append(obj);
	} else if (type == 'article') {
		artfoot.append(obj);
	} else {
		var place = (type == 'main') ? f_main : side_a;
		place.prepend(obj);
	}

	// モジュールHTMLをサーバからロード？
	if (obj.data('load-module-html')) load_module_html( obj );
});

//////////////////////////////////////////////////////////////////////////////
// ●モジュールクラスやアイコンを設定
//////////////////////////////////////////////////////////////////////////////
function init_module(obj) {
	var div = $('<div>');
	div.addClass('module-edit-header');
	var name = obj.data('module-name').replace(/,\d+$/,'');
	if (! modules[ name ]) {
		// 使われてるモジュールが削除されてる等
		obj.remove();
		return ;
	}
	var hash = modules[ name ].data();
	if (hash) {
		for (var k in hash) {
			// 元々持つのdata要素を上書きしないようにする
			if (obj.data(k) != undefined) continue;
			obj.data(k, hash[k]);
		}
	}

	// モジュールに title 属性を設定
	if (!obj.attr('title')) {
		var title = obj.children('.hatena-moduletitle');
		title = title.length ? title.text() : '';
		title = title || modules[name].attr('title') ||  obj.data('module-name') || '(unknown)';
		obj.attr('title', title);
	}

	if (obj.data('readme')) {
		var info = $('<span>');
		info.addClass('ui-icon ui-icon-help ui-button info');
		info.attr({
			onclick: '',
			'data-url': obj.data("readme-url")
		});
		info.data('title', obj.data('readme-title'));
		info.data('class', 'pre');
			div.append(info);
	}

	if (obj.data('setting')) {
		var set = $('<span>');
		set.addClass('ui-icon ui-icon-wrench ui-button');
		set.attr('title', btn_setting_title);
		set.click(function(){
			module_setting(obj);
		});
		div.append(set);
	}

	if (obj.data('css-setting')) {
		var set = $('<span>');
		set.addClass('ui-icon ui-icon-image ui-button');
		set.attr('title', btn_cssset_title);
		set.click(function(){
			module_setting(obj, 'css');
		});
		div.append(set);
	}

	if (!obj.data('fix')) {
		var close = $('<span>');
		close.addClass('ui-icon ui-icon-close ui-button');
		close.attr('title', btn_close_title);
		close.click(function(){
			my_confirm({
				id: '#msg-delete-confirm',
				hash: { n: obj.attr('title') },
				btn_ok: $('#btn-close').text(),
				callback: function(flag) {
					if (flag) obj.detach();
				}
			});
		});
		div.append(close);
	}

	obj.addClass('design-module-edit');
	obj.prepend(div);

	obj.show();
};

//////////////////////////////////////////////////////////////////////////////
// ●モジュールの設定を変更する
//////////////////////////////////////////////////////////////////////////////
function module_setting(obj, mode) {
	var name = obj.data('module-name');

	var formdiv = $('<div>').attr('id', 'popup-dialog');
	var form = $secure('#setting-form').clone();
	var url  = form.data('setting-url') + name;
	if (mode) url += '&mode=' + mode;
	form.removeAttr('id');
	form.append($('<input>').attr({
		type: 'hidden',
		name: 'module_name',
		value: name
	}));
	form.append($('<input>').attr({
		type: 'hidden',
		name: 'setting_mode',
		value: mode
	}));
	var body = $('<div>').attr('id', 'js-form-body');
	form.append( body );
	formdiv.append( form );

	// エラー表示用
	var errdiv = $('<div>').addClass('error-message');
	var errmsg = $('<strong>').addClass('error').css('display', 'block');
	var erradd = $('<div>');
	errdiv.append(errmsg, erradd);

	var ajax = {
		url: form.attr('action'),
		type: 'POST',
		success: function(data){
			if (! data.match(/ret=(-?\d+)(?:\n|$)/) ) {
				errmsg.html( $('#msg-save-error').html() );
			} else if (RegExp.$1 != '0') {
				errmsg.html( $('#msg-save-error').html() +'(ret='+ RegExp.$1 +')');
			} else {
				//成功
				formdiv.dialog( 'close' );
				// モジュールHTMLをサーバからロード？
				if (mode == 'css') load_module_css( obj );
				if (obj.data('load-module-html')) load_module_html( obj );
				return ;
			}
			errmsg.attr('title', data);
			if (data.match(/\nmsg=([\s\S]*)$/) ) erradd.html( RegExp.$1 );
		},
		error: function(xmlobj){
			errmsg.html( $('#msg-ajax-error').html() );
			errmsg.attr('title', xmlobj.responseText);
		},
	};

	var buttons = {};
	var ok_func = buttons[ $('#btn-ok').text() ] = function(){
		// ファイルアップロードチェック
		var file;
		var files = form.find('input[type="file"]');
		for(var i=0; i<files.length; i++)
			if ($(files[i]).val()) file=true;
		
		// フォームデータ生成
		if (file) {
		        var fd = new FormData( form[0] );
			ajax.data = fd;
			ajax.processData = false;
			ajax.contentType = false;
		} else {
			ajax.data = form.serialize();
		}
		// 今すぐ保存
		$.ajax( ajax );
	};
	buttons[ $('#ajs-cancel').text() ] = function(){
		formdiv.dialog( 'close' );
	};

	// Enterキーで設定ウィンドウを閉じる
	form.on('keypress', 'input', function(evt) {
		if (evt.which === 13) { ok_func(); return false; }
		return true;
	});

	// こうしておこないとロードしたJavaScriptが実行されない
	$('#body').append( formdiv );

	// ダイアログの設定
	formdiv.dialog({
		autoOpen: false,
		modal: true,
		width:  DialogWidth,
		minHeight: 100,
		maxHeight: $(window).height(),
		title:   obj.attr('title').replace('%n', obj.attr('title')),
		buttons: buttons,
		beforeClose: function(evt,ui) {
			formdiv.remove();
		}
	});

	// フォーム本体をロード
	body.load(url, function(){
		var id = obj.attr('id');
		if (id) body.prepend( $('<div>').text('id : #' + id) );
		if (1 || mode == 'css') {	// HTMLソースを表示
			var vbtn = $('<button>').attr('type','button');
			vbtn.text( $('#btn-view-html').text() );
			vbtn.css( 'float', 'right' );
			vbtn.click( function(){
				view_html_source(obj)
			});
			body.prepend( vbtn );
		}
		body.append( errdiv );
		formdiv.dialog( "open" );
	//	adiary_init( body );
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●結果を保存する
//////////////////////////////////////////////////////////////////////////////
btn_save.click(function(){
	$('#js-form input.js-value').detach();	// 戻るをされた時の対策
	var form = $secure('#js-form');
	if (!form.length) return;

	var form_append = function(key, obj) {
		var i=0;
		obj.each( function(idx,dom){
			var name = $(dom).data('module-name');
			if (!name || name == '') return;
			var inp1 = $('<input>').addClass('js-value');
			inp1.attr({
				type: 'hidden',
				name:  key,
				value: name
			});
			// console.log(key + '=' + name);
			form.append(inp1);
			var inp2 = $('<input>').addClass('js-value');
			inp2.attr({
				type: 'hidden',
				name: name + '_int',
				value: i++
			});
			form.append(inp2);
		});
	};

	form_append('side_a_ary', side_a.children(module_selector));
 	form_append('side_b_ary', side_b.children(module_selector));
 	form_append('header_ary', f_head.children(module_selector));

	var main_a_ary = [];
	var main_b_ary = [];
	{
		var x = main_a_ary;
		var items = f_main.children(module_selector + ', #article');
		for(var i=0; i<items.length; i++) {
			var id = $(items[i]).attr('id');
			if (id == 'article' || id == 'articles') {
				x = main_b_ary;
				continue;
			}
			x.push(items[i]);
		}
	}

	form_append('main_a_ary', $(main_a_ary));
 	form_append('main_b_ary', $(main_b_ary));

	// 記事本体とコメント欄
	form_append('art_h_ary', arthead.children(module_selector));
	form_append('art_f_ary', artfoot.children(module_selector));
	form_append('com_ary'  , combody.children(module_selector));

	form.submit();
});

//////////////////////////////////////////////////////////////////////////////
// ●モジュールをロードして置き換える
//////////////////////////////////////////////////////////////////////////////
function load_module_html(obj) {
	if (!obj.data('load-module-html')) return;

	// HTML取得用フォーム
	var name = obj.data('module-name');
	var form = $secure('#load-module-form');
	$('#js-load-module-name').val( name );
	var url = form.attr('action');

	$.post(url, form.serialize(), function(data){
		if (data.match(/^[\r\n\s]*$/)) return;
		var div = $('<div>').html(data);
		var newobj = div.children( module_selector );

		init_module( newobj );
		obj.replaceWith( newobj );
	//	adiary_init( newobj );
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●CSSをロードして置き換える
//////////////////////////////////////////////////////////////////////////////
function load_module_css(obj) {
	var name = obj.data('module-name');
	if (!obj.data('css-setting')) return;

	var form = $secure('#load-module-form');
	$('#js-load-module-name').val( name );
	var url = form.attr('action');
	var data= form.serialize() + '&mode=css';

	$.post(url, data, function(data){
		// モジュールのstyleを削除
		$f(module_selector).removeAttr('style');
		if (data.match(/^\s*reload=1\s*$/)) {
			if (!$f('#user-css').length) {	// usercssが読み込まれてない
				var style = $('<link>').attr({
					id: 'user-css',
					rel: 'stylesheet',
					href: $('#user-css-url').data('url')
				});
				$f('head').append(style);
				return ;
			}
			// インストール済の時は、CSS強制リロード
			var r = if_cw.reload_user_css();
			if (!r) return;	// 成功
		}
		if (IE8) return;	// 以下が動かない

		// CSSテキストを適用
		var id = 'js-css-' + name.replace(/[_,]/g, '-');
		$f('#' + id).remove();
		var css = $('<style>').attr({
			id: id,
			type: 'text/css'
		});
		css.html(data);
		$f('head').append(css);
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●モジュールの背景色を変えて表示
//////////////////////////////////////////////////////////////////////////////
var disp_modules = $('#display-modules');
disp_modules.change(function() {
	var flag = disp_modules.prop('checked');

	if (flag)
		$f(module_selector).addClass('display');
	else
		$f(module_selector).removeClass('display');
});
disp_modules.change();


//////////////////////////////////////////////////////////////////////////////
// ●モジュールのHTMLソースを表示
//////////////////////////////////////////////////////////////////////////////
function view_html_source(_obj) {
	var div = $('<div>');
	var obj = _obj.clone();
	{	// 整形する
		obj.find('.module-edit-header').remove();	// 編集ボタンの削除
		obj.removeClass('design-module-edit ui-sortable-handle display');
		obj.removeAttr('title');
		obj.removeAttr('style');
		if (obj.attr('class') == '') obj.removeAttr('class');

		// いらない属性の削除
		obj.find('[target]').removeAttr('target');
		obj.find('[title]').removeAttr('target');
		obj.find('[for]').removeAttr('for');
		obj.find('[style]').removeAttr('style');
		obj.find('.resize-parts').remove();

		// hrefを'#'に置換
		obj.find('[href]').attr('href', '#');

		// id=js-generate の削除
		obj.find('[id]').each(function(idx,dom){
			var ob = $(dom);
			var id = ob.attr('id');
			if (! id.match(/^js-generate/)) return;
			ob.removeAttr('id');
		});
	}
	div.attr('title', $('#msg-html-source').text() );
	div.addClass( 'pre' );
	div.text( obj[0].outerHTML );
	div.dialog({ width: DialogWidth });
}

//############################################################################
});
});
//############################################################################
// 設定画面用のサブルーチン
//############################################################################
// FX : rgb(200,200,200), tranparent
// GC : rgb(200,200,200), rgb(0, 0, 0, 0)
// IE8: #ccf / #ccccff
function parse_color(col) {
	col = col.toLowerCase();
	if (col == 'transparent') return '';
	col = col.replace(/^#([0-9a-f])([0-9a-f])([0-9a-f])$/, "#$1$1$2$2$3$3");
	if (col.match(/^#[0-9a-f]{6}$/)) return col;

	var ma = col.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
	if (ma) {
		var c1 = Number(ma[1]).toString(16);
		var c2 = Number(ma[2]).toString(16);
		var c3 = Number(ma[3]).toString(16);
		if (c1.length == 1) c1 = '0' + c1;
		if (c2.length == 1) c2 = '0' + c2;
		if (c3.length == 1) c3 = '0' + c3;
		return '#' + c1 + c2 + c3;
	}
	return '';	// unknown type
}

function parse_px(m) {
	return Math.round( parse_px_float(m) );
}
function parse_px_float(m) {
	var ma = m.match(/^(-?\d+(?:\.\d+)?)\s*(?:px)$/);
	if (ma) return ma[1];
	return 0;
}

function get_border_color(obj) {
	return parse_color(
		obj.css('border-color')
		|| obj.css('border-bottom-color')
		|| obj.css('border-top-color')
		|| obj.css('border-right-color')
		|| obj.css('border-left-color')
	);
}

function delay_color_setting(target, obj, style, func) {
	setTimeout( function(){
		var col = parse_color(obj.css('background-color'));
		if (col) $('#select-bg').val(col);
		if (func) {
			if (typeof(func) == 'function')	return func(obj);
			obj.removeClass(func);
		}
	}, 500);
}



