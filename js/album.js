//############################################################################
// アルバム用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$( function(){
	var main = $('#album');
	var form = $('#album-form');
	var tree = $('#album-folder-tree');
	var view = $('#album-folder-view');

	var path = $('#image-path').text();
	var files;
	var cur_folder;

	// ファイルアップロード関連
	var upform   = $('#upload-form');
	var iframe   = $('#form-response');
	var message  = $('#upload-messages');
	var upfolder = $('#upload-folder');
	var upreset  = $('#upload-reset');
	var filesdiv = $('#file-elements');
	var inputs   = filesdiv.find('input');

	// Drag&Drop関連
	var dnd_div  = $('#dnd-files');
	var upfiles  = [];

	var isMac = /Mac/.test(navigator.platform);
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
tree.dynatree({
	persist: true,
	cookieId: 'album:' + Blogpath,
	minExpandLevel: 2,
	imagePath: $('#icon-path').text(),

	initAjax: { url: tree.data('url') },
	dnd: {
		onDragStart: function(node) {
			if (node.data.fix) return false;
			logMsg("tree.onDragStart(%o)", node);
			return true;	// Return false to cancel dragging of node.
		},
		autoExpandMS: 1000,
		preventVoidMoves: true, // Prevent dropping nodes 'before self', etc.
		onDragEnter: function(node, sourceNode) {
			 return true;
		},
		onDragOver: function(node, sourceNode, hitMode) {
			if(node.isDescendantOf(sourceNode))
				return false;
			if(node.data.isroot)
				return false;
			if(node.data.fix && (hitMode==='before' || hitMode==='after'))
				return false;
			if(!node.data.isFolder && hitMode === "over")
				return "after";
		},
		onDrop: function(node, sourceNode, hitMode, ui, draggable) {
			sourceNode.move(node, hitMode);
		},
	},
	onPostInit: function(isReloading, isError) {
		if (isError) {
			$('#load-error').show();
			return;
		}
		var rootNode = tree.dynatree("getRoot");
		rootNode.visit(function(node){
			var data = node.data;
			if (data.count != 0) {
				data.name  = data.title;
				data.title = data.name + ' (' + node.data.count + ')';
			}
			data.key      = tag_decode(data.key);
			data.expand   = true;
			data.isFolder = true;
		});
		rootNode.render();

		var root = rootNode.getChildren()[1];
		root.data.fix    = true;

		// ゴミ箱の追加
		rootNode.addChild({
			title: $('#msg-trashbox').text(),
			key: '.trashbox/',
			fix: true,
			expand: true,
			icon: 'trashbox.png',
			isFolder: true
		});

		// 選択中のノード
		var sel = tree.dynatree("getActiveNode");
		if (!sel) {
			root.activate();
			sel = root;
		}
		open_folder(sel);
	},
	onActivate: function(node) {
		open_folder(node);
	},
	// ノードの編集
	onClick: function(node, event) {
		if( event.shiftKey ) editNode(node);
		return true;
	},
	onDblClick: function(node, event) {
		editNode(node);
		return false;
	},
	onKeydown: function(node, event) {
		switch( event.which ) {
			case 113: // [F2]
				editNode(node);
				return false;
			case 13: // [enter]
				if( isMac ) editNode(node);
				return false;
		}
	}
});

