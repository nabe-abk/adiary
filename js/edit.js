//############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_text;	// global function
var insert_image;	// global function for album.js
var DialogWidth;
var IE11;
var html_mode;		// html input mode

$(function(){
//############################################################################
var body = $('#body');
var tagsel = $secure('#tag-select');
var upsel  = $secure('#upnode-select');
var parsel = $('#select-parser');
var edit   = $('#editarea');

var addtag  = $secure('#edit-add-tag');
var dndbody = $('#edit');

load_tags_list(tagsel);
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
//----------------------------------------------------------------------------
// ●タグの削除ボタン（×ボタン）
//----------------------------------------------------------------------------
var tagdel = $('<span>').addClass('ui-icon ui-icon-close');
tagdel.click(function(evt){
	var obj = $(evt.target);
	obj.parent().remove();
});
$("#edit-tags span.tag").append( tagdel.clone(true) );

//----------------------------------------------------------------------------
// ●タグ追加ダイアログの表示
//----------------------------------------------------------------------------
var tagsel_dialog;
var tagsel_form = $secure('#tag-select-form').detach();
addtag.click( function(){
	var form = $('<form>').append( tagsel_form );
	var div  = $('<div>') .append( form  );

	// 入力要素
	var inp = form.find('#input-new-tag');

	//enterで確定させる
	function tag_append_func() {
		var tag = inp.val();
		if (tag.match(',')) return false;
		tag_append( tag );
		div.dialog('close');
		return false;
	}
	inp.keydown(function(evt){
		if (evt.keyCode != 13) return;
		return tag_append_func();
	});

	// ボタンの設定
	var buttons = {};
	var ok_func = buttons[$('#new-tag-append').text()] = tag_append_func;
	buttons[ $('#ajs-cancel').text() ] = function(){
		div.dialog( 'close' );
	};
	div.dialog({
		modal: true,
		minWidth:  240,
		minHeight: 200,
		title:   addtag.data('title'),
		buttons: buttons,
		beforeClose: function(){
			tagsel.val('');
			inp.val('');
		}
	});
	tagsel_dialog = div;
});

//----------------------------------------------------------------------------
// ●タグ選択フォームの処理
//----------------------------------------------------------------------------
tagsel.change(function(){
	if ($(':selected',tagsel).data('new')) return;
	tag_append( tagsel.val() );
	tagsel_dialog.dialog( 'close' );
});

//----------------------------------------------------------------------------
// ●タグの追加
//----------------------------------------------------------------------------
function tag_append(tag_text) {
	if (tag_text=="") return;
	var tags = $('#tags');
	var ch = tags.children();
	for(var i=0; i<ch.length; i++) {
		if ($(ch[i]).text() == tag_text) return;
	}
	var tag = $('<span>').addClass('tag').html( tag_esc_amp(tag_text) );
	var inp = $('<input>').attr({
		type: 'hidden',
		name: 'tag_ary',
		value: tag_text
	});
	tag.append( inp, tagdel.clone(true) );
	tags.append(tag);
}

//############################################################################
// ■公開状態の変更
//############################################################################
var echk = $('#enable-chk');
var dchk = $('#draft-chk');
echk.change( echk_change );
dchk.change( echk_change );
echk_change();

function echk_change() {
	if (dchk.prop('checked')) {	// 下書き
		$('.save-btn-title').text( dchk.data('on') );
		return;
	}
	if (echk.prop('checked'))
		$('.save-btn-title').text( echk.data('on') );
	else
		$('.save-btn-title').text( echk.data('off') );
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
	if (set == undefined) return;
	if (set.substr(-1) != '/') set += '/';
	lkey.val( set );
	lkey.data('set', set);
});

//############################################################################
// ■編集ロック機能
//############################################################################
var edit_pkey = $('#edit-pkey').val();
var edit_sid;
var el_time   = $('#edit-lock-time').text() || 0;
var do_edit;

// 初期化
if (Storage.defined('edit_pkey')) {
	// ロック済みの場合解除
	ajax_edit_unlock({
		name: Storage.get('edit_pkey'),
		sid:  Storage.get('edit_sid'),
		callback: edit_mode
	});
	Storage.remove('edit_pkey');
	Storage.remove('edit_sid');
} else {
	edit_mode();
}

function edit_mode() {
	if (!edit_pkey || el_time<10) {
		do_edit = true;
		return;
	}

	// 編集モード
	edit_pkey = '0' + edit_pkey;
	// sid生成
	var d = new Date();
	if (window.location.hash) {
		edit_sid = window.location.hash.substr(1).replace('%20', ' ');
	} else {
		edit_sid = d.getFullYear()
		+ '/' + ('00'+(d.getMonth()+1)).substr(-2)
		+ '/' + ('00' + d.getDate()   ).substr(-2)
		+ ' ' + ('00' + d.getHours()  ).substr(-2)
		+ ':' + ('00' + d.getMinutes()).substr(-2)
		+ ':' + ('00' + d.getSeconds()).substr(-2);
		window.location.hash = edit_sid;
	}

	// 編集中の確認
	ajax_check_lock({
		name: edit_pkey,
		sid:  edit_sid,
		callback: edit_lock_checked
	});
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
		$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', true);
		$('#edit').find('textarea').prop('readonly', true);
		$('#del-submit-check').prop('checked', false).change();

		do_edit = false;
		display_lock_state(data);	// 編集中状態の表示
		set_lock_interval();
	});
}

