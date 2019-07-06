//############################################################################
// ■サブルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// CSSファイルの追加
//////////////////////////////////////////////////////////////////////////////
adiary.prepend_css = function(file) {
	const $link = $("<link>")
	$link.attr({
		rel: "stylesheet",
		href: file
	});
	this.$head.prepend($link);
	return $link;
}

//////////////////////////////////////////////////////////////////////////////
// スタイルの追加
//////////////////////////////////////////////////////////////////////////////
adiary.append_style = function(css) {
	const $style = $('<style>').attr('type','text/css').html(css || '');
	this.$head.append($style);
	return $style;
}

//////////////////////////////////////////////////////////////////////////////
// load script
//////////////////////////////////////////////////////////////////////////////
adiary.inc = {};
adiary.load_script = function(url, func) {
	const inc = this.inc;
	const x   = inc[url];
	if (x) {
		if (!func) return;
		if (x==1) return func();
		// now loading
		x.on('load', func);
		return;
	}

	const $s = $(document.createElement('script'));
	inc[url] = $s;
	$s.attr('src',   url);
	$s.attr('async', 'async');

	if (func) $s.on('load', function(evt){
		inc[url] = 1;
		func(evt);
	});

	// Do not work and "sync" download by jQuery
	// this.$head.append( $s );

	this.$head[0].appendChild( $s[0] );
}

//////////////////////////////////////////////////////////////////////////////
// load message
//////////////////////////////////////////////////////////////////////////////
adiary.msg = function(key) {
	if (!this.msgs) this.load_msg();
	return this.msgs[key];
}
adiary.load_msg = function(key) {
	const msgs = {};

	$('[data-secure].adiary-msgs').each(function(idx,dom) {
		try {
			const json = $(dom).html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			for(var i in data)
				msgs[i] = data[i];
		} catch(e) {
			console.error(e);
		}
	});
	this.msgs = msgs;
}

//////////////////////////////////////////////////////////////////////////////
// タグ除去
//////////////////////////////////////////////////////////////////////////////
adiary.tag_esc = function(text) {
	return text
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;')
}
adiary.tag_esc_br = function(text) {
	return this.tag_esc(text).replace(/\n|\\n/g,'<br>');
}
adiary.tag_esc_amp = function(text) {
	return this.tag_esc( text.replace(/&/g,'&amp;') );
}
adiary.tag_decode = function(text) {
	return text
		.replace(/&apos;/g, "'")
		.replace(/&quot;/g, '"')
		.replace(/&gt;/g, '>')
		.replace(/&lt;/g, '<')
		.replace(/&#92;/g, "\\")	// for JSON data
}
adiary.tag_decode_amp = function(text) {
	return this.tag_decode(text).replace(/&amp;/g,'&');
}

//////////////////////////////////////////////////////////////////////////////
// テキストエリアに文字挿入
//////////////////////////////////////////////////////////////////////////////
adiary.insert_to_textarea = function(ta, text) {
	var start = ta.selectionStart;	// カーソル位置
	ta.value  = ta.value.substring(0, start) + text + ta.value.substring(start);
	start += text.length;
	ta.setSelectionRange(start, start);
}

//############################################################################
// ■その他jsファイル用サブルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●ファイルサイズ等の書式を整える
//////////////////////////////////////////////////////////////////////////////
adiary.size_format = function(s) {
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

//////////////////////////////////////////////////////////////////////////////
// ●さつきタグ記号のエスケープ
//////////////////////////////////////////////////////////////////////////////
adiary.esc_satsuki_tag = function(str) {
	return str.replace(/([:\[\]])/g, function(w,m){ return "\\" + m; });
}
adiary.unesc_satsuki_tag = function(str) {
	return str.replace(/\\([:\[\]])/g, "$1");
}
