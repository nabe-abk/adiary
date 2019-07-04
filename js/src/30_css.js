//############################################################################
// ■CSSへの機能提供ライブラリ
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
adiary.get_value_from_css = function(id, attr) {
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
adiary.css_init(function(){
	var flag = this.get_value_from_css('sidebar-move-to-before-main');
	if (SP || !flag) return;

	// 入れ替え
	var sidebar = $('#sidebar');
	sidebar.insertBefore( 'div.main:first-child' );
});

adiary.css_init(function(){
	var flag = this.get_value_from_css('side-b-move-to-footer');
	if (SP || !flag) return;

	// 入れ替え
	$('#footer').prepend( $('#side-b').addClass('js-auto-width') );
});

//////////////////////////////////////////////////////////////////////////////
//●dropdown-menuの位置変更
//////////////////////////////////////////////////////////////////////////////
adiary.css_init(function(){
	var flag = this.get_value_from_css('dropdown-menu-move-to-after-header-div');
	if (SP || !flag) return;

	// 入れ替え
	var header = $('#header');
	var ddmenu = header.find('.dropdown-menu');
	header.append( ddmenu );
});

//////////////////////////////////////////////////////////////////////////////
//●ui-iconの自動ロード		※ここを変更したら amp プラグインも変更する
//////////////////////////////////////////////////////////////////////////////
adiary.css_init(function(){
	var vals = [0, 0x40, 0x80, 0xC0, 0xff];
	var color = this.get_value_from_css('ui-icon-autoload', 'background-color');
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
		+ 'url("' + this.PubdistDir + 'ui-icon/' + file + '.png") }';
	var style = $('<style>').attr('type','text/css');
	this.$head.append(style);
	style.html(css);

});

//////////////////////////////////////////////////////////////////////////////
//●viewport の上書き
//////////////////////////////////////////////////////////////////////////////
adiary.css_init(function(){
	var val = this.get_value_from_css('viewport-setting');
	if (!val) return;
	$('#viewport').attr('content', val);
});

//////////////////////////////////////////////////////////////////////////////
//●syntax highlight機能の自動ロード
//////////////////////////////////////////////////////////////////////////////
adiary.css_init(function(){
	const $codes = $('pre.syntax-highlight');
	if (!$codes.length) return;
	if (window.alt_SyntaxHighlight) return window.alt_SyntaxHighlight();

	let css = this.get_value_from_css('syntax-highlight-theme') || this.SyntaxHighlightTheme;
	css = css.replace(/\.css$/, '').replace(/[^\w\-]/g, '');
	const css_file = this.PubdistDir + 'highlight-js/'+ css +'.css';

	const $style = $('#syntaxhighlight-theme');
	if ($style.length)
		return $('#syntaxhighlight-theme').attr('href', css_file);

	this.prepend_css(css_file, 'syntaxhighlight-theme');

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
