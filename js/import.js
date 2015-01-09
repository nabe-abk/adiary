//############################################################################
// adiary データimport用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$(function(){
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
	var form = $secure('#import-form');
	var file = $('#file');
	var prog = $('#progress');

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
// ●インポートボタン処理
//////////////////////////////////////////////////////////////////////////////
adiary_session($('button.import'), {
	myself: Vmyself,

	load_formdata: function(btn){
		var fd = new FormData( form[0] );
		fd.append('type', btn.attr('name'));
		if (btn.data('class')) fd.append('class', btn.data('class'));
		return fd;
	},

	init: function(){
		init_progressbar()
	},
	error: function(){
		prog.progressbar({ value: 100 });
	},
	success: function(){
		prog.progressbar({ value: 100 });
	},
	xhr: function(){
		var XHR = $.ajaxSettings.xhr();
		XHR.upload.addEventListener('progress', xhr_progress);
		return XHR;
	},
});


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

//############################################################################
});
