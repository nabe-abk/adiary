//############################################################################
// ■サブルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// セキュアなオブジェクト取得
//////////////////////////////////////////////////////////////////////////////
window.$secure = function(id) {
	var obj = $(document).myfind('[id="' + id.substr(1) + '"]');
	if (obj.length >1) {
		show_error('Security Error!<p>id="' + id + '" is duplicate.</p>');
		return $([]);		// 2つ以上発見された
	}
	return obj;
}

//////////////////////////////////////////////////////////////////////////////
// CSSファイルの追加
//////////////////////////////////////////////////////////////////////////////
window.prepend_css = function(file) {
	var css = $("<link>")
	css.attr({
		rel: "stylesheet",
		href: file
	});
	$("head").prepend(css);
	return css;
}

//////////////////////////////////////////////////////////////////////////////
// load script
//////////////////////////////////////////////////////////////////////////////
var load_script_chache = [];
window.load_script = function(url, func) {
	if (load_script_chache[url]) {
		if (func) func();
		return;
	}
	load_script_chache[url] = 1;

	var $s = $(document.createElement('script'));
	$s.attr('src',   url);
	$s.attr('async', 'async');
	if (func) $s.on('load', func);
	(document.getElementsByTagName('head')[0]).appendChild( $s[0] );
}

//////////////////////////////////////////////////////////////////////////////
// タグ除去
//////////////////////////////////////////////////////////////////////////////
window.tag_esc = function(text) {
	return text
	.replace(/</g, '&lt;')
	.replace(/>/g, '&gt;')
	.replace(/"/g, '&quot;')
	.replace(/'/g, '&apos;')
}
window.tag_esc_br = function(text) {
	return tag_esc(text).replace(/\n|\\n/g,'<br>');
}
window.tag_esc_amp = function(text) {
	return tag_esc( text.replace(/&/g,'&amp;') );
}
window.tag_decode = function(text) {
	return text
	.replace(/&apos;/g, "'")
	.replace(/&quot;/g, '"')
	.replace(/&gt;/g, '>')
	.replace(/&lt;/g, '<')
	.replace(/&#92;/g, "\\")	// for JSON data
}
window.tag_decode_amp = function(text) {
	return tag_decode(text).replace(/&amp;/g,'&');
}

//////////////////////////////////////////////////////////////////////////////
// link_keyのエンコード :: adiary.pmと同一の処理
//////////////////////////////////////////////////////////////////////////////
window.link_key_encode = function(text) {
	if (typeof text != 'string') { return ''; }
	return text.replace(/[^^\w!\(\)\*\-\.\~\/:;=]/g, function(data) {
		return '%' + ('0' + data.charCodeAt().toString(16)).substr(-2);
	}).replace(/^\//, './/');
}

//////////////////////////////////////////////////////////////////////////////
// 条件にマッチする親要素を最初にみつけるまで探索
//////////////////////////////////////////////////////////////////////////////
window.find_parent = function(obj, filter) {
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
window.insert_to_textarea = function(ta, text) {
	var start = ta.selectionStart;	// カーソル位置
	// カーソル移動
	ta.value = ta.value.substring(0, start)	+ text + ta.value.substring(start);
	start += text.length;
	ta.setSelectionRange(start, start);
}

//############################################################################
// ■その他jsファイル用サブルーチン
//############################################################################
//----------------------------------------------------------------------------
// ●ファイルサイズ等の書式を整える
//----------------------------------------------------------------------------
window.size_format = function(s) {
	function sprintf_3f(n){
		n = n.toString();
		var idx = n.indexOf('.');
		var len = (0<=idx && idx<3) ? 4 : 3;
		return n.substr(0,len);
	}

	if (s > 104857600) {	// 100MB
		s = Math.round(s/1048576);
		s = s.toString().replace(/(\d)(?=(\d\d\d)+(?!\d))/g, '$1,');
		return s + ' MB';
	}
	if (s > 1023487) return sprintf_3f( s/1048576 ) + ' MB';
	if (s >     999) return sprintf_3f( s/1024    ) + ' KB';
	return s + ' Byte';
}

//----------------------------------------------------------------------------
// ●さつきタグ記号のエスケープ
//----------------------------------------------------------------------------
window.esc_satsuki_tag = function(str) {
	return str.replace(/([:\[\]])/g, function(w,m){ return "\\" + m; });
}
window.unesc_satsuki_tag = function(str) {
	return str.replace(/\\([:\[\]])/g, "$1");
}