function start_edit(){
	do_edit = true;
	do_edit_lock();
	set_lock_interval();

	// リロード時に使えるようにするための設定
	$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', false);
	$('#edit').find('textarea').prop('readonly', false);
	if (!window.FormData) $('#edit').find('.js-fileup').prop('disabled', true);

	// ページを離れるときにunlock
	$(window).on('unload', function(){
		Storage.set('edit_pkey', edit_pkey);
		Storage.set('edit_sid',  edit_sid);
	});
}

//----------------------------------------------------------------------------
// ●編集中の確認タイマーと手動確認
//----------------------------------------------------------------------------
var lock_interval;
function set_lock_interval() {
	if (el_time<1) return;
	lock_interval = setInterval(do_edit_lock, el_time*1000);
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
	ajax_edit_lock({
		action: do_edit ? 'ajax_lock' : 'ajax_check_lock',
		name: edit_pkey,
		sid:  edit_sid,
		callback: display_lock_state
	});
}

function display_lock_state(data) {
	lockers_ul.empty();
	if (data && data.length)
		lock_notice.showDelay();
	else {
		lock_notice.hideDelay();
		if (!do_edit) start_edit();
	}
	// 編集中の人々を表示
	for(var i in data) {
		var li = $('<li>').text(data[i].id + ' (' + data[i].sid + ')');
		lockers_ul.append(li);
	}
	var d = new Date();
	$('#check-time').text(
		('00' + d.getHours()  ).substr(-2)
	+ ':' + ('00' + d.getMinutes()).substr(-2)
	+ ':' + ('00' + d.getSeconds()).substr(-2)
	);
}

//----------------------------------------------------------------------------
// ●ロックAjax処理
//----------------------------------------------------------------------------
function ajax_edit_unlock(opt) {
	opt.unlock = 1;
	return ajax_edit_lock(opt);
}
function ajax_check_lock(opt) {
	opt.action = 'ajax_check_lock';
	return ajax_edit_lock(opt);
}

function ajax_edit_lock(opt) {
	opt.action = opt.action || 'ajax_lock';
	console.log(opt.unlock ? 'ajax_unlock' : opt.action, opt.name, opt.sid);

	var param = {
		type: 'POST',
		url: Vmyself + '?etc/ajax_dummy',
		dataType: 'json',
		data: {
			action: opt.action,
			csrf_check_key: csrf_key,
			name: opt.name,
			sid: opt.sid,
			unlock: opt.unlock || '0'
		}
	};
	if (opt.callback) param.success = opt.callback;
	$.ajax( param );
}

