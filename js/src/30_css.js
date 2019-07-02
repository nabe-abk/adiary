//############################################################################
// ■CSSへの機能提供ライブラリ
//############################################################################
var css_initial_functions = [];
//////////////////////////////////////////////////////////////////////////////
// ●CSSから値を取得する
//////////////////////////////////////////////////////////////////////////////
function get_value_from_css(id, attr) {
	var span = $('<span>').attr('id', id).css('display', 'none');
	$('#body').append(span);
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

//////////////////////////////////////////////////////////////////////////////
//●sidebarのHTML位置変更
//////////////////////////////////////////////////////////////////////////////
css_initial_functions.push(function(){
	var flag = get_value_from_css('sidebar-move-to-before-main');
	if (SP || !flag) return;

	// 入れ替え
	var sidebar = $('#sidebar');
	sidebar.insertBefore( 'div.main:first-child' );
});


css_initial_functions.push(function(){
	var flag = get_value_from_css('side-b-move-to-footer');
	if (SP || !flag) return;

	// 入れ替え
	$('#footer').prepend( $('#side-b').addClass('js-auto-width') );
});

//////////////////////////////////////////////////////////////////////////////
//●dropdown-menuの位置変更
//////////////////////////////////////////////////////////////////////////////
css_initial_functions.push(function(){
	var flag = get_value_from_css('dropdown-menu-move-to-after-header-div');
	if (SP || !flag) return;

	// 入れ替え
	var header = $('#header');
	var ddmenu = header.find('.dropdown-menu');
	header.append( ddmenu );
});



//////////////////////////////////////////////////////////////////////////////
//●ui-iconの自動ロード		※ここを変更したら amp プラグインも変更する
//////////////////////////////////////////////////////////////////////////////
css_initial_functions.push(function(){
	var vals = [0, 0x40, 0x80, 0xC0, 0xff];
	var color = get_value_from_css('ui-icon-autoload', 'background-color');
	if (!color || color == 'transparent') return;
	if (color.match(/\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*0/)) return;

	var ma = color.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	var cols = [];
	if (ma) {
		cols[0] = parseInt('0x' + ma[1]);
		cols[1] = parseInt('0x' + ma[2]);
		cols[2] = parseInt('0x' + ma[3]);
	} else {
		// rgb( 0, 0, 255 )
		var ma = color.match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
		if (!ma) return;
		cols[0] = ma[1];
		cols[1] = ma[2];
		cols[2] = ma[3];
	}
	// 用意されているアイコンからもっとも近い色を選択
	var file='';
	for(var i=0; i<3; i++) {
		var c = cols[i];
		var diff=255;
		var near;
		for(var j=0; j<vals.length; j++) {
			var d = Math.abs(vals[j] - c);
			if (d>diff) continue;
			near = vals[j];
			diff = d;
		}
		file += (near<16 ? '0' : '') + near.toString(16);
	}
	// アイコンのロード
	var css = '.ui-icon, .art-nav a:before, .art-nav a:after { background-image: '
		+ 'url("' + PubdistDir + 'ui-icon/' + file + '.png") }';
	var style = $('<style>').attr('type','text/css');
	$('head').append(style);
	style.html(css);

});

//////////////////////////////////////////////////////////////////////////////
//●syntax highlight機能の自動ロード
//////////////////////////////////////////////////////////////////////////////
var alt_SyntaxHighlight = false;
var syntax_highlight_css = 'adiary';
function load_SyntaxHighlight() {}	// 互換性のためのダミー

$(function(){
	var $codes = $('pre.syntax-highlight');
	if (!$codes.length) return;
	if (alt_SyntaxHighlight) return alt_SyntaxHighlight();

	load_script(ScriptDir + 'highlight.pack.js', function(){
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
	var style = $('<link>').attr({
		rel: "stylesheet",
		id: 'syntaxhighlight-theme'
	});
	$("head").prepend(style);
});

css_initial_functions.push(function(){
	var css = get_value_from_css('syntax-highlight-theme') || syntax_highlight_css;
	css = css.replace(/\.css$/, '').replace(/[^\w\-]/g, '');
	$('#syntaxhighlight-theme').attr('href', PubdistDir + 'highlight-js/'+ css +'.css');
});

//////////////////////////////////////////////////////////////////////////////
//●MathJaxの自動ロード
//////////////////////////////////////////////////////////////////////////////
var MathJaxURL = 'https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS_HTML';
$(function(){
	var mj_span = $('span.math');
	var mj_div  = $('div.math');
	if (!mj_span.length && !mj_div.length) return;

	window.MathJax = {
		TeX: { equationNumbers: {autoNumber: "AMS"} },
		tex2jax: {
			inlineMath: [],
			displayMath: [],
			processEnvironments: false,
			processRefs: false
		},
		extensions: ['jsMath2jax.js']
	};
	load_script( MathJaxURL );
});

//////////////////////////////////////////////////////////////////////////////
//●viewport の上書き
//////////////////////////////////////////////////////////////////////////////
css_initial_functions.push(function(){
	var val = get_value_from_css('viewport-setting');
	if (!val) return;
	$('#viewport').attr('content', val);
});

//////////////////////////////////////////////////////////////////////////////
//●CSSによる設定を反映
//////////////////////////////////////////////////////////////////////////////
function css_inital() {
	for(var i=0; i<css_initial_functions.length; i++)
		(css_initial_functions[i])();
}
$(function(){ css_inital() });
