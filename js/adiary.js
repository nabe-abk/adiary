//############################################################################
// adiary 汎用 JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
var Default_show_speed = 300;
var Default_image_popup_delay = 300;
var DialogWidth = 640;
var popup_offset_x = 15;
var popup_offset_y = 10;
var IE67=false;
var IE8=false;
var Blogpath;	// _frame.html で設定される
var Storage;
$(function(){ if(Blogpath) Storage=load_PrefixStorage( Blogpath ); });
//////////////////////////////////////////////////////////////////////////////
//●RSSからの参照リンクURLの細工を消す
//////////////////////////////////////////////////////////////////////////////
{
	var x = window.location.toString();
	if (x.indexOf('#rss-tm') > 0) {
		window.location = x.replace(/#rss-tm\d*/,'');
	}
}

//////////////////////////////////////////////////////////////////////////////
//●for IE8
//////////////////////////////////////////////////////////////////////////////
if (!('console' in window)) {
	window.console = {};
	window.console.log = function(x){return x};
}
// IE8ではsubstr(-1)が効かない
String.prototype.last_char = function() {
	return this.substr(this.length-1, 1);
}

//////////////////////////////////////////////////////////////////////////////
//●<body>にCSSのためのブラウザクラスを設定
//////////////////////////////////////////////////////////////////////////////
// この関数は、いち早く設定するためにHTMLから直接呼び出す
function set_browser_class_into_body() {
	var x = [];
	var ua = navigator.userAgent;

	     if (ua.indexOf('Chrome') != -1) x.push('GC');
	else if (ua.indexOf('WebKit') != -1) x.push('GC');
	else if (ua.indexOf('Opera')  != -1) x.push('Op');
	else if (ua.indexOf('Gecko')  != -1) x.push('Fx');
	
	var m = ua.match(/MSIE (\d+)/);
	if (m) x.push('IE', 'IE' + m[1]);
	  else x.push('NotIE');
	if (m && m[1]<8) IE67=true;
	if (m && m[1]<9) IE8=true;

	// スマホ
	var smp=true;
	     if (ua.indexOf('Android') != -1) x.push('android');
	else if (ua.indexOf('iPhone')  != -1) x.push('iphone apple');
	else if (ua.indexOf('iPod')    != -1) x.push('ipod apple');
	else if (ua.indexOf('iPad')    != -1) x.push('ipad apple');
	else if (ua.indexOf('BlackBerry') != -1) x.push('berry');
	else smp=false;
	if (smp) x.push('smp');

	// bodyにクラス設定する
	$('#body').addClass( x.join(' ') );
}

//############################################################################
//■初期化処理
//############################################################################
var initfunc = [];
$(function(){
	var body = $('#body');
	var popup_div  = $('<div>').attr('id', 'popup-div');
	var popup_help = $('<div>').attr('id', 'popup-help');
	body.append( popup_div  );
	body.append( popup_help );
	body.append( $('<div>').attr('id', 'popup-com')      );
	body.append( $('<div>').attr('id', 'popup-textarea') );


//////////////////////////////////////////////////////////////////////////////
//●画像・ヘルプのポップアップ
//////////////////////////////////////////////////////////////////////////////
function easy_popup(evt) {
	var obj = $(evt.target);
	var div = evt.data.div;
	var func= evt.data.func;
	var do_popup = function(evt) {
		if (div.is(":animated")) return;
		func(obj, div);
	  	div.css("left", evt.pageX +popup_offset_x);
	  	div.css("top" , evt.pageY +popup_offset_y);
		div.show(Default_show_speed);
	};

	var delay = obj.data('delay') || Default_image_popup_delay;
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

body.on('mouseover', ".js-popup-img",    {func: function(obj,div){
	var img = $('<img>');
	img.attr('src', obj.data('img-url'));
	img.addClass('popup-image');
	div.empty();
	div.append( img );
}, div: popup_div}, easy_popup);

body.on('mouseover', ".help[data-help]", {func: function(obj,div){
	var text = tag_esc_br( obj.data("help") );
	div.html( text );
}, div: popup_help}, easy_popup);

body.on('mouseout', ".js-popup-img",    {div: popup_div }, easy_popup_out);
body.on('mouseout', ".help[data-help]", {div: popup_help}, easy_popup_out);


//////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
//////////////////////////////////////////////////////////////////////////////
// onclick要素を確認することで
// ユーザーが任意のURLを自由に呼び出せないようにしている。
body.on('click', '.info[data-info], .info[data-url][onclick]', function(evt){
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
		div.dialog({ width: DialogWidth });
		return;
	}
	var url = obj.data("url");
	div2.load( url, function(){
		div.dialog({ width: DialogWidth, height: 320 });
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム要素の全チェック
//////////////////////////////////////////////////////////////////////////////
body.on('click', 'input.js-checked', function(evt){
	var obj = $(evt.target);
	var target = obj.data( 'target' );
	$(target).prop("checked", obj.is(":checked"));
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム操作による、disabledの自動変更
//////////////////////////////////////////////////////////////////////////////
body.on('click', 'input.js-disabled', function(evt){
	js_disabled_click( evt.target );
});
initfunc.push( function(R){
	R.find('input.js-disabled').each( function(idx,dom) {
		js_disabled_click(dom);
	} );
});
function js_disabled_click(dom) {
	var btn = $(dom);
	var form =$(btn.data('target'));
	var flag = (btn.data('change') == '1');

	// チェックボックスが外されている状態なら条件反転
	var type=btn.attr('type').toLowerCase();
	if (type == 'checkbox' && !btn.is(":checked")) flag = !flag;
	if (type == 'radio'    && !btn.is(":checked")) return;
	if (flag)
		form.attr('disabled','disabled');
	else
		form.removeAttr('disabled');
}

//////////////////////////////////////////////////////////////////////////////
//●複数チェックボックスフォーム、全選択、submitチェック
//////////////////////////////////////////////////////////////////////////////
body.on('click', 'input.js-form-check, button.js-form-check', function(evt){
	var obj = $(evt.target);
	var form = obj.parents('form.js-form-check');
	if (!form.length) return;
	form.data('confirm', obj.data('confirm') );
});

body.on('submit', 'form.js-form-check', function(evt){
	var form = $(evt.target);
	var target = form.data('target');	// 配列
	var c = false;
	if (target) {
		c = $( target + ":checked" ).length;
		if (!c) return false;	// ひとつもチェックされてない
	}

	// 確認メッセージがある？
	var confirm = form.data('confirm');
	if (!confirm) return true;
	if (c) confirm = confirm.replace("%c", c);
	return window.confirm( confirm );
});

/// End of $(function(){
});


//////////////////////////////////////////////////////////////////////////////
//●フォーム操作、クリック操作による表示・非表示の変更
//////////////////////////////////////////////////////////////////////////////
// 一般要素 + input type="checkbox", type="button"
// (例)
// <input type="button" value="ボタン" class="js-hide" data-target="xxx"
//  data-hide-speed="500" data-hide-val="表示する" data-show-val="非表示にする">

initfunc.push( init_js_switch );

function init_js_switch(R) {
	R.find('.js-switch').each( function() {
		var obj = $(this);
		var f = display_toggle(obj, true);	// initalize
		if (f) obj.click( function(evt){ display_toggle($(evt.target), false) } );
	} );

function display_toggle(btn, init) {
	if (btn[0].tagName == 'A') return false;	// リンククリックは無視
	var type = btn[0].tagName == 'INPUT' && btn.attr('type').toLowerCase();
	var id = btn.data('target');
	if (!id) {
		// 子要素のクリックを拾うための処理
		btn = find_parent(btn, function(par){ return par.attr("data-target") });
		if (!btn) return;
		id = btn.data('target');
	}
	var target = $(id);
	if (!target.length) return false;
	var speed  = btn.data('switch-speed');
	speed = (speed === undefined) ? Default_show_speed : parseInt(speed);
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
	} else {
		flag = init ? !target.is(':hidden') : target.is(':hidden');
	}

	// 変更後の状態を設定
	speed = IE8 ? undefined : speed;
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
		if (IE8) span.css('display', 'inline-block');
		btn.prepend(span);
	}
	return true;
}
///
};

//////////////////////////////////////////////////////////////////////////////
//●input[type="text"]などで enter による submit 停止
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.find('form input.no-enter-submit, form.no-enter-submit input').keypress( function(ev){
		if (ev.which === 13) return false;
		return true;
	});
});

//////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.find('textarea').keypress( function(evt){
		var obj = $(evt.target);
		if (obj.prop('readonly') || obj.prop('disabled')) return;
		if (evt.keyCode != 9) return;

		evt.preventDefault();
		insert_to_textarea(evt.target, "\t");
	});
});


