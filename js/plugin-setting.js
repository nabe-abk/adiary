//############################################################################
// プラグイン設定JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$(function(){
	$('button.setting').click( function(evt){
		module_setting($(evt.target));
	});

//////////////////////////////////////////////////////////////////////////////
// ●モジュールの設定を変更する
//////////////////////////////////////////////////////////////////////////////
var formdiv = $('<div>');
var form = $('#ajax-form');
var formbody = $('<div>').addClass('body');
{
	form.detach();
	form.append( formbody );
	formdiv.append( form );
	$('#body').append( formdiv );
}

function module_setting(obj) {
	var name = obj.data('module-name');
	var url = obj.data('url');

	// エラー表示用
	var errdiv = $('<div>').addClass('error-message');
	var errmsg = $('<strong>').addClass('error').css('display', 'block');
	var erradd = $('<div>');
	errdiv.append(errmsg, erradd);

	var buttons = {};
	buttons[ $('#btn-ok').text() ] = function(){
		// alert( form.serialize() );
		// 今すぐ保存
		$.ajax({
			url: form.attr('action'),
			type: 'POST',
			data: form.serialize(),
			success: function(data){
				if (! data.match(/ret=(-?\d+)(?:\n|)$/) ) {
					errmsg.html( $('#msg-save-error').html() );
				} else if (RegExp.$1 != '0') {
					var code = RegExp.$1;
					errmsg.html( $('#msg-save-error').html() +'(ret='+ code +')');
				} else {
					//成功
					formdiv.dialog( 'close' );
					// モジュールHTMLをサーバからロード？
					if (obj.data('load-module-html')) load_module_html( obj );
					return ;
				}
				errmsg.attr('title', data);
				if (data.match(/\nmsg=([\s\S]*)$/) ) erradd.html( RegExp.$1 );
			},
			error: function(xmlobj){
				errmsg.html( $('#msg-ajax-error').html() );
				errmsg.attr('title', xmlobj.responseText);
			}
		});
	};
	buttons[ $('#btn-cancel').text() ] = function(){
		formdiv.dialog( 'close' );
	};

	// ダイアログの設定
	formdiv.dialog({
		autoOpen: false,
		modal: true,
		minWidth:  DialogWidth,
		minHeight: 100,
		title:   obj.data('title').replace('%n', obj.data('title')),
		buttons: buttons
	});

	// フォーム本体をロード
	formbody.load(url, function(){
		formbody.append( errdiv );
		formdiv.dialog( "open" );
		// adiary_init( formbody );

		formbody.append( $('<input>').attr({
			type: 'hidden',
			name: 'module_name',
			value: name
		}) );
	});
}

//////////////////////////////////////////////////////////////////////////////
});
