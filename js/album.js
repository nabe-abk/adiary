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

	// ファイルアップロード関連
	var upform   = $('#upload-form');
	var iframe   = $('#form-response');
	var message  = $('#upload-messages');
	var upfolder = $('#upload-folder');
	var upreset  = $('#upload-reset');
	var filesdiv = $('#file-elements');
	var inputs   = filesdiv.find('input');

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
// ●[file] 
//////////////////////////////////////////////////////////////////////////////
main.on("drop", function(evt) {
	evt.stopPropagation();
	evt.preventDefault();  
	alert(111);
	//$('#file')[0].files = evt.originalEvent.dataTransfer.files;
});
main.on('dragover', function(evt) {
	return false;
 });


//////////////////////////////////////////////////////////////////////////////
// ●[file] <input type=file> が変更された
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
// ●[file] submit
//////////////////////////////////////////////////////////////////////////////
upform.submit(function(){
	var flag = false;
	inputs.each(function(num, obj){
		if ($(obj).val() != '') flag=true;
	});
	if (!flag) return false;
	
	// submit処理
	iframe.unbind();
	iframe.load(function(){
		upform[0].reset();
		var ary = iframe.contents().text().split(/\n/);
		var ret = ary.shift();
		var reg = ret.match(/ret=\d+/);
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
	});
	return true;
});

//////////////////////////////////////////////////////////////////////////////
// ●[file] reset
//////////////////////////////////////////////////////////////////////////////
upreset.click(function(){
	message.hide();
});

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
			src: path + folder + '.thumbnail/' + file.name + '.jpg'
		});
		img.click( img_click );
		img.dblclick( img_dblclick );
		link.append(img);
		view.append(link);
	}
	
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

	function img_dblclick(evt) {
		var obj = $(evt.target);
		dbl_click = true;
		obj.click();
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
});