//////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	var load_picker;
	var cp = R.find('input.color-picker');
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
		cp.ColorPicker( { onSubmit: function(hsb, hex, rgb, _el) {
			var el = $(_el);
			el.val('#' + hex);
			el.ColorPickerHide();
			var prev = el.prev();
			if (! prev.hasClass('colorbox')) return;
			prev.css('background-color', '#' + hex);
		}});
		cp.bind('keyup', function(evt){
			$(evt.target).ColorPickerSetColor(evt.target.value);
		});
		cp.bind('keydown', function(evt){
			if (evt.keyCode != 27) return;
			$(evt.target).ColorPickerHide();
		});
	};

	if (cp.ColorPicker) return initfunc();

	// color pickerのロード
	var dir = ScriptDir + 'colorpicker/';
	append_css_file(dir + 'css/colorpicker.css');
	$.getScript(dir + "colorpicker.js", initfunc);
///
});

//////////////////////////////////////////////////////////////////////////////
//●input[type="text"], input[type="password"]の自由リサイズ
//////////////////////////////////////////////////////////////////////////////
// IE9でもまともに動かないけど無視^^;;;
initfunc.push( function(R){
	R.find('input').each( function(){
		if (this.type != 'text'
		 && this.type != 'search'
		 && this.type != 'tel'
		 && this.type != 'url'
		 && this.type != 'email'
		 && this.type != 'password'
		) return;
		set_input_resize($(this));
	} )

function set_input_resize(obj) {
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
		child.each( function() {
			$(this).detach();
			par.append(this);
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
	R.find('form input, form textarea').each( function(){
		if (this.tagName != 'TEXTAREA'
		 && this.type != 'text'
		 && this.type != 'search'
		 && this.type != 'tel'
		 && this.type != 'url'
		 && this.type != 'email'
		 && this.type != 'password'
		) return;

		var obj = $(this);
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
//●INPUT type="radio", type="checkbox" のラベル関連付け（直後のlabel要素）
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	R.find('input[type="checkbox"],input[type="radio"]').each( function() {
		var obj = $(this);
		var label = obj.next();
		if (!label.length || label[0].tagName != 'LABEL' || label.attr('for')) return;

		var id = obj.attr("id");
		if (!id) {
			var flag;
			for(var i=0; i<100; i++) {
				id = 'js-generate-id-' + Math.floor( Math.random()*0x80000000 );
				if (! $('#' + id).length ) {
					flag=true;
					break;
				}
			}
			if (!flag) return;
			obj.attr('id', id);
		}
		// labelに設定
		label.attr('for', id);
	});
///
});


//############################################################################
// ■初期化処理
//############################################################################
function adiary_init(R) {
	for(var i=0; i<initfunc.length; i++)
		initfunc[i](R);
}
$( function(){ adiary_init($('#body')) });

//////////////////////////////////////////////////////////////////////////////
//●自動でadiary初期化ルーチンが走るようにjQueryに細工する
//////////////////////////////////////////////////////////////////////////////
$( function(){
	var hooking = false;
	function hook_function(obj, args) {
		if (hooking || obj.attr('id') !== 'body' && obj.parents('#body').length === 0) return;
		hooking = true;
		var R = $('<div>');
		for(var i=0; i<args.length; i++) {
			if (!args[i] instanceof jQuery) continue;
			if (typeof args[i] !== 'string') {
				adiary_init(args[i]);
				continue;
			}
			var R = $('<div>');
			R.append(args[i]);
			adiary_init(R);
			args[i] = R.html();
		}
		hooking = false;
	}

	var hooks = ['append', 'prepend', 'before', 'after', 'html'];
	function hook(name) {
		var func = $.fn[name];
		$.fn[name] = function() {	// closure
			hook_function(this, arguments);
			return func.apply(this, arguments);
		}
	}
	for(var i=0; i<hooks.length; i++) {
		hook(hooks[i]);
	}
});
//////////////////////////////////////////////////////////////////////////////
//●タブ機能
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	var obj = R.find('.jqueryui-tabs');
	if (!obj.length) return;
	obj.tabs();
});

//////////////////////////////////////////////////////////////////////////////
//●accordion機能
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R){
	var obj = R.find('.jqueryui-accordion');
	if (!obj.length) return;
	obj.accordion({
		heightStyle: "content"
	});
});

//////////////////////////////////////////////////////////////////////////////
//●フォーム値の保存
//////////////////////////////////////////////////////////////////////////////
initfunc.push( function(R) {
	R.find('input.js-save, select.js-save').each( function() {
		var obj = $(this);
		var id  = obj.attr("id");
		if (!id) return;
		obj.change( function(evt){
			var obj = $(evt.target);
			Storage.set(id, obj.val());
		});
		if ( Storage.defined(id) )
			obj.val( Storage.get(id) );
	});
});

//////////////////////////////////////////////////////////////////////////////
//●コメント欄の >>14 等をリンクに変更する
//////////////////////////////////////////////////////////////////////////////
$( function(){
	var popup=$('#popup-com');
	var timer;
	$('#com div.comment-text a[data-reply], #comlist-table a[data-reply]').each(function(idx,dom) {
		var link = $(dom);
		var num  = link.data('reply').toString().replace(/[^\d]/g, '');
		var com  = $('#c' + num);
		if (!com.length) return;

		link.mouseover(function() {
			popup.html( com.html() );
		  	popup.css("top" , link.offset().top  +popup_offset_y);
		  	popup.css("left", link.offset().left +popup_offset_x);
			popup.show(Default_show_speed);
		});
		link.mouseout(function() {
			timer = setTimeout(function(){
				popup.hide('fast');
			}, 300);
		});
		popup.mouseover(function() {
			clearTimeout(timer);
		});
		popup.mouseleave(function() {
			popup.hide('fast');
		});
	});
});

//############################################################################
// ■スケルトン内部使用ルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●セキュリティコードの設定
//////////////////////////////////////////////////////////////////////////////
function put_sid(id) {
	var str="";
	for (var i=3; i<arguments.length; i++) {
		if (i & 1) {
			str += String.fromCharCode(  arguments[i] );
		}
	}
	if (id) {
		$('#' + id).val(str);
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●検索条件表示の関連処理
//////////////////////////////////////////////////////////////////////////////
function init_top_search(id) {
	var form = $(id);
	
	var tagdel = $('<span>').addClass('ui-icon ui-icon-close');
	tagdel.click(function(evt){
		var obj = $(evt.target);
		obj.parent().remove();
		form.submit();
	});
	form.find("div.taglist span.tag").append(tagdel);

	var ymddel = $('<span>').addClass('ui-icon ui-icon-close');
	ymddel.click(function(evt){
		form.attr('action', form.data('noymd-url'));
		form.submit();
	});

	form.find("div.yyyymm span.yyyymm").append(ymddel);
}

//////////////////////////////////////////////////////////////////////////////
// ●検索ハイライト表示
//////////////////////////////////////////////////////////////////////////////
function word_highlight(id) {
	var ch = $(id).children();
	var words = [];
	for(var i=0; i<ch.length; i++) {
		var w = $(ch[i]).text();
		if (w.length < 1) continue;
		words.push( w.toLowerCase() );
	}

	var target = $("#articles article h2 .title, #articles article div.body div.body-main");
	var h_cnt = 0;
	rec_childnodes(target, words);

// childnodesを再起関数で探索
function rec_childnodes(_nodes, words) {
	// ノードはリアルタイムで書き換わるので、呼び出し時点の状態を保存しておく
	var nodes = [];
	for(var i=0; i<_nodes.length; i++)
		nodes.push(_nodes[i]);
	
	// テキストノードの書き換えループ
	for(var i=0; i<nodes.length; i++) {
		if (nodes[i].nodeType == 3) {
			var text = nodes[i].nodeValue;
			if (text == undefined || text.match(/^[\s\n\r]*$/)) continue;
			do_highlight_string(nodes[i], words);
			h_cnt++; if (h_cnt>999) break; 
			continue;
		}
		if (! nodes[i].hasChildNodes() ) continue;
		rec_childnodes( nodes[i].childNodes, words );	// 再起
	}
}
function do_highlight_string(node, words) {
	var par  = node.parentNode;
	var str  = node.nodeValue;
	var str2 = str.toLowerCase();
	var find = false;
	var d = document;
	while(1) {
		var p=str.length;
		var n=-1;
		for(var i=0; i<words.length; i++) {
			var w = words[i];
			var x = str2.indexOf(w);
			if (x<0 || p<=x) continue;
			p = x;
			n = i;
		}
		if (n<0) break;	// 何も見つからなかった
		// words[n]が位置pに見つかった
		var len = words[n].length;
		var before = d.createTextNode( str.substr(0,p)   );
		var word   = d.createTextNode( str.substr(p,len) );
		var span   = d.createElement('span');
		span.className = "highlight highlight" + n;
		span.appendChild( word );
		if (p) par.insertBefore( before, node );
		par.insertBefore( span, node );

		find = true;
		str  = str.substr ( p + len );
		str2 = str2.substr( p + len );
	}
	if (!find) return ;
	// 残った文字列を追加して、nodeを消す
	if (str.length) {
		var remain = d.createTextNode( str );
		par.insertBefore( remain, node );
	}
	par.removeChild( node );
}
///
}

//////////////////////////////////////////////////////////////////////////////
// ●タグ一覧のロード
//////////////////////////////////////////////////////////////////////////////
function load_taglist(id, func) {
	var sel = $(id);	// セレクトボックス
	var _default = sel.data('default') || '';
	func = func ? func : function(data){
		var r_func = function(ary, head, tab) {
			for(var i=0; i<ary.length; i++) {
				var val = head + ary[i].title;
				var opt = $('<option>').attr('value', val).html( val );
				opt.css('padding-left', tab);
				if ( val == _default ) opt.prop('selected', true);
				sel.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, head+val+'::', tab+8 );
			}
		};
		r_func(data, '', 0);
	};
	$.getJSON( sel.data('url'), func );
}

//////////////////////////////////////////////////////////////////////////////
// ●コンテンツ一覧のロード
//////////////////////////////////////////////////////////////////////////////
function load_contents_list(id) {
	var obj = $(id);
	$.getJSON( obj.data('url'), function(data){
		var _default  = obj.data('default');
		var this_pkey = obj.data('this-pkey');

		var r_func = function(ary, tab) {
			for(var i=0; i<ary.length; i++) {
				var pkey  = ary[i].key;
				if (pkey == this_pkey) continue;
				var title = ary[i].title;
				var opt = $('<option>').attr('value', pkey).text( title );
				opt.data('link_key', ary[i].link_key);
				opt.css('padding-left', tab);
				if ( pkey == _default ) opt.prop('selected', true);
				obj.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, tab+8 );
			}
		};
		r_func(data, 0);
	});
}

//////////////////////////////////////////////////////////////////////////////
//●twitterウィジェットのデザイン変更スクリプト
//////////////////////////////////////////////////////////////////////////////
function twitter_css_fix(css_text, width){
	var try_max = 20;
	var try_msec = 250;
	function callfunc() {
		var r=1;
		if (try_max--<1) return;
		try{
			r = css_fix(css_text, width);
		} catch(e) { ; }
		if (r) setTimeout(callfunc, try_msec);
	}
	setTimeout(callfunc, try_msec);

function css_fix(css_text, width) {
	var iframes = $('iframe');
	var iframe;
	var ch;
	for (var i=0; i<iframes.length; i++) {
		iframe = iframes[i];
		if (iframe.id.substring(0, 15) != 'twitter-widget-') continue;
		if (iframe.className.indexOf('twitter-timeline')<0) continue;
		if (iframes[i].id.substring(0, 15) != 'twitter-widget-') continue;
		var doc = iframe.contentDocument || iframe.document;
		if (!doc || !doc.documentElement) continue;
		var ch = doc.documentElement.children;
		break;
	}
	if (!ch) return -1;
	var head;
	var body;
	for (var i=0; i<ch.length; i++) {
		if (ch[i].nodeName == 'HEAD') head = ch[i];
		if (ch[i].nodeName == 'BODY') body = ch[i];
	}
	if (!head || !body) return -2;
	if (body.innerHTML.length == 0) return -3;

	var css = $('<style>').attr({
		id: 'add-tw-css',
		type: 'text/css'
	});
	css.html(css_text);
	$(head).append(css);

	if (width > 49) {
		iframe.css({
			'width': width + "px",
			'min-width': width + "px"
		});
	}
	return ;
};
///
}

//############################################################################
// ■サブルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// CSSファイルの追加
//////////////////////////////////////////////////////////////////////////////
function append_css_file(file) {
	$("head").append("<link>");
	css = $("head").children(":last");
	css.attr({
		type: "text/css",
		rel: "stylesheet",
		href: file
	});
	return css;
}

//////////////////////////////////////////////////////////////////////////////
// タグ除去
//////////////////////////////////////////////////////////////////////////////
function tag_esc(text) {
	return text
	.replace(/</g, '&lt;')
	.replace(/>/g, '&gt;')
	.replace(/"/g, '&quot;')
	.replace(/'/g, '&apos;')
}
function tag_esc_br(text) {
	return tag_esc(text).replace(/\n|\\n/g,'<br>');
}

function tag_decode(text) {
	return text
	.replace(/&apos;/g, "'")
	.replace(/&quot;/g, '"')
	.replace(/&gt;/g, '>')
	.replace(/&lt;/g, '<')
	.replace(/&#92;/g, "\\")	// for JSON data
}

//////////////////////////////////////////////////////////////////////////////
// link_keyのエンコード :: adiary.pmと同一の処理
//////////////////////////////////////////////////////////////////////////////
function link_key_encode(text) {
	return text.replace(/^\//, './/').replace(/[^\w!\(\)\*\-\.\~\/:;=&]+/g, function(data) {
		return decodeURI(data).replace("'", '%27');
	});
}

//////////////////////////////////////////////////////////////////////////////
// 条件にマッチする親要素を最初にみつけるまで探索
//////////////////////////////////////////////////////////////////////////////
function find_parent(obj, filter) {
	for(var i=0; i<999; i++) {
		obj = obj.parent();
		if (!obj.length) return;
		if (!obj[0].tagName) return;
		if (filter(obj)) return obj;
	}
	return;
}

//////////////////////////////////////////////////////////////////////////////
// テキストエリアに文字挿入
//////////////////////////////////////////////////////////////////////////////
function insert_to_textarea(ta, text) {
	var start = ta.selectionStart;	// カーソル位置
	if (start == undefined) {
		// for IE8
		var tmp = document.selection.createRange();
		tmp.text = text;
		return;
	}
	// カーソル移動
	ta.value = ta.value.substring(0, start)	+ text + ta.value.substring(start);
	start += text.length;
	ta.setSelectionRange(start, start);
}

//////////////////////////////////////////////////////////////////////////////
// ●テキストエリア入力画面のpopup
//////////////////////////////////////////////////////////////////////////////
function textarea_dialog(dom, func) {
	var obj  = $(dom);
	var div  = $('#popup-textarea');
	var text = obj.data('msg');

	div.empty();
	if (text && text != '') {
		var p = $('<p>');
		p.html(text);
		div.append(p);
	}
	var ta = $('<textarea>').attr('rows', 5).addClass('w100p');
	div.append(ta);

	// ボタンの設定
	var ok     = obj.data('ok')     || 'OK';
	var cancel = obj.data('cancel') || 'CANCEL';
	var buttons = {};
	buttons[ok] = function(){
		div.dialog( 'close' );
		func( ta.val() );	// callback
	};
	buttons[cancel] = function(){
		div.dialog( 'close' );
	};

	// ダイアログの表示
	div.dialog({
		modal: false,
		minWidth:  DialogWidth,
		minHeight: 100,
		title:   obj.data('title'),
		buttons: buttons
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●エラーの表示
//////////////////////////////////////////////////////////////////////////////
function show_error(id, hash, addclass) {
	if (addclass == undefined) addclass='';
	addclass += ' error-dialog';
	return show_dialog('ERROR',id,hash,addclass);
}
function show_dialog(title, id, hash, addclass) {
	var html = $(id).html();
	if (hash) html = html.replace(/%([A-Za-z])/g, function(w,m1){ return hash[m1] });
	html = html.replace(/%[A-Za-z]/g, '');

	var div = $('<div>');
	div.html( html );
	div.attr('title', title || 'Dialog');
	div.dialog({
		modal: true,
		dialogClass: addclass,
		buttons: { OK: function(){ div.dialog('close'); } }
	});
	return false;
}

//############################################################################
// adiary用 Ajaxセッションライブラリ
//############################################################################
function adiary_session(_btn, opt){
  $(_btn).click( function(evt){
	var btn = $(evt.target);
	var myself = opt.myself || btn.data('myself');
	var log = $(opt.log || btn.data('log-target') || '#session-log');

	var load_session = myself + '?etc/load_session';
	var interval = opt.interval || log.data('interval') || 300;
	var snum;
	log.show(Default_show_speed);

	if (opt.init) opt.init(evt);

	// セッション初期化
	$.post( load_session, {
			action: 'etc/init_session',
			csrf_check_key: opt.csrf_key || $('#csrf-key').val(),
		}, function(data) {
			var reg = data.match(/snum=(\d+)/);
			if (reg) {
				snum = reg[1];
				ajax_session();
			}
		}, 'text'
	);

	// Ajaxセッション開始
	function ajax_session(){
		log_start();
		console.log('[adiary_session()] session start');
		var fd;
		if (opt.load_formdata) fd = opt.load_formdata(btn);
				else   fd = new FormData( opt.form );
		var ctype;
		if (typeof(fd) == 'string') fd += '&snum=' + snum;
		else {
			fd.append('snum', snum);
			ctype = false;
		}
		$.ajax(myself + '?etc/ajax_dummy', {
			method: 'POST',
			contentType: ctype,
			processData: false,
			data: fd,
			dataType: opt.dataType || 'text',
			error: function(data) {
				if (opt.error) opt.error();
				console.log('[adiary_session()] http post fail');
				console.log(data);
				log_stop();
			},
			success: function(data) {
				if (opt.success) opt.success();
				console.log('[adiary_session()] http post success');
				console.log(data);
				log_stop();
			},
			xhr: opt.xhr
		});
	}
	
	/// ログ表示タイマー
	var log_timer;
	function log_start( snum ) {
		btn.prop('disabled', true);
		log.data('snum', snum);
		log_timer = setInterval(log_load, interval);
	}
	function log_stop() {
		if (log_timer) clearInterval(log_timer);
		log_timer = 0;
		log_load();
		btn.prop('disabled', false);
	}
	function log_load() {
		var url = load_session + '&snum=' + snum;
		log.load(url, function(data){
			log.scrollTop( log.prop('scrollHeight') );
		});
	}
  });
};

//############################################################################
// 外部スクリプトロード用ライブラリ
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ■SyntaxHighlighterのロードと適用
//////////////////////////////////////////////////////////////////////////////
var load_sh_flag = false;
var alt_syntax_highlighter = false;
function load_SyntaxHighlighter() {
	if (load_sh_flag) return;
	load_sh_flag=true;
	if (alt_syntax_highlighter) return alt_syntax_highlighter();
$(function(){
	var dir = ScriptDir + 'SyntaxHighlighter/';
	$.getScript(dir + "scripts/shCore.js", function(){
		$.getScript(dir + "scripts/shAutoloader.js", function(){ 
			var ary = [
  'applescript		@shBrushAppleScript.js',
  'actionscript3 as3	@shBrushAS3.js',
  'bash shell		@shBrushBash.js',
  'coldfusion cf	@shBrushColdFusion.js',
  'cpp c		@shBrushCpp.js',
  'c# c-sharp csharp	@shBrushCSharp.js',
  'css			@shBrushCss.js',
  'delphi pascal	@shBrushDelphi.js',
  'diff patch pas	@shBrushDiff.js',
  'erl erlang		@shBrushErlang.js',
  'groovy		@shBrushGroovy.js',
  'java			@shBrushJava.js',
  'jfx javafx		@shBrushJavaFX.js',
  'js jscript javascript @shBrushJScript.js',
  'perl pl		@shBrushPerl.js',
  'php			@shBrushPhp.js',
  'text plain		@shBrushPlain.js',
  'py python		@shBrushPython.js',
  'ruby rails ror rb	@shBrushRuby.js',
  'sass scss		@shBrushSass.js',
  'scala		@shBrushScala.js',
  'sql			@shBrushSql.js',
  'vb vbnet		@shBrushVb.js',
  'xml xhtml xslt html	@shBrushXml.js'];
			for(var i = 0; i < ary.length; i++)
				ary[i] = ary[i].replace('@', dir + 'scripts/');
			SyntaxHighlighter.autoloader.apply(null, ary);
			SyntaxHighlighter.defaults['toolbar'] = false;
			SyntaxHighlighter.all();
		})
	});
	// CSSの追加
	append_css_file(dir + 'styles/shCore.css');
	append_css_file(dir + 'styles/shThemeDefault.css');
});
///
}

//############################################################################
// Prefix付DOM Storageライブラリ
//							(C)2010 nabe@abk
//############################################################################
// Under source is MIT License
//
// ・pathを適切に設定することで、同一ドメイン内で住み分けることができる。
// ・ただし紳士協定に過ぎないので過剰な期待は禁物
// is_session  0(default):LocalStorage 1:sessionStorage 2:ワンタイムなobj
//
//（利用可能メソッド） set(), get(), remove(), clear()
//
function load_PrefixStorage(path) {
	var ls = new PrefixStorage(path);
	return ls;	// fail
}
function PrefixStorage(path, is_session) {
	// ローカルストレージのロード
	this.ls = Load_DOMStorage( is_session );

	// プレフィックス
	this.prefix = String(path) + '::';
}

//-------------------------------------------------------------------
// メンバ関数
//-------------------------------------------------------------------
PrefixStorage.prototype.set = function (key,val) {
	this.ls[this.prefix + key] = val;
};
PrefixStorage.prototype.get = function (key) {
	return this.ls[this.prefix + key];
};
PrefixStorage.prototype.getInt = function (key) {
	var v = this.ls[this.prefix + key];
	if (v==undefined) return 0;
	return Number(v);
};
PrefixStorage.prototype.defined = function (key) {
	return (this.ls[this.prefix + key] !== undefined);
};
PrefixStorage.prototype.remove = function(key) {
	this.ls.removeItem(this.prefix + key);
};
PrefixStorage.prototype.allclear = function() {
	this.ls.clear();
};
PrefixStorage.prototype.clear = function(key) {
	var ls = this.ls;
	var pf = this.prefix;
	var len = pf.length;

	if (ls.length != undefined) {
		var ary = new Array();
		for(var i=0; i<ls.length; i++) {
			var k = ls.key(i);
			if (k.substr(0,len) === pf) ary.push(k);
		}
		// forでkey取り出し中には削除しない
		//（理由はDOM Storage仕様書参照のこと）
		for(var i in ary) {
			delete ls[ ary[i] ];
		}
	} else {
		// DOMStorageDummy
		for(var k in ls) {
			if (k.substr(0,len) === pf)
				delete ls[k];
		}
	}
};

//////////////////////////////////////////////////////////////////////////////
// ■ Storageの取得
//////////////////////////////////////////////////////////////////////////////
//(参考資料) http://www.html5.jp/trans/w3c_webstorage.html
function Load_DOMStorage(is_session) {
	var storage;
	// LocalStorage
	try{
		if (typeof(localStorage) != "object" && typeof(globalStorage) == "object") {
			storage = globalStorage[location.host];
		} else {
			storage = localStorage;
		}
	} catch(e) {
		// Cookieが無効のとき
	}
	// 未定義のとき DOM Storage もどきをロード
	if (!storage) {
		storage = new DOMStorageDummy();
	}
	return storage;
}

//////////////////////////////////////////////////////////////////////////////
// ■ sessionStorage 程度の DOM Storage もどき
//////////////////////////////////////////////////////////////////////////////
// length, storageイベントは非対応
//
function DOMStorageDummy() {
	// メンバ関数
	DOMStorageDummy.prototype.setItem = function(key, val) { this[key] = val; };
	DOMStorageDummy.prototype.getItem = function(key) { return this[key]; };
	DOMStorageDummy.prototype.removeItem = function(key) { delete this[key]; };
	DOMStorageDummy.prototype.clear = function() {
		for(var k in this) {
			if(typeof(this[k]) == 'function') continue;
			delete this[k];
		}
	}
}

