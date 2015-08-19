//############################################################################
// タグ編集用JavaScript
//							(C)2013 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';
$( function(){
	var form = $secure('#form');
	var tree = $('#tree');
	var submit = $('#submit');
	var reset  = $('#reset');

	var base_url = tree.data('base-url');

	var select_node;
	var dels = [];
	var contents_priority_step = 10;

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
			submit.prop('disabled', true);
			reset.prop ('disabled', true);
			$('#load-error').show();
			return;
		}
		var rootNode = tree.dynatree("getRoot");
		rootNode.visit(function(node){
			var data  = node.data;
			data.href = base_url + data.link_key;
			node.setTitle( data.title );

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
// ●コンテンツキーの編集
//////////////////////////////////////////////////////////////////////////////
function editNode( node ) {
	var link_key = node.data.link_key;
	var title = node.data.title;

	// Disable dynatree mouse and key handling
	node.tree.$widget.unbind();

	// Replace node with <input>
	var inp = $('<input>').attr({
		type:  'text',
		value: tag_decode(link_key)
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

	var tree_click = function(evt){
		if (inp[0] == evt.target) return;
		inp.blur();
	};
	tree.click(tree_click);

	inp.blur(function(evt){
		tree.unbind('click', tree_click);
		node.setTitle(title);
		node.tree.$widget.bind();
		node.focus();
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●送信前のデータ整形
//////////////////////////////////////////////////////////////////////////////
form.submit(function(){
	var rootNode = tree.dynatree("getRoot");
	var div = $secure('#div-in-form');
	div.empty();

	// treeと順序の情報
	var cnt=contents_priority_step;
	function search_nodes(node, upnode) {
		var ch = node.getChildren();
		for(var i=0; i<ch.length; i++) {
			var data = ch[i].data;
			var val = data.key + ',' + upnode + ',' + cnt + ',' + data.link_key;
			cnt += contents_priority_step;
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
