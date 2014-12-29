//############################################################################
// adiaryデザイン編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$(function(){
	var module_data_id   = '#design-modules-data';
	var module_selector  = '*[data-module-name]';
	var module_name_attr = 'data-module-name';
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
	var side_a = $('#side-a');
	var side_b = $('#side-b');
	var btn_setting_title = $('#btn-setting').text() || '';
	var btn_close_title   = $('#btn-close').text()   || '';

	var editbox = $('#module-editbox');
	editbox.detach();

	var modules = [];	// 各モジュールを取得し保存
	$(module_data_id + '>' + module_selector).each( function(idx,obj){
		obj = $(obj);
		obj.detach();
		modules[ obj.data('module-name') ] = obj;
		// データチェック
		var html = obj.html();
		var x = html.match(/\s+(id\s*=\s*"[\w\-]*")/);
		if (x && !x[1].match(/^id="js-generate-id-/)) {
			alert('"' + obj.data('module-name') + '" sample html has id-attribute. Please correct to "data-id" attribute) : ' + x[1]);
		}
	});

	// モジュールにボタン追加
	$('#sidebar ' + module_selector).each( function(idx,obj){
		init_module( $(obj) );
	});

	// 編集ボックスを追加
	side_a.prepend(editbox);
	
	// sortable設定
	side_a.addClass('connectedSortable');
	side_b.addClass('connectedSortable');
	side_a.sortable({ items: '>' + module_selector, connectWith: ".connectedSortable" });
	side_b.sortable({ items: '>' + module_selector, connectWith: ".connectedSortable" });

//////////////////////////////////////////////////////////////////////////////
// ●要素を追加する
//////////////////////////////////////////////////////////////////////////////
$('#add-module').change(function(evt){
	var _this = $(evt.target)
	var name = _this.val();
	if (name == '') return;
	_this.val('');

	var mod = modules[ name ];
	if (! mod.length) return;

	var id = mod.data('id');
	if (id != '' && $('#' + id).length) {	// 同じidが既に存在する、↓同じモジュール名が存在する
		show_error( '#msg-duplicate-id', {
			n: mod.attr('title')
		});
		return false;
	}
	var obj = mod.clone(true);
	if (id) obj.attr('id', id);

	// data-id to id
	obj.find('*[data-id]').each(function(){
		var el = $(this);
		$(el).attr('id', el.data('id'));
	});

	// 多重インストールが許可されている場合、エイリアスを作る
	if (!id) {
		name = obj.data('module-name');
		for(var i=1; i<9999; i++) {
			var name2 = name + ',' + i.toString();
			if ($('*[data-module-name="'+ name2 +'"]').length) continue;
			break;
		}
		obj.data('module-name', name2);
		obj.attr('data-module-name', name2);	// 必須
		name = name2;
	}

	init_module(obj);
	if (obj.hasClass('location-last')) {	// System info専用
		obj.appendTo(side_b);
	} else {
		obj.insertAfter(editbox);
	}

	// モジュールHTMLをサーバからロード？
	if (obj.data('load-module-html')) load_module_html( obj );
});

//////////////////////////////////////////////////////////////////////////////
// ●モジュールクラスやアイコンを設定
//////////////////////////////////////////////////////////////////////////////
function init_module(obj) {
	var div = $('<div>');
	div.addClass('module-edit-header');
	var name = obj.data('module-name').replace(/,\d+$/,'');
	if (! modules[ name ]) {
		// 使われてるモジュールが削除されてる等
		obj.remove();
		return ;
	}
	var hash = modules[ name ].data();
	if (hash) {
		var orig = obj.data('module-name');
		for (var k in hash) {
			obj.data(k, hash[k]);
		}
		// jQuery中でのデータ管理(kの値)と名前が異なるため他の方法はない
		obj.data('module-name', orig);
	}

	// モジュールに title 属性を設定
	if (!obj.attr('title')) {
		var title = obj.children('.hatena-moduletitle');
		title = title.length ? title.text() : '';
		title = title || obj.data('title') ||  obj.data('module-name') || '(unknown)';
		obj.attr('title', title);
	}

	if (obj.data('readme')) {
		var info = $('<span>');
		info.addClass('ui-icon ui-icon-help ui-button info');
		info.attr({
			onclick: '',
			'data-url': obj.data("readme-url")
		});
		info.data('title', obj.data('readme-title'));
		info.data('class', 'pre');
		div.append(info);
	}

	if (obj.data('setting')) {
		var set = $('<span>');
		set.addClass('ui-icon ui-icon-wrench ui-button');
		set.attr('title', btn_setting_title);
		set.click(function(){
			module_setting(obj);
		});
		div.append(set);
	}
	var close = $('<span>');
	close.addClass('ui-icon ui-icon-close ui-button');
	close.attr('title', btn_close_title);
	close.click(function(){
		var confirm = $('#msg-delete-confirm');
		if (confirm) {
			confirm = confirm.html().replace("%n", obj.attr('title'));
			if (!window.confirm( confirm )) return;
		}
		obj.detach();
	});
	div.append(close);

	obj.addClass('design-module-edit');
	obj.prepend(div);

	obj.show();
	obj.css('min-height', 32);
};

//////////////////////////////////////////////////////////////////////////////
// ●モジュールの設定を変更する
//////////////////////////////////////////////////////////////////////////////
var formdiv = $('<div>');
var form = $('#ajax-form');
{
	form.detach();
	formdiv.append( form );
	$('#body').append( formdiv );
}
function module_setting(obj) {
	var name = obj.data('module-name');
	var url = editbox.data('setting-url') + name;
	var body = $('#js-form-body');
	$('#js-form-module-name').val( name );

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
				if (! data.match(/ret=(-?\d+)(?:\n|$)/) ) {
					errmsg.html( $('#msg-save-error').html() );
				} else if (RegExp.$1 != '0') {
					errmsg.html( $('#msg-save-error').html() +'(ret='+ RegExp.$1 +')');
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
		title:   obj.attr('title').replace('%n', obj.attr('title')),
		buttons: buttons
	});

	// フォーム本体をロード
	body.load(url, function(){
		body.append( errdiv );
		formdiv.dialog( "open" );
	//	adiary_init( body );
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●結果を保存する
//////////////////////////////////////////////////////////////////////////////
$('#js-save').click(function(){
	$('#js-form input.js-value').detach();	// 戻るをされた時の対策
	var form = $('#js-form');
	if (!form.length) return;

	var form_append = function(key, obj) {
		var i=0;
		obj.each( function(idx,_this){
			var name = $(_this).data('module-name');
			if (!name || name == '') return;
			var inp1 = $('<input>');
			inp1.addClass('js-value');
			inp1.attr('type', 'hidden');
			inp1.attr('name',  key);
			inp1.attr('value', name);
			form.append(inp1);
			var inp2 = $('<input>');
			inp2.addClass('js-value');
			inp2.attr('type', 'hidden');
			inp2.attr('name',  name + '_int');
			inp2.attr('value', i++);
			form.append(inp2);
		});
	};

	form_append('side_a_ary', side_a.children(module_selector));
 	form_append('side_b_ary', side_b.children(module_selector));
 	
 	alert( form.html() );
	form.submit();
});

//////////////////////////////////////////////////////////////////////////////
// ●モジュールをロードして置き換える
//////////////////////////////////////////////////////////////////////////////
function load_module_html(obj) {
	var name = obj.data('module-name');
	if (!obj.data('load-module-html')) return;

	// HTML取得用フォーム
	var form = $('#load-module-html-form');
	$('#js-load-module-name').val( name );
	var url  = form.attr('action');

	$.post(url, form.serialize(), function(data){
		if (data.match(/^[\r\n\s]*$/)) return;
		var div = $('<div>').html(data);
		var newobj = div.children( module_selector );

		init_module( newobj );
		obj.replaceWith( newobj );
	//	adiary_init( newobj );
	});
}

//############################################################################
});
