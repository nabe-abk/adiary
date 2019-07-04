//############################################################################
// タグ編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';
$( function(){
	var form = $secure('#form');
	var tree = $secure('#tree');
	var join = $('#join-children');
	var del  = $('#delete');
	var submit = $('#submit');
	var reset  = $('#reset');

	var base_url = tree.data('base-url');

	var select_node;
	var dels = [];
	var tag_priority_step = 10;

	var isMac = /Mac/.test(navigator.platform);
//////////////////////////////////////////////////////////////////////////////
// ●初期化処理
//////////////////////////////////////////////////////////////////////////////
tree.dynatree({
	initAjax: { url: tree.data('url') },
	dnd: {
		onDragStart: function(node) {
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
		        // Prohibit creating childs in non-folders (only sorting allowed)
			if( !node.data.isFolder && hitMode === "over" )
				return "after";
		},
		onDrop: function(node, sourceNode, hitMode, ui, draggable) {
			sourceNode.move(node, hitMode);
			if (select_node) {
				join.prop('disabled', select_node.getChildren() ? false : true);
			}
		},
	},
	onPostInit: function(isReloading, isError) {
		if (isError) {
			join.prop  ('disabled', true);
			del.prop   ('disabled', true);
			submit.prop('disabled', true);
			reset.prop ('disabled', true);
			$('#load-error').show();
			return;
		}
		var rootNode = tree.dynatree("getRoot");
		rootNode.visit(function(node){
			var par   = node.getParent();
			var path  = (par && par != rootNode) ? par.data.full + '::' : '';
			var data  = node.data;

			data.name = "" + data.title;
			data.full = path + data.title;
			data.href = base_url + encodeURIComponent( data.full );
			set_node_title(node);

			// ダブルタップで編集
			$(node.span).on("mydbltap", function(evt) {
				editNode(node);
			});
			
			// ノードを開く
			node.expand(true);
		});
		var ch = rootNode.getChildren();
		if (ch && ch.length>0) ch[1].activate();
		submit.prop('disabled', false);
		reset.prop ('disabled', false);
	},
	onActivate: function(node) {
		select_node = node;
		del.prop('disabled', false);
		join.prop('disabled', node.getChildren() ? false : true);
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
// ●リンクの動作を停止
//////////////////////////////////////////////////////////////////////////////
tree.on('click dblclick', 'a', function(evt) {
	evt.preventDefault();
});

//////////////////////////////////////////////////////////////////////////////
// ●データからタイトルを設定
//////////////////////////////////////////////////////////////////////////////
function set_node_title(node) {
	var data  = node.data;
	var title = data.name + ' (' + data.qt + ')';
	data.title = title;
	node.setTitle( title );
}

//////////////////////////////////////////////////////////////////////////////
// ●タグの名称編集
//////////////////////////////////////////////////////////////////////////////
function editNode( node ) {
	// Disable dynatree mouse and key handling
	node.tree.$widget.unbind();

	// Replace node with <input>
	var inp = $('<input>').attr({
		type:  'text',
		value: adiary.tag_decode_amp(node.data.name)
	});

	// ノードの選択中表示を解除する
	var span = $(node.span);
	span.removeClass('dynatree-active');

	// <a>タグが消える瞬間にイベントを拾ってしまうので対策
	var item = span.find( ".dynatree-title" );	// aタグ
	item.removeAttr('href');

	// aタグ内にinputを入れるとマウスクリックに対して
	// 不可思議な動作をするので、span に置き換える。
	var box = $('<span>');
	box.addClass( item.attr('class') );
	box.append( inp );
	item.replaceWith( box );

	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.select();
	inp.keydown(function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				$(this).blur();
				break;
			case 13: // [enter]
				var name = adiary.tag_esc_amp( inp.val() );
				if (name.match(/^\s*$/)) {
					$(this).blur();
					break;
				}
				if (name.match(/[,]|::/)) {
					adiary.show_error('#tag-name-error');
					break;
				}
				node.data.name = name;
				$(this).blur();
				break;
		}
	});

	var tree_click = function(evt){
		if (inp[0] == evt.target) return;
		inp.blur();
	};
	tree.click(tree_click);

	inp.blur(function(evt){
		tree.unbind('click', tree_click);
		set_node_title(node);
		node.tree.$widget.bind();
		node.focus();
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●タグの統合
//////////////////////////////////////////////////////////////////////////////
join.click(function(){
	var pkey = select_node.data.key;
	var ary  = select_node.data.joinkeys || [];
	join.prop('disabled', true);

	var qt=0;
	function search_nodes(node) {
		var ch = node.getChildren();
		for(var i=ch.length-1; -1<i; i--) {	// removeのために逆回し
			ary.push(ch[i].data.key);
			if (ch[i].data.joinkeys) ary = ary.concat( ch[i].data.joinkeys );
			if (ch[i].getChildren()) search_nodes(ch[i]);
			qt += ch[i].data.qt;
			ch[i].remove();
		}
	}
	search_nodes(select_node);

	select_node.data.joinkeys = ary;
	select_node.data.qt      += qt;
	set_node_title( select_node );
});

//////////////////////////////////////////////////////////////////////////////
// ●タグの削除
//////////////////////////////////////////////////////////////////////////////
del.click(function(){
	if (select_node.getChildren()) join.click();

	var pkey = select_node.data.key;
	var ary  = select_node.data.joinkeys;
	dels.push(pkey);
	if (ary) dels = dels.concat(ary);

	select_node.remove();

	select_node = undefined;
	del.prop('disabled', true);
});

//////////////////////////////////////////////////////////////////////////////
// ●送信前のデータ整形
//////////////////////////////////////////////////////////////////////////////
form.submit(function(){
	var rootNode = tree.dynatree("getRoot");
	var div = $secure('#div-in-form');
	div.empty();

	// タグの削除
	for(var i=0; i<dels.length; i++) {
		var inp = $('<input>').attr({
			type: 'hidden',
			name: 'del_ary',
			value: dels[i]
		});
		div.append(inp);
	}

	// treeと順序の情報
	var cnt=0;
	function search_nodes(node, upnode) {
		var ch = node.getChildren();
		for(var i=0; i<ch.length; i++) {
			var data = ch[i].data;
			var val = data.key + ',' + upnode + ',' + cnt + ',' + data.name;
			cnt += tag_priority_step;
			var inp = $('<input>').attr({
				type: 'hidden',
				name: 'tag_ary',
				value: adiary.tag_decode_amp(val)
			});
			div.append(inp);
			// join情報
			if (data.joinkeys) {
				var ary = data.joinkeys;
				ary.unshift( data.key );
				var val = ary.join(',');
				var inp = $('<input>').attr({
					type: 'hidden',
					name: 'join_ary',
					value: val
				});
				div.append(inp);
			}
			// 再帰呼び出し
			if (ch[i].getChildren()) search_nodes(ch[i], data.key);
		}
	}
	search_nodes(rootNode, 0);

	return true;
});

//////////////////////////////////////////////////////////////////////////////
// ●キャンセル（リロード）
//////////////////////////////////////////////////////////////////////////////
reset.click(function(){
	tree.dynatree("getTree").reload();
});

//############################################################################
});
