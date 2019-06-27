//############################################################################
// 編集ヘルパー機能 JavaScript
//							(C)2019 nabe@abk
//############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_image;	// global function for edit.js, album.js
/*
insert_image( data )
  data = {
	caption: "caption text",
	class:   "class text",
	files: [{
		folder: "album folder",
		file:	"file name",
		ext:	"file extension",
		isimg:	true or false,
		exif:	true or false,		// paste exif flag
		thumbnail: true or false	// paste thumbnail
	}, {
		<next file...>
	}, ...
	]
  }
*/
$(function(){
//############################################################################
// ■記法ヘルパー機能
//############################################################################
var Helpers = [];
//----------------------------------------------------------------------------
// Satsuki
//----------------------------------------------------------------------------
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
	cont:	{ func: 'insert',	tag: "\n====\n" },
	code:	{ func: 'block',	start: '>|?|', end: '||<' },
	math:	{ func: 'block',	start: '>>>||math', end: '||<<<' },
	math_i:	{ func: 'inline',	tag: '[[math:$0]]' },
	album:	{ func: 'album' },
	image:	{
		original:	'[image:L:%d:%f:%f%c]',
		thumbnail:	'[image:S:%d:%f:%f%c]',
		file:		'[file:%e:%d:%f:%f]',
		chain:		"\n",
		exif:		true
	},
	figure: {
		html:		false,
		start:		">>|figure$1$2",
		end:		"|<<",
		arg1_format:	" $1",
		arg2_format:	" caption=$1"
	}
});
//----------------------------------------------------------------------------
// Markdown
//----------------------------------------------------------------------------
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
	cont:	{ func: 'insert',	tag: "\n====\n" },
	code:	{ func: 'block',	start: '```', end: '```' },
	math:	{ func: 'block',	start: '```math', end: '```' },
	math_i:	{ func: 'inline',	tag: '[[math:$0]]' },
	album:	{ func: 'album' },
	image:	{
		original:	'[image:L:%d:%f:%f%c]',
		thumbnail:	'[image:S:%d:%f:%f%c]',
		file:		'[file:%e:%d:%f:%f]',
		chain:		"\n",
		exif:		true
	},
	figure: {
		html:		true,
		start:		'<figure markdown="1"$1>',
		end:		'$2</figure>',
		tag:		"\t$0",
		arg1_format:	' class="$1\"',
		arg2_format:	"\t<figcaption>$1</figcaption>\n"
	}
});
//----------------------------------------------------------------------------
// reStructuredText
//----------------------------------------------------------------------------
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
	cont:	null,
	code:	{ func: 'block',	tag: "\t$0", start: ".. code::\n", end: '', blank: true },
	math:	{ func: 'block',	tag: "\t$0", start: ".. math::\n", end: '', blank: true },
	math_i:	{ func: 'inline',	tag: ':math:`$0`' },
	album:	{ func: 'album' },
	image:	{
		original:	'.. image:: files/%d%f',
		thumbnail:	".. image:: files/%d%f\n	:class: thumbnail",
		file:		'`%f <files/%d%f>`__',
		chain:		"\n\n",
		blank:		true,
		exif:		false
	},
	figure:	{
		each:		true,		// each image in each figure
		original:	'.. figure:: files/%d%f',
		thumbnail:	".. figure:: files/%d%f\n	:class: thumbnail",
		start:		'',
		end:		'$1$2',
		arg1_format:	"\n	:align: $1",
		arg2_format:	"\n\n	$1\n",
		class_map:	{
			'center':	'center',
			'float-l':	'left',
			'float-r':	'right'
		},
		exif:		false
	}
});
//----------------------------------------------------------------------------
// HTML
//----------------------------------------------------------------------------
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
	cont:	{ func: 'insert',	tag: "\n====\n" },
	code:	{ func: 'block',	start: '<pre class="syntax-highlight">', end: '</pre>', pre: true },
	math:	{ func: 'block',	start: '<pre class="math">',		 end: '</pre>', pre: true },
	math_i:	{ func: 'inline',	tag:   '<span class="math">$0</span>'	              , pre: true },
	album:	{ func: 'album' },
	image:	{
		//	%a : image attribute
		//	%p : image_dir
		original:	'<a href="%p%d%f"><img alt="%f" src="%p%d%f"></a>',
		thumbnail:	'<a href="%p%d%f"><img alt="%f" src="%p%d.thumbnail/%f"></a>',
		file:		'<a href="%p%d%f">%f</a>',
		chain:		"\n",
		exif:		false
	},
	figure: {
		html:		true,
		start:		'<figure$1>',
		end:		'$2</figure>',
		tag:		"\t$0",
		arg1_format:	' class="$1\"',
		arg2_format:	"\t<figcaption>$1</figcaption>\n"
	}
});

//############################################################################
function helper(edit) {
	this.$edit   = $(edit);
	this.edit    = this.$edit[0];
	this.$div    = $secure('#edit-helper');
	this.$other  = $secure('#other-helper');
	this.$parsel = $('#select-parser');

	// 画像関連
	this.image_dir  = $('#image-dir').text();
	this.image_attr = $('#image-attr').text();
	this.exif_tag   = $('#exif-tag').text();

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
	this.replace(help, $obj.val());
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

	this.replace(help, arg);
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
	this.replace(help, arg);
}

