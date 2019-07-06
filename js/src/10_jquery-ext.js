//############################################################################
//■jQuery拡張
//############################################################################
$.fn.extend({
//////////////////////////////////////////////////////////////////////////////
//●ディレイ付showとhide
//////////////////////////////////////////////////////////////////////////////
showDelay: function(){
	let args = Array.from(arguments)
	args.unshift(adiary.DefaultShowSpeed);
	return $.fn.show.apply(this, args);
},
hideDelay: function(){
	let args = Array.from(arguments);
	args.unshift(adiary.DefaultShowSpeed);
	return $.fn.hide.apply(this, args);
},
toggleDelay: function(){
	let args = Array.from(arguments);
	args.unshift(adiary.DefaultShowSpeed);
	return $.fn.toggle.apply(this, args);
},
//////////////////////////////////////////////////////////////////////////////
//●自分自身と子要素から探す / 同じセレクタでは１度しか見つからない
//////////////////////////////////////////////////////////////////////////////
findx: function(sel){
	let x = $.fn.filter.apply(this, arguments);
	let y = $.fn.find.apply  (this, arguments);
	x = x.add(y);
	// 重複処理の防止
	const r = [];
	const mark = '-mark-' + sel;
	for(var i=0; i<x.length; i++) {
		var $obj = $(x[i]);
		if ($obj.parents('.js-hook-stop').length || $obj.hasClass('js-hook-stop')) continue;
		if ($obj.data(mark)) continue;
		$obj.data(mark, '1');
		r.push(x[i]);
	}
	return $(r);
},
//////////////////////////////////////////////////////////////////////////////
//●自分を含むrootからfindする
//////////////////////////////////////////////////////////////////////////////
// document/html に未追加のDOM要素でfindするため
// $(sel) element for "this" dom element is not append "document/html"
//
rootfind: function(sel) {
	var html = this.parents().last();
	return html.find(sel);
},
//////////////////////////////////////////////////////////////////////////////
//●指定のdataを持っているか？
//////////////////////////////////////////////////////////////////////////////
myhasData: function(name) {
	const v = this.data(name);
	return v !== undefined;
},
//////////////////////////////////////////////////////////////////////////////
//●スマホでDnDをエミュレーションする
//////////////////////////////////////////////////////////////////////////////
dndEmulation: function(opt){
	var self = this[0];
	if (!self) return;

	opt = opt || {};

	// mouseイベント作成
	function make_mouse_event(name, evt, touch) {
		var e = $.Event(name);
		e.altKey   = evt.altKey;
		e.metaKey  = evt.metaKey;
		e.ctrlKey  = evt.ctrlKey;
		e.shiftKey = evt.shiftKey;
		e.clientX = touch.clientX;
		e.clientY = touch.clientY;
		e.screenX = touch.screenX;
		e.screenY = touch.screenY;
		e.pageX   = touch.pageX;
		e.pageY   = touch.pageY;
		e.which   = 1;
		return e;
	}
	// 自分自身を含めた親要素をすべて取得
	function get_par_elements(dom) {
		var ary  = [];
		while(dom) {
			ary.push( dom );
			if (dom == self) break;
			dom = dom.parentNode;
		}
		return ary;
	}

	// クロージャ変数
	var prev;
	var flag;
	var timer;
	var orig_touch;

	// mousedownエミュレーション
	this.on('touchstart', function(_evt){
		var evt = _evt.originalEvent;
		prev = evt.target;
		orig_touch = evt.touches[0];
		var e = make_mouse_event('mousedown', evt, evt.touches[0]);
		$( prev ).trigger(e);
		
		// ある程度時間が経過しないときは処理を無効化する。
		flag  = false;
		timer = setTimeout(function(){
			timer = false;
			flag  = true;
		}, adiary.TouchDnDTime)
	});

	// mouseupエミュレーション
	this.on('touchend', function(_evt){
		var evt = _evt.originalEvent;
		if (timer) clearTimeout(timer);
		timer = false;
		var e = make_mouse_event('mouseup', evt, evt.changedTouches[0]);
		$( evt.target ).trigger(e);
	});

	// ドラッグエミュレーション
	this.on('touchmove', function(_evt){
		var evt = _evt.originalEvent;

		// 一定時間立たなければ、処理を開始しない
		if (!flag) return;

		var touch = evt.changedTouches[0];
		var dom   = document.elementFromPoint(touch.clientX, touch.clientY);
		var enter = get_par_elements(dom);

		// マウス移動イベント
		var e = make_mouse_event('mousemove', evt, touch);
		$(enter).trigger(e);

		// opt.leave が指定されてないか
		// 要素移動がなければこれで終了
		evt.preventDefault();
		if (!opt.leave || dom == prev) return;

		// 要素移動があれば leave と enter イベント生成
		var leave = get_par_elements(prev);

		// 重複要素を除去
		while(leave.length && enter.length
		   && leave[leave.length -1] == enter[enter.length -1]) {
			leave.pop();
			enter.pop();
		}

		// イベント発火。発火順 >>leave,out,enter,over
		var e_leave = make_mouse_event('mouseleave', evt, touch);
		var e_out   = make_mouse_event('mouseout',   evt, touch);
		var e_enter = make_mouse_event('mouseenter', evt, touch);
		var e_over  = make_mouse_event('mouseover',  evt, touch);
		$(leave).trigger( e_leave );
		$(prev) .trigger( e_out   );
		$(enter).trigger( e_enter );
		$(dom)  .trigger( e_over  );

		// 新しい要素を保存
		prev=dom;
	});
}
//////////////////////////////////////////////////////////////////////////////
});
//////////////////////////////////////////////////////////////////////////////
//●ダブルタップイベント
//////////////////////////////////////////////////////////////////////////////
$.event.special.mydbltap = {
	setup: function(){
		var flag;
		var mouse;
		$(this).on('click', function(evt){
			if (flag) {
				flag = false;
				// タッチイベントが起きてない時は
				// マウスダブルクリックの可能性があるので発火しない
				if (mouse) return;
				return $(evt.target).trigger('mydbltap');
			}
			flag  = true;
			mouse = true;
			setTimeout( function(){ flag = false; }, adiary.DoubleTapTime);
		});
		$(this).on('touchstart', function(){
			mouse = false;
		});
	}
};

//////////////////////////////////////////////////////////////////////////////
//●$() でXSS対策
//////////////////////////////////////////////////////////////////////////////
{
	const init_orig = $.fn.init;
	$.fn.init = function(sel,cont) {
		if (typeof sel === "string" && sel.match(/<.*?[\W]on\w+\s*=/i))
			throw 'Security error by adiary.js : ' + sel;
		return  new init_orig(sel,cont);
	};
}
