//############################################################################
// ■CSSへの機能提供
//############################################################################
adiary.css_funcs = [];
adiary.css_init  = function(func) {
	if (func)
		return this.css_funcs.push(func);

	const funcs = this.css_funcs;
	for(var i=0; i<funcs.length; i++)
		funcs[i].call(this);
}
adiary.init(adiary.css_init);

//////////////////////////////////////////////////////////////////////////////
// ●CSSから値を取得する
//////////////////////////////////////////////////////////////////////////////
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

//////////////////////////////////////////////////////////////////////////////
//●sidebarのHTML位置変更
//////////////////////////////////////////////////////////////////////////////
$$.css_init(function(){
	var flag = this.get_value_from_css('sidebar-move-to-before-main');
	if (SP || !flag) return;

	// 入れ替え
	var sidebar = $('#sidebar');
	sidebar.insertBefore( 'div.main:first-child' );
});

$$.css_init(function(){
	var flag = this.get_value_from_css('side-b-move-to-footer');
	if (SP || !flag) return;

	// 入れ替え
	$('#footer').prepend( $('#side-b') );
});

//////////////////////////////////////////////////////////////////////////////
//●viewport の上書き
//////////////////////////////////////////////////////////////////////////////
$$.css_init(function(){
	var val = this.get_value_from_css('viewport-setting');
	if (!val) return;
	$('#viewport').attr('content', val);
});

//////////////////////////////////////////////////////////////////////////////
//●ui-iconの生成
//////////////////////////////////////////////////////////////////////////////
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

//////////////////////////////////////////////////////////////////////////////
//●syntax highlight機能の自動ロード
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const $codes = $('pre.syntax-highlight');
	if (!$codes.length) return;
	if (window.alt_SyntaxHighlight) return window.alt_SyntaxHighlight();

	let css = this.get_value_from_css('syntax-highlight-theme') || this.SyntaxHighlightTheme;
	css = css.replace(/\.css$/, '').replace(/[^\w\-]/g, '');
	const css_file = this.PubdistDir + 'highlight-js/'+ css +'.css';

	const $style = $('#syntaxhighlight-theme');
	if ($style.length)
		return $('#syntaxhighlight-theme').attr('href', css_file);

	this.prepend_css(css_file).attr('id', 'syntaxhighlight-theme');

	this.load_script(this.ScriptDir + 'highlight.pack.js', function(){
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

//////////////////////////////////////////////////////////////////////////////
//●MathJaxの自動ロード
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const MathJaxURL = 'https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS_HTML';
	if (! $('span.math, div.math').length ) return;

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
	this.load_script( MathJaxURL );
});

//////////////////////////////////////////////////////////////////////////////
//●Lightbox Loadingアイコンの動的ロード
//////////////////////////////////////////////////////////////////////////////
$$.load_LightboxLoaderIcon = function(sel){
	if (this.load_lbicon) return;
	this.load_lbicon = true;
	this.append_style( sel
		+ "{ background-image: url('" + $$.PubdistDir + "lb_loading.gif') }"
	);
}
