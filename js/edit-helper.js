//############################################################################
// 編集ヘルパー機能 JavaScript
//							(C)2019 nabe@abk
//############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_image;	// global function for edit.js, album.js

$(function(){
//############################################################################
// ■テキストエリア加工
//############################################################################

//----------------------------------------------------------------------------
// ●カーソル位置にテキスト挿入
//----------------------------------------------------------------------------
// save to global for album.js
insert_image = function(text, caption, fig_class) {
	if (html_mode) {
		var imgdir = $('#image-dir').text();
		text = text.replace(/\[image:((?:\\[:\[\]]|[^\]])+)\]/g, function(ma, m1){
			var ary = m1.split(':');
			var thumb1 = (ary[0] == 'S') ? '.thumbnail/' : '';
			var thumb2 = (ary[0] == 'S') ? '.jpg'        : '';
			ary[1] = unesc_satsuki_tag( ary[1] );
			ary[2] = unesc_satsuki_tag( ary[2] );
			var file = imgdir + ary[1] + ary[2];
			var img  = imgdir + ary[1] + thumb1 + ary[2] + thumb2;
			// 属性
			var attr = '';
			var $info = $('#imglink-info');
			attr += $info.data('class')  ? ( ' class="' + $info.data('class')  + '"') : '';
			attr += $info.data('target') ? (' target="' + $info.data('target') + '"') : '';
			var data = $info.data('data');
			if (data) {
				var k = $('#edit-pkey').val()*1 || floor((new Date()).getTime());
				var ary = data.replace(/%k/g, k).split(/\s+/);
				for(var i=0; i<ary.length; i++) {
					var at = ary[i];
					var ma = at.match(/^([A-Za-z][\w\-]*)=(.*)/);
					if (!ma) continue;
					attr += ' data-' + ma[1] + '="' + ma[2] + '"';
				}
			}
			return '<figure class="image">'
				+ '<a href="' + file + '"' + attr + '>'
				+ '<img src="' + img + '">'
				+ '</a></figure>';
		});
		text = text.replace(/\[file:((?:\\[:\[\]]|[^\]])+)\]/g, function(ma, m1){
			var ary = m1.split(':');
			var ext = ary[0];
			ary[1] = unesc_satsuki_tag( ary[1] );
			ary[2] = unesc_satsuki_tag( ary[2] );
			ary[3] = unesc_satsuki_tag( ary[3] );
			return '<a href="' + imgdir + ary[1] + ary[2] + '">'
				+ ary[3] + '</a>';
		});
	}

	//------------------------------------------------------------------
	// キャプションとブロックの処理
	//------------------------------------------------------------------
	if (caption) caption = caption.replace(/^\s+/,'').replace(/\s+$/,'');
	if (caption || fig_class) {
		caption = caption ? caption : '';
		fig_class  = fig_class  ? fig_class  : '';
		if (helper_mode == 'default') {
			if (caption) fig_class = fig_class + ((fig_class == '') ? '' : ' ') + "caption=" + caption
			if (fig_class) {
				text = "\n>>|figure " + fig_class + "\n"
					+ text + "\n" +
					"|<<\n";
			}
		} else {
			text = (helper_mode == 'markdown' ? ' ' : '')
				+ "\n" + '<figure class="' + fig_class + '">'
				+ text
				+ (caption ? '<figcaption>'+ tag_esc_amp(caption) +'</figcaption>' : '').toString()
				+ "</figure>\n";
		}
	}
	return insert_text(text);
}

