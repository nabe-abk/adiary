//##############################################################################
// adiary.js with lightbox.js
//
//##############################################################################
//[TAB=8]
'use strict';
$(function(){
//##############################################################################
// initalize
//##############################################################################
(function(){
	const self = this;

	this.SP = false;		// smart phone mode
	this.DialogWidth       = -1;	// auto
	this.DialogMinWidth    = 480;

	this.CommentEnableTime = 10000;	// msec
	this.CommentEnableKeys = 10;
	this.SyntaxHighlightTheme = '00_adiary';

	// load adiary vars
	let data = this.asys_vars;
	const ary = ['ScriptDir', 'PubdistDir', 'SpecialQuery', 'Static'];
	for(var i in ary) {
		this[ary[i]] = data[ary[i]];
	}

	// remove #rss-tm hash
	if (window.location.hash.indexOf('#rss-tm') == 0) {
		history.pushState("", document.title, location.pathname + location.search);
	}

	// Smartphone mode
	if (this.$body.hasClass('sp')) {
		this.SP = 1;
		this.DialogWidth    = 320;
		this.DialogMinWidth =   0;
	}

	// DB time, Total time
	if (data.DBTime)    $('#system-info-db-time')   .text( data.DBTime    );
	if (data.TotalTime) $('#system-info-total-time').text( data.TotalTime );

	// Google Analytics 4
	if (data.GA4_ID) {
		window.dataLayer = window.dataLayer || [];
		function gtag(){dataLayer.push(arguments);}
		gtag('js', new Date());
		gtag('config', data.GA4_ID);
		this.load_script('https://www.googletagmanager.com/gtag/js?id=' + data.GA4_ID);
	}

	// Google Analytics - UA (2023/07 obsolute)
	if (data.GA_ID) {
		var ga=function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
		ga('create', data.GA_ID, 'auto');
		ga('send', 'pageview');
		this.load_script('https://www.google-analytics.com/analytics.js');
	}

	// load message
	this.load_msg('[data-secure].adiary-msgs');

	// load script		ex) twitter-widget of filter syntax
	$('script-load').each(function(idx, dom) {
		self.load_script(dom.getAttribute('src'));
	});

}).call(adiary);

//##############################################################################
// extend jQuery
//##############################################################################
(function() {
	const init_orig = $.fn.init;
	$.fn.init = function(sel,cont) {
		if (typeof sel === "string" && sel.match(/<.*?[\W]on\w+\s*=/i))
			throw 'Security error by ' + $$.name + '.js : ' + sel;
		return  new init_orig(sel,cont);
	};
})();

////////////////////////////////////////////////////////////////////////////////
// Emulate jquery.cookie for dynatree
////////////////////////////////////////////////////////////////////////////////
(function(_ls) {
	const ls = _ls;
	$.cookie = function(key, val) {
		if (val === undefined) return ls.get(key);
		ls.set(key, val);
	}
	$.removeCookie = function(key) {
		ls.removeItem(key);
	}
})($$.Storage);

//##############################################################################
// ■CSSへの機能提供
//##############################################################################
$$.css_funcs = [];
$$.css_init  = function(func) {
	if (func)
		return this.css_funcs.push(func);

	const funcs = this.css_funcs;
	for(var i=0; i<funcs.length; i++)
		funcs[i].call(this);
}
$$.init(adiary.css_init);

////////////////////////////////////////////////////////////////////////////////
// ●CSSから値を取得する
////////////////////////////////////////////////////////////////////////////////
$$.get_value_from_css = function(id, attr) {
	var span = $('<span>').attr('id', id).css('display', 'none');
	this.$body.append(span);
	if (attr) {
		attr = span.css(attr);
		span.remove();
		return attr;
	}
	var size = span.css('min-width');	// 1pxの時のみ有効
	var str  = span.css('font-family');
	span.remove();
	if (str == null || size != '1px') return '';
	str = str.replace(/["']/g, '');
	return str || size;
}

////////////////////////////////////////////////////////////////////////////////
//●sidebarのHTML位置変更
////////////////////////////////////////////////////////////////////////////////
$$.css_init(function(){
	var flag = this.get_value_from_css('sidebar-move-to-before-main');
	if (this.SP || !flag) return;

	// 入れ替え
	var sidebar = $('#sidebar');
	sidebar.insertBefore( 'div.main:first-child' );
});

$$.css_init(function(){
	var flag = this.get_value_from_css('side-b-move-to-footer');
	if (this.SP || !flag) return;

	// 入れ替え
	$('#footer').prepend( $('#side-b') );
});

////////////////////////////////////////////////////////////////////////////////
//●viewport の上書き
////////////////////////////////////////////////////////////////////////////////
$$.css_init(function(){
	var val = this.get_value_from_css('viewport-setting');
	if (!val) return;
	$('#viewport').attr('content', val);
});

////////////////////////////////////////////////////////////////////////////////
//●ui-iconの生成
////////////////////////////////////////////////////////////////////////////////
$$.css_init(function(){
	let color_bin;
	{
		const css = this.get_value_from_css('ui-icon-autoload', 'background-color');
		if (!css) return;
		const col = css.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
		if (col) {
			color_bin = String.fromCharCode(
				parseInt('0x'+col[1]), parseInt('0x'+col[2]), parseInt('0x'+col[3])
			);
		} else {
			const rgb = css.match(/\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)/);
			if (!rgb) return;
			color_bin = String.fromCharCode(rgb[1], rgb[2], rgb[3]);
		}
	}
	// console.log(color_bin.charCodeAt(0), color_bin.charCodeAt(1), color_bin.charCodeAt(2));

	// generate ui-icon.png
	let png = atob( 'iVBORw0KGgoAAAANSUhEUgAAAFAAAAAgAQMAAAC//W0vAAAABlBMVEUAAP/8/PzLviUMAAAAAnRSTlP/AOW3MEoAAADJSURBVBjTdc4xjgIxDEDRjChSUOQIPkoOskehMBIH4EoZUUy509GgTaQtpiSIJiiRjR0BooBUr3D8bfj1zBvJMSiWxbSFMFnmw8Hcrg1jvf6OO1Nr2/zVyz7ZBwtkp1ydavMFdNbOP515KW5e94HkLjyv+7eJ/4V92Z6PHGtPRD6z1iT8+bLPDDYyIyGxJCYmbJ5QOHLDAuRNhoAFsyNQQh6S3TpTfHBpCKutVUIamhc2DJiVTjhy0WVgiCdZJvQSjs9Ezyu/XHYH55/2IroZ0KMAAAAASUVORK5CYII=')

	// exchange png color
	{
		const PALATTE_OFFSET = 0x29;
		png = png.substr(0, PALATTE_OFFSET) + color_bin + png.substr(PALATTE_OFFSET+3);
	}

	// calc CRC32
	const GEN    = 0xEDB88320;
	const offset = 0x25;
	const length = 10;

	const data = png.substr(offset, length);
	let crc  = 0xffffffff;
	{
		let d;
		let bits = length<<3;
		for(let i=0,j=0; i<bits; i++) {
			if ((i & 7) == 0) d = data.charCodeAt(j++);
			crc ^= (d & 1);
			let x = crc & 1;
			crc >>>=1;
			d   >>>=1;
			if (x) crc ^= GEN;
		}
		crc = ~crc;
		crc = String.fromCharCode( (crc>>>24) & 0xff, (crc>>>16) & 0xff, (crc>>>8) & 0xff, crc & 0xff);
	}
	{
		const p = offset + length;
		png = png.substr(0, p) + crc + png.substr(p+4);
	}
	const $style = this.ui_icon_style = this.ui_icon_style || this.append_style();
	const css = '.ui-icon, .art-nav a:before, .art-nav a:after {'
			+ 'background-image: '
			+ 	'url("data:image/png;base64,' + btoa(png) + '")'
			+ '}';
	$style.html(css);
});

////////////////////////////////////////////////////////////////////////////////
//●syntax highlight機能の自動ロード
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const $codes = $('pre.syntax-highlight');
	if (!$codes.length) return;
	if (window.alt_SyntaxHighlight) return window.alt_SyntaxHighlight();

	let css = this.get_value_from_css('syntax-highlight-theme') || this.SyntaxHighlightTheme;
	css = css.replace(/\.css$/, '').replace(/[^\w\-]/g, '');
	const css_file = this.PubdistDir + 'highlight-styles/'+ css +'.css';

	const $style = $('#syntaxhighlight-theme');
	if ($style.length)
		return $('#syntaxhighlight-theme').attr('href', css_file);

	this.prepend_css(css_file).attr('id', 'syntaxhighlight-theme');

	this.load_script(this.ScriptDir + 'highlight.min.js', function(){
		const buf = [];
		hljs.addPlugin({
			'before:highlightElement': ({el, language}) => {
				el.innerHTML = el.innerHTML.replace(/\x1b/g, "");
				for(const com of $(el).find('span.comment, strong.comment')){
					buf.push(com.outerHTML);
					com.innerHTML = "\x1b" + buf.length + "\x1b";
				}
			},
			'after:highlightElement': ({ el, result, text }) => {
				el.innerHTML = el.innerHTML.replace(/\x1b(?:\<span [^>]*>)?(\d+)(?:\<\/span>)?\x1b/g, (all, m1) => {
					return buf[m1 - 1];
				});
			}
		});

		$codes.each(function(i, block) {
			hljs.highlightBlock(block);

			var $obj = $(block);
			if (! $obj.hasClass('line-number')) return;

			var num = parseInt($obj.data('number'));
			if (!num || num == NaN) num=1;

			var $div = $('<div>').addClass('line-number-block');
			var cnt  = $obj.text().split("\n").length -1;
			var line = '';
			for(var i=0; i<cnt; i++) {
				line += (num+i).toString() + "\n";
			}
			$div.text(line);
			$obj.prepend( $div );
		});
	});
});

////////////////////////////////////////////////////////////////////////////////
//●MathJaxの自動ロード
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const $math = $('span.math, div.math');
	if (! $math.length ) return;

	const MathJaxURL = 'https://cdn.jsdelivr.net/npm/mathjax@4/tex-mml-chtml.js';
	window.MathJax = {
		tex: {
			tags: "ams",
			inlineMath:  [["\x01\x01", "\x01\x01"]],
			displayMath: [["\x01\x02", "\x01\x02"]],
			processEscapes: false,
			processEnvironments: false,
			processRefs: false,
			autoload: {
				color: [],
				colorv2: ['color']
			}
		},
		extensions: ["TeX/AMSmath.js", "TeX/AMSsymbol.js"]
	};
	this.load_script(MathJaxURL, async function(){
      		for(const dom of $math) {
			const deli = dom.tagName === 'SPAN' ? "\x01\x01" : "\x01\x02";
			dom.innerHTML = deli + dom.innerHTML + deli;
		}
		await MathJax.typesetPromise($math);
		$math.trigger('mathjax-complite');
	});
});