//############################################################################
// ■テキストエリア加工サブルーチン
//############################################################################
//----------------------------------------------------------------------------
// ●カーソル位置にテキスト挿入
//----------------------------------------------------------------------------
// save to global for album.js
insert_image = function(text, caption, fig_class) {
	if (html_mode) {
		var imgdir = $('#image-dir').text();
		text = text.replace(/\[image:((?:\\[:\[\]]|[^\]])+)\]/g, function(ma, m1){
			var ary = m1.split(':');
			var thumb1 = (ary[0] == 'S') ? '.thumbnail/' : '';
			var thumb2 = (ary[0] == 'S') ? '.jpg'        : '';
			ary[1] = unesc_satsuki_tag( ary[1] );
			ary[2] = unesc_satsuki_tag( ary[2] );
			var file = imgdir + ary[1] + ary[2];
			var img  = imgdir + ary[1] + thumb1 + ary[2] + thumb2;
			// 属性
			var attr = '';
			var $info = $('#imglink-info');
			attr += $info.data('class')  ? ( ' class="' + $info.data('class')  + '"') : '';
			attr += $info.data('target') ? (' target="' + $info.data('target') + '"') : '';
			var data = $info.data('data');
			if (data) {
				var k = $('#edit-pkey').val()*1 || floor((new Date()).getTime());
				var ary = data.replace(/%k/g, k).split(/\s+/);
				for(var i=0; i<ary.length; i++) {
					var at = ary[i];
					var ma = at.match(/^([A-Za-z][\w\-]*)=(.*)/);
					if (!ma) continue;
					attr += ' data-' + ma[1] + '="' + ma[2] + '"';
				}
			}
			return '<figure class="image">'
				+ '<a href="' + file + '"' + attr + '>'
				+ '<img src="' + img + '">'
				+ '</a></figure>';
		});
		text = text.replace(/\[file:((?:\\[:\[\]]|[^\]])+)\]/g, function(ma, m1){
			var ary = m1.split(':');
			var ext = ary[0];
			ary[1] = unesc_satsuki_tag( ary[1] );
			ary[2] = unesc_satsuki_tag( ary[2] );
			ary[3] = unesc_satsuki_tag( ary[3] );
			return '<a href="' + imgdir + ary[1] + ary[2] + '">'
				+ ary[3] + '</a>';
		});
	}

	//------------------------------------------------------------------
	// キャプションとブロックの処理
	//------------------------------------------------------------------
	if (caption) caption = caption.replace(/^\s+/,'').replace(/\s+$/,'');
	if (caption || fig_class) {
		caption = caption ? caption : '';
		fig_class  = fig_class  ? fig_class  : '';
		if (helper_mode == 'default') {
			if (caption) fig_class = fig_class + ((fig_class == '') ? '' : ' ') + "caption=" + caption
			if (fig_class) {
				text = "\n>>|figure " + fig_class + "\n"
					+ text + "\n" +
					"|<<\n";
			}
		} else {
			text = (helper_mode == 'markdown' ? ' ' : '')
				+ "\n" + '<figure class="' + fig_class + '">'
				+ text
				+ (caption ? '<figcaption>'+ tag_esc_amp(caption) +'</figcaption>' : '').toString()
				+ "</figure>\n";
		}
	}
	return insert_text(text);
}
insert_text = function(text) {
	edit.focus();
	insert_to_textarea(edit[0], text);	// adiary.js
}

//----------------------------------------------------------------------------
// ●選択範囲のテキスト取得
//----------------------------------------------------------------------------
function get_selection() {
	var ta = edit[0];
	var start = ta.selectionStart;
	var end   = ta.selectionEnd;
	return ta.value.substring(start, end);
}

//----------------------------------------------------------------------------
// ●選択範囲のテキストを置き換え
//----------------------------------------------------------------------------
function replace_selection( text ) {
	var ta = edit[0];
	var start = ta.selectionStart;
	var end   = ta.selectionEnd;
	// 置き換え
	ta.value = ta.value.substring(0, start) + text + ta.value.substr(end);
	// カーソル移動
	if (text.substr(0,1) == "\n") { start+=1; }
	ta.setSelectionRange(start, start + text.length );
}

