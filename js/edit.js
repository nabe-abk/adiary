//############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_image;	// global function for album.js
var IE11;

$(function(){
//############################################################################
const $tagsel = $secure('#tag-select');
const $upsel  = $secure('#upnode-select');
const $edit   = $('#editarea');
const CSRF_key = $('#csrf-key').val();

adiary.load_tags_list($tagsel);
adiary.load_contents_list($upsel);

//############################################################################
// ■下書きを開く
//############################################################################
{
	var $draft = $('#select-draft');
	$('#open-draft').click(function(){
		var pkey = $draft.val();
		window.location = $draft.data('base-url') + '0' + pkey + '?edit';
	});
	$('#open-template').click(function(){
		var pkey = $draft.val();
		window.location = $draft.data('base-url') + '0' + pkey + '?edit&template=1';
	});
}

//############################################################################
// ■タグの削除ボタン、タグの追加
//############################################################################
{
	//--------------------------------------------------------------------
	// ●タグの削除ボタン（×ボタン）
	//--------------------------------------------------------------------
	const $tagdel = $('<span>').addClass('ui-icon ui-icon-close');
	$tagdel.click(function(evt){
		var obj = $(evt.target);
		obj.parent().remove();
	});
	$("#edit-tags span.tag").append( $tagdel.clone(true) );

	//--------------------------------------------------------------------
	// ●タグの追加
	//--------------------------------------------------------------------
	function tag_append(text) {
		if (text=="") return;

		var $tags = $('#tags');
		var ch = $tags.children();
		for(var i=0; i<ch.length; i++) {
			if ($(ch[i]).text() == text) return;
		}
		// append
		var $tag = $('<span>').addClass('tag').html( adiary.tag_esc_amp(text) );
		var $inp = $('<input>').attr({
			type: 'hidden',
			name: 'tag_ary',
			value: text
		});
		$tag.append( $inp, $tagdel.clone(true) );
		$tags.append( $tag );
	}

	//----------------------------------------------------------------------------
	// ●タグ追加ダイアログの表示
	//----------------------------------------------------------------------------
	const $addtag  = $secure('#edit-add-tag');
	const $tagform = $secure('#tag-select-form').detach();
	var $div;
	$addtag.click( function(){
		$div = $('<div>').append( $tagform );

		// 入力要素
		var $inp = $tagform.find('#input-new-tag');

		//enterで確定させる
		function tag_append_func() {
			var tag = $inp.val();
			if (tag.match(',')) return false;
			tag_append( tag );
			$div.dialog('close');
			return false;
		}
		$inp.keydown(function(evt){
			if (evt.keyCode != 13) return;
			return tag_append_func();
		});

		// ボタンの設定
		var buttons = {};
		var ok_func = buttons[$('#new-tag-append').text()] = tag_append_func;
		buttons[ adiary.msg('cancel') ] = function(){
			$div.dialog( 'close' );
		};
		$div.dialog({
			modal: true,
			minWidth:  240,
			minHeight: 200,
			title:   $addtag.data('title'),
			buttons: buttons,
			beforeClose: function(){
				$tagsel.val('');
				$inp.val('');
			}
		});
	});

	//----------------------------------------------------------------------------
	// ●タグ選択フォームの処理
	//----------------------------------------------------------------------------
	$tagsel.change(function(){
		if ($(':selected', $tagsel).data('new')) return;
		tag_append( $tagsel.val() );
		$div.dialog( 'close' );
	});
}

//############################################################################
// ■公開状態の変更
//############################################################################
{
	var $echk = $('#enable-chk');
	var $dchk = $('#draft-chk');
	$echk.change( echk_change );
	$dchk.change( echk_change );
	echk_change();

	function echk_change() {
		if ($dchk.prop('checked')) {	// 下書き
			$('.save-btn-title').text( $dchk.data('on') );
			return;
		}
		if ($echk.prop('checked'))
			$('.save-btn-title').text( $echk.data('on') );
		else
			$('.save-btn-title').text( $echk.data('off') );
	}
}

//############################################################################
// ■upnodeの変更 / link_keyの設定
//############################################################################
{
	const $upsel = $('#upnode-select');
	const $lkey  = $('#link-key');

	$upsel.change(function(){
		if (! $lkey.data('suggest')) return;	// 機能がoff
		var val = $lkey.val();
		if (val != '' && val != $lkey.data('set')) return;

		var $opt = $upsel.children(':selected');
		if (!$opt.length) return;

		var set = $opt.data('link_key');
		if (set == undefined) return;
		if (set.substr(-1) != '/') set += '/';
		$lkey.val( set );
		$lkey.data('set', set);
	});
}

//############################################################################
// ■編集ロック機能
//############################################################################
{
//############################################################################
function edit(pkey) {
	this.pkey     = pkey;
	this.sid      = '';
	this.interval = parseInt( $('#edit-lock-interval').text() );
	this.timer    = null;
	this.editing  = false;

	if (!pkey || this.interval<10) this.interval = 0;
	this.init();
	this.start();
};

//----------------------------------------------------------------------------
// ●初期化
//----------------------------------------------------------------------------
edit.prototype.init = function() {
	let self = this;

	// sid生成
	let d = new Date();
	if (window.location.hash) {
		this.sid = window.location.hash.substr(1).replace('%20', ' ');
	} else {
		this.sid = d.getFullYear()
		+ '/' + ('00'+(d.getMonth()+1)).substr(-2)
		+ '/' + ('00' + d.getDate()   ).substr(-2)
		+ ' ' + ('00' + d.getHours()  ).substr(-2)
		+ ':' + ('00' + d.getMinutes()).substr(-2)
		+ ':' + ('00' + d.getSeconds()).substr(-2);
		if (this.interval)
			window.location.hash = this.sid;
	}

	// ロックの強制確認ボタン
	$('#force-lock-check').click(function(){
		self.stop_timer();
		self.lock();
		self.start_timer();
	});
}

//----------------------------------------------------------------------------
// ●編集開始
//----------------------------------------------------------------------------
edit.prototype.start = function() {
	if (!this.interval) return this.enable();

	// 他にロックをかけている人は居ないかチェック
	let self = this;
	this.lock(function(data) {
		// 他の編集中の人が居る
		if (data && data.length) self.open_dialog(data);
	});
}

//----------------------------------------------------------------------------
// ●ロックをかける
//----------------------------------------------------------------------------
edit.prototype.lock = function(callback) {
	let self = this;
	this.ajax_lock({
		force:    self.editing || 0,
		callback: function(h) {
			if (h.return != 0) return;	 // internal error
			self.view_lockers(h.data);

			let data = h.data;
			if (!self.editing && (!data || !data.length)) {
				self.enable();
				self.start_timer();
			}
			if (callback) return callback(data);
		}
	})
}

//----------------------------------------------------------------------------
// ●編集中の確認タイマーと手動確認
//----------------------------------------------------------------------------
edit.prototype.start_timer = function(callback) {
	if (this.timer || !this.interval) return;

	let self = this;
	this.timer = setInterval(function(){
		self.lock()
	}, this.interval*1000);
}

edit.prototype.stop_timer = function() {
	if (!this.timer) return;
	clearInterval(this.timer);
	this.timer = null;
}

//----------------------------------------------------------------------------
// ●編集するか確認
//----------------------------------------------------------------------------
edit.prototype.open_dialog = function(data) {
	let self = this;

	// 編集するか確認
	let html = '<ul>'
	for(var i in data) {
		html += '<li>' + data[i].id + ' (' + data[i].sid + ')' + '</li>';
	}
	html+='</ul>';
	adiary.confirm({
		id: '#edit-confirm',
		hash: { u: html }
	}, function(flag){
		if (flag) {
			self.enable();
			self.lock();
			self.start_timer();
			return;
		}

		self.disable();
		self.start_timer();
	});
}

//----------------------------------------------------------------------------
// ●編集できる状態にする
//----------------------------------------------------------------------------
edit.prototype.enable = function() {
	this.editing = true;

	$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', false);
	$('#edit').find('textarea').prop('readonly', false);
	$('#edit').find('.fileup').prop('disabled', false);

	// ページを離れるときにunlock
	if (this.interval) {
		let self = this;
		$(window).on('unload', function(){
			self.ajax_unlock();
		});
	}
}

//----------------------------------------------------------------------------
// ●編集できない状態にする
//----------------------------------------------------------------------------
edit.prototype.disable = function() {
	this.editing = false;

	$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', true);
	$('#edit').find('textarea').prop('readonly', true);
	$('#edit').find('.fileup').prop('disabled', true);
}

//----------------------------------------------------------------------------
// ●ロック状態を表示する
//----------------------------------------------------------------------------
const $lock_notice = $('#edit-lock-notice');
const $lockers_ul  = $('#edit-lockers');
edit.prototype.view_lockers = function(data) {
	$lockers_ul.empty();

	if (data && data.length)
		$lock_notice.showDelay();
	else {
		$lock_notice.hideDelay();
	}
	// 編集中の人々を表示
	for(var i in data) {
		var li = $('<li>').text(data[i].id + ' (' + data[i].sid + ')');
		$lockers_ul.append(li);
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
edit.prototype.ajax_unlock = function(opt) {
	if (!opt) opt={};
	opt.unlock = 1;
	opt.async  = false;
	return this.ajax_lock(opt);
}
edit.prototype.ajax_lock = function(opt) {
	opt.action = opt.action || 'ajax_lock';

	var param = {
		type: 'POST',
		url: adiary.myself + '?etc/ajax_dummy',
		dataType: 'json',
		data: {
			action: opt.action,
			csrf_check_key: CSRF_key,
			pkey:   opt.pkey || this.pkey,
			sid:    opt.sid  || this.sid,
			unlock: opt.unlock ? 1 : 0,
			force:  opt.force  ? 1 : 0
		}
	};
	if (opt.async !== undefined) param.async = opt.async;

	let d = param.data;
	console.log((new Date()).toLocaleTimeString(), opt.unlock ? 'ajax_unlock' : d.action, d.pkey, d.sid, "force=" + d.force);

	if (opt.callback) param.success = opt.callback;
	$.ajax( param );
}
//############################################################################
	const e = new edit( $('#edit-pkey').val() );
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
				upload_files_insert(data, {
					folder:		folder,
					thumbnail:	$('#paste-thumbnail').val() == '0' ? false : true,
					caption:	$('#paste-caption').val(),
					exif:		$('#paste-to-exif').prop('checked'),
					class:		$('#paste-class').val()
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
	buttons[ adiary.msg('cancel') ] = function(){
		div.dialog( 'close' );
		$upform.detach();
		div.remove();
	};
	div.dialog({
		modal: true,
		width:  adiary.DialogWidth,
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
		var fs  = adiary.size_format(files[i].size);
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
function upload_files_insert(data, opt) {
	try {
		data['fail']    = parseInt(data['fail']);
		data['success'] = parseInt(data['success']);
		data['ret']     = parseInt(data['ret']);
	} catch(e) {
	}

	if (data['fail']) {
		adiary.show_error('#msg-upload-fail', {
			n: data['fail'] + data['success'],
			f: data['fail'],
			s: data['success']
		});
		return;
	} else if (data['ret']) {
		adiary.show_error('#msg-upload-error');
		return;
	}

	// 記事に挿入
	var ary = data['files'];
	if (!data['success'] || !ary) return;

	let files = [];
	for(var i=0; i<ary.length; i++) {
		let file = ary[i];
		let reg  = name.match(/\.(\w+)$/);
		let ext  = reg ? reg[1] : '';
		files.push({
			folder: opt.folder,
			file:	file.name,
			ext:	ext,
			isimg:	file.isImg,
			exif:	file.isImg && opt.exif,
			thumbnail: opt.thumbnail
		});
	}

	insert_image({
		caption: opt.caption,
		class:   opt.class,
		files: files
	});
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
	$.ajax(adiary.myself + '?etc/ajax_dummy', {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'json',
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			adiary.show_error('#msg-upload-error');
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
$edit.on('dragover', function(evt) {
	return false;
});
$edit.on("drop", function(evt) {
	evt.stopPropagation();
	evt.preventDefault();

	if ($edit.prop('readonly')) return;
	if (!evt.originalEvent.dataTransfer) return;

	var files = evt.originalEvent.dataTransfer.files;
	if (!files || !files.length) return;
	if (!window.FormData) return;

	// ダイアログを出す
	open_upload_dialog(files);
});

//############################################################################
});
