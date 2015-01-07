//############################################################################
// アルバム用JavaScript
//							(C)2014 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
//
//tree.json
//	name	フォルダ名	ex) yyy/
//	key	フォルダパス	ex) xxx/yyy/
//	date	UTC
//	count	全ファイル数（サブフォルダ含む）
//
//view.json
//	name	ファイル名
//	size	ファイルサイズ
//	date	UTC
//	isImg	画像ファイルか？ true/false
//
$( function(){
	var main = $('#album');
	var form = $('#album-form');
	var tree = $('#album-folder-tree');
	var view = $('#album-folder-view');
	var selfiles = $('#selected-files')

	// 表示設定
	var all_select = $('#all-select');
	var thumb_size = $('#thumb-maxsize');
	var view_type  = $('#view-type');
	var sort_type  = $('#sort-type');
	var sort_rev   = $('#sort-rev');
	var is_thumbview;

	// ツリー関連
	var path = $('#image-path').text();
	var cur_files;
	var cur_folder;
	var cur_node;

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
	var isIE8 = ('IE'.substr(-1) === 'IE');
	if (isIE8) thumb_size.prop('disabled', true);
	if (isIE8) $('#auto-upload-box').hide();
	
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
tree.dynatree({
	persist: true,
	cookieId: 'album:' + Blogpath,
	minExpandLevel: 2,
	imagePath: $('#icon-path').text(),

	initAjax: { url: tree.data('url') },
	onPostInit: function(isReloading, isError) {
		if (isError) {
			error_msg('#msg-load-error');
			return;
		}

		// ロードしたデータの加工
		var rootNode = tree.dynatree("getRoot");
		rootNode.visit(function(node){
			var data = node.data;
			data.name     = tag_decode(data.name || '');
			data.key      = tag_decode(data.key);
			data.title    = get_title(data);
			data.expand   = true;
			data.isFolder = true;
		});
		var rnodes = rootNode.getChildren();
		if (!rnodes) return;	// エラー回避
		var root = rnodes[1];
		root.data.fix = true;

		// ゴミ箱の設定
		if (rnodes[2].data.name === '.trashbox/') {
			var data = rnodes[2].data;
			data.name  = $('#msg-trashbox').text();
			data.title = get_title(data);
			data.name  = '.trashbox/';
			data.fix   = true;
			data.icon  = 'trashbox.png';
		} 

		// 選択中のノード
		var sel = tree.dynatree("getActiveNode");
		if (!sel) {
			root.activate();
			sel = root;
		}

		// レンダリング
		rootNode.render();
		open_folder(sel, isReloading);
	},
	onActivate: function(node) {
		open_folder(node);
	},
	// ノードの編集
	onClick: function(node, event) {
		if( event.shiftKey ) edit_node(node);
		return true;
	},
	onDblClick: function(node, event) {
		edit_node(node);
		return false;
	},
	onKeydown: function(node, event) {
		switch( event.which ) {
			case 113: // [F2]
				edit_node(node);
				return false;
			case 13: // [enter]
				if( isMac ) edit_node(node);
				return false;
		}
	},

	//----------------------------------------------------
	// Drag & Drop
	//----------------------------------------------------
	dnd: {
		onDragStart: function(node) {
			if (node.data.fix) return false;
			logMsg("tree.onDragStart(%o)", node);
			return true;	// Return false to cancel dragging of node.
		},
		autoExpandMS: 1000,
		preventVoidMoves: true, // Prevent dropping nodes 'before self', etc.
		onDragEnter: function(node, srcNode) {
			 return true;
		},
		onDragOver: function(node, srcNode, hitMode) {
			if (hitMode==='before' || hitMode==='after') return false;
			if(node.isDescendantOf(srcNode)) return false;
			if(node.data.isroot) return false;
			if (!srcNode) return true;

			// 現在のディレクトリ内への移動
			var src_par = srcNode.getParent();
			if (src_par && src_par.data.key === node.data.key) return false;

			return true;
		},
		onDrop: drop_to_tree
	}

});

function get_title(data) {
	// tag_esc in adiary.js
	return tag_esc(data.name) + (data.count==0 ? '' : ' (' + data.count + ')');
}
function get_folder(key) {
	return (key == '/') ? '' : key;
}

//############################################################################
// ■フォルダツリー関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●画像ファイルのドラッグ指定
//////////////////////////////////////////////////////////////////////////////
var visible_on_stop;
var img_draggable_option = {
	connectToDynatree: true,
	zIndex: 100,
	opacity: 	isIE8 ? null : 0.7,
	opacity_text:	isIE8 ? null : 0.95,	// filename-view
	delay:   	isIE8 ? null : 200,
	cursorAt: { top: -5, left:-5 },
	//----------------------------------------
	// ドラッグ中の画像要素
	//----------------------------------------
	helper: function(evt,ui){
		// 開始要素が選択されてない時、選択する
		var obj = $(evt.target);
		if (!is_thumbview && !obj.hasClass('fileline')) obj = obj.parents('.fileline');
		if (!obj.hasClass('selected')) {
			obj.addClass('selected')
			update_selected_files();
		};
		// 選択中の画像すべて
		var div = $('<div>');
		if (is_thumbview) {
			// アイコンビューのとき
			var imgs = view.find('.selected').clone();
			imgs.removeClass('selected');
			imgs.css( {'max-width': 60, 'max-height': 60 });
			div.css('max-width', 320);
			imgs.css({
				padding: 1,
				border: 'none',
				visibility: 'visible'
			});
			div.append(imgs);
		} else {
			// ファイル名ビューのとき
			var files = view.find('.selected');
			for(var i=0; i<files.length; i++) {
				var span = $('<span>').text( $(files[i]).data('title') );
				div.append( span );
			}
			div.attr('id', 'album-dnd-name-view');
			div.css('visibility', 'visible');
		}
		return div;
	},
	//----------------------------------------------------------------
	// ドラッグ開始イベント
	//----------------------------------------------------------------
	start: function(evt,ui) {
		var imgs = view.find('.selected').parent();
		imgs.css('visibility', 'hidden');
		visible_on_stop = true;
	},
	//----------------------------------------------------------------
	// ドラッグ終了イベント
	//----------------------------------------------------------------
	stop: function(evt,ui) {
		if (!visible_on_stop) return;
		var imgs = view.find('.selected').parent();
		imgs.css('visibility', 'visible');
	},

	//----------------------------------------------------------------
	// ドラッグ終了時、「戻る」アニメーションの判定
	//----------------------------------------------------------------
	// trueを返すと、戻るアニメーションが表示される（ドロップ失敗）
	revert: function(obj){
		if(typeof obj === "boolean") {
			// jQuery上で処理される drop可能/不可能対象の時
			return !obj;
		}

		// dynatreeへのドロップの場合 obj が渡される
		var helper = $.ui.ddmanager && $.ui.ddmanager.current && $.ui.ddmanager.current.helper;
		var isRejected = helper && helper.hasClass("dynatree-drop-reject");
		return isRejected;
	}
};

//////////////////////////////////////////////////////////////////////////////
// ●フォルダ名の編集
//////////////////////////////////////////////////////////////////////////////
function edit_node( node ) {
	if (node.data.fix) return;	// root and ゴミ箱

	var ctree = node.tree;
	ctree.$widget.unbind();		// Disable dynatree mouse- and key handling
	var name = node.data.name;
	name = name.substr(0, name.length-1);	// 201201/ to 201201

	// タイトルを <input> 要素に置き換える
	var inp = $('<input>').attr({
		type:  'text',
		value: name
	});
	var title = $(".dynatree-title", node.span);
	title.empty();
	title.append( inp );

	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.select();
	inp.keydown(function(evt){
		var obj = $(evt.target);
		switch( evt.which ) {
			case 27: // [esc]
				obj.blur();
				break;
			case 13: // [enter]
				rename_folder(obj, node, inp.val());
				break;
		}
	});
	//-------------------------------------------
	// ○フォーカスが離れた（編集終了）
	//-------------------------------------------
	inp.blur(function(evt){
		node.setTitle( node.data.title );
		ctree.$widget.bind();
		node.data.rename = false;
		node.focus();
		if (evt && evt.which == 13 && node.data.key != cur_node.data.key)
			node.activate();
	});
}

//-------------------------------------------
// ○リネームの実行
//-------------------------------------------
function rename_folder(obj, node, name) {
	if (name.last_char() != '/') name += '/';
	if (node.data.name === name) {
		obj.blur();	// 変更なし
		return;
	};
	node.data.rename = true;

	ajax_submit({
		action: 'rename_folder',
		data: {
			folder: get_folder( node.getParent().data.key ),
			old:    node.data.name,
			name:   name
		},
		success: function(data) {
			if (data.ret !== 0) {
				obj.blur();
				// blur()してから呼び出さないとキー入力がbindされない
				error_msg('#msg-fail-rename-folder');
				return;
			}
			node.data.name  = name;
			node.data.title = get_title( node.data );
			set_keydata(node.getParent().data.key, node);

			if (cur_node.data.key === node.data.key) set_current_folder(node);
			node.data.rename = false;
			obj.blur();
		},
		error: function() {
			node.data.rename = false;
			obj.blur();
			error_msg('#msg-fail-rename-folder');
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●リロードボタン
//////////////////////////////////////////////////////////////////////////////
function tree_reload() {
	tree.dynatree('getTree').reload();
}

$('#album-reload').click( function(){
	ajax_submit({
		action: 'refresh',
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-reload');
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-reload');
		}
	});
});

//////////////////////////////////////////////////////////////////////////////
// ●フォルダ作成ボタン
//////////////////////////////////////////////////////////////////////////////
$('#album-new-folder').click( function(){
	var node = cur_node;
	var ary  = node.getChildren();
	var name = "New-folder";
	if (ary) {
		// フォルダ名の重複防止
		var h = {};
		for(var i=0; i<ary.length; i++) {
			var dir = ary[i].data.title;
			dir = dir.substr(0, dir.length-1);
			h[dir] = true;
		}
		if (h[name]) {
			// new-folder.2 .3 .4 ...
			for(var i=2; i<1000; i++) {
				var n = name + '.' + i;
				if (h[n]) continue;
				name = n;
				break;
			}
		}
	}
	// フォルダの作成
	ajax_submit({
		action: 'create_folder',
		data: {
			folder: cur_folder,
			name:   name
		},
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-create');
			name += '/';
			var create = node.addChild({
			        isFolder: true,
				title: name
			});
			create.data.name  = name;
			create.data.key   = cur_folder + name;
			create.data.count = 0;
			create.data.title = get_title( create.data );

			// 名前変更モード
			node.expand();
			edit_node(create);
		},
		error: function() {
			error_msg('#msg-fail-create');
		}
	});
});

//////////////////////////////////////////////////////////////////////////////
// ●ゴミ箱空ボタン
//////////////////////////////////////////////////////////////////////////////
$('#album-clear-trashbox').click( function(){
	// 確認メッセージ
	if(! confirm( $('#msg-confirm-trash').text() )) return;

	ajax_submit({
		action: 'clear_trashbox',
		success: function(data) {
			if (data.ret !== 0) error_msg('#msg-fail-clear-trash');
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-clear-trash');
			tree_reload();
		}
	});
});

//////////////////////////////////////////////////////////////////////////////
// ●フォルダの移動
//////////////////////////////////////////////////////////////////////////////
function drop_to_tree(node, srcNode, hitMode, ui, draggable) {
	// フォルダの中へのドロップのみ有効
	if (hitMode !== "over") return false;
	// ファイルのドロップ？
	if (!srcNode) return move_files(node, srcNode, hitMode, ui, draggable);

	ajax_submit({
		action: 'move_files',
		data: {
			from: srcNode.getParent().data.key,
			to:   node.data.key,
			file_ary: [ chop_slash(srcNode.data.name) ]
		},
		success: function(data) {
			if (data.ret !== 0) error_msg('#msg-fail-mv-folder', {files: data.files});
			srcNode.move(node, hitMode);
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-mv-folder');
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●ファイルの移動
//////////////////////////////////////////////////////////////////////////////
function move_files(node, srcNode, hitMode, ui, draggable) {
	// 現在のフォルダには移動できない
	if (node.data.key === cur_node.data.key) return false;

	var imgs = view.find('.selected');
	var files = [];
	for(var i=0; i<imgs.length; i++)
		files.push( $(imgs[i]).data('title') );
	if (!files.length) return false;

	ajax_submit({
		action: 'move_files',
		data: {
			from: cur_folder,
			to:   node.data.key,
			file_ary: files
		},
		success: function(data) {
			if (data.ret !== 0) error_msg('#msg-fail-mv-files', {files: data.files});
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-mv-files');
			// ファイルを再表示
			var imgs = view.find('.selected').parent();
			imgs.css('visibility', 'visible');
		}
	});

	// 元アイコンは非表示のままにする
	visible_on_stop = false;
	return true;
}


//////////////////////////////////////////////////////////////////////////////
// ●選択ファイルの一覧の更新
//////////////////////////////////////////////////////////////////////////////
function update_selected_files() {
	var imgs = view.find('.selected');

	selfiles.empty();
	for(var i=0; i<imgs.length; i++) {
		var name = $(imgs[i]).data('title');
		var li = $('<li>').text( name );
		li.data('name', name);
		li.dblclick(function(evt){ edit_file_name($(evt.target)); });
		selfiles.append(li);
	}
}

//----------------------------------------------------------------------------
// ファイル名の編集
//----------------------------------------------------------------------------
function edit_file_name(li) {
	var inp = $('<input>').attr({
		type:  'text',
		value: li.data('name')
	}).addClass('w90p');
	li.empty();
	li.append( inp );

	inp.focus();
	inp.select();
	inp.keydown(function(evt){
		var obj = $(evt.target);
		switch( evt.which ) {
			case 27: // [esc]
				obj.blur();
				break;
			case 13: // [enter]
				rename_file(inp, li, inp.val());
				break;
		}
	});
	//-------------------------------------------
	// ○フォーカスが離れた（編集終了）
	//-------------------------------------------
	inp.blur(function(evt){
		li.text( li.data('name') );
	});
	
}

//----------------------------------------------------------------------------
// ファイル名の変更
//----------------------------------------------------------------------------
function rename_file(obj, li, new_name) {
	ajax_submit({
		action: 'rename_file',
		data: {
			folder: cur_folder,
			old:    li.data('name'),
			name:   new_name,
			size:	$('#thumbnail-size').val()
		},
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-rename-file');
			var old = li.data('name');
			li.data('name', new_name);
			obj.blur();

			// ファイル名の変更を記録する
			for(var i in cur_files) {
				var x = cur_files[i].name;
				if (cur_files[i].name != old) continue;
				cur_files[i].name = new_name;
				break;
			}

			// 選択済情報を保持する
			var lis = selfiles.find('li');
			var files = {};
			for(var i=0; i<lis.length; i++) {
				files[ $(lis[i]).data('name') ] = true;
			}
			update_view(true, files);
		},
		error: function() {
			error_msg('#msg-fail-rename-file');
			obj.blur();
		}
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●サブルーチン
//////////////////////////////////////////////////////////////////////////////
// tree操作時のエラー表示
function error_msg(id, h) {
	if (h && h.files)
		h.f = '<div class="small">' + h.files.join("<br>") + '</blockquote>';
	show_error(id, h);
}

// 末尾の / を除去
function chop_slash(str) {
	if (str.last_char() != '/') return str;
	return str.substr(0, str.length-1);
}

// keyの設定
function set_keydata(folder, node) {
	folder = folder + node.data.name;
	var cur = (node.data.key === cur_node.data.key);
	node.data.key = folder;
	if (cur) set_current_folder(node);

	var list = node.getChildren();
	if (!list) return;

	for(var i=0; i<list.length; i++)
		set_keydata(folder, list[i]);
};

//############################################################################
// ■メインビュー関連
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●フォルダを開く
//////////////////////////////////////////////////////////////////////////////
function open_folder(node, isReloading) {
	if (!isReloading) {
		message.hide();
		all_select.prop('checked', false);
	}
	if (node.data.rename) return;	// リネーム中は何もしない
	ajax_submit({
  		data: {	path: node.data.key },
		action: 'load_image_files',
		success: function(data) {
			// データsave
			cur_files = data;
			set_current_folder(node)

			// viewの更新
			update_view();
		},
		error: function() {
			$('#current-folder').text( '(load failed!)' );
			error_msg('#msg-load-error');
			cur_files = [];
			update_view();
		}
	});
}

function set_current_folder(node) {
	folder = get_folder( node.data.key );
	upfolder.val( folder );
	cur_folder = folder;
	cur_node   = node;

	var icon = $('#folder-icon');
	icon.empty();
	icon.removeClass('dynatree-icon');

	var title = node.data.key;
	if (title.substr(0,9) == '.trashbox') {
		title = $('#msg-trashbox').text() + title.substr(9);
		icon.append(
			$('<img>').attr('src', $('#icon-path').text() + 'trashbox.png' )
		);
	} else {
		icon.addClass('dynatree-icon');
	}
	$('#current-folder').text( title );
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
		dataType: opt.type || 'json',
		error: function(data) {
			if (opt.error) opt.error(data);
			console.log('[ajax_submit()] http post fail');
			console.log(data);
		},
		success: function(data) {
			if (opt.success) opt.success(data);
			console.log('[ajax_submit()] http post success');
			console.log(data);
		},
		traditional: true
	});
	return true;
}

//////////////////////////////////////////////////////////////////////////////
// ●全選択
//////////////////////////////////////////////////////////////////////////////
all_select.change( function(){ all_select_change() } );

function all_select_change(init) {
	var stat = all_select.is(":checked");
	var imgs = is_thumbview ? view.find('img') : view.find('.fileline');
	for(var i=0; i<imgs.length; i++) {
		var obj = $(imgs[i]);
		if (stat) {
			obj.addClass('selected');
			continue;
		}
		if (!init) obj.removeClass('selected');
	}
	update_selected_files();
}

//////////////////////////////////////////////////////////////////////////////
// ●表示形式変更
//////////////////////////////////////////////////////////////////////////////
view_type.change( view_change );
sort_type.change( view_change );
sort_rev.change ( view_change );
function view_change() {
	// 選択済情報を保持する
	var imgs = view.find('.selected');
	var files = {};
	for(var i=0; i<imgs.length; i++) {
		files[ $(imgs[i]).data('title') ] = true;
	}
	update_view(false, files);
}


//////////////////////////////////////////////////////////////////////////////
// ●ビューのアップデート
//////////////////////////////////////////////////////////////////////////////
function update_view(flag, selected) {
	var thumbq = cur_node.data.thumb_remake;
	if (flag) {
		// サムネイルの強制更新
		thumbq = thumbq ? thumbq+1 : 1;
		cur_node.data.thumb_remake = thumbq;
	}
	thumbq = thumbq ? ('?' + thumbq) : '' ;

	// 選択済みファイルのハッシュ
	selected = selected ? selected : {};

	// ソート処理
	{
		var type = sort_type.val();
		var func = sort_rev.val() != 0
			? function(a,b) { return (a[type] < b[type]) ?  1 : -1; }
			: function(a,b) { return (a[type] < b[type]) ? -1 :  1; };
		cur_files.sort( func );
	}

	view.empty();
	if (view_type.val() != 'name')
	  for(var i in cur_files) {
		// サムネイルビュー
		is_thumbview = true;
		view.removeClass('name-view');
		view.addClass('thumb-view');
		var file = cur_files[i];
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
			src: path + folder + '.thumbnail/' + file.name + '.jpg' + thumbq,
			title: file.name,
			'data-title': file.name,
			'data-isimg': file.isImg ? 1 : 0
		});
		img.click( img_click );
		img.dblclick( img_dblclick );
		if (selected[file.name]) img.addClass('selected');
		link.append(img);
		view.append(link);

		// for Drag&Drop
		img.draggable( img_draggable_option );
	} else {
	  for(var i in cur_files) {
		// ファイル名ビュー
		is_thumbview = false;
		view.removeClass('thumb-view');
		view.addClass('name-view');
		var file = cur_files[i];
		var link = $('<a>', {
			href: path + folder + file.name
		});
		if (file.isImg) {
			link.attr({
				'data-lightbox': 'roadtrip',
				'data-title': file.name
			});
		}
		var span = $('<span>').addClass('fileline').data('title', file.name);
		// ファイル名
		var fname = $('<span>').text( file.name );
		fname.addClass('js-popup-img').data('img-url', path + folder + '.thumbnail/' + file.name + '.jpg' + thumbq);
		span.append( $('<span>').addClass('filename').append( fname ) );
		// 日付
		var date = new Date( file.date*1000 );
		var tms  = date.toLocaleString().replace(/\b(\d[\/: ])/g, "0$1");
		span.append( $('<span>').addClass('filedate').text( tms ) );
		// サイズ
		span.append( $('<span>').addClass('filesize').text( size_format(file.size) ) );

		// 追加
		span.click( img_click );
		span.dblclick( img_dblclick );
		if (selected[file.name]) span.addClass('selected');
		link.append(span);
		view.append(link);

		// for Drag&Drop
		span.draggable( img_draggable_option );
		span.draggable( { opacity: img_draggable_option.opacity_text } );
	  }
	}

	//-----------------------------------------------
	// 画像のクリック
	//-----------------------------------------------
	var dbl_click;
	function img_click(evt) {
		if (dbl_click || evt.ctrlKey) {
			dbl_click = false;
			return;
		}
		// イベント処理
		var obj = $(evt.target);
		if (!is_thumbview && !obj.hasClass('fileline')) obj = obj.parents('.fileline');
		evt.stopPropagation();
		evt.preventDefault()
		if (obj.hasClass('selected'))
			obj.removeClass('selected');
		else
			obj.addClass('selected');
		update_selected_files();
	}

	//-----------------------------------------------
	// 画像のダブルクリック
	//-----------------------------------------------
	function img_dblclick(evt) {
		var obj = $(evt.target);
		if (!is_thumbview && !obj.hasClass('fileline')) obj = obj.parents('.fileline');
		dbl_click = true;
		obj.click();
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●サムネイル最大サイズの変更
//////////////////////////////////////////////////////////////////////////////
thumb_size.change( thumb_size_change )
if (thumb_size.val() != 120) thumb_size_change();

var apeend_style;
function thumb_size_change() {
	var size = Number( thumb_size.val() );
	if (size<60 || 320<size) return;
	if (IE8) return;

	if (apeend_style) apeend_style.remove();
	apeend_style = $('<style>').text(
		'#album-folder-view img {'
		+ 'max-width:  ' + size + 'px;'
		+ 'max-height: ' + size + 'px;'
		+ '}'
	);
	$('head').append(apeend_style);
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

	var ary=[];
	for(var i=0; i<sel.length; i++) {
		var img = $(sel[i]);
		var tag = img.data('isimg') ? imgtag : filetag;

		var name = img.data('title');
		var reg  = name.match(/\.(\w+)$/);
		var ext  = reg ? reg[1] : '';
		var rep  = {
			d: escape_satsuki(cur_folder),
			e: escape_satsuki(ext),
			f: escape_satsuki(name)
		};
		tag = tag.replace(/%([def])/g, function($0,$1){ return rep[$1] });
		ary.push(tag);
	}
	var text= ary.join( evt.ctrlKey ? " \\\n" : "\n" )

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

function escape_satsuki(text) {
	return text.replace(/([:\[\]])/g, "\\$1")

}

//////////////////////////////////////////////////////////////////////////////
// ●サムネイルの再生成
//////////////////////////////////////////////////////////////////////////////
$('#remake-thumbnail').click(function(){
	var sel = view.find('.selected');
	if (!sel.length) return false;

	var files = [];
	for(var i=0; i<sel.length; i++) {
		files.push( $(sel[i]).data('title') );
	}

	ajax_submit({
		action: 'remake_thumbnail',
		data: {
			folder: cur_folder,
			file_ary: files,
			size: $('#thumbnail-size').val()
		},
		success: function(data) {
			if (data.ret !== 0) {
				// ファイル名が不正など
				error_msg('#msg-fail-remake');
				return;
			}
			var node = cur_node;
			// view更新
			update_view(true);
		},
		error: function() {
			// 通常起きない
			error_msg('#msg-fail-remake');
		}
	});
});

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

	// 自動アップロード
	if ($('#auto-upload').prop('checked')) upform.submit();
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
	apeend_input_file();
}
//-----------------------------
// 新しい要素の追加
//-----------------------------
function apeend_input_file() {
	if (inputs.length > 99) return;
	var inp = $('<input>', {
		type: 'file',
		name: 'file' + inputs.length + '_ary',
		multiple: 'multiple'
	}).change(input_change);
	filesdiv.append( inp );

	// 要素リスト更新
	inputs = filesdiv.find('input');
}

inputs.change( input_change );
input_change();

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
		upload_post_process( iframe.contents().text() );
	});
	message.html('<div class="message uploading">' + $('#uploading-msg').text() + '</div>');
	message.show();
	return true;
});

function upload_post_process(text) {
	upform_reset();	// フォームリセット
	var ary = text.split(/[\r\n]/);		// \r for IE8
	var ret = ary.shift();
	var reg = ret.match(/^ret=\d*/);
	if (reg) {
		ret = reg[0];
		message.html( ary.join("\n") );
		message.show( Default_show_speed );
	}

	// ファイル選択を初期化する
	filesdiv.empty();
	apeend_input_file();

	// アルバムツリーのリロード
	tree_reload();
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
			upload_post_process( xhr.responseText );
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			upload_post_process(data);
		}
	});

	upform_reset();
	message.html('<div class="message uploading">' + $('#uploading-msg').text() + '</div>');
	message.show();
	return false;
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