//############################################################################
// ■ファイルアップロード機能
//############################################################################
var $upform   = $('#upload-form').detach();
var $file_btn = $upform.find('#file-btn');
var $file_div = $upform.find('#file-btn-div');
var $fileup   = $secure('#edit-file-upload');
//----------------------------------------------------------------------------
// ●アップロードダイアログ
//----------------------------------------------------------------------------
$fileup.click(function(){
	update_files_view([]);
	open_upload_dialog();
});
function open_upload_dialog(files) {
	var div = $('<div>').append( $upform );
	var cnt = 0;

	if (files) {
		$file_div.hide();
		update_files_view(files);
	} else {
		$file_div.show();
	}

	// 設定済サムネイルサイズをロードさせるためのidの細工
	var thsize = $upform.find('select.thumbnail-size');
	if (thsize.length==1) thsize.attr('id', 'thumbnail-size');

	// ボタンの設定
	var buttons = {};
	var ok_func = buttons['Upload'] = function(){
		if (!files && !$file_btn.val()) return;	// no selected

		div.parent().find('.ui-button').button("option", "disabled", true);

		ajax_upload( $upform[0], files, {
			callback: function(data, folder){
				upload_files_insert(data, folder, {
					exif: $('#paste-to-exif').prop('checked'),
					caption: $('#paste-caption').val(),
					fig_class: $('#paste-class').val(),
					img_tag:  $upform.find('#paste-imgtag').val(),
					file_tag: $('#paste-tag').data('file'),
					exif_tag: $('#paste-tag').data('exif')
				});
			},
			complete: function(){
				div.dialog( 'close' );
				$upform.detach();
				div.remove();
			}
		});

		$file_btn.val('');
	};
	buttons[ $('#ajs-cancel').text() ] = function(){
		div.dialog( 'close' );
		$upform.detach();
		div.remove();
	};
	div.dialog({
		modal: true,
		width:  DialogWidth,
		// minHeight: 200,
		title:   $fileup.data('title'),
		buttons: buttons
	});
}
//----------------------------------------------------------------------------
// ●選択ファイル一覧表示 / ファイル選択後の処理
//----------------------------------------------------------------------------
function update_files_view(files) {
	var $div = $upform.find('#dnd-files');
	$div.empty();
	for(var i=0; i<files.length; i++) {
		if (!files[i]) continue;
		var fs  = size_format(files[i].size);
		var div = $('<div>').text(
			files[i].name + ' (' + fs + ')'
		);
		$div.append(div);
	}
}

$file_btn.on('change', function() {
	var files = $file_btn[0].files;
	update_files_view(files)
});

//----------------------------------------------------------------------------
// ●アップロード後の処理
//----------------------------------------------------------------------------
function upload_files_insert(data, folder, opt) {
	try {
		data['fail']    = parseInt(data['fail']);
		data['success'] = parseInt(data['success']);
		data['ret']     = parseInt(data['ret']);
	} catch(e) {
	}

	if (data['fail']) {
		show_error('#msg-upload-fail', {
			n: data['fail'] + data['success'],
			f: data['fail'],
			s: data['success']
		});
	} else if (data['ret']) {
		show_error('#msg-upload-error');
	}

	// 記事に挿入
	var ary = data['files'];
	if (!data['success'] || !ary) return;

	var exiftag = opt.exif ? opt.exif_tag : null;
	var text = '';
	var esc_dir = esc_satsuki_tag(folder);
	for(var i=0; i<ary.length; i++) {
		var name = ary[i].name;
		var reg  = name.match(/\.(\w+)$/);
		var ext  = reg ? reg[1] : '';
		var rep  = {
			d: esc_dir,
			e: esc_satsuki_tag(ext),
			f: esc_satsuki_tag(name),
			c: ''
		};
		if (exiftag && name.match(/\.jpe?g$/i)) {
			rep.c = exiftag.replace(/%([def])/g, function($0,$1){ return rep[$1] });
		}

		// タグ生成
		var tag = ary[i].isImg ? opt.img_tag : opt.file_tag;
		tag = tag.replace(/%([cdef])/g, function($0,$1){ return rep[$1] });
		// 記録
		text += (text ? "\n" : "") + tag;
	}

	insert_image(text, opt.caption, opt.fig_class);
}

