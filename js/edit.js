//############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]
'use strict';
var insert_text;	// global function
var IE8;
var IE9;
$(function(){
//############################################################################
var body = $('#body');
var tagsel = $('#tag-select');
var upsel  = $('#upnode-select');
var parsel = $('#select-parser');
var edit = $('#editarea');

load_taglist(tagsel);
load_contents_list(upsel);

var csrf_key = $('#csrf-key').val();

//############################################################################
// ■下書きを開く
//############################################################################
var sel_draft = $('#select-draft');
$('#open-draft').click(function(){
	var pkey = sel_draft.val();
	window.location = sel_draft.data('base-url') + '0' + pkey + '?edit';
});
$('#open-template').click(function(){
	var pkey = sel_draft.val();
	window.location = sel_draft.data('base-url') + '0' + pkey + '?edit&template=1';
});

//############################################################################
// ■タグの削除ボタン、タグの追加
//############################################################################
var tagdel = $('<span>').addClass('ui-icon ui-icon-close');
tagdel.click(function(evt){
	var obj = $(evt.target);
	obj.parent().remove();
});
$("#edit-tags span.tag").append(tagdel);

//----------------------------------------------------------------------------
// ●タグの追加
//----------------------------------------------------------------------------
tagsel.change(function(evt){
	if ($(':selected',tagsel).data('new')) return new_tag_append();
	var val = tagsel.val();
	tag_append( val );
});

function tag_append(tag_text) {
	if (tag_text=="") return;
	var tags = $('#tags');
	var ch = tags.children();
	for(var i=0; i<ch.length; i++) {
		if ($(ch[i]).text() == tag_text) return;
	}
	var tag = $('<span>').addClass('tag').html( tag_text );
	var inp = $('<input>').attr({
		type: 'hidden',
		name: 'tag_ary',
		value: tag_text
	});
	tag.append( inp, tagdel.clone(true) );
	tags.append(tag);
}

//----------------------------------------------------------------------------
// ●新規タグの追加
//----------------------------------------------------------------------------
var newtag_dialog = $('<div>');
body.append(newtag_dialog);
function new_tag_append() {
	var div = newtag_dialog;
	div.empty();
	var inp = $('<input>').attr('type', 'text').css('width', 200).addClass('mono');
	var p = $('<div>').html( $('#new-tag-msg').html() );
	div.append( inp, p );

	var buttons = {};
	buttons[ $('#new-tag-append').text() ] = tag_append_func;
	buttons[ $('#new-tag-cancel').text() ] = function(){
		div.dialog('close');
		tagsel.val('');
	}
	// enterで確定させる
	inp.keydown(function(evt){
		if (evt.keyCode != 13) return;
		return tag_append_func();
	});

	function tag_append_func() {
		var tag = inp.val();
		if (tag.match(',')) return false;
		tag_append( inp.val() );
		div.dialog('close');
		tagsel.val('');
	}

	div.dialog({
		modal: true,
		minWidth:  240,
		minHeight: 100,
		title: $('#new-tag-title').text(),
		buttons: buttons
	});
}

//############################################################################
// ■パーサーの変更
//############################################################################
parsel.change( parser_change );
parser_change();

function parser_change() {
	// 記法ヘルプのリンク先変更
	var link = $secure('#parser-help-link');
	var is_markdown = parsel.val().match(/^markdown/i);

	var url = is_markdown ? link.data('markdown') : link.data('default');
	link.attr('href', 'http://adiary.org/v3man/' + url);

	// 記法ヘルパー
	$('#btn-quote'     ).prop('disabled', is_markdown);
	$('#btn-annotation').prop('disabled', is_markdown);

	// 箇条書き
	$('#btn-list').data('tag', is_markdown ? '* ' : '-');
}

//############################################################################
// ■upnodeの変更 / link_keyの設定
//############################################################################
var upsel = $('#upnode-select');
var lkey  = $('#link-key');
upsel.change(function(){
	if (! lkey.data('suggest')) return;	// 機能がoff
	var val = lkey.val();
	if (val != '' && val != lkey.data('set')) return;

	var opt = upsel.children(':selected');
	if (!opt.length) return;

	var set = opt.data('link_key');
	if (set.rsubstr(1) != '/') set += '/';
	lkey.val( set );
	lkey.data('set', set);
});

//############################################################################
// ■画像アルバムを開く
//############################################################################
var album_btn = $secure('#album-open');
album_btn.click(function(){
	var win = window.open(album_btn.data('url'), 'album', 'location=yes, menubar=no, resizable=yes, scrollbars=yes');
	win.focus();
});

//############################################################################
// ■編集ロック機能
//############################################################################
var edit_pkey = $('#edit-pkey').val();
var el_time = $('#edit-lock-time').val();
var el_sid;
var dont_edit;

if (edit_pkey && el_time>9) {
	// 編集モード
	edit_pkey = '0' + edit_pkey;
	// sid生成
	var d = new Date();
	var el_sid;
	if (window.location.hash) {
		el_sid = window.location.hash.substr(1);
	} else {
		el_sid = d.getFullYear()
		+ '/' + ('00'+(d.getMonth()+1)).rsubstr(2)
		+ '/' + ('00' + d.getDate()   ).rsubstr(2)
		+ ' ' + ('00' + d.getHours()  ).rsubstr(2)
		+ ':' + ('00' + d.getMinutes()).rsubstr(2)
		+ ':' + ('00' + d.getSeconds()).rsubstr(2);
		window.location.hash = el_sid;
	}

	// 編集中の確認
	ajax_edit_lock('ajax_check_lock', edit_lock_checked);
}

//----------------------------------------------------------------------------
// ●編集中の確認結果
//----------------------------------------------------------------------------
function edit_lock_checked(data) {
	if (!data || !data.length) {
		return start_edit();
	}
	// 編集するか確認
	var html = '<ul>'
	for(var i in data) {
		html += '<li>' + data[i].id + ' (' + data[i].sid + ')' + '</li>';
	}
	html+='</ul>';
	my_confirm({
		id: '#edit-confirm',
		hash: { u: html }
	}, function(flag){
		if (flag) return start_edit();	// OK
		// CANCEL
		$('#edit').find('form, button:not(.helper), input, select').prop('disabled', true);

		dont_edit = true;
		display_lock_state(data);	// 編集中状態の表示
		set_lock_interval();
	});
}

function start_edit(){
	do_edit_lock();
	set_lock_interval();
	$('#edit').find('form, button:not(.helper), input, select').prop('disabled', false);

	// ページを離れるときにunlock	※IE8では無効
	$(window).bind('unload', function(){
		console.log('ajax_unlock');
		ajax_edit_lock('ajax_lock', function(){}, 1);
	});
}

//----------------------------------------------------------------------------
// ●編集中の確認タイマーと手動確認
//----------------------------------------------------------------------------
var lock_interval;
function set_lock_interval() {
	lock_interval = setInterval(do_edit_lock, el_time*1000 );
}

$('#force-lock-check').click(function(){
	clearInterval(lock_interval);
	do_edit_lock();
	set_lock_interval();
});
//----------------------------------------------------------------------------
// ●編集中ロックをかけつつ、現在のロック状況を表示
//----------------------------------------------------------------------------
var lock_notice = $('#edit-lock-notice');
var lockers_ul  = $('#edit-lockers');
function do_edit_lock() {
	ajax_edit_lock(dont_edit ? 'ajax_check_lock' : 'ajax_lock', display_lock_state);
}

function display_lock_state(data) {
	if (data && data.length)
		lock_notice.delay_show();
	else	lock_notice.delay_hide();
	// 編集中の人々
	lockers_ul.empty();
	for(var i in data) {
		var li = $('<li>').text(data[i].id + ' (' + data[i].sid + ')');
		lockers_ul.append(li);
	}
	var d = new Date();
	$('#check-time').text(
		('00' + d.getHours()  ).rsubstr(2)
	+ ':' + ('00' + d.getMinutes()).rsubstr(2)
	+ ':' + ('00' + d.getSeconds()).rsubstr(2)
	);
}

//----------------------------------------------------------------------------
// ●ロックAjax処理
//----------------------------------------------------------------------------
function ajax_edit_lock(action, func, unlock) {
	$.ajax({
		type: 'POST',
		url: Vmyself + '?etc/ajax_dummy',
		dataType: 'json',
		data: {
			action: action,
			csrf_check_key: csrf_key,
			name: edit_pkey,
			sid: el_sid,
			unlock: unlock || '0'
		},
		success: func
	});
	return ;
}

//############################################################################
// ■テキストエリア加工サブルーチン
//############################################################################
//----------------------------------------------------------------------------
// ●カーソル位置にテキスト挿入
//----------------------------------------------------------------------------
function _insert_text(text) {
	edit.focus();
	insert_to_textarea(edit[0], text);	// adiary.js
}
insert_text = _insert_text;

//----------------------------------------------------------------------------
// ●選択範囲のテキスト取得
//----------------------------------------------------------------------------
var range_st;
var range_end;
function get_selection() {
	var ta = edit[0];
	var start = range_st  = ta.selectionStart;
	var end   = range_end = ta.selectionEnd;
	if (start == undefined) {	// for IE8
		edit.focus();
		var len = function(text) {
			return text.replace(/\r/g, "").length;
		};
		var sel = document.selection.createRange();
		var p   = document.body.createTextRange();
		p.moveToElementText( ta );
		p.setEndPoint( "StartToStart", sel );
		range_st  = len(ta.value) - len(p.text);
		range_end = range_st + len(sel.text);
		return sel.text;
	}
	return ta.value.substring(start, end);
}

//----------------------------------------------------------------------------
// ●選択範囲のテキストを置き換え
//----------------------------------------------------------------------------
function replace_selection( text ) {
	var ta = edit[0];
	var start = IE9 ? range_st  : ta.selectionStart;	// for IE9
	var end   = IE9 ? range_end : ta.selectionEnd;
	if (ta.selectionStart == undefined) {	// for IE8
		edit.focus();
		var range = ta.createTextRange();
		range.collapse();
		range.moveStart('character', range_st );
		range.moveEnd  ('character', range_end - range_st );
		range.text = text;
		return ;
	}
	// 置き換え
	ta.value = ta.value.substring(0, start) + text + ta.value.substr(end);
	// カーソル移動
	if (text.substr(0,1) == "\n") { start+=1; }
	ta.setSelectionRange(start, start + text.length );
}

//############################################################################
// ■記法ヘルパー機能
//############################################################################
// <button type="button" id="btn-strong">太字</button>
// <button type="button" id="btn-link">リンク</button>
// <button type="button" id="btn-google">検索</button>
// <button type="button" id="btn-list">箇条書き</button>
// <button type="button" id="btn-annotation">注釈</button>
//
//----------------------------------------------------------------------------
// ●インラインタグ汎用処理
//----------------------------------------------------------------------------
function inline_tag_btn(evt) {
	var obj = $(evt.target);
	var tag_st  = obj.data('start');
	var tag_end = obj.data('end');
	var text = get_selection();
	if (text) {
		text = parse_lines(text, function(str) {
			return tag_st + esc_satsuki_tag(str) + tag_end;
		})
		return replace_selection(text);
	}

	form_dialog({
		title: obj.data('msg'),
		callback: function (h) {
			if (!h.str) return;
			insert_text(tag_st + h.str + tag_end);
		}
	});
}

//----------------------------------------------------------------------------
// ●太字、注釈
//----------------------------------------------------------------------------
$secure('#btn-strong'    ).click( inline_tag_btn );
$secure('#btn-annotation').click( inline_tag_btn );

//----------------------------------------------------------------------------
// ●リンク生成
//----------------------------------------------------------------------------
function link_tag_btn(evt, func) {
	var obj = $(evt.target);
	var text = get_selection();
	if (0 <= text.indexOf("\n"))	// 複数行は処理しない
		return show_error('#msg-multiline');

	form_dialog({
		title: obj.data('msg'),
		elements: [
			obj.data('msg1'),
			{type:'text', name:'str1', val:obj.data('val1'), dclass:'w240' },
			obj.data('msg2'),
			{type:'text', name:'str2', val: text }
		],
		callback: func || function (h) {
			if (h.str1 == '') return;
			if (h.str2 != '') h.str2 = ':' + h.str2;
			h.str1 = esc_satsuki_tag(h.str1);
			replace_selection( obj.data('start') + h.str1 + h.str2 + obj.data('end') );
		}
	});
}
$secure('#btn-link').click( function(evt) {
	link_tag_btn(evt, function (h) {
		if (h.str1 == '') return;
		if (h.str2 == '') return;
		var ma = h.str1.match(/^(https?:\/\/)(.+)/i);
		if (! ma) return;
		var url = ma[1] + esc_satsuki_tag(ma[2]);
		replace_selection( '[' + url + ':' + h.str2 + ']' );
	});
});
$secure('#btn-google').click( link_tag_btn );

//----------------------------------------------------------------------------
// ●色変え、フォント変え
//----------------------------------------------------------------------------
function font_change(evt) {
	var obj = $(evt.target);
	var val = obj.val();
	if (val == '') return;
	obj.data('start', obj.data('start-base') + val + ':' );
	inline_tag_btn(evt);
	obj.val('');
}
$secure('#select-color'   ).val('').change( font_change );
$secure('#select-fontsize').val('').change( font_change );

//----------------------------------------------------------------------------
// ●ブロックタグ汎用処理
//----------------------------------------------------------------------------
function block_tag_btn(evt) {
	if (edit[0].selectionStart == undefined)	// IE8 非対応
		return show_error('#msg-for-ie8');

	var obj = $(evt.target);
	block_selection_fix(evt);	// 選択範囲調整

	var tag     = (obj.data('tag')   || '');
	var tag_st  = (obj.data('start') || '') + "\n";
	var tag_end = "\n" + (obj.data('end') || '');

	var text = get_selection();
	if (text) {
		text = parse_lines_for_block(text, tag);
		return replace_selection(tag_st + text + tag_end);
	}

	form_dialog({
		title: obj.data('msg'),
		elements: {type:'textarea', name:'str' },
		callback: function (h) {
			if (!h.str) return;
			var str = parse_lines_for_block(h.str, tag);
			insert_text(tag_st + str + tag_end + "\n");
		}
	});
}

//----------------------------------------------------------------------------
// ●リストと引用タグ
//----------------------------------------------------------------------------
$secure('#btn-list' ).click( block_tag_btn );

$secure('#btn-quote').click( function(evt) {
	if (edit[0].selectionStart == undefined)	// IE8 非対応
		return show_error('#msg-for-ie8');

	var obj = $(evt.target);
	obj.data('start', obj.data('start-base'));
	if (IE9) return block_tag_btn(evt);		// ダイアログを出すと選択範囲が消えてしまう

	form_dialog({
		title: obj.data('msg'),
		elements: [
			{type:'p', html: obj.data('sp-msg') },
			{type:'text', name: 'url', val: 'http://' }
		],
		callback: function(h) {
			var start = obj.data('start-base');
			if (h.url.match(/^(https?:\/\/)(.+)/i))
				start += '[&' + h.url + ']';

			obj.data('start', start);
			block_tag_btn(evt);
		},
		cancel: function() {
			block_tag_btn(evt);
		}
	});
});

//----------------------------------------------------------------------------
// ● 選択範囲やカーソル位置を行ごとに調整する
//----------------------------------------------------------------------------
function block_selection_fix(evt) {
	var obj = $(evt.target);
	var ta  = edit[0]
	var start = ta.selectionStart;
	var end   = ta.selectionEnd;

	if (start == end) {	// 範囲選択なし
		// 行頭なら動かさない
		if (start == 0 || ta.value.substr(start -1,1) == "\n")
			return ;

		// 行の途中なら次の行頭へ
		var x = ta.value.indexOf("\n", start);
		if (x<0) {
			if (ta.value.rsubstr(1) != "\n") ta.value += "\n";
			start = end = ta.value.length;
		} else
			start = end = x+1;

	} else { 		// 選択範囲あり
		var x = ta.value.lastIndexOf("\n", start);
		start = (x<0) ? 0 : x+1;
		var x = ta.value.indexOf("\n", end);
		end = (x<0) ? ta.value.length : x;
	}
	ta.setSelectionRange(start, end);
	edit.focus();
}

//----------------------------------------------------------------------------
// ●行ごとに処理
//----------------------------------------------------------------------------
function parse_lines(text, func) {
	var ary = text.split(/\r?\n/);
	for(var i=0; i<ary.length; i++) {
		if (ary[i] == '') continue;
		ary[i] = func(ary[i]);
	}
	return ary.join("\n");
}

function parse_lines_for_block(text, tag) {
	var ary = text.split(/\r?\n/);
	while(ary[ary.length-1] == '') ary.pop();
	while(ary[0]            == '') ary.shift();
	for(var i=0; i<ary.length; i++) {
		ary[i] = tag + ary[i];
	}
	return ary.join("\n");
}


//----------------------------------------------------------------------------
// ●さつきタグ記号のエスケープ
//----------------------------------------------------------------------------
function esc_satsuki_tag(str) {
	return str.replace(/([:\[\]])/g, function(w,m){ return "\\" + m; });
}

//############################################################################
});