//############################################################################
// ■記法ヘルパー機能
//############################################################################
var Helpers = [];
Helpers.push({
	regexp:	/^(?:default|satsuki)/i,
	escape:	true,
	url:	'https://adiary.org/v3man/Satsuki/',
	head:	{ func: 'block',	tag:  '*$0',	form_type: 'text' },
	strong:	{ func: 'inline',	tag: '[bf:$0]' },
	link:	{ func: 'inline',	tag: '[$0$1]',   arg_format: ':$1' },
	anno:	{ func: 'inline',	tag: '(($0))'	},
	list:	{ func: 'block',	tag: '-$0'	},
	quote:	{ func: 'block',	start: '>>$1', end: '<<', sp:true, arg_format: '[&$1]' },
	color:	{ func: 'inline',	tag: '[color:$1:$0]' },
	fsize:	{ func: 'inline',	tag: '[$1:$0]'	},

	toc:	{ func: 'insert',	tag: "\n[*toc]\n" },
	google:	{ func: 'inline',	tag: '[g:$0$1]', arg_format: ':$1' },
	wiki:	{ func: 'inline',	tag: '[w:$0]' },
	album:	{ func: 'album' }
});
Helpers.push({
	regexp:	/^markdown/i,
	escape: true,
	url:	'https://adiary.org/v3man/Markdown/syntax',
	head:	{ func: 'block',	tag:  '#$0',	form_type: 'text' },
	strong:	{ func: 'inline',	tag: '**$0**' },
	link:	{ func: 'inline',	tag: '[$0$1]',   arg_format: ':$1' },
	anno:	{ func: 'inline',	tag: '(($0))'	},
	list:	{ func: 'block',	tag: '- $0'	},
	quote:	{ func: 'block',	tag: '> $0'	},
	color:	{ func: 'inline',	tag: '[color:$1:$0]' },
	fsize:	{ func: 'inline',	tag: '[$1:$0]'	},

	toc:	{ func: 'insert',	tag: "\n[*toc]\n" },
	google:	{ func: 'inline',	tag: '[g:$0$1]', arg_format: ':$1' },
	wiki:	{ func: 'inline',	tag: '[w:$0]' },
	album:	{ func: 'album' }
});
Helpers.push({
	regexp:	/^(?:re?st)/i,
	escape:	false,
	url:	'https://docutils.sphinx-users.jp/docutils/docs/ref/rst/restructuredtext.html',
	head:	{ func: 'block',	start: '==============================', end: '==============================', blank: true },
	strong:	{ func: 'inline',	tag: ' **$0** ' },
	link:	{ func: 'inline',	tag: '[$0$1]',   arg_format: ':$1' },
	anno:	{ func: 'inline',	tag: '(($0))'	},
	list:	{ func: 'block',	tag: '- $0',	blank: true },
	quote:	{ func: 'block',	tag: "\t$0",	blank: true },
	color:	null,
	fsize:	null,

	toc:	{ func: 'insert',	tag: "\n\n.. contents::\n\n" },
	google:	null,
	wiki:	null,
	album:	{ func: 'album' }
});
Helpers.push({
	regexp:	/^(?:simple|html)/i,
	escape:	false,
	head:	{ func: 'block',	tag:  '<h3>$0</h3>',	form_type: 'text' },
	strong:	{ func: 'inline',	tag: '<strong>$0</strong>' },
	link:	{ func: 'inline',	tag: '<a href="$0">$1</a>' },
	anno:	null,
	list:	{ func: 'block',	tag: '-$0'	},
	quote:	{ func: 'block',	start: '<blockquote$1>', end: '</blockquote>' },
	color:	{ func: 'inline',	tag: '<span style="color:$1">$0</span>' },
	fsize:	{ func: 'inline',	tag: '<span class="$1">$0</span>'	},

	toc:	null,
	google:	null,
	wiki:	null,
	album:	{ func: 'album' }
});