//----------------------------------------------------------------------------
// ●アップロード処理
//----------------------------------------------------------------------------
function ajax_upload( form_dom, files, option ) {
	var date = $('#edit-date').val().toString() || '';
	var year;
	var mon;
	if (date.match(/^\d\d\d\d[\-\/]\d\d/)) {
		year = date.substr(0,4);
		mon  = date.substr(5,2);
	} else {
		var d = new Date();
		year = d.getFullYear();
		mon  = (101 + d.getMonth()).toString().substr(1);
	}
	var folder = $fileup.data('folder');
	if (folder == '') folder='adiary/%y/';
	folder = folder.replace('%y', year).replace('%m', mon).replace(/^\/+/, '');

	// FormData生成
	var fd = new FormData( form_dom );
	if (!IE11 && !$file_btn.val()) fd.delete('_file_btn');
	fd.append('csrf_check_key', $('#csrf-key').val());
	fd.append('action', 'etc/ajax_upload');
	fd.append('folder', folder);

	// DnDされたファイル
	if (files) {
		for(var i=0; i<files.length; i++) {
			if (!files[i]) continue;
			fd.append('file_ary', files[i]);
		}
	}

	// progress bar init
	var $prog  = $('#progress');
	var $label = $prog.find('.label').text('');
	$prog.show();
	$prog.progressbar({
		value: 0,
		change: function() {
			$label.text( $prog.progressbar( "value" ) + "%" );
		},
		complete: function() {
			$label.text( "Upload complite!" );
		}
	});

	// submit処理
	$.ajax(Vmyself + '?etc/ajax_dummy', {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'json',
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			show_error('#msg-upload-error');
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			if (option.callback) option.callback(data, folder);
		},
		complete: function(xhr, text) {
			$prog.hide();
			if (option.complete) option.complete(xhr, text);
		},
		xhr: function() {
			var XHR = $.ajaxSettings.xhr();
			XHR.upload.addEventListener('progress', function(e){
				var par = Math.floor(e.loaded*100/e.total + 0.5);
				$prog.progressbar({ value: par });
			});
			return XHR;
		}
	});
}
//----------------------------------------------------------------------------
// ●ドラッグ＆ドロップ
//----------------------------------------------------------------------------
dndbody.on('dragover', function(evt) {
	return false;
});
dndbody.on("drop", function(evt) {
	evt.stopPropagation();
	evt.preventDefault();

	if (!do_edit) return;
	if (!evt.originalEvent.dataTransfer) return;

	var files = evt.originalEvent.dataTransfer.files;
	if (!files || !files.length) return;
	if (!window.FormData) return;

	// ダイアログを出す
	open_upload_dialog(files);
});

//############################################################################
// ■記法ヘルパー機能
//############################################################################
var helper_mode;
var helper_info = {};
var helper = {
	strong:	$secure('#btn-strong'),
	link:	$secure('#btn-link'),
	google:	$secure('#btn-google'),
	list:	$secure('#btn-list'),
	quote:	$secure('#btn-quote'),
	annotation: $secure('#btn-annotation'),
	album:	$secure('#album-open'),
	color:	$secure('#select-color'),
	fsize:	$secure('#select-fontsize')
};
helper.color.val('');
helper.fsize.val('');
for(var key in helper) {
	if (helper[key][0].tagName == "SELECT") {
		var func = function(k) {	// closure
			return function(evt){
				var obj = $(evt.target);
				if (obj.val() == '') return;
				var info = helper_info[helper_mode];
				if (!info) return;
				var r = info[k].func(evt);
				obj.val('');
				return r;
			};
		}(key);
		helper[key].change( func );
		continue;
	}

	var func = function(k) {	// closure
		return function(evt){
			var info = helper_info[helper_mode];
			if (!info) return;
			return info[k].func(evt);
		};
	}(key);
	helper[key].click( func );
}

