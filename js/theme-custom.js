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

	var sel = $('#theme-select');
	var theme_query='';

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

//////////////////////////////////////////////////////////////////////////////
// ●テーマ変更時の処理
//////////////////////////////////////////////////////////////////////////////
sel.change(function(){
	var theme = sel.val();
	theme_query = '?theme&n=' + theme;
	iframe.attr('src', Vmyself + theme_query ); 
	var opt = sel.children(':selected');
	if (opt.data('readme')) {
		readme.data('url', Vmyself + '?design/theme_readme&name=' + theme);
		readme.removeAttr('disabled');
	} else {
		readme.attr('disabled', true);
	}
	// カスタマイズ機能の初期化
	init_custmize(theme);
});
sel.change();

//////////////////////////////////////////////////////////////////////////////
// ●iframe内ロード（CSS欄追加。リンク書き換え）
//////////////////////////////////////////////////////////////////////////////
iframe.on('load', function(){
	if_css = $('<style>').attr('type','text/css');
	iframe.contents().find('head').append(if_css);

	if (!theme_query) return;
	iframe.contents().find('a').each(function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (!url) return;
		if (url.substr(0,Vmyself.length) != Vmyself) {
			obj.attr('target', '_top');
			return;
		}
		var m;
		if (m = url.match(/(.*?)\?(&.*)/)) {
			url = m[1] + theme_query + m[2];
		} else if (0 < url.indexOf('?')) {
			// obj.attr('target', '_top');
			return;
		} else if (m = url.match(/(.*?)(#.*)/)) {
			url = m[1] + theme_query + m[2];
		} else {
			url += theme_query;
		}
		obj.attr('href', url);
	});	// contents
	
	if (css_text) update_css();
});
//############################################################################
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ機能
//////////////////////////////////////////////////////////////////////////////
	var custom_form = $('#custom-form');
	var custom_cols = $('#custom-colors');

	var cols;
	var css_text;

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

	var cols = custom_cols.find('input');
	for(var i=0; i<cols.length; i++) {
		var obj = $(cols[i]);
		var name=obj.attr('name');
		if (name.indexOf('fix') == 0) continue;

		var hsv = RGBtoHSV( obj.data('default') );
		if (!hsv) return;
		// 色変換
		hsv.h += h;
		hsv.s *= (s/255);
		hsv.v *= (v/255);
		var rgb = HSVtoRGB( hsv );
		obj.val( rgb );
		if (obj.ColorPickerSetColor) {
			var prev = obj.prev();
			if (prev.hasClass('colorbox'))
				prev.css('background-color', rgb);
			obj.ColorPickerSetColor( rgb );
		}
	}
	update_css();
}
$('#h-slider, #s-slider, #v-slider').slider({
	range: "min",
	max: 255,
	value: 255,
	slide: change_hsv,
	change: change_hsv
});
h_slider.slider('option', 'max', 360);
h_slider.slider('value', 0);

//////////////////////////////////////////////////////////////////////////////
// ●RGBtoHSV
//////////////////////////////////////////////////////////////////////////////
function RGBtoHSV(str) {
	var ma = str.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;

	var r = parseInt('0x' + ma[1]);
	var g = parseInt('0x' + ma[2]);
	var b = parseInt('0x' + ma[3]);

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
	var ary =$('#attr-msg').text().split(/\n/);
	for(var i=0; i<ary.length; i++) {
		var line = ary[i];
		var ma = line.match(/(.*?)\s*=\s*([^\s]*)/);
		if (ma) n2msg[ma[1]] = ma[2];
	}
}
function name2msg(name) {
	for(var n in n2msg)
		name = name.replace(n, n2msg[n]);
	return name;
}
//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ情報のロード
//////////////////////////////////////////////////////////////////////////////
function init_custmize(name) {
  cols = undefined;
  css_text = '';
  $.ajax({
	url: Vmyself + '?design/theme_colors&name=' + name,
	dataType: 'json',
	success: function(data){
		if (data.error || !data._css_text) {
			custom_form.hide();
			custom_cols.empty();
			iframe_resize();
			return;
		}
		// 値保存
		css_text = data._css_text;
		delete data['_css_text'];
		cols = data;

		// フォーム初期化
		init_custom_form(data);
	},
	error: function(){
		custom_form.hide();
		custom_cols.empty();
		iframe_resize();
	}
  });
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function init_custom_form(data) {
	cols = [];

	// データの取り出しと並べ替え
	var priority = ['base', 'main', 'art', 'wiki', 'footnote', 'border'];
	function get_priority(name) {
		if (name.indexOf( 'fix' ) == 0) return 1000;
		for(var i=0; i<priority.length; i++)
			if (name.indexOf( priority[i] ) == 0) return i;
		return 999;
	}
	for(var k in data) {
		cols.push({name: k, val: data[k], priority: get_priority(k) });
	}
	cols = cols.sort(function(a, b) {
		if (a.priority < b.priority) return -1;
		if (a.priority > b.priority) return  1;
	        return (a.name < b.name) ? -1 : 1;
	});

	// フォームの生成
	custom_cols.empty();
	for(var i=0; i<cols.length; i++) {
		var name = cols[i].name;
		var val  = cols[i].val;
		var msg  = name2msg(name);

		var span = $('<span>').addClass('color-box');
		span.text(msg);
		var inp = $('<input>').addClass('color-picker no-enter-submit').attr({
			type: 'text',
			name: name,
			value: val
		});
		inp.data('default', val);	// 初期値
		inp.change( update_css );
		span.append(inp);
		custom_cols.append(span);
	}

	custom_form.show();
	iframe_resize();
}

//////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
//////////////////////////////////////////////////////////////////////////////
function update_css() {
	var col = {};
	custom_cols.find('input').each(function(idx,dom){
		var obj = $(dom);
		var val = obj.val();
		if (val.match(/#[0-9A-Fa-f]{3}/) || val.match(/#[0-9A-Fa-f]{6}/))
			col[ obj.attr('name') ] = val;
	});
	var lines = css_text.split("\n");
	for(var i=0; i<lines.length; i++) {
		var x = lines[i];
		var ma = x.match(/\$c=(\w+)/);
		if (!ma) continue;
		lines[i] = x.replace(/#[0-9A-Fa-f]+/, col[ ma[1] ]);
	}
	var new_css = lines.join("\n");
	if_css.html( new_css );
}

//############################################################################
});
