//############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]
var insert_text;	// global function
$(function(){
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
	var link = $('#parser-help-link');
	var val = parsel.val();
	var url = link.data('default');
	if (val.match(/markdown/i)) url = link.data('markdown');
	link.attr('href', 'http://adiary.org/v3man/' + url);
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
	if (set.last_char() != '/') set += '/';
	lkey.val( set );
	lkey.data('set', set);
});

//############################################################################
// ■画像アルバムを開く
//############################################################################
var album_btn = $('#album-open');
album_btn.click(function(){
	var win = window.open(album_btn.data('url'), 'album', 'location=yes, menubar=no, resizable=yes');
	win.focus();
});

//############################################################################
// ■テキストエリア加工サブルーチン
//############################################################################
//----------------------------------------------------------------------------
// ●カーソル位置にテキスト挿入
//----------------------------------------------------------------------------
function _insert_text(text) {
	edit.focus();
	insert_to_textarea(edit[0], text);
}
insert_text = _insert_text;


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
		$('#edit').find('form, button, input, select').prop('disabled', true);

		dont_edit = true;
		display_lock_state(data);	// 編集中状態の表示
		set_lock_interval();
	});
}

function start_edit(){
	do_edit_lock();
	set_lock_interval();
	$('#edit').find('form, button, input, select').prop('disabled', false);
}

//----------------------------------------------------------------------------
// ●編集中の確認タイマーと手動確認
//----------------------------------------------------------------------------
var lock_interval;
function set_lock_interval() {
	// 接続時間を考慮し、少し短い間隔でロック処理する
	var diff = el_time * 0.9;
	if (diff > 5) diff=5;
	if (diff < 2) diff=2;
	lock_interval = setInterval(do_edit_lock, (el_time-diff)*1000 );
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
		lock_notice.show( Default_show_speed );
	else	lock_notice.hide( Default_show_speed );
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
}

//----------------------------------------------------------------------------
// ●ページを離れるときにunlock
//----------------------------------------------------------------------------
// IE8では無効
$(window).bind('unload', function(){
	ajax_edit_lock('ajax_lock', function(){}, 1);
});




///
});
