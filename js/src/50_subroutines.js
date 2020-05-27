//############################################################################
// ■サブルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// CSS append
//////////////////////////////////////////////////////////////////////////////
$$.prepend_css = function(file) {
	const $link = $("<link>")
	$link.attr({
		rel: "stylesheet",
		href: file
	});
	this.$head.prepend($link);
	return $link;
}

//////////////////////////////////////////////////////////////////////////////
// add style
//////////////////////////////////////////////////////////////////////////////
$$.append_style = function(css) {
	const $style = $('<style>').attr('type','text/css').html(css || '');
	this.$head.append($style);
	return $style;
}

//////////////////////////////////////////////////////////////////////////////
// load script
//////////////////////////////////////////////////////////////////////////////
$$.inc = {};
$$.load_script = function(url, func) {
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
// escape html tag
//////////////////////////////////////////////////////////////////////////////
$$.tag_esc = function(text) {
	return text
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;')
}
$$.tag_esc_br = function(text) {
	return this.tag_esc(text).replace(/\n|\\n/g,'<br>');
}
$$.tag_esc_amp = function(text) {
	return this.tag_esc( text.replace(/&/g,'&amp;') );
}
$$.tag_decode = function(text) {
	return text
		.replace(/&apos;/g, "'")
		.replace(/&quot;/g, '"')
		.replace(/&gt;/g, '>')
		.replace(/&lt;/g, '<')
		.replace(/&#92;/g, "\\")	// for JSON data
}
$$.tag_decode_amp = function(text) {
	return this.tag_decode(text).replace(/&amp;/g,'&');
}

//////////////////////////////////////////////////////////////////////////////
// insert to textarea
//////////////////////////////////////////////////////////////////////////////
$$.insert_to_textarea = function(ta, text) {
	var start = ta.selectionStart;	// current cursol
	ta.value  = ta.value.substring(0, start) + text + ta.value.substring(start);
	start += text.length;
	ta.setSelectionRange(start, start);
}

//////////////////////////////////////////////////////////////////////////////
// parse form
//////////////////////////////////////////////////////////////////////////////
$$.parse_form = function($par, cancel) {
	const data = {};
	const $cancel = (cancel instanceof jQuery) ? cancel
		: (cancel === undefined ? cancel : $(cancel));

	$par.find('input, select, textarea').each(function(idx, dom){
		if (dom.disabled) return;
		if (dom.type == 'checkbox' && !dom.checked) return;
		if ($cancel && $cancel.find(dom).length) return;

		const $obj = $(dom);
		const name = $obj.attr('name');
		if (name == undefined || name == '') return;
		data[name] = $obj.val();
	});
	return data;
};

//////////////////////////////////////////////////////////////////////////////
// Cookie
//////////////////////////////////////////////////////////////////////////////
$$.set_cookie = function(name, val) {
	document.cookie = encodeURIComponent(name) + '=' + encodeURIComponent(val) + '; SameSite=Lax;';
}
$$.get_cookie = function(name) {
	var ary = document.cookie.split(/; */);
	for (var i=0; i<ary.length; i++) {
		var x = ary[i].split('=', 2);
		var k = decodeURIComponent( x[0] );
		if (name != k) continue;
		return decodeURIComponent( x[1] );
	}
	return;
}

//////////////////////////////////////////////////////////////////////////////
// file size format
//////////////////////////////////////////////////////////////////////////////
$$.size_format = function(s) {
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