////////////////////////////////////////////////////////////////////////////////
//●Lightbox Loadingアイコンの動的ロード
////////////////////////////////////////////////////////////////////////////////
$$.load_LightboxLoaderIcon = function(sel){
	if (this.load_lbicon) return;
	this.load_lbicon = true;
	this.append_style( sel
		+ "{ background-image: url('" + $$.PubdistDir + "lb_loading.gif') }"
	);
}

//##############################################################################
// dom extend
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
////////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////////
//●画像・コメントのポップアップ
////////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
////////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////////
//【スマホ】ドロップダウンメニューでの hover の代わり
////////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
////////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////////
//●【スマホ】DnDエミュレーション登録
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	$R.findx('.treebox').dndEmulation();
});

//##############################################################################
// ■スケルトン用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●コメント欄の加工
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const self=this;
	$('#com div.comment-text').each(function(idx,dom) {
		const $obj = $(dom);

		////////////////////////////////////////////////////////////////
		// リンクに加工 ex) >>14 >>2
		////////////////////////////////////////////////////////////////
		let flag;
		let text = $obj.html();
		text = text.replace(/&gt;&gt;(\d+)/g, function(all, num){
			flag=true;
			return '<a href="#c' + num + '">&gt;&gt;' + num + '</a>';
		});
		if (!flag) return;
		$obj.html(text);

		////////////////////////////////////////////////////////////////
		// regist popup
		////////////////////////////////////////////////////////////////
		$obj.find('a').on('mouseover', {
			func: function($obj, $div) {
				const num  = $obj.attr('href').toString().replace(/[^\d]/g, '');
				const $com = $('#c' + num);
				if (!$com.length) return $div.empty();
				$div.attr('id', 'popup-com');
				$div.html( $com.html() );
			}
		}, function(evt){ self.popup(evt) });
	});
});

