//############################################################################
// タグ編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
$( function(){
	var form = $('#form');
	var tree = $('#tree');
	var open　 = $('#open');
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
		},
	},
	onPostInit: function(isReloading, isError) {
		if (isError) {
			open.prop  ('disabled', true);
			submit.prop('disabled', true);
			reset.prop ('disabled', true);
			$('#load-error').show();
			return;
		}
		submit.prop('disabled', false);
		reset.prop ('disabled', false);
		tree.dynatree("getRoot").getChildren()[1].activate();
	},
	onActivate: function(node) {
		select_node = node;
		open.prop('disabled', false);
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
	var link_key = node.data.link_key;
	var title = node.data.title;
	var tree = node.tree;

	// Disable dynatree mouse- and key handling
	tree.$widget.unbind();

	// Replace node with <input>
	var inp = $('<input>').attr({
		type:  'text',
		value: tag_decode(link_key)
	});
	var item = $(".dynatree-title", node.span);
	item.empty();
	item.append( inp );
	
	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.keydown(function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				$(this).blur();
				break;
			case 13: // [enter]
				node.data.link_key = inp.val();
				$(this).blur();
				break;
		}
	});
	inp.blur(function(evt){
		node.setTitle(title);
		tree.$widget.bind();
		node.focus();
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●タグの削除
//////////////////////////////////////////////////////////////////////////////
open.click(function(){
	var link_key = link_key_encode( select_node.data.link_key );
	var base_url = tree.data('base-url');
	window.open( base_url + link_key );
});

//////////////////////////////////////////////////////////////////////////////
// ●送信前のデータ整形
//////////////////////////////////////////////////////////////////////////////
form.submit(function(){
	var rootNode = tree.dynatree("getRoot");
	var div = $('#div-in-form');
	div.empty();

	// treeと順序の情報
	var cnt=0;
	function search_nodes(node, upnode) {
		var ch = node.getChildren();
		for(var i=0; i<ch.length; i++) {
			var data = ch[i].data;
			var val = data.key + ',' + upnode + ',' + cnt + ',' + data.link_key;
			cnt += tag_priority_step;
			var inp = $('<input>').attr({
				type: 'hidden',
				name: 'contents_ary',
				value: val
			});
			div.append(inp);
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