//----------------------------------------------------------------------------
helper_info.default = {
	strong: 	{ func: inline_tag,		start: '[bf:', end: ']'},
	link:		{ func: http_tag },
	google:		{ func: link_tag,		start: '[g:',  end: ']'},
	annotation:	{ func: inline_tag,		start: '((',   end: '))'},
	list:		{ func: block_tag,		tag: '-'},
	quote:		{ func: satsuki_quote_tag,	'start-base': '>>',	end: '<<'},
	color:		{ func: inline_tag,		'start-base':'[color:',	end: ']'},
	fsize:		{ func: inline_tag,		'start-base':'[',	end: ']'},
	album:		{ func: open_album }
};
helper_info.markdown = {
	strong: 	{ func: inline_tag,		start: '[bf:', end: ']'},
	link:		{ func: http_tag },
	google:		{ func: link_tag,		start: '[g:',  end: ']'},
	annotation:	null,
	list:		{ func: block_tag,		tag: '* '},
	quote:		{ func: block_tag,		tag: '> '},
	color:		{ func: inline_tag,		'start-base':'[color:',	end: ']'},
	fsize:		{ func: inline_tag,		'start-base':'[',	end: ']'},
	album:		{ func: open_album }
};
helper_info.simple = {
	strong: 	{ func: html_inline_tag,	tag: 'strong' },
	link:		{ func: html_http_tag },
	google:		null,
	annotation:	null,
	list:		{ func: block_tag,		start: '<ul>', tag:'<li>', end:'</ul>'},
	quote:		{ func: block_tag,		start: '<blockquote>', end:'</blockquote>'},
	color:		{ func: html_inline_style,	tag: 'color' },
	fsize:		{ func: html_inline_class },
	album:		{ func: open_album }
};

//----------------------------------------------------------------------------
// ●ヘルパーの初期化
//----------------------------------------------------------------------------
function init_helper(parser_name) {
	var mode = (parser_name || helper_mode).replace(/[-_][\w-]+$/, '');
	helper_mode =  mode;
	html_mode   = (mode == 'simple');

	var link = $secure('#parser-help-link');
	var url  = link.data(mode);
	if (url) {
		link.show();
		link.attr('href', 'http://adiary.org/v3man/' + url);
	} else	link.hide();

	// 記法ヘルパー
	var info = helper_info[mode] || {};
	for(var key in helper) {
		var btn = helper[key];
		var h   = info[key];
		btn.prop('disabled', h ? false : true);
		if (!h) continue;

		var attr = ['tag', 'start', 'end', 'start-base'];
		for(var i=0; i<attr.length; i++) {
			var name = attr[i];
			btn.data(name, h[name]);
			if (! h[name]) btn.removeData(name);
		}
	}
	if (info.init) info.init(mode);
}

//----------------------------------------------------------------------------
// ●パーサーの変更
//----------------------------------------------------------------------------
parsel.change( function(){
	init_helper( parsel.val() );
});
parsel.change();	// call init_helper()

//----------------------------------------------------------------------------
// ●paste処理 / init_helper() 後に呼び出すこと
//----------------------------------------------------------------------------
{
	var txt = $('#paste-txt');
	if (txt.length && $('#editarea').val() == "") {
		insert_image( txt.text(), $('#paste-caption').text(), $('#paste-class').text() );
	}
}