////////////////////////////////////////////////////////////////////////////////
//●セキュリティコードの設定
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const $form = $('#comment-form');
	if (!$form.length) return;
	const $csrf = $form.find('[name="csrf_check_key"]');
	if ($csrf.length) return;		// login中は無用

	let   pkey = $('#comment-form-apkey').val() || '';
	const ary  = ($form.data('secure') || '').split(',');
	if (!pkey.match(/^\d+$/)) return;
	pkey = parseInt(pkey) & 255;

	let sid = '';
	for(var i=0; i<ary.length-1; i++) {
		if (!ary[i].match(/^\d+$/)) return;
		sid += String.fromCharCode( ary[i] ^ pkey );
	}

	// 投稿ボタンを disable に
	const $btn = $('#post-comment');
	$btn.prop('disabled', true);

	// 10key押されるか、10秒経ったら設定
	const $ta = $form.find('textarea');

	let hook;
	let timer;
	const enable_func = function() {
		clearTimeout( timer );
		$ta.off('keydown', hook);
		$('#comment-form-sid').val(sid);
		$btn.prop('disabled', false);
	};

	let cnt=this.CommentEnableKeys;
	if (cnt) {
		hook = function() {
			cnt--;
			if (cnt) return;
			enable_func();
		}
		$ta.on('keydown', hook);
	}

	timer = setTimeout(enable_func, this.CommentEnableTime);
});

