//############################################################################
// ■スケルトン用ルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●コメント欄の加工
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const self=this;
	$('#com div.comment-text').each(function(idx,dom) {
		const $obj = $(dom);

		//////////////////////////////////////////////////////////////
		// リンクに加工 ex) >>14 >>2
		//////////////////////////////////////////////////////////////
		let flag;
		let text = $obj.html();
		text = text.replace(/&gt;&gt;(\d+)/g, function(all, num){
			flag=true;
			return '<a href="#c' + num + '">&gt;&gt;' + num + '</a>';
		});
		if (!flag) return;
		$obj.html(text);

		//////////////////////////////////////////////////////////////
		// regist popup
		//////////////////////////////////////////////////////////////
		$obj.find('a').on('mouseover', {
			func: function($obj, $div) {
				const num  = $obj.attr('href').toString().replace(/[^\d]/g, '');
				const $com = $('#c' + num);
				if (!$com.length) return $div.empty();
				$div.attr('id', 'popup-com');
				$div.html( $com.html() );
			}
		}, function(evt){ self.popup(evt) });
	});
});

//////////////////////////////////////////////////////////////////////////////
//●セキュリティコードの設定
//////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const $form = $('#comment-form');
	if (!$form.length) return;
	const $csrf = $form.find('[name="csrf_check_key"]');
	if ($csrf.length) return;		// login中は無用

	let   pkey = $('#comment-form-apkey').val() || '';
	const ary  = ($form.data('secure') || '').split(',');
	if (!pkey.match(/^\d+$/)) return;
	pkey = parseInt(pkey) & 255;

	let sid = '';
	for(var i=0; i<ary.length-1; i++) {
		if (!ary[i].match(/^\d+$/)) return;
		sid += String.fromCharCode( ary[i] ^ pkey );
	}

	// 投稿ボタンを disable に
	const $btn = $('#post-comment');
	$btn.prop('disabled', true);

	// 10key押されるか、10秒経ったら設定
	const $ta = $form.find('textarea');

	let hook;
	let timer;
	const enable_func = function() {
		clearTimeout( timer );
		$ta.off('keydown', hook);
		$('#comment-form-sid').val(sid);
		$btn.prop('disabled', false);
	};

	let cnt=this.CommentEnableKeys;
	if (cnt) {
		hook = function() {
			cnt--;
			if (cnt) return;
			enable_func();
		}
		$ta.on('keydown', hook);
	}

	timer = setTimeout(enable_func, this.CommentEnableTime);
});

//////////////////////////////////////////////////////////////////////////////
// ●検索条件の項目マーク
//////////////////////////////////////////////////////////////////////////////
$$.init_top_search = function(id, flag) {
	var $form = $secure(id);
	var tagdel = $('<span>').addClass('ui-icon ui-icon-close');
	if (!flag) tagdel.click(function(evt){
		var $obj = $(evt.target);
		$obj.parent().remove();
		$form.submit();
	});
	$form.find("div.taglist span.tag, div.ctype span.ctype, div.yyyymm span.yyyymm").append(tagdel);
}

//////////////////////////////////////////////////////////////////////////////
// ●検索ハイライト表示
//////////////////////////////////////////////////////////////////////////////
$$.word_highlight = function(id) {
	var ch = $(id).children();
	var words = [];
	for(var i=0; i<ch.length; i++) {
		var w = $(ch[i]).text();
		if (w.length < 1) continue;
		words.push( w.toLowerCase() );
	}

	var target = $("#articles article h2 .title, #articles article div.body div.body-main, #articles span.tags");
	var h_cnt = 0;
	rec_childnodes(target, words);

	// childnodesを再起関数で探索
	function rec_childnodes(_nodes, words) {
		// ノードはリアルタイムで書き換わるので、呼び出し時点の状態を保存しておく
		var nodes = [];
		for(var i=0; i<_nodes.length; i++)
			nodes.push(_nodes[i]);
		
		// テキストノードの書き換えループ
		for(var i=0; i<nodes.length; i++) {
			if (nodes[i].nodeType == 3) {
				var text = nodes[i].nodeValue;
				if (text == undefined || text.match(/^[\s\n\r]*$/)) continue;
				do_highlight_string(nodes[i], words);
				h_cnt++; if (h_cnt>999) break; 
				continue;
			}
			if (! nodes[i].hasChildNodes() ) continue;
			rec_childnodes( nodes[i].childNodes, words );	// 再起
		}
	}
	function do_highlight_string(node, words) {
		var par  = node.parentNode;
		var str  = node.nodeValue;
		var str2 = str.toLowerCase();
		var find = false;
		var d = document;
		while(1) {
			var p=str.length;
			var n=-1;
			for(var i=0; i<words.length; i++) {
				var w = words[i];
				var x = str2.indexOf(w);
				if (x<0 || p<=x) continue;
				p = x;
				n = i;
			}
			if (n<0) break;	// 何も見つからなかった
			// words[n]が位置pに見つかった
			var len = words[n].length;
			var before = d.createTextNode( str.substr(0,p)   );
			var word   = d.createTextNode( str.substr(p,len) );
			var span   = d.createElement('span');
			span.className = "highlight highlight" + n;
			span.appendChild( word );
			if (p) par.insertBefore( before, node );
			par.insertBefore( span, node );

			find = true;
			str  = str.substr ( p + len );
			str2 = str2.substr( p + len );
		}
		if (!find) return ;
		// 残った文字列を追加して、nodeを消す
		if (str.length) {
			var remain = d.createTextNode( str );
			par.insertBefore( remain, node );
		}
		par.removeChild( node );
	}
}

//////////////////////////////////////////////////////////////////////////////
// ●タグ一覧のロード
//////////////////////////////////////////////////////////////////////////////
$$.load_tags_list = function(id) {
	const $sel     = $(id);		// セレクトボックス
	const _default = $sel.data('default') || '';

	$.getJSON( $sel.data('url'), function(data){
		var r_func = function(ary, head, tab) {
			for(var i=0; i<ary.length; i++) {
				var name= ary[i].title;
				var val = head + name;
				var opt = $('<option>').attr('value', val);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + val );
				if ( val == _default ) opt.prop('selected', true);
				$sel.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, head+name+'::', tab+1 );
			}
		};
		r_func(data, '', 0);
		$sel.change();
	});
}

//////////////////////////////////////////////////////////////////////////////
// ●コンテンツ一覧のロード
//////////////////////////////////////////////////////////////////////////////
$$.load_contents_list = function(id) {
	var obj = $(id);
	$.getJSON( obj.data('url'), function(data){
		var _default  = obj.data('default');
		var this_pkey = obj.data('this-pkey');

		var r_func = function(ary, tab) {
			for(var i=0; i<ary.length; i++) {
				var pkey  = ary[i].key;
				if (pkey == this_pkey) continue;
				var title = ary[i].title;
				if (title.length > 20)
					title = title.substr(0,20) + '...';

				var opt = $('<option>').attr('value', pkey);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + title );
				opt.data('link_key', ary[i].link_key);
				if ( pkey == _default ) opt.prop('selected', true);
				obj.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, tab+1 );
			}
		};
		r_func(data, 0);
		obj.change();
	});
}

