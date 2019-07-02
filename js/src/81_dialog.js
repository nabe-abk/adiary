//############################################################################
// ダイアログ関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●エラーの表示
//////////////////////////////////////////////////////////////////////////////
window.show_error = function(h, _arg) {
	if (typeof(h) === 'string') h = {id: h, html:h, hash:_arg};
	h.dclass = (h.dclass ? h.dclass : '') + ' error-dialog';
	h.default_title = 'ERROR';
	return show_dialog(h);
}
window.show_dialog = function(h, _arg) {
	if (typeof(h) === 'string') h = {id: h, html:h, hash:_arg};
	var obj  = h.id && h.id.substr(0,1) == '#' && $secure( h.id ) || $('<div>');
	var html = obj.html() || h.html;
	if (h.hash) html = html.replace(/%([A-Za-z])/g, function(w,m1){ return h.hash[m1] });
	html = html.replace(/%[A-Za-z]/g, '');

	var div = $('<div>');
	div.html( html );
	div.attr('title', h.title || obj.data('title') || h.default_title || 'Dialog');
	div.dialog({
		modal: true,
		dialogClass: h.dclass,
		buttons: { OK: function(){ div.dialog('close'); } }
	});
	return false;
}

//////////////////////////////////////////////////////////////////////////////
// ●確認ダイアログ
//////////////////////////////////////////////////////////////////////////////
window.my_confirm = function(h, callback) {
	if (typeof(h) === 'string') h = {id: h, html:h };
	let $obj = h.id && h.id.substr(0,1) == '#' && $secure( h.id ) || $('<div>');
	let html = $obj.html() || h.html;
	if (h.hash) html = html.replace(/%([A-Za-z])/g, function(w,m1){ return h.hash[m1] });

	callback = callback || h.callback;

	let $div = $('<div>');
	$div.html( html );
	$div.attr('title', h.title || $obj.data('title') || $('#ajs-confirm').text());
	let btn = {};
	btn[ h.btn_ok || $('#ajs-ok').text() ] = function(){
		div.dialog('close');
		callback(true);
	};
	btn[ h.btn_cancel || $('#ajs-cancel').text() ] = function(){
		div.dialog('close');
		callback(false);
	};
	$div.dialog({
		modal: true,
		dialogClass: h.class,
		buttons: btn,
		open: function(){
			// set default false
			//div.siblings('.ui-dialog-buttonpane').find('button:eq(0)').focus();
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●テキストエリア入力のダイアログ
//////////////////////////////////////////////////////////////////////////////
window.textarea_dialog = function(dom, func) {
	var obj  = $(dom);
	form_dialog({
		title: obj.data('title'),
		elements: [
			{type: 'p', html: obj.data('msg')},
			{type: 'textarea', name: 'ta'}
		],
		callback: function( h ) { func( h.ta ) }
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●入力のダイアログの表示
//////////////////////////////////////////////////////////////////////////////
window.form_dialog = function(h) {
	var ele = h.elements || { type:'text', name:'str', dclass:'w80p' };
	if (!Array.isArray(ele)) ele = [ ele ];
	var div = $('<div>').attr('id','popup-dialog');

	var form = $('<form>');
	for(var i=0; i<ele.length; i++) {
		var x = ele[i];
		if (!x) continue;
		if (typeof(x) == 'string') {
			var line = $('<div>').html(x);
			form.append( line );
			continue;
		}
		if (x.type == 'p') {
			form.append( $('<p>').html( x.html ) );
			continue;
		}
		if (x.type == 'textarea') {
			var t = $('<textarea>').attr({
				rows: x.rows || 5,
				name: x.name
			}).addClass('w100p');
			if (x.val != '') t.text( x.val );
			form.append( t );
			continue;
		}
		if (x.type == '*') {
			form.append( x.html );
			continue;
		}
		// else
		var inp = $('<input>').attr({
			type: x.type || 'text',
			name: x.name,
			value: x.val
		});
		inp.addClass( x.dclass || 'w80p');
		form.append( inp );
	}
	div.empty();
	div.append( form );

	// ボタンの設定
	var buttons = {};
	var ok_func = buttons[ $('#ajs-ok').text() ] = function(){
		var inputs = div.find('input');
		for(var i=0; i<inputs.length; i++) {
			var obj = inputs[i];
			if (obj.validity && !obj.validity.valid) return; // validation error
		}
		div.dialog( 'close' );
		var ret = {};
		var ary = form.serializeArray();
		for(var i=0; i<ary.length; i++){
			ret[ ary[i].name ] = ary[i].value.replace(/\r/g, '');
		}
		h.callback( ret );	// callback
	};
	buttons[ $('#ajs-cancel').text() ] = function(){
		div.dialog( 'close' );
		if (h.cancel) h.cancel();
	};
	// Enterキーによる送信防止
	form.on('keypress', 'input', function(evt) {
		if (evt.which === 13) { ok_func(); return false; }
		return true;
	});

	// ダイアログの表示
	div.dialog({
		modal: true,
		width:  DialogWidth,
		minHeight: 100,
		title:   h.title || $('#msg-setting-title').text(),
		buttons: buttons
	});
}