////////////////////////////////////////////////////////////////////////////////
// ●検索条件の項目マーク
////////////////////////////////////////////////////////////////////////////////
$$.init_top_search = function(id, flag) {
	var $form = $secure(id);
	var tagdel = $('<span>').addClass('ui-icon ui-icon-close');
	if (!flag) tagdel.click(function(evt){
		var $obj = $(evt.target);
		$obj.parent().remove();
		$form.submit();
	});
	$form.find("div.taglist span.tag, div.ctype span.ctype, div.yyyymm span.yyyymm").append(tagdel);
}

////////////////////////////////////////////////////////////////////////////////
// ●検索ハイライト表示
////////////////////////////////////////////////////////////////////////////////
$$.word_highlight = function(id) {
	var ch = $(id).children();
	var words = [];
	for(var i=0; i<ch.length; i++) {
		var w = $(ch[i]).text();
		if (w.length < 1) continue;
		words.push( w.toLowerCase() );
	}

	var target = $("#articles article h2 .title, #articles article div.body div.body-main, #articles span.tags");
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
}

////////////////////////////////////////////////////////////////////////////////
// ●タグ一覧のロード
////////////////////////////////////////////////////////////////////////////////
$$.load_tags_list = function(id) {
	const $sel     = $(id);		// セレクトボックス
	const _default = $sel.data('default') || '';

	$.getJSON( $sel.data('url'), function(data){
		var r_func = function(ary, head, tab) {
			for(var i=0; i<ary.length; i++) {
				var name= ary[i].title;
				var val = head + name;
				var opt = $('<option>').attr('value', val);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + val );
				if ( val == _default ) opt.prop('selected', true);
				$sel.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, head+name+'::', tab+1 );
			}
		};
		r_func(data, '', 0);
		$sel.change();
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●コンテンツ一覧のロード
////////////////////////////////////////////////////////////////////////////////
$$.load_contents_list = function(id) {
	var obj = $(id);
	$.getJSON( obj.data('url'), function(data){
		var _default  = obj.data('default');
		var this_pkey = obj.data('this-pkey');

		var r_func = function(ary, tab) {
			for(var i=0; i<ary.length; i++) {
				var pkey  = ary[i].key;
				if (pkey == this_pkey) continue;
				var title = ary[i].title;
				if (title.length > 20)
					title = title.substr(0,20) + '...';

				var opt = $('<option>').attr('value', pkey);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + title );
				opt.data('link_key', ary[i].link_key);
				if ( pkey == _default ) opt.prop('selected', true);
				obj.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, tab+1 );
			}
		};
		r_func(data, 0);
		obj.change();
	});
}

//##############################################################################
// ■スケルトン内部使用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●ソーシャルボタンの加工
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
  $('.social-button').each(function(idx,dom) {
	var obj = $(dom);
	var url_orig = obj.data('url') || '';
	if (0<url_orig || !url_orig.match(/^https?:\/\//i)) return;

	var url = encodeURIComponent( url_orig );
	var share = obj.children('a.share');
	var count = obj.children('a.count');

	var share_link = share.attr('href');
	var count_link = count.attr('href');
	if (obj.hasClass('twitter-share')) {
		share_link += url;
		count_link += url_orig.replace(/^https?:\/\/(?:www\.)?/i, '').replace(/^www\./i, '');
	} else {
		share_link += url;
		count_link += url;
	}
	share.attr('href', share_link);
	count.attr('href', count_link);

	//////////////////////////////////////////////////////////////
	// カウンタ値のロード
	//////////////////////////////////////////////////////////////
	count.text('-');
	function load_and_set_counter(obj, url, key) {
		$.ajax({
			url: url,
			dataType: "jsonp",
			success: function(c) {
				if (key && typeof(c) == 'object') c = c[key];
				c = c || 0;
				obj.text(c);
			}
		})
	}

	// 値のロード
	if (obj.hasClass('twitter-share'))
		// return load_and_set_counter(count, '//urls.api.twitter.com/1/urls/count.json?url=' + url, 'count');
		return;

	if (obj.hasClass('facebook-share'))
		return load_and_set_counter(count, '//graph.facebook.com/?id=' + url, 'shares');

	if (obj.hasClass('hatena-bookmark'))
		return load_and_set_counter(count, 'https://b.hatena.ne.jp/entry.count?url=' + url);	// for SSL

	if (obj.hasClass('pocket-bookmark')) {
		// Deleted. Because "query.yahooapis.com" is dead
		return count.hide();
	}
  });
});