//############################################################################
function helper(edit) {
	this.$edit   = $(edit);
	this.edit    = this.$edit[0];
	this.$div    = $secure('#edit-helper');
	this.$other  = $secure('#other-helper');
	this.$parsel = $('#select-parser');

	this.helper  = {};
	this.escape  = false;

	this.init();
};
//----------------------------------------------------------------------------
// ●初期化
//----------------------------------------------------------------------------
helper.prototype.init = function() {
	const self = this;
	self.$div.find("select.helper").change(function(evt){
		var $obj = $(evt.target);
		if ($obj.val() == '') return;
		self.call(evt);
		$obj.val('');
	});
	self.$div.find("button.helper").click(function(evt){
		self.call(evt);
	});
	self.$other.change(function(evt){
		self.call(evt, self.$other.children(':selected'))
		$(evt.target).val('');
	});

	self.$parsel.change(function(){
		self.load();
	});
	self.load();
}
//----------------------------------------------------------------------------
// ●helper情報のロード
//----------------------------------------------------------------------------
helper.prototype.load = function() {
	const parser = this.$parsel.val();
	this.helper  = {};
	for(var key in Helpers) {
		var reg = Helpers[key].regexp;
		if (!parser.match(reg)) continue;

		this.helper = Helpers[key];
		break;
	}
	const $obj = this.$div.find(".helper");
	for(var i=0; i<$obj.length; i++) {
		const $x = $( $obj[i] );
		const type = $x.data('type');
		$x.prop('disabled', this.helper[type] ? false : true)
	}
	
	const $link = $('#parser-help-link');
	const url   = this.helper.url;
	if (url) {
		$link.attr('href', url);
		$link.show();
	} else  $link.hide();

	// その他
	const opt = this.$other.children(':enabled');
	this.$other.prop('disabled', opt.length<2 ? true : false);

	// save vars
	this.escape = this.helper['escape'];
}

//----------------------------------------------------------------------------
// ●機能呼び出し
//----------------------------------------------------------------------------
helper.prototype.call = function(evt, $_obj) {
	const $obj = $_obj || $(evt.target);
	const type = $obj.data('type');
	const help = this.helper[type];
	if (!type || !help) return;

	this[help['func']].call(this, help, $obj);
}

//////////////////////////////////////////////////////////////////////////////
// ■記法ヘルパーの各機能
//////////////////////////////////////////////////////////////////////////////
//----------------------------------------------------------------------------
// ●テキスト挿入
//----------------------------------------------------------------------------
helper.prototype.insert = function(help, $obj) {
	this.insert_text_and_select( help['tag'] );
}

//----------------------------------------------------------------------------
// ●インラインタグ
//----------------------------------------------------------------------------
helper.prototype.inline = function(help, $obj) {
	if ($obj.data('msg1')) return this.ex_inline(help, $obj);
	if (this.selected()) return this._inline(help, $obj);

	const self = this;
	form_dialog({
		title: $obj.data('msg'),
		callback: function (h) {
			if (h.str == '' || h.str.match(/^\s*$/)) return;
			self.insert_text_and_select(h.str);
			self._inline(help, $obj)
		}
	});
}
helper.prototype._inline = function(help, $obj) {
	this.replace({
		tag:	help['tag'],
		arg:	$obj.val()
	});
}

//----------------------------------------------------------------------------
// ●インラインタグ（拡張）
//----------------------------------------------------------------------------
helper.prototype.ex_inline = function(help, $obj) {

	let sel = this.get_selection();
	if (sel && 0 <= sel.indexOf("\n"))	// 複数行は処理しない
		return show_error('#msg-multiline');

	let elements = [];
	let i=0;
	let info = [];
	while($obj.data('msg' + i)) {
		let val = $obj.data('val' + i) || '';
		let reg = $obj.data('match' + i);
		if (reg != '') reg = RegExp(reg);
		if (sel !='' && (reg =='' || reg.test(sel))) {
			val=sel;
			sel='';
		}
		elements.push( $obj.data('msg' + i) );
		elements.push( {type:'text', name:'str' + i, val:val } );

		info.push({
			name: 'str' + i,
			match: reg
		});
		i++;
	}

	const self = this;
	form_dialog({
		title: $obj.data('msg'),
		elements: elements,
		callback: function (h) {
			let ary = [];
			for(let x in info) {
				let z = info[x];
				let v = h[ z.name ];
				if (v.match(/^\s+$/)) v='';
				if (v != '' && z.match && ! z.match.test(v)) v='';
				ary.push(v);
			}

			if (ary[0] == '') return;
			self.replace_selection(ary[0]);
			self._ex_inline(help, $obj, ary[1]);
			return;
		}
	});
}

helper.prototype._ex_inline = function(help, $obj, arg) {
	if (arg && arg != '' && help['arg_format']) {
		let x = help['arg_format'];
		arg   = x.replace(/\$1/g, arg);
	}

	this.replace({
		tag:	help['tag'],
		arg:	arg
	});
}

