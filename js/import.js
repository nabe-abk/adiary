//############################################################################
// adiary データimport用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$(function(){
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
	var form = $('#import-form');
	var file = $('#file');
	var prog = $('#progress');
	var log  = $('#session-log');
	var interval = log.data('interval') || 500;
	
	// for debug
	// $(".jqueryui-accordion").accordion({ active: 4 });
//////////////////////////////////////////////////////////////////////////////
// ●FormDataが使えない場合の処理
//////////////////////////////////////////////////////////////////////////////
var ajax = window.FormData;
if (location.search.indexOf('&ajax=0') > 0) ajax=0; // for debug
$('#input-ajax').val( ajax ? 1 : 0 );
if (!ajax) {
	//$('button,input').prop('disabled', true);
	//show_error('#js-no-FormData');
	// IE8-9用

	// 押したボタンに応じてフォームを設定
	var type = $('<input>').attr({type: 'hidden', name: 'type'});
	var cls  = $('<input>').attr({type: 'hidden', name: 'class'});
	form.append(type,cls);
	$('button,input[type="button"]').attr('type', 'submit').click( function(evt){
		var btn = $(evt.target);
		type.val( btn.attr('name') );
		if (btn.data('class')) cls.val( btn.data('class') );
	});
	// ファイルが選択されていればsubmit
	form.submit(function(){
		if(! file.val() ) {	// ファイルが選択されてない
			show_error('#js-no-file');
			return false;
		}
	});
	return;
}

//////////////////////////////////////////////////////////////////////////////
// ●インポートボタン
//////////////////////////////////////////////////////////////////////////////
$('button.import').click( function(evt){
	var btn  = $(evt.target);

	var fd = new FormData( form[0] );
	fd.append('type', btn.attr('name'));
	if (btn.data('class')) fd.append('class', btn.data('class'));

	if(! file.val() ) 	// ファイルが選択されてない
		return show_error('#js-no-file');

	// プログレスバーの準備
	init_progressbar();
	log.show(500);

	// 開始処理
	import_start();

	var url = form.attr('action');
	$.ajax(url, {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'text',
		error: function(data) {
			prog.progressbar({ value: 100 });
			console.log('import fail');
			console.log(data);
			import_end();
		},
		success: function(data) {
			prog.progressbar({ value: 100 });
			console.log('http post success');
			console.log(data);
			import_end();
		},
		xhr: function(){
			var XHR = $.ajaxSettings.xhr();
			XHR.upload.addEventListener('progress', xhr_progress);
			return XHR;
		}
	});
});
//////////////////////////////////////////////////////////////////////////////
// ●インポート開始処理、終了処理
//////////////////////////////////////////////////////////////////////////////
function import_start() {
	$('button.import').prop('disabled', true);
	log_start();
}

function import_end() {
	log_stop();
	log_load();
	$('button.import').prop('disabled', false);
}

//////////////////////////////////////////////////////////////////////////////
// ●プログレスバー初期化
//////////////////////////////////////////////////////////////////////////////
function init_progressbar() {
	var label = prog.find('.label');
	prog.progressbar({
		value: 0,
		change: function() {
			label.text( prog.progressbar( "value" ) + "%" );
		},
		complete: function() {
			label.text( "Upload complite!" );
		}
	})
}
//////////////////////////////////////////////////////////////////////////////
// ●プログレス表示
//////////////////////////////////////////////////////////////////////////////
function xhr_progress(e) {
	var par = Math.floor(e.loaded*100/e.total + 0.5);
	prog.progressbar({ value: par });
}

//////////////////////////////////////////////////////////////////////////////
// ●ログの管理
//////////////////////////////////////////////////////////////////////////////
var log_timer;
function log_start() {
	log_timer = setInterval(log_load, interval);
}
function log_stop() {
	if (log_timer) clearInterval(log_timer);
	log_timer = 0;
}

//////////////////////////////////////////////////////////////////////////////
// ●ログ表示
//////////////////////////////////////////////////////////////////////////////
function log_load() {
	var url = log.data('url');
	log.load(url, function(data){
		log.scrollTop( log.prop('scrollHeight') );
	});
}

//############################################################################
});