////////////////////////////////////////////////////////////////////////////////
//●twitterウィジェットのデザイン変更スクリプト
////////////////////////////////////////////////////////////////////////////////
$$.twitter_css_fix = function(){}

////////////////////////////////////////////////////////////////////////////////
//●月別過去ログリストのリロード
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const self = this;
	var selbox = $('#month-list-select-box');
	selbox.change(function(evt){
		var obj = $(evt.target);
		if(!obj.data('url')) return;	// for security
		var val = obj.val(); 
		if (val=='') return;
		if (self.Static)
			return window.location = self.myself + 'q/' + val + '.html';
		window.location = self.myself + '?d=' + val;
	});
	var cur = $('#yyyymm-cond').data('yyyymm');
	if (!cur || typeof(cur) != 'number') return;
	selbox.val( cur.toString() );
});

//##############################################################################
// other functions
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●特殊Queryの処理
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
 	if (!this.SpecialQuery) return;
 	const myself   = this.myself;
 	const sp_query = this.SpecialQuery;
 
 	$('a').each( function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (! url) return;
		if (url.indexOf(myself)!=0) return;
		if (url.match(/\?[\w\/]+$/)) return;		// 管理画面では解除する
		if (url.match(/\?(.+&)?_\w+=/)) return;		// すでに特殊Queryがある

		var ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + sp_query + (ma[3] ? ma[3] : '');
		obj.attr('href', url);
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●さつきタグ記号のエスケープ
////////////////////////////////////////////////////////////////////////////////
$$.esc_satsuki_tag = function(str) {
	return str.replace(/([:\[\]])/g, function(w,m){ return "\\" + m; });
}
$$.unesc_satsuki_tag = function(str) {
	return str.replace(/\\([:\[\]])/g, "$1");
}

////////////////////////////////////////////////////////////////////////////////
// ●セッションを保持して随時データをロードする
////////////////////////////////////////////////////////////////////////////////
$$.session = function(btn, opt){
  const self=this;
  $(btn).click( function(evt){
	var $btn = $(evt.target);
	var myself = opt.myself || self.myself;
	var $log   = opt.$log   || $btn.rootfind($btn.data('log-target') || '#session-log');

	var load_session = myself + '?etc/load_session';
	var interval = opt.interval || $log.data('interval') || 300;
	var snum;

	if (opt.load_log) $log = opt.load_log(evt);
	$log.showDelay();
	if (opt.init) opt.init(evt);

	// セッション初期化
	$.post( load_session, {
			action: 'etc/init_session',
			csrf_check_key: opt.csrf_key || $('#csrf-key').val()
		}, function(data) {
			var reg = data.match(/snum=(\d+)/);
			if (reg) {
				snum = reg[1];
				ajax_session();
				return;
			}
			console.warn(error);
		}, 'text'
	);

	// Ajaxセッション開始
	function ajax_session(){
		log_start();
		var fd;
		if (opt.load_formdata) fd = opt.load_formdata($btn);
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
			error: function(jqXHR, status, msg) {
				const e_msg = '[' + $$.name + '.session()] Ajax fail: ' + msg;
				console.warn(e_msg);
				log_stop(function(){
					$log.text($log.text() + "\n" + e_msg + "\n");
					$log.scrollTop( $log.prop('scrollHeight') );
					if (opt.error) opt.error(jqXHR, status, msg);
				});
			},
			success: function(data) {
				log_stop(function(){
					if (opt.success) opt.success(data);
				});
			},
			complete:	opt.complete,
			xhr:		opt.xhr
		});
	}

	/// ログ表示タイマー
	var log_timer;
	function log_start( snum ) {
		$btn.prop('disabled', true);
		$log.data('snum', snum);
		log_timer = setInterval(log_load, interval);
	}
	function log_stop(func) {
		if (log_timer) clearInterval(log_timer);
		log_timer = 0;
		log_load(func);
		$btn.prop('disabled', false);
	}
	function log_load(func) {
		var url = load_session + '&snum=' + snum;
		$log.load(url, function(data){
			$log.scrollTop( $log.prop('scrollHeight') );
			if (func) func();
		});
	}
  });
};