//############################################################################
// ■フォルダツリー関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●フォルダ名の変更
//////////////////////////////////////////////////////////////////////////////
function editNode( node ) {
	var prev_title = node.data.title;
	var tree = node.tree;

	// Disable dynatree mouse- and key handling
	tree.$widget.unbind();

	// Replace node with <input>
	var inp = $('<input>').attr({
		type:  'text',
		value: tag_decode(prev_title)
	});
	var title = $(".dynatree-title", node.span);
	title.empty();
	title.append( inp );
	
	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.select();
	inp.keydown(function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				$(this).blur();
				break;
			case 13: // [enter]
				var title = inp.val();
				title = tag_esc(title);
				node.setTitle(title);
				$(this).blur();
				break;
		}
	});
	inp.blur(function(evt){
		node.setTitle(prev_title);
		tree.$widget.bind();
		node.focus();
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●リロードボタン
//////////////////////////////////////////////////////////////////////////////
function album_reload() {
	location.href = location.href;
}
$('#album-reload').click( album_reload );


//////////////////////////////////////////////////////////////////////////////
// ●フォルダ作成ボタン
//////////////////////////////////////////////////////////////////////////////
$('#album-new-folder').click( function(){
	alert('まだ使えません m(__)m');
});


//////////////////////////////////////////////////////////////////////////////
// ●ゴミ箱空ボタン
//////////////////////////////////////////////////////////////////////////////
$('#album-clear-trashbox').click( function(){
	alert('まだ使えません m(__)m');
});

//############################################################################
// ■メインビュー関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●フォルダを開く
//////////////////////////////////////////////////////////////////////////////
function open_folder(node) {
	message.hide();
	ajax_submit({
  		data: {	path: node.data.key },
		action: 'load_image_files',
		success: function(data) {
			// データsave
			files  = data;
			folder = (node.data.key == '/') ? '' : node.data.key;
			upfolder.val( folder );
			cur_folder = folder;

			var title = node.data.key;
			if (node.data.key == '.trashbox/') title = $('#msg-trashbox').text();
			$('#current-folder').text( title );

			// viewの更新
			update_view();
		},
		error: function() {
			$('#current-folder').text( '(load failed!)' );
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●ajaxデータ送信
//////////////////////////////////////////////////////////////////////////////
function ajax_submit(opt) {
	var data = opt.data || {};
	data.action = $('#action-base').val() + opt.action;
	data.csrf_check_key = $('#csrf-key').val();

	$.ajax(form.data('myself') + '?etc/ajax_dummy', {
		method: 'POST',
		data: data,
		dataType: 'json',
		error: function(data) {
			if (opt.error) opt.error(data);
			console.log('[ajax_submit()] http post fail');
			console.log(data);
		},
		success: function(data) {
			if (opt.success) opt.success(data);
			console.log('[ajax_submit()] http post success');
			console.log(data);
		}
	});
	return true;
}

//////////////////////////////////////////////////////////////////////////////
// ●ビューのアップデート
//////////////////////////////////////////////////////////////////////////////
function update_view() {
	view.empty();
	for(var i in files) {
		var file = files[i];
		var link = $('<a>', {
			href: path + folder + file.name
		});
		if (file.isImg) {
			link.attr({
				'data-lightbox': 'roadtrip',
				'data-title': file.name
			});
		}
		var img  = $('<img>', {
			src: path + folder + '.thumbnail/' + file.name + '.jpg',
			title: file.name,
			'data-isimg': file.isImg ? 1 : 0
		});
		img.click( img_click );
		img.dblclick( img_dblclick );
		link.append(img);
		view.append(link);
	}
	
	//-----------------------------------------------
	// 画像のクリック
	//-----------------------------------------------
	var dbl_click;
	function img_click(evt) {
		var obj = $(evt.target);
		if (dbl_click || evt.ctrlKey) {
			dbl_click = false;
			return;
		}
		evt.stopPropagation();
		evt.preventDefault()
		if (obj.hasClass('selected'))
			obj.removeClass('selected');
		else
			obj.addClass('selected');
	}

	//-----------------------------------------------
	// 画像のダブルクリック
	//-----------------------------------------------
	function img_dblclick(evt) {
		var obj = $(evt.target);
		dbl_click = true;
		obj.click();
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●記事に貼り付け
//////////////////////////////////////////////////////////////////////////////
var paste_form = $('#paste-form');
paste_form.submit(function(){
	// エラー時送信しない為
	if ($('#paste-txt').val() == '') return false;
	return true;
});

$('#paste-thumbnail').click( paste_button );
$('#paste-original' ).click( paste_button );

function paste_button(evt) {
	var sel = view.find('.selected');
	if (!sel.length) return false;

	var obj = $(evt.target);
	var filetag = paste_form.data('tag');
	var imgtag  = obj.data('tag');

	var text='';
	for(var i=0; i<sel.length; i++) {
		var img = $(sel[i]);
		var tag = img.data('isimg') ? imgtag : filetag;

		var name = img.attr('title');
		var reg  = name.match(/\.(\w+)$/);
		var ext  = reg ? reg[1] : '';
		var rep  = {
			d: cur_folder,
			e: ext,
			f: name
		};
		tag = tag.replace(/%([def])/g, function($0,$1){ return rep[$1] });
		text += tag + "\n";
	}
	if (window.opener) {
		// 子ウィンドウとして開かれていたら
		window.opener.insert_text(text)
		window.close();
		return false;
	}
	$('#paste-txt').val(text);
	paste_form.submit();

	return false;
}

//############################################################################
// ■ファイルアップロード関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●ドラッグ＆ドロップ
//////////////////////////////////////////////////////////////////////////////
main.on('dragover', function(evt) {
	return false;
});
main.on("drop", function(evt) {
	evt.stopPropagation();
	evt.preventDefault();
	var dnd_files = evt.originalEvent.dataTransfer.files;
	if (!dnd_files) return;
	if (!FormData)  return;

	for(var i=0; i<dnd_files.length; i++)
		upfiles.push( dnd_files[i] );
	update_upfiles();
});

function update_upfiles() {
	dnd_div.empty();
	for(var i=0; i<upfiles.length; i++) {
		if (!upfiles[i]) next;
		var fs  = size_format(upfiles[i].size);
		var div = $('<div>').text(
			upfiles[i].name + ' (' + fs + ')'
		);
		// 削除アイコン
		var del = $('<span>').addClass('ui-icon ui-icon-close');
		del.data('num', i);
		del.click(function(evt){
			var obj = $(evt.target);
			var num = obj.data('num');
			upfiles[num] = null;
			obj.parent().remove();
		});
		div.append(del);
		dnd_div.append(div);
	}
}

function size_format(s) {
	function sprintf_3f(n){
		n = n.toString();
		var idx = n.indexOf('.');
		var len = (0<=idx && idx<3) ? 4 : 3;
		return n.substr(0,len);
	}

	if (s > 104857600) {	// 100MB
		s = Math.round(s/1048576);
		s = s.toString().replace(/(\d)(?=(\d\d\d)+(?!\d))/g, '$1,');
		return s + ' MB';
	}
	if (s > 1023487) return sprintf_3f( s/1048576 ) + ' MB';
	if (s >     999) return sprintf_3f( s/1024    ) + ' KB';
	return s + ' Byte';
}

//////////////////////////////////////////////////////////////////////////////
// ●<input type=file> が変更された
//////////////////////////////////////////////////////////////////////////////
function input_change() {
	var flag = true;
	inputs.each(function(num, obj){
		if ($(obj).val() == '') flag=false;
	});
	if (!flag) return;

	// 新しい要素の追加
	if (inputs.length > 99) return;
	var inp = $('<input>', {
		type: 'file',
		name: 'file' + inputs.length,
		multiple: 'multiple'
	}).change(input_change);
	filesdiv.append( inp );

	// 要素リスト更新
	inputs = filesdiv.find('input');
}
inputs.change( input_change );

//////////////////////////////////////////////////////////////////////////////
// ●ファイルアップロード : submit
//////////////////////////////////////////////////////////////////////////////
upform.submit(function(){
	// ajaxで処理？
	if (upfiles.length) {
		for(var i=0; i<upfiles.length; i++)
			if (upfiles[i]) return ajax_upload();
	}

	// ファイルがセットされているか確認
	var flag = false;
	inputs.each(function(num, obj){
		if ($(obj).val() != '') flag=true;
	});
	if (!flag) return false;

	// submit処理
	iframe.unbind();
	iframe.load( function(){
		parse_upload_response( iframe.contents().text() )
	});
	message.html('<div class="message uploading">' + $('#uploading-msg').text() + '</div>');
	message.show();
	return true;
});

function parse_upload_response(text) {
	upform_reset();
	var ary = text.split(/\n/);
	var ret = ary.shift();
	var reg = ret.match(/^ret=\d*/);
	if (reg) {
		ret = reg[0];
		message.html( ary.join("\n") );
		message.show( Default_show_speed );
	}

	// ファイル選択を１つ残して削除
	for(var i=1; i<inputs.length; i++) {
		inputs[i].remove();
	}
	inputs = filesdiv.find('input');
}

//////////////////////////////////////////////////////////////////////////////
// ●ajaxでファイルアップロード 
//////////////////////////////////////////////////////////////////////////////
function ajax_upload() {
	var fd = new FormData( upform[0] );
	for(var i=0; i<upfiles.length; i++) {
		if (!upfiles[i]) continue;
		fd.append('file_ary', upfiles[i]);
	}

	// submit処理
	$.ajax(upform.attr('action'), {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'text',
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			parse_upload_response( xhr.responseText );
			iframe_write( xhr.responseText );
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			parse_upload_response(data);
			iframe_write(data);
		}
	});

	upform_reset();
	message.html('<div class="message uploading">' + $('#uploading-msg').text() + '</div>');
	message.show();
	return false;
}

function iframe_write(data) {
	var doc = iframe[0].contentDocument;
	doc.open();
	doc.write(data);
	doc.close();
}

//////////////////////////////////////////////////////////////////////////////
// ●アップロードフォームのリセット
//////////////////////////////////////////////////////////////////////////////
function upform_reset(){
	message.hide();
	upfiles = [];
	update_upfiles();
}
upreset.click( upform_reset );



//############################################################################
});