//----------------------------------------------------------------------------
// ■画像アルバムを開く
//----------------------------------------------------------------------------
helper.prototype.album = function(help, $obj) {
	var url = $obj.data('url');
	var win = window.open(url, 'album', 'location=yes, menubar=no, resizable=yes, scrollbars=yes');
	win.focus();
};

//////////////////////////////////////////////////////////////////////////////
// ■結果反映
//////////////////////////////////////////////////////////////////////////////
helper.prototype.replace = function(help, arg1, arg2) {
	let text = this.get_selection();
	if (!text.length) return;

	arg1 = (arg1 == undefined) ? '' : arg1;
	arg2 = (arg2 == undefined) ? '' : arg2;

	let tag   = help['tag']   || '';
	let start = help['start'] || '';
	let end   = help['end']   || '';

	const arg = help['arg'] ? help['arg'] : '';
	tag   = tag  .replace(/\$1/g, arg1).replace(/\$2/g, arg2);
	start = start.replace(/\$1/g, arg1).replace(/\$2/g, arg2) + (start != '' ? "\n" : '');
	end   = (end   != '' ? "\n" : '')  + end.replace(/\$1/g, arg1).replace(/\$2/g, arg2);
	const blank = help['blank'] ? "\n" : '';

	const self = this;
	text = this.each_lines(text, function(str) {
		if (help['escape'])
			str = self.esc_satsuki_tag_nested(str);
		if (help['pre'])
			str = tag_esc(str);
		return tag ? tag.replace(/\$0/, str) : str;
	});

	return this.replace_selection(blank + start + text + end + blank);
}

//////////////////////////////////////////////////////////////////////////////
// ■テキストエリア処理
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
// ●カーソル位置へブランク行挿入
//----------------------------------------------------------------------------
helper.prototype.insert_blank = function(text) {
	const edit = this.edit;
	const st   = edit.selectionStart;
	const ed   = edit.selectionEnd;
	let   blank = '';
	if (st == 0) return;
	blank += (        edit.value.substring(st-1, 1) != "\n")   ? "\n" : '';
	blank += (st>2 && edit.value.substring(st-2, 2) != "\n\n") ? "\n" : '';

	edit.value = edit.value.substring(0, st) + blank + edit.value.substring(st);
	edit.setSelectionRange(st + blank.length, ed + blank.length);
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

//////////////////////////////////////////////////////////////////////////////
// ■画像挿入
//////////////////////////////////////////////////////////////////////////////
helper.prototype.insert_image = function(data) {
	const help  = this.helper;
	const image = this.helper.image;
	const chain = image.chain;
	if (!image) return;

	let fig;
	let original_tag  = image['original'];
	let thumbnail_tag = image['thumbnail'];
	let htclass = data.class;
	let caption = data.caption.replace(/^\s+/,'').replace(/\s+$/,'');
	if (htclass!='' || caption!='') {
		fig = this.helper.figure;
		if (fig && fig.each) {	// each image in each figure
			original_tag  = fig.original  ? fig.original  : original_tag;
			thumbnail_tag = fig.thumbnail ? fig.thumbnail : thumbnail_tag;
		}
		if (fig.class_map) htclass = fig.class_map[ htclass ];
	}
	let arg1='';
	let arg2='';
	if (htclass != '')
		arg1 = fig['arg1_format'].replace(/\$1/g, fig.html ? tag_esc(htclass) : htclass);
	if (caption != '')
		arg2 = fig['arg2_format'].replace(/\$1/g, caption);

	let text='';
	for(let i in data.files) {
		let file = data.files[i];
		let tag  = file.isimg ? (file.thumbnail ? thumbnail_tag : original_tag) : image['file'];
		let exif = (image.exif && file.exif) ? this.exif_tag : '';
		// console.log(file);

		if (help['escape']) {
			file.folder = esc_satsuki_tag( file.folder );
			file.file   = esc_satsuki_tag( file.file   );
			file.ext    = esc_satsuki_tag( file.ext    );
		}

		let rep = {
			d: file.folder == '/' ? '' : file.folder,
			f: file.file,
			e: file.ext,
			c: '',
			p: this.image_dir,
			a: this.image_attr
		};

		if (exif)
			rep.c = exif.replace(/%([a-z])/g, function($0,$1){ return rep[$1] });

		let start='';
		let end  ='';
		if (file.isimg && fig && fig.each) {	// figure for each image file
			start = fig['start'].replace(/\$1/g, arg1).replace(/\$2/g, arg2);
			end   = fig['end']  .replace(/\$1/g, arg1).replace(/\$2/g, arg2);
		}

		text += (text != '' ? chain : '') + start + tag.replace(/%([\w])/g, function($0,$1){ return rep[$1] }) + end;
	}
	if (!fig || fig.each) {
		if (image['blank']) this.insert_blank();
		this.insert_text(text);
		if (image['blank']) this.insert_blank();
		return;
	}

	// figure block
	this.insert_text_and_select("\n" + text + "\n");
	this.fix_block_selection();
	this.replace(fig, arg1, arg2);
}

//############################################################################
	const help = new helper('#editarea');
	insert_image = function(data) {
		return help.insert_image(data);
	}
//----------------------------------------------------------------------------
// ●paste処理
//----------------------------------------------------------------------------
	const txt = $('#paste-txt');
	if (txt.length && $('#editarea').val() == "") {
		let data;
		try {
			data = JSON.parse(txt.text());
		} catch(e) {
			console.error(e);
		}
		if(data) insert_image( data );
	}
//############################################################################
});