////////////////////////////////////////////////////////////////////////////////
// CSS append
////////////////////////////////////////////////////////////////////////////////
$$.prepend_css = function(file) {
	const $link = $("<link>")
	$link.attr({
		rel: "stylesheet",
		href: file
	});
	this.$head.prepend($link);
	return $link;
}

////////////////////////////////////////////////////////////////////////////////
// add style
////////////////////////////////////////////////////////////////////////////////
$$.append_style = function(css) {
	const $style = $('<style>').html(css || '');
	this.$head.append($style);
	return $style;
}

//##############################################################################
// init
//##############################################################################
$$.init();

//##############################################################################
});


//##############################################################################
//##############################################################################
/*!
 * Lightbox v2.9.0 - patch4
 * by Lokesh Dhakar
 *
 * More info:
 * http://lokeshdhakar.com/projects/lightbox2/
 *
 * Copyright 2007, 2015 Lokesh Dhakar
 * Released under the MIT license
 * https://github.com/lokesh/lightbox2/blob/master/LICENSE
 *
 *
 * Patch1: Swipe extend for smartphone
 * Patch2: Image's min-width
 * Patch3: Download click with CTRL key
 * Patch4: Back button hack
 * Patch5: Add <span> to a.lb-prev a.lb-next. loader.gif dynamic load.
 * by nabe@abk - https://twitter.com/nabe_abk
 */
