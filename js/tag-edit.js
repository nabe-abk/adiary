//############################################################################
// タグ編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$( function(){
	var form = $secure('#form');
	var tree = $('#tree');
	var join = $('#join-children');
	var del  = $('#delete');
	var submit = $('#submit');
	var reset  = $('#reset');

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
// ●タグの名称編集
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
// ●タグの統合
//////////////////////////////////////////////////////////////////////////////
join.click(function(){
	var pkey = select_node.data.key;
	var ary  = select_node.data.joinkeys || [];
	join.prop('disabled', true);

	function search_nodes(node) {
		var ch = node.getChildren();
		for(var i=ch.length-1; -1<i; i--) {	// removeのために逆回し
			ary.push(ch[i].data.key);
			if (ch[i].data.joinkeys) ary = ary.concat( ch[i].data.joinkeys );
			if (ch[i].getChildren()) search_nodes(ch[i]);
			ch[i].remove();
		}
	}
	search_nodes(select_node);

	select_node.data.joinkeys = ary;
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
			var val = data.key + ',' + upnode + ',' + cnt + ',' + data.title;
			cnt += tag_priority_step;
			var inp = $('<input>').attr({
				type: 'hidden',
				name: 'tag_ary',
				value: val
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
