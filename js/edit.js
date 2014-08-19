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
	
	var edit = $('#editarea');

	load_taglist(tagsel);
	load_contents_list(upsel);

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
	var p = $('<p>').html( $('#new-tag-msg').text() );
	div.append( inp, p );

	var buttons = {};
	buttons[ $('#new-tag-append').text() ] = function(){
		tag_append( inp.val() );
		div.dialog('close');
		tagsel.val('');
	}
	buttons[ $('#new-tag-cancel').text() ] = function(){
		div.dialog('close');
		tagsel.val('');
	}

	// enterで確定させる
	inp.keydown(function(evt){
		if (evt.keyCode != 13) return;
		tag_append( inp.val() );
		div.dialog('close');
		tagsel.val('');
	});

	div.dialog({
		modal: true,
		minWidth:  240,
		minHeight: 100,
		title: $('#new-tag-title').text(),
		buttons: buttons
	});
}

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
	var ta  = edit[0];		// textarea element
	var start = ta.selectionStart;	// カーソル位置
	if (start == undefined) {
		// for IE8
		var tmp = document.selection.createRange();
		tmp.text = text;
		return ;
	}
	// カーソル移動
	ta.value = ta.value.substring(0, start)	+ text + ta.value.substring(start);
	start += text.length;
	ta.setSelectionRange(start, start);
}
insert_text = _insert_text;



///
});