!function(t,i){"function"==typeof define&&define.amd?define(["jquery"],i):"object"==typeof exports?module.exports=i(require("jquery")):t.lightbox=i(t.jQuery)}(this,(function(t){function i(i){this.album=[],this.currentImageIndex=void 0,this.init(),this.options=t.extend({},this.constructor.defaults),this.option(i)}return i.defaults={albumLabel:"Image %1 of %2",alwaysShowNavOnTouchDevices:!1,fadeDuration:600,fitImagesInViewport:!0,imageFadeDuration:600,positionFromTop:50,resizeDuration:700,showImageNumberLabel:!0,wrapAround:!1,disableScrolling:!1,min_width:t("<div>").attr("id","lightbox-min-width").appendTo(t("body")).width(),swipeThreshold:60,lightboxHash:"#*LBHash*",sanitizeTitle:!1},i.prototype.option=function(i){t.extend(this.options,i)},i.prototype.imageCountLabel=function(t,i){return this.options.albumLabel.replace(/%1/g,t).replace(/%2/g,i)},i.prototype.init=function(){var i=this;t(document).ready((function(){i.enable(),i.build()}))},i.prototype.enable=function(){var i=this;t("body").on("click","a[rel^=lightbox], area[rel^=lightbox], a[data-lightbox], area[data-lightbox]",(function(e){if(e.shiftKey)return!0;if(e.ctrlKey){var n=t(e.currentTarget),o=n.attr("href")||n.parent("a").attr("href"),a=n.attr("title");null==a&&(a=o.replace(/^.*\//,""));var h=t("<a>").attr({href:o,download:a}),s=document.createEvent("MouseEvent");return s.initEvent("click",!0,!1),h[0].dispatchEvent(s),!1}return i.start(t(e.currentTarget)),!1}))},i.prototype.build=function(){var i=this;t('<div id="lightboxOverlay" class="lightboxOverlay"></div><div id="lightbox" class="lightbox"><div class="lb-outerContainer"><div class="lb-container"><img class="lb-image" src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" /><div class="lb-nav"><a class="lb-prev" href="" ><span></span></a><a class="lb-next" href="" ><span></span></a></div><div class="lb-loader"><a class="lb-cancel"></a></div></div></div><div class="lb-dataContainer"><div class="lb-data"><div class="lb-details"><span class="lb-caption"></span><span class="lb-number"></span></div><div class="lb-closeContainer"><a class="lb-close"></a></div></div></div></div>').appendTo(t("body")),this.$lightbox=t("#lightbox"),this.$overlay=t("#lightboxOverlay"),this.$outerContainer=this.$lightbox.find(".lb-outerContainer"),this.$container=this.$lightbox.find(".lb-container"),this.$image=this.$lightbox.find(".lb-image"),this.$nav=this.$lightbox.find(".lb-nav"),this.containerPadding={top:parseInt(this.$container.css("padding-top"),10),right:parseInt(this.$container.css("padding-right"),10),bottom:parseInt(this.$container.css("padding-bottom"),10),left:parseInt(this.$container.css("padding-left"),10)},this.imageBorderWidth={top:parseInt(this.$image.css("border-top-width"),10),right:parseInt(this.$image.css("border-right-width"),10),bottom:parseInt(this.$image.css("border-bottom-width"),10),left:parseInt(this.$image.css("border-left-width"),10)},this.$overlay.hide().on("click",(function(){return i.end(),!1})),this.$lightbox.hide().on("click",(function(e){return"lightbox"===t(e.target).attr("id")&&i.end(),!1})),this.$outerContainer.on("click",(function(e){return"lightbox"===t(e.target).attr("id")&&i.end(),!1})),this.$lightbox.find(".lb-prev").on("click",(function(){return 0===i.currentImageIndex?i.changeImage(i.album.length-1):i.changeImage(i.currentImageIndex-1),!1})),this.$lightbox.find(".lb-next").on("click",(function(){return i.currentImageIndex===i.album.length-1?i.changeImage(0):i.changeImage(i.currentImageIndex+1),!1})),this.$nav.on("mousedown",(function(t){3===t.which&&(i.$nav.css("pointer-events","none"),i.$lightbox.one("contextmenu",(function(){setTimeout(function(){this.$nav.css("pointer-events","auto")}.bind(i),0)})))})),this.$lightbox.find(".lb-loader, .lb-close").on("click",(function(){return i.end(),!1}))},i.prototype.start=function(i){var e=this,n=t(window);"onhashchange"in window&&(location.hash=this.options.lightboxHash,n.on("hashchange.lightbox.back",(function(t){location.hash!=e.options.lightboxHash&&e.end()}))),n.on("resize",t.proxy(this.sizeOverlay,this)),t("select, object, embed").css({visibility:"hidden"}),this.sizeOverlay(),this.album=[];var o=0;function a(t){e.album.push({link:t.attr("href"),title:t.attr("data-title")||t.attr("title")})}var h,s=i.attr("data-lightbox");if(s){h=t(i.prop("tagName")+'[data-lightbox="'+s+'"]');for(var r=0;r<h.length;r=++r)a(t(h[r])),h[r]===i[0]&&(o=r)}else if("lightbox"===i.attr("rel"))a(i);else{h=t(i.prop("tagName")+'[rel="'+i.attr("rel")+'"]');for(var l=0;l<h.length;l=++l)a(t(h[l])),h[l]===i[0]&&(o=l)}var d=n.scrollTop()+this.options.positionFromTop,c=n.scrollLeft();this.$lightbox.css({top:d+"px",left:c+"px"}).fadeIn(this.options.fadeDuration),this.options.disableScrolling&&t("body").addClass("lb-disable-scrolling"),this.changeImage(o)},i.prototype.changeImage=function(i){var e=this;this.disableKeyboardNav();var n=this.$lightbox.find(".lb-image");this.$overlay.fadeIn(this.options.fadeDuration),$$&&$$.load_LightboxLoaderIcon&&$$.load_LightboxLoaderIcon(".lb-cancel"),t(".lb-loader").fadeIn("slow"),this.$lightbox.find(".lb-image, .lb-nav, .lb-prev, .lb-next, .lb-dataContainer, .lb-numbers, .lb-caption").hide(),this.$outerContainer.addClass("animating");var o=new Image;o.onload=function(){var a,h,s,r,l,d;n.attr("src",e.album[i].link),t(o);var c=e.options.min_width;o.width<c&&(o.height=Math.round(o.height*c/o.width),o.width=c),n.width(o.width),n.height(o.height),e.options.fitImagesInViewport&&(d=t(window).width(),l=t(window).height(),r=d-e.containerPadding.left-e.containerPadding.right-e.imageBorderWidth.left-e.imageBorderWidth.right-20,s=l-e.containerPadding.top-e.containerPadding.bottom-e.imageBorderWidth.top-e.imageBorderWidth.bottom-120,e.options.maxWidth&&e.options.maxWidth<r&&(r=e.options.maxWidth),e.options.maxHeight&&e.options.maxHeight<r&&(s=e.options.maxHeight),(o.width>r||o.height>s)&&(o.width/r>o.height/s?(h=r,a=parseInt(o.height/(o.width/h),10),n.width(h),n.height(a)):(a=s,h=parseInt(o.width/(o.height/a),10),n.width(h),n.height(a)))),e.sizeContainer(n.width(),n.height())},o.src=this.album[i].link,this.currentImageIndex=i},i.prototype.sizeOverlay=function(){this.$overlay.width(t(document).width()).height(t(document).height())},i.prototype.sizeContainer=function(t,i){var e=this,n=this.$outerContainer.outerWidth(),o=this.$outerContainer.outerHeight(),a=t+this.containerPadding.left+this.containerPadding.right+this.imageBorderWidth.left+this.imageBorderWidth.right,h=i+this.containerPadding.top+this.containerPadding.bottom+this.imageBorderWidth.top+this.imageBorderWidth.bottom;function s(){e.$lightbox.find(".lb-dataContainer").width(a),e.$lightbox.find(".lb-prevLink").height(h),e.$lightbox.find(".lb-nextLink").height(h),e.showImage()}n!==a||o!==h?this.$outerContainer.animate({width:a,height:h},this.options.resizeDuration,"swing",(function(){s()})):s()},i.prototype.showImage=function(){this.$lightbox.find(".lb-loader").stop(!0).hide(),this.$lightbox.find(".lb-image").fadeIn(this.options.imageFadeDuration),this.updateNav(),this.updateDetails(),this.preloadNeighboringImages(),this.enableKeyboardNav(),this.enableSwipeNav()},i.prototype.updateNav=function(){var t=!1;try{document.createEvent("TouchEvent"),t=!!this.options.alwaysShowNavOnTouchDevices}catch(t){}this.$lightbox.find(".lb-nav").show(),this.album.length>1&&(this.options.wrapAround?(t&&this.$lightbox.find(".lb-prev, .lb-next").css("opacity","1"),this.$lightbox.find(".lb-prev, .lb-next").show()):(this.currentImageIndex>0&&(this.$lightbox.find(".lb-prev").show(),t&&this.$lightbox.find(".lb-prev").css("opacity","1")),this.currentImageIndex<this.album.length-1&&(this.$lightbox.find(".lb-next").show(),t&&this.$lightbox.find(".lb-next").css("opacity","1"))))},i.prototype.updateDetails=function(){var i=this;if(void 0!==this.album[this.currentImageIndex].title&&""!==this.album[this.currentImageIndex].title){var e=this.$lightbox.find(".lb-caption");this.options.sanitizeTitle?e.text(this.album[this.currentImageIndex].title):e.html(this.album[this.currentImageIndex].title),e.fadeIn("fast").find("a").on("click",(function(i){void 0!==t(this).attr("target")?window.open(t(this).attr("href"),t(this).attr("target")):location.href=t(this).attr("href")}))}if(this.album.length>1&&this.options.showImageNumberLabel){var n=this.imageCountLabel(this.currentImageIndex+1,this.album.length);this.$lightbox.find(".lb-number").text(n).fadeIn("fast")}else this.$lightbox.find(".lb-number").hide();this.$outerContainer.removeClass("animating"),this.$lightbox.find(".lb-dataContainer").fadeIn(this.options.resizeDuration,(function(){return i.sizeOverlay()}))},i.prototype.preloadNeighboringImages=function(){this.album.length>this.currentImageIndex+1&&((new Image).src=this.album[this.currentImageIndex+1].link);this.currentImageIndex>0&&((new Image).src=this.album[this.currentImageIndex-1].link)},i.prototype.enableKeyboardNav=function(){t(document).on("keyup.keyboard",t.proxy(this.keyboardAction,this))},i.prototype.disableKeyboardNav=function(){t(document).off(".keyboard")},i.prototype.keyboardAction=function(t){var i=t.keyCode,e=String.fromCharCode(i).toLowerCase();27===i||e.match(/x|o|c/)?this.end():"p"===e||37===i?0!==this.currentImageIndex?this.changeImage(this.currentImageIndex-1):this.options.wrapAround&&this.album.length>1&&this.changeImage(this.album.length-1):"n"!==e&&39!==i||(this.currentImageIndex!==this.album.length-1?this.changeImage(this.currentImageIndex+1):this.options.wrapAround&&this.album.length>1&&this.changeImage(0))},i.prototype.enableSwipeNav=function(){if(window.addEventListener){var i,e,n=this.options.swipeThreshold;this.evt1func=function(t){var n=document.body.clientWidth/window.innerWidth;i=1==t.touches.length&&n<1.1,e=t.touches[0].pageX},this.evt2func=function(o){if(i){var a=o.changedTouches[0].pageX-e;if(a>n)(h=t.Event("keyup")).keyCode=37,t(document).trigger(h);else if(a<-n){var h;(h=t.Event("keyup")).keyCode=39,t(document).trigger(h)}}},window.addEventListener("touchstart",this.evt1func),window.addEventListener("touchend",this.evt2func)}},i.prototype.end=function(){this.disableKeyboardNav(),t(window).off("resize",this.sizeOverlay),this.$lightbox.fadeOut(this.options.fadeDuration),this.$overlay.fadeOut(this.options.fadeDuration),t("select, object, embed").css({visibility:"visible"}),this.options.disableScrolling&&t("body").removeClass("lb-disable-scrolling"),t(window).off("hashchange.lightbox.back"),location.hash==this.options.lightboxHash&&history.back()},new i}));
