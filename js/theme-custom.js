//############################################################################
// adiaryテーマカスタマイズ用JavaScript
//							(C)2015 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';
//////////////////////////////////////////////////////////////////////////////
// ●初期設定
//////////////////////////////////////////////////////////////////////////////
$(function(){
	var body = $('#body');
	var form = $('#form');
	var iframe = $('#iframe');
	var if_css;
	var readme = $('#readme-button');
	var submit_btn = $('#submit-btn');

	var sysmode_no = $('#sysmode-no');
	var sysmode_no_flag;

	var sel = $('#theme-select');
	var theme_query='';

	var theme_dir = sel.data('theme_dir');

//////////////////////////////////////////////////////////////////////////////
// ●iframeの自動リサイズ
//////////////////////////////////////////////////////////////////////////////
	function iframe_resize() {
		var h = body.height() - iframe.position().top;
		$('#debug-msg').html(body.height() + ' / ' + iframe.position().top);
		iframe.css('height', h);
	}
	iframe_resize();
	$(window).resize( iframe_resize );

	var detail = $('#detail-mode');
	function detail_click(evt) {
		var obj = detail;
		var tar = $(obj.data('target'));
		if (obj.prop('checked'))
			tar.show(DefaultShowSpeed, iframe_resize);
		else
			tar.hide(DefaultShowSpeed, iframe_resize);
	}
	detail.click( detail_click );
	detail_click( );

//////////////////////////////////////////////////////////////////////////////
// ●テーマ変更時の処理
//////////////////////////////////////////////////////////////////////////////
{
var timer;
var current_theme;
sel.change(function(evt){
	var theme = sel.val();
	if (timer || current_theme == theme) return;
	current_theme = theme;

	theme_query = '&_theme=' + theme;
	iframe.attr('src', Vmyself + '?' + theme_query ); 
	var opt = sel.children(':selected');
	if (opt.data('readme')) {
		readme.data('url', Vmyself + '?design/theme_readme&name=' + theme);
		readme.removeAttr('disabled');
	} else {
		readme.data('url', '');
		readme.attr('disabled', true);
	}
	// システムモード対応確認
	check_system_mode(readme.data('url'));

	// カスタマイズ機能の初期化
	init_custmize(theme);
});
sel.change();
// ↑↓キーでめくる
sel.keyup( function(evt){
	if (evt.keyCode != 38 && evt.keyCode != 40) return;
	if (timer) clearTimeout(timer);
	timer = setTimeout( function(){
		timer = null;
		sel.change();
	}, 300 );
});
// GCで標準でめくる動作（changeイベント発生）を止める
sel.keydown( function(evt){
	if (evt.keyCode != 38 && evt.keyCode != 40) return;
	if (!timer) timer = setTimeout( function(){}, 100 );	// dummy
});

}
//////////////////////////////////////////////////////////////////////////////
// ●システムモードの対応確認
//////////////////////////////////////////////////////////////////////////////
function check_system_mode(url) {
	if (!url) {
		sysmode_no_flag = true;
		sysmode_no.prop('checked', true);
		return ;
	}
	function parse_readme(text) {
		var lines = text.split(/\r?\n/);

		sysmode_no_flag = true;
		for(var i=0; i<lines.length; i++) {
			if (! lines[i].match(/system-mode:\s*yes/i)) continue;
			sysmode_no_flag = false;
		}
		if (sysmode_no_flag)
			sysmode_no.prop('checked', true);
		else if (! sysmode_no.data('orig'))
			sysmode_no.prop('checked', false);
	};
	$.ajax({
		url: url,
		dataType: 'text',
		success: parse_readme
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●システムモードの非対応警告
//////////////////////////////////////////////////////////////////////////////
sysmode_no.change(function(){
	if (sysmode_no.prop('checked')) return;
	if (!sysmode_no_flag) return;

	my_confirm('#sysmode-no-warning', function(flag){
		if (!flag)
			sysmode_no.prop('checked', true);
	});
});


//////////////////////////////////////////////////////////////////////////////
// ●iframe内ロード（CSS欄追加。リンク書き換え）
//////////////////////////////////////////////////////////////////////////////
iframe.on('load', function(){
	// 選択中テーマがちゃんとロードされているか確認
	var ftheme = iframe.contents().find('#theme-css').attr('href');
	if (!ftheme) return;
	ftheme = ftheme.replace(/^.*\/([\w\-]+\/[\w\-]+)\/[\w\-]+\.css$/, "$1");
	if (ftheme != current_theme) return;

	if_css = $('<style>').attr('type','text/css', 'id', 'theme-realtime-custom-css');
	iframe.contents().find('head').append(if_css);

	if (!theme_query) return;
	iframe.contents().find('a').each(function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (! url) return;
		if (url.indexOf(Vmyself)!=0) return;
		if (url.match(/\?(.+&)?_\w+=/)) return;	// すでに特殊Queryがある

		// デザイン画面では解除
		if (url.match(/\?design\//)) {
			obj.attr('target', '_top');
			return;
		}

		var ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + theme_query + (ma[3] ? ma[3] : '');
		obj.attr('href', url);
	});

	if (css_text) {
		iframe.contents().find('#theme-custom-css').remove();
		update_css();
	}
});
//############################################################################
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ機能
//////////////////////////////////////////////////////////////////////////////
	var custom_form  = $('#custom-form');
	var color_bar    = $('#custom-color-bar');
	var custom_cols  = $('#custom-colors');
	var custom_detail= $('#custom-colors-detail');
	var detail_mode  = $('#detail-mode');

	var input_cols  = $;
	var select_opts = $;
	var rel_col;
	var rel_pol;

	var cols;
	var opts;
	var css_text;

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ情報のロード
//////////////////////////////////////////////////////////////////////////////
function init_custmize(name) {
  cols = undefined;
  opts = undefined;
  css_text = '';
  submit_btn.prop('disabled', true);
  $.ajax({
	url: Vmyself + '?design/theme_colors&name=' + name,
	dataType: 'json',
	success: function(data){
		if (data.error || !data._css_text)
			return custom_form_empty();
		// 値保存
		css_text = data._css_text;
		delete data['_css_text'];
		var data2 = data._options;
		delete data['_options'];
		$('#custom-flag').val('1');

		// フォーム初期化
		init_custom_form(data, data2);
		submit_btn.prop('disabled', false);
	},
	error: custom_form_empty
        });
}
function custom_form_empty() {
	custom_form.hide();
	custom_cols.empty();
	custom_detail.empty();
	input_cols  = $;
	select_opts = $;
	iframe_resize();
	$('#custom-flag').val('');
	submit_btn.prop('disabled', false);
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function init_custom_form(data, data2) {
	cols = [];

	// データの取り出しと並べ替え
	var priority = ['base', 'main', 'art', 'wiki', 'footnote', 'border'];
	function get_priority(name) {
		if (name.indexOf( 'fix' ) == 0) return 1000;
		for(var i=0; i<priority.length; i++)
			if (name.indexOf( priority[i] ) == 0) return i;
		return 999;
	}
	var err='';
	for(var k in data) {
		if (k.substr(0,5) == '-err-') {
			err += '<div>' + data[k] + '</div>';
			continue;
		}
		if (k.rsubstr(4) == '-cst') continue;
		if (k.rsubstr(4) == '-rel') continue;
		cols.push({name: k, val: data[k], priority: get_priority(k) });
	}
	if (err.length) show_error({html: err});
	cols = cols.sort(function(a, b) {
		if (a.priority < b.priority) return -1;
		if (a.priority > b.priority) return  1;
	        return (a.name < b.name) ? -1 : 1;
	});

	// フォームの生成
	custom_cols.empty();
	custom_detail.empty();
	input_cols = [];
	rel_col = [];
	rel_pol = [];
	for(var i=0; i<cols.length; i++) {
		var name = cols[i].name;
		var val  = cols[i].val;
		var cval = data[name+'-cst'] || val; // 初期値
		var rel  = data[name+'-rel'];	// 他に連動
		var msg  = name2msg(name);

		var span = $('<span>').addClass('color-box');
		span.text(msg);
		var inp = $('<input>').addClass('color-picker no-enter-submit').attr({
			type: 'text',
			id: 'inp-' + name,
			name: 'c_' + name,
			value: cval
		});
		inp.data('original', val);	// テーマ初期値
		inp.data('default_',cval);	// 現在の設定値（保存用）
		inp.data('default', cval);	// 現在の設定値
		inp.change( function(evt){
			update_css();
			var obj = $(evt.target);
			obj.ColorPickerSetColor( obj.val() );
		});
		(function(){
			var iobj = inp;		// クロージャ
			var n = name;
			iobj.data('onChange', function(hsb, hex, rgb) {
				iobj.data('val', '#' + hex);
				relation_colors(n);
				update_css();
				iobj.removeData('val');
			});
		})();
		span.append(inp);
		input_cols.push(inp);
		if (rel) {
			rel_col[name] = rel;
			var p = exp_to_poland(rel);
			if (p)	rel_pol[name] = p;	// 連動色？
			else	show_error('#css-exp-error', {s: rel});
		}

		// 要素を追加
		var div = rel ? custom_detail : custom_cols;
		if (name.substr(0,3) == 'fix'
		 && name != 'fixbg' && name != 'fixmain' && name != 'fixartbg' && name != 'fixfont')
			div = custom_detail;
		div.append(span);
	}
	input_cols = $(input_cols);

	// オプション選択生成
	opts = [];
	select_opts = [];
	if (data2) {
		for(var k in data2) {
			if (k.rsubstr(4) == '-cst') continue;
			opts.push({name: k, val: data2[k + '-cst'], list: data2[k] });
		}
		opts = opts.sort(function(a, b) {
		        return (a.name < b.name) ? -1 : 1;
		});

		var obj = $('<span>').attr('id', 'options');
		for(var i=0; i<opts.length; i++) {
			var sel = $('<select>').attr('name', opts[i].name);
			sel.append($('<option>').attr('value','').text( name2msg('default') ));
			sel.change( function(evt){
				update_css();
			});
			var list = opts[i].list;
			var val  = opts[i].val || '';
			sel.data('default', val);
			for(var j=0; j<list.length; j++) {
				var n = name2msg( list[j] );	// 翻訳
				var o = $('<option>')
					.attr('value', list[j])
					.text(n);
				if (list[j] == val) o.prop('selected', true);
				sel.append(o);
			}
			obj.append( sel );
			select_opts.push( sel );
			if (IE8) sel.val('');	// なぜかこうするとうまく動く
		}
		custom_cols.prepend( obj );
		select_opts = $(select_opts);
	}
	if (cols.length < 1) color_bar.hide();
			else color_bar.show();
	custom_form.show();
	iframe_resize();

	// すべてロードされる前に送信されることがある。
	custom_form.append($('<input>').attr({
		type:	'hidden',
		name:	'custom_flag',
		value:	1
	}));
}

//////////////////////////////////////////////////////////////////////////////
// ●値連動処理
//////////////////////////////////////////////////////////////////////////////
function relation_colors(name) {
	if (detail_mode.prop('checked')) return;
	for(var k in rel_pol) {
		var pol  = rel_pol[k];
		var v;
		if (pol[0] == 'auto:')
			v = automatic(k, pol[1]);
		else
			v = exec_poland( pol, k );
		// console.log(k + ' = ' + v + ' = ' + rel_col[k] );
		if (!v) {
			show_error('#css-exp-error', {s: rel_col[k]});
			continue;
		}
		var obj = $('#inp-' + k);
		set_color(obj, v);
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function update_css() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom);
		var val = obj.data('val') || obj.val();
		if (val.match(/#[0-9A-Fa-f]{3}/) || val.match(/#[0-9A-Fa-f]{6}/))
			col[ obj.attr('name').substr(2) ] = val;
	});
	var opt = {};
	select_opts.each(function(idx,dom){
		var obj = $(dom);
		opt[ obj.attr('name') ] = obj.val();
	});
	var lines = css_text.split("\n");
	var in_opt;
	var opt_sel;
	for(var i=0; i<lines.length; i++) {
		var x = lines[i];
		// 画像ファイル
		var ma = x.match(/(.*?)url\s*\(\s*(['"])([^'"]+)\2\s*\)(.*)/i);
		if (ma) {
			var file = ma[3];
			file = file.replace('./', '');
			if (file.match(/^[\w-]+(?:\.[\w-]+)*$/))
				x = ma[1] + "url('" + theme_dir + current_theme + '/' + file + "')" + ma[4];
			lines[i] = x;
		}
		// オプション
		var ma = in_opt || x.match(/\$(option\d*)=([\w-\.]+)/);
		if (ma) {
			if (!in_opt) {
				in_opt  = true;
				opt_sel = (opt[ ma[1] ] == ma[2]);
				lines[i]='';
			} else if (ma = x.match(/(.*?)\s*\*\//)) {
				in_opt = false;
				x = ma[1];
				ma = x.match(/^(.*[;}])/);
				if (ma) x=ma[1];
				   else x='';
				lines[i]=x;
			}
			if (!opt_sel) lines[i]='';
			continue;
		}

		// 色カスタム
		var ma = x.match(/\$c=(\w+)/);
		if (!ma) continue;
		lines[i] = x.replace(/#[0-9A-Fa-f]+/, col[ ma[1] ]);
	}
	var new_css = lines.join("\n");
	try {
		if_css.html( new_css );
	} catch(e) {
		// for IE8
		iframe.contents().find('head').append(if_css);
		if_css[0].styleSheet.cssText = new_css;
	}

	// CSSによる設定反映
	iframe[0].contentWindow.css_inital();
}

//////////////////////////////////////////////////////////////////////////////
// ●リセット
//////////////////////////////////////////////////////////////////////////////
$('#btn-reset').click( function() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom)
		var col = obj.data('default_');
		obj.data('default', col);
		set_color(obj, col);
	});
	select_opts.each(function(idx,dom){
		var obj = $(dom)
		obj.val( obj.data('default') );
	});
	form_reset();
	update_css();
});

//////////////////////////////////////////////////////////////////////////////
// ●テーマ初期値リセット
//////////////////////////////////////////////////////////////////////////////
$('#btn-super-reset').click( function() {
	var col = {};
	input_cols.each(function(idx,dom){
		var obj = $(dom)
		var col = obj.data('original');
		obj.data('default', col);
		set_color(obj, col);
	});
	select_opts.each(function(idx,dom){
		var obj = $(dom)
		obj.val('');
	});
	form_reset();
	update_css();
});


//////////////////////////////////////////////////////////////////////////////
// ●色を設定
//////////////////////////////////////////////////////////////////////////////
function set_color(obj, rgb) {
	obj.val( rgb );
	if (obj.ColorPickerSetColor) {
		var prev = obj.prev();
		if (prev.hasClass('colorbox'))
			prev.css('background-color', rgb);
		obj.ColorPickerSetColor( rgb );
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●色一括変更機能
//////////////////////////////////////////////////////////////////////////////
var h_slider = $('#h-slider');
var s_slider = $('#s-slider');
var v_slider = $('#v-slider');
function change_hsv() {
	if (!if_css) return;
	var h = h_slider.slider( "value" );
	var s = s_slider.slider( "value" );
	var v = v_slider.slider( "value" );

	var cols = input_cols;
	for(var i=0; i<cols.length; i++) {
		var obj = $(cols[i]);
		var name=obj.attr('name');
		if (name.indexOf('c_fix') == 0) continue;

		var hsv = RGBtoHSV( obj.data('default') );
		if (!hsv) return;
		// 色変換
		hsv.h += h;
		hsv.s *= (s/160);
		hsv.v += (v-256);
		var rgb = HSVtoRGB( hsv );
		set_color(obj, rgb);
	}
	update_css();
}
$('#h-slider, #s-slider, #v-slider').slider({
	range: "min",
	max: 512,
	value: 256,
//	change: change_hsv,
	slide: change_hsv
});
h_slider.slider('option', 'max', 360);
form_reset();

function form_reset() {
	h_slider.slider('value', 0);
	s_slider.slider('value', 160);
	v_slider.slider('value', 256);
}

//////////////////////////////////////////////////////////////////////////////
// ●RGBtoHSV
//////////////////////////////////////////////////////////////////////////////
function RGBtoHSV(str) {
	var ma = str.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;

	var r = parseInt('0x' + ma[1]);
	var g = parseInt('0x' + ma[2]);
	var b = parseInt('0x' + ma[3]);

	if (r==0 && g==0 && b==0)
		return {h:0, s:0, v:0};

	// 最大値 = V
	var max = r;
	if (max<g) max=g;
	if (max<b) max=b;
	var v = max;

	// 最小値
	var min = r;
	var min_is = 'r';
	if (min > g) {
		min = g;
		min_is = 'g';
	}
	if (min > b) {
		min = b;
		min_is = 'b';
	}
	// S
	var s = (max-min)*255/max;
	// h
	var h;
	if (max == min) h=0;
	else if (min_is == 'b')
		h = 60*(g-r)/(max-min) + 60;
	else if (min_is == 'r')
		h = 60*(b-g)/(max-min) + 180;
	else if (min_is == 'g')
		h = 60*(r-b)/(max-min) + 300;
	if (h<0)   h+=360;
	if (h>360) h-=360;

	return { h: h, s: s, v: v };
}

//////////////////////////////////////////////////////////////////////////////
// ●HSVtoRGB
//////////////////////////////////////////////////////////////////////////////
function HSVtoRGB( hsv ) {
	if (hsv.s<0) hsv.s=0;
	if (hsv.v<0) hsv.v=0;
	var max = hsv.v;
	var min = max - (hsv.s*max/255);

	var r;
	var g;
	var b;
	var h = hsv.h;
	if (h<0)   h+=360;
	if (h>360) h-=360;
	if (h<60) {
		r = max;
		g = (h/60) * (max-min) + min;
		b = min;
	} else if (h<120) {
		r = ((120-h)/60) * (max-min) + min;
		g = max;
		b = min;
	} else if (h<180) {
		r = min;
		g = max;
		b = ((h-120)/60) * (max-min) + min;
	} else if (h<240) {
		r = min;
		g = ((240-h)/60) * (max-min) + min;
		b = max;
	} else if (h<300) {
		r = ((h-240)/60) * (max-min) + min;
		g = min;
		b = max;
	} else {
		r = max;
		g = min;
		b = ((360-h)/60) * (max-min) + min;
	}
	// safety
	r = Math.round(r);
	g = Math.round(g);
	b = Math.round(b);
	if (r<0) r=0;
	if (g<0) g=0;
	if (b<0) b=0;
	if (255<r) r=255;
	if (255<g) g=255;
	if (255<b) b=255;

	// 文字列変換
	r = (r<16 ? '0' : '') + r.toString(16);
	g = (g<16 ? '0' : '') + g.toString(16);
	b = (b<16 ? '0' : '') + b.toString(16);
	return '#' + r + g + b;
}

//////////////////////////////////////////////////////////////////////////////
// ●色名の翻訳
//////////////////////////////////////////////////////////////////////////////
	var n2msg = {};
{
	// 色名の翻訳テキスト
	var ary =$('#attr-msg').html().split("\n");
	for(var i=0; i<ary.length; i++) {
		var line = ary[i];
		var ma = line.match(/(.*?)\s*=\s*([^\s]*)/);
		if (ma) n2msg[ma[1]] = ma[2];
	}
}
function name2msg(name) {
	for(var n in n2msg) {
		name = name.replace(n + '-', n2msg[n]);
		name = name.replace(n      , n2msg[n]);
	}
	return name;
}

//////////////////////////////////////////////////////////////////////////////
// ●逆ポーランドに変換
//////////////////////////////////////////////////////////////////////////////
// 演算子優先度
var oph = {
	'(': 1,
	')': 1,
	'+': 10,
	'-': 10,
	'*': 20,
	'/': 20,
	'@': 999	// 関数呼び出し
};

function exp_to_poland(exp) {
	var m;
	if (m = exp.match(/^\s*auto\s*:\s*(\w+)\s*$/)) {
		return ['auto:', m[1]];
	}

	exp = exp.replace(/^\s*(.*?)\s*$/, "$1");
	exp = exp.replace(/\s*([\+\-\(\)\*])\s*/g, "$1");
	exp = exp.replace(/\(-/g,'(0-');
	exp = exp.replace(/\s+/g, ' ');
	exp = exp.replace(/(\w+)\s*\(/g, "_$1@(");
	exp = '(' + exp + ')';

	var ary = [];
	while(exp.length) {
		var re = exp.match(/^(.*?)([ \+\-\(\)\*\/\@])(.*)/);
		if (!re) return;		// error
		if (re[2] == ' ') return;	// error
		if (re[1] != '') {
			var x = re[1].replace(/^\#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$/, "#$1$1$2$2$3$3");
			if (!( x.match(/^\#[0-9a-fA-F]{6}$/)
			    || x.match(/^\d+(?:\.\d+)?$/)
			    || x.match(/^[A-Za-z_]\w*$/)
			   ) ) return ;			// error;
			ary.push(x);
		}
		ary.push(re[2]);
		exp = re[3];
	}

	// 変換処理
	var st = [];
	var out= [];
	for(var i=0; i<ary.length; i++) {
		var x = ary[i];
		if (! x.match(/[\+\-\(\)\*\/\@]/)) {
			out.push(x);
			continue;
		}
		// 演算子
		var xp = oph[x];	// そのまま積む
		if (x == '(' || st.length == 0 || oph[ st[st.length-1] ]<xp) {
			if (x == ')') return;	// error
			st.push(x);
			continue;
		}
		// 優先度の低い演算子が出るまでスタックから取り出す
		while(st.length) {
			var y  = st.pop();
			var yp = oph[y];
			if (yp < xp)  break;
			if (y == '(') break;
			out.push(y);
		}
		if (x != ')') st.push(x);
	}
	if (st.length) return;	// error

	return out;
}

//////////////////////////////////////////////////////////////////////////////
// ●逆ポーランド式を実行
//////////////////////////////////////////////////////////////////////////////
var color_funcs = [];
function exec_poland(p) {
	var st = [];
	// console.log(p.join(' '));
	
	for(var z=0; z<p.length; z++) {
		var op = p[z];
		if (!oph[op]) {
			var x = op;
			try {
				if (x.substr(0,1) == '#')
					x = parse_rgb(x);
				else if (x.match(/^[A-Za-z]\w*$/)) {
					var obj = $('#inp-'+x);
					x = parse_rgb( obj.data('val') || obj.val() || '' );
				} else if (x.substr(0,1) != '_')
					x = parseFloat( x );
			} catch(e) {
				return;
			}
			if (x === '') return;	// error
			st.push(x);
			continue;
		}

		// 演算子
		var y = st.pop();
		var x = st.pop();
		var xary = x instanceof Array;
		var yary = y instanceof Array;
		if (x === '' || y === '') return;	// error

		if (op == '@') {
			var func = color_funcs[ x.substr(1) ];
			if (!func) return;		// error
			x = func(y);
		}
		if (op == '+' || op == '-') {
			var func = (op=='+')
				 ? function(a,b) { return a+b; }
				 : function(a,b) { return a-b; }
			if (!xary && !yary)
				x = func(x,y);
			else if (xary && yary)
				for(var i=0; i<3; i++)
					x[i] = func(x[i], y[i]);
			else return;	// error
		}

		if (op == '*' || op == '/') {
			var func = (op=='*')
				 ? function(a,b) { return a*b; }
				 : function(a,b) { return a/b; }
			if (!xary && !yary)
				x = func(x,y);
			else if (xary && !yary)
				for(var i=0; i<3; i++)
					x[i] = func(x[i], y);
			else if (!xary && yary)
				for(var i=0; i<3; i++)
					x[i] = func(x, y[i]);
			else return;	// error
		}

		st.push(x);
	}
	if (st.length != 1 || !st[0] instanceof Array) return;	// error
	return rgb2hex( st[0] );
}

function parse_rgb(rgb) {
	var ma = rgb.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;
	return [parseInt('0x' + ma[1]), parseInt('0x' + ma[2]), parseInt('0x' + ma[3])];
}

function rgb2hex(ary) {
	for(var i=0; i<3; i++) {
		ary[i] = Math.round(ary[i]);
		if (ary[i]<   0) ary[i]=0;
		if (ary[i]>0xff) ary[i]=0xff;
	}
	// 文字列変換
	var r = (ary[0]<16 ? '0' : '') + ary[0].toString(16);
	var g = (ary[1]<16 ? '0' : '') + ary[1].toString(16);
	var b = (ary[2]<16 ? '0' : '') + ary[2].toString(16);
	return '#' + r + g + b;
}

//////////////////////////////////////////////////////////////////////////////
// ●関数
//////////////////////////////////////////////////////////////////////////////
color_funcs['test'] = function() {
	return [16,32,64];
}

//////////////////////////////////////////////////////////////////////////////
// ●値の自動連動
//////////////////////////////////////////////////////////////////////////////
function automatic(des_name, src_name) {
	var des = $('#inp-' + des_name);
	var src = $('#inp-' + src_name);
	var c_des = des.data('original');
	var c_src = src.data('original')
	var c_cur = src.data('val') || src.val();
	if (!c_des || !c_src || !c_cur) return;
	if (c_src == c_cur) return c_des;

	// HSV空間での差分
	var h_des = RGBtoHSV( c_des );
	var h_src = RGBtoHSV( c_src );
	var diff = [];
	diff.h = h_des.h - h_src.h;
	diff.s = h_des.s - h_src.s;
	diff.v = h_des.v - h_src.v;
/*	// 比では黒をうまく扱えない
	diff.s = h_des.s / (h_src.s || 0.0000001);	// 
	diff.v = h_des.v / (h_src.v || 0.0000001);	// 0除算防止
*/

	// 今の色に変化を適用
	var hsv = RGBtoHSV( c_cur );
	console.log(hsv.h, hsv.s, hsv.v);
	hsv.h = hsv.h + diff.h;
	hsv.s = hsv.s + diff.s;
	hsv.v = hsv.v + diff.v;
	console.log(des_name,"-->",hsv.h, hsv.s, hsv.v);

	return HSVtoRGB( hsv );
}


//////////////////////////////////////////////////////////////////////////////
// ●式解析デバッグ
//////////////////////////////////////////////////////////////////////////////
$('#parse').click( function() {
	$('#solution').val('');

	var exp = $('#expression').val();
	var pol = exp_to_poland( exp );
	if (!pol) return;
	$('#solution').val( pol );

	var sol = pol[0] == 'auto:' ? automatic('btnbg0', pol[1]) : exec_poland( pol, 'btnbg1' );
	if (sol == null) sol='';
	$('#solution').val( pol + ' >>> ' + sol );
});
$('#expression').keypress(function(evt){
	if (evt.keyCode != 13) return;
	evt.preventDefault();
	$('#parse').click();
});


//############################################################################
});
