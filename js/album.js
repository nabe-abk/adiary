//############################################################################
// アルバム用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$( function(){
	var form = $('#album-form');
	var tree = $('#album-folder-tree');
	var view = $('#album-folder-view');

	var iframe = $('#iframe-upload-form');
	var if_msg;
	var if_dir;
	var if_size;

	var path = $('#image-path').text();
	var folder = '';
	var files;

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
//////////////////////////////////////////////////////////////////////////////
// ●アップロードiframeフォーム初期化処理
//////////////////////////////////////////////////////////////////////////////
var _iframe_height;
iframe.load(function(){
	var upbody   = iframe.contents();
	var div_body = upbody.find('#div-body');
	var upform   = upbody.find('#form');
	var filesdiv = upbody.find('#file-elements');
	var inputs   = filesdiv.find('input');

	// その他要素
	if_msg  = upbody.find('#messages');
	if_dir  = upbody.find('#folder');
	if_size = upbody.find('#size');
	if_dir.val( folder );

	iframe_height();
	inputs.change(input_change);

	//-----------------------------------------------
	// <input type=file> が変更された
	//-----------------------------------------------
	function input_change(){
		var flag = true;
		inputs.each(function(num, obj){
			if ($(obj).val() == '') flag=false;
		});
		if (!flag) return;

		// 新しい要素の追加
		if (inputs.length > 99) return;
		var inp = $('<input>', {
			type: 'file',
			name: 'file' + inputs.length
		}).change(input_change);
		filesdiv.append( inp );

		// 要素リスト更新
		inputs = filesdiv.find('input');
		iframe_height();
	}

	//-----------------------------------------------
	// iframeの高さ調整
	//-----------------------------------------------
	function iframe_height(){
		iframe.height( div_body.height()+2 );
	}
	_iframe_height = iframe_height;	// export

	//-----------------------------------------------
	// submit時
	//-----------------------------------------------
	upform.submit(function(){
		var flag = false;
		inputs.each(function(num, obj){
			if ($(obj).val() != '') flag=true;
		});
		if (!flag) return false;
		return true;
	});

	//-----------------------------------------------
	// resetクリック
	//-----------------------------------------------
	upbody.find('#reset').click(function(){
		if_msg.hide();
		iframe_height();
		return true;
	});
});

//////////////////////////////////////////////////////////////////////////////
// ●フォルダを開く
//////////////////////////////////////////////////////////////////////////////
function open_folder(node) {
	if (if_msg) {	// フォルダを移動したらアップロードメッセージを消す
		if_msg.hide();
		_iframe_height();
	}

	ajax_submit({
  		data: {	path: node.data.key },
		action: 'load_image_files',
		success: function(data) {
			// データsave
			folder = (node.data.key == '/') ? '' : node.data.key;
			files  = data;
			if (if_dir) if_dir.val( folder );

			var title = node.data.key;
			if (node.data.key == '.trashbox/') title = $('#msg-trashbox').text();
			$('#current-folder').text( title );

			// viewの更新
			update_view();
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●ビューのアップデート
//////////////////////////////////////////////////////////////////////////////
function update_view() {
	view.empty();
	for(var i in files) {
		var file = files[i];
		var span = $('<span>');
		var img  = $('<img>', {
			src: path + folder + '.thumbnail/' + file.title + '.jpg'
		});
		span.append(img);
		view.append(span);
	}
}

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
// ●送信前のデータ整形
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
// ●リロードボタン
//////////////////////////////////////////////////////////////////////////////
$('#album-reload').click( function(){
	location.href = location.href;
});


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
});