//////////////////////////////////////////////////////////////////////////////
// ■記法ヘルパーの各機能
//////////////////////////////////////////////////////////////////////////////
//----------------------------------------------------------------------------
// ●インラインタグ汎用処理
//----------------------------------------------------------------------------
function inline_tag(evt, func) {
	var obj = $(evt.target);
	var st_base = obj.data('start-base');
	var tag_st  = obj.data('start');
	var tag_end = obj.data('end');
	if (st_base) tag_st = st_base + obj.val() + ':';
	var text = get_selection();
	if (text) {
		text = parse_lines(text, function(str) {
			if (func) return func({str: str}, obj);
			return tag_st + esc_satsuki_tag_nested(str) + tag_end;
		})
		return replace_selection(text);
	}

	form_dialog({
		title: obj.data('msg'),
		callback: function (h) {
			if (!h.str) return;
			if (func) return func(h, obj);
			insert_text(tag_st + h.str + tag_end);
		}
	});
}

//----------------------------------------------------------------------------
// ●HTMLインラインタグ汎用処理
//----------------------------------------------------------------------------
function html_inline_tag(evt) {
	inline_tag(evt, function (h, obj) {
		var tag = obj.data('tag');
		insert_text('<' + tag + '>' + h.str + '</' + tag + '>');
	});
}
function html_inline_class(evt) {
	inline_tag(evt, function (h, obj) {
		var val = obj.val();
		insert_text('<span class="' + val + '">' + h.str + '</span>');
	});
}
function html_inline_style(evt) {
	inline_tag(evt, function (h, obj) {
		var val = obj.val();
		var tag = obj.data('tag');
		insert_text('<span style="' + tag + ':' + val + ';">' + h.str + '</span>');
	});
}


//----------------------------------------------------------------------------
// ●ブロックタグ汎用処理
//----------------------------------------------------------------------------
function block_tag(evt) {
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
// ●リンク生成
//----------------------------------------------------------------------------
function link_tag(evt, func) {
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

function http_tag(evt) {
	link_tag(evt, function (h) {
		var ma = h.str1.match(/^(https?:\/\/)(.+)/i);
		if (! ma) return;
		if (h.str2 != '') h.str2 = ':' + h.str2;
		var url = ma[1] + esc_satsuki_tag_nested(ma[2]);
		replace_selection( '[' + url + h.str2 + ']' );
	});
}


function html_http_tag(evt) {
	link_tag(evt, function (h) {
		var ma = h.str1.match(/^https?:\/\/.+/i);
		if (! ma) return;
		if (h.str2 == '') h.str2 = h.str1;
		replace_selection( '<a href="' + h.str1 + '">' + h.str2 + '</a>' );
	});
}

//----------------------------------------------------------------------------
// ●引用タグの処理
//----------------------------------------------------------------------------
function satsuki_quote_tag(evt) {
	var obj = $(evt.target);
	obj.data('start', obj.data('start-base'));

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
			block_tag(evt);
		},
		cancel: function() {
			block_tag(evt);
		}
	});
}

//----------------------------------------------------------------------------
// ■画像アルバムを開く
//----------------------------------------------------------------------------
function open_album(evt) {
	var url = $(evt.target).data('url');
	var win = window.open(url, 'album', 'location=yes, menubar=no, resizable=yes, scrollbars=yes');
	win.focus();
};

//////////////////////////////////////////////////////////////////////////////
// ■記法ヘルパー用サブルーチン
//////////////////////////////////////////////////////////////////////////////
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
			if (ta.value.substr(-1) != "\n") ta.value += "\n";
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
// ●satsuki tagのエスケープ処理
//----------------------------------------------------------------------------
function esc_satsuki_tag_nested(str) {
	var buf = [];
	str =str.replace(/[\x01-\x03]/g, '')
		.replace(/\\\[/g, "\x01")
		.replace(/\\\]/g, "\x02");
	var ma;
	while(ma = str.match(/^(.*)(\[[^\[\]]*\])(.*)$/)) {
		str = ma[1] + "\x03" + buf.length + ma[3];
		buf.push(ma[2]);
	}
	str = esc_satsuki_tag(str)
		.replace(/\x03(\d+)/, function(all, num) { return buf[num] })
		.replace(/\x02/g, "\\]")
		.replace(/\x01/g, "\\[");
	return str;
}

//############################################################################
});