//----------------------------------------------------------------------------
// ●ブロックタグ
//----------------------------------------------------------------------------
helper.prototype.block = function(help, $obj) {
	if (this.selected()) {
		return this._block(help, $obj);
	}

	const self = this;
	form_dialog({
		title: $obj.data('msg'),
		elements: {
			type: help['form_type'] || 'textarea',
			name:'str'
		},
		callback: function (h) {
			let text = h.str;
			if (text == '' || text.match(/^\s*$/)) return;
			text = text.replace(/^\n*/, "\n").replace(/\n*$/, "\n");
			self.insert_text_and_select(text);
			self._block(help, $obj)
		}
	});
}
helper.prototype._block = function(help, $obj) {
	this.fix_block_selection();	// 選択範囲調整
	if (!help['sp']) return this._block2(help, $obj);

	// block quoteの引用元URL等

	const self   = this;
	const sp_val = $obj.data('sp-val');
	const sp_reg = $obj.data('sp-match');
	form_dialog({
		title: $obj.data('msg'),
		elements: [
			{type:'p', html: $obj.data('sp-msg') },
			{type:'text', name: 'arg', val: sp_val }
		],
		callback: function(h) {
			if (sp_reg != '') {
				const reg = RegExp(sp_reg, 'i');
				if (! reg.test(h.arg)) h.arg='';
			}
			if (h.arg != '' && help['arg_format'] != '') {
				let x = help['arg_format'];
				h.arg = x.replace(/\$1/g, h.arg);
			}
			self._block2(help, $obj, h.arg);
		},
		cancel: function() {
			self._block2(help, $obj, '');
		}
	});
}
helper.prototype._block2 = function(help, $obj, arg) {
	this.replace({
		tag:	help['tag'],
		start:	help['start'],
		end:	help['end'],
		blank:	help['blank'],
		arg:	arg
	});
}

//----------------------------------------------------------------------------
// ■画像アルバムを開く
//----------------------------------------------------------------------------
function open_album(evt) {
	var url = $(evt.target).data('url');
	var win = window.open(url, 'album', 'location=yes, menubar=no, resizable=yes, scrollbars=yes');
	win.focus();
};

//////////////////////////////////////////////////////////////////////////////
// ■結果反映
//////////////////////////////////////////////////////////////////////////////
helper.prototype.replace = function(h) {
	let text = this.get_selection();
	if (!text.length) return;

	let tag   = h['tag']   || '';
	let start = h['start'] || '';
	let end   = h['end']   || '';

	const arg = h['arg'] ? h['arg'] : '';
	tag   = tag  .replace(/\$1/g, arg);
	start = start.replace(/\$1/g, arg) + (start != '' ? "\n" : '');
	end   = (end   != '' ? "\n" : '')  + end.replace(/\$1/g, arg);
	const blank = h['blank'] ? "\n" : '';

	const self = this;
	text = this.each_lines(text, function(str) {
		if (h['escape'])
			str = self.esc_satsuki_tag_nested(str);
		return tag ? tag.replace(/\$0/, str) : str;
	});
	return this.replace_selection(blank + start + text + end + blank);
}

//////////////////////////////////////////////////////////////////////////////
// ■テキストエリア処理ルーチン
//////////////////////////////////////////////////////////////////////////////
//----------------------------------------------------------------------------
// ●カーソル位置へテキスト挿入
//----------------------------------------------------------------------------
helper.prototype.insert_text = function(text) {
	this._insert_text(text, 0);
}
helper.prototype.insert_text_and_select = function(text) {
	this._insert_text(text, true);
}
helper.prototype._insert_text = function(text, sel_flag) {
	this.$edit.focus();

	const edit = this.edit;
	let   pos  = this.edit.selectionStart;
	let before = edit.value.substring(0, pos);
	let  after = edit.value.substring(pos);
	if ((pos == 0 || before.substr(-1) == "\n") && text.substr(0,1) == "\n") text  =  text.substr(1);
	if (             after.substr(0,1) == "\n"  && text.substr(-1)  == "\n") after = after.substr(1);
	edit.value = before + text + after;

	// カーソル移動
	const st = pos + (text.substr(0,1) == "\n" ? 1 : 0);
	const ed = pos +  text.length;
	edit.setSelectionRange(sel_flag ? st : ed, ed);
}

//----------------------------------------------------------------------------
// ●選択範囲があるかないか
//----------------------------------------------------------------------------
helper.prototype.selected = function() {
	const start = this.edit.selectionStart;
	const end   = this.edit.selectionEnd;
	return start != end;
}

//----------------------------------------------------------------------------
// ●選択範囲のテキスト取得
//----------------------------------------------------------------------------
helper.prototype.get_selection = function() {
	const start = this.edit.selectionStart;
	const end   = this.edit.selectionEnd;
	return this.edit.value.substring(start, end);
}

//----------------------------------------------------------------------------
// ●選択範囲のテキストを置き換え
//----------------------------------------------------------------------------
helper.prototype.replace_selection = function(text) {
	const edit  = this.edit;
	const start = edit.selectionStart;
	const end   = edit.selectionEnd;
	edit.value  = edit.value.substring(0, start) + text + edit.value.substr(end);

	// カーソル移動
	const st = start + (text.substr(0,1) == "\n" ? 1 : 0);
	const ed = start +  text.length;
	edit.setSelectionRange(st, ed);
}

//----------------------------------------------------------------------------
// ● 選択範囲やカーソル位置を行ごとに調整する
//----------------------------------------------------------------------------
helper.prototype.fix_block_selection = function() {
	const edit= this.edit;
	let start = edit.selectionStart;
	let end   = edit.selectionEnd;

	if (start == end) {	// 範囲選択なし
		// 行頭なら動かさない
		if (start == 0 || edit.value.substr(start -1,1) == "\n")
			return ;

		// 行の途中なら次の行頭へ
		const x = edit.value.indexOf("\n", start);
		if (x<0) {
			if (edit.value.substr(-1) != "\n") edit.value += "\n";
			start = end = edit.value.length;
		} else
			start = end = x+1;

	} else { 		// 選択範囲あり
		const x = edit.value.lastIndexOf("\n", start);
		const y = edit.value.indexOf    ("\n", end-1);
		start = (x<0) ? 0 : x+1;
		end   = (y<0) ? edit.value.length : y;
	}
	edit.setSelectionRange(start, end);
	this.$edit.focus();
}

//----------------------------------------------------------------------------
// ●行ごとに処理
//----------------------------------------------------------------------------
helper.prototype.each_lines = function(text, func) {
	var ary = text.split(/\r?\n/);
	for(var i=0; i<ary.length; i++) {
		if (ary[i] == '') continue;
		ary[i] = func(ary[i]);
	}
	return ary.join("\n");
}

//----------------------------------------------------------------------------
// ●前後の空行除去
//----------------------------------------------------------------------------
helper.prototype.normalize_block = function(text) {
	return text
		.replace(/^(?:\r?\n)+/, '')
		.replace(/(?:\r?\n)+$/, '')
}

//----------------------------------------------------------------------------
// ●satsuki tagのエスケープ処理
//----------------------------------------------------------------------------
helper.prototype.esc_satsuki_tag_nested = function(str) {
	var buf = [];
	str =str.replace(/[\x01-\x03]/g, '')
		.replace(/\\\[/g, "\x01")
		.replace(/\\\]/g, "\x02");
	var ma;
	while(ma = str.match(/^(.*)(\[[^\[\]]*\])(.*)$/)) {
		str = ma[1] + "\x03" + buf.length + ma[3];
		buf.push(ma[2]);
	}
	str = esc_satsuki_tag(str)
		.replace(/\x03(\d+)/, function(all, num) { return buf[num] })
		.replace(/\x02/g, "\\]")
		.replace(/\x01/g, "\\[");
	return str;
}

//############################################################################
	const h = new helper('#editarea');
//----------------------------------------------------------------------------
// ●paste処理 / init_helper() 後に呼び出すこと
//----------------------------------------------------------------------------
	var txt = $('#paste-txt');
	if (txt.length && $edit.val() == "") {
		insert_image( txt.text(), $('#paste-caption').text(), $('#paste-class').text() );
	}
//############################################################################
});
