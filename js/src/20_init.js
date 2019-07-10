//////////////////////////////////////////////////////////////////////////////
//●初期化処理
//////////////////////////////////////////////////////////////////////////////
adiary.init_funcs  = [];
adiary.init = function(func) {
	if (func)
		return this.init_funcs.push(func);

	this.$head = $('head');
	this.$body = $('#body');

	// load adiary vars
	let $obj = $secure('#adiary-vars');
	let data;
	if ($obj && $obj.myhasData('secure')) {
		const json = $obj.html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
		      data = JSON.parse(json);
		const ary  = ['myself', 'myself2', 'Basepath', 'ScriptDir', 'PubdistDir', 'SpecialQuery'];
		for(var i in ary) {
			this[ary[i]] = data[ary[i]];
		}
      	}

	// remove #rss-tm hash
	if (window.location.hash.indexOf('#rss-tm') == 0) {
		history.pushState("", document.title, location.pathname + location.search);
	}

	// PrefixStorage
	if (this.Basepath)
		window.Storage = new PrefixStorage( this.myself );

	// DB time, Total time
	if (data.DBTime)    $('#system-info-db-time')   .text( data.DBTime    );
	if (data.TotalTime) $('#system-info-total-time').text( data.TotalTime );

	// Google Analytics
	if (data.GA_ID) {
		ga=function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
		ga('create', data.GA_ID, 'auto');
		ga('send', 'pageview');
		this.load_script('https://www.google-analytics.com/analytics.js');
	}

	// other initlize functions
	const funcs = this.init_funcs;
	for(var i=0; i<funcs.length; i++)
		funcs[i].call(this);
};
//////////////////////////////////////////////////////////////////////////////
// run init
//////////////////////////////////////////////////////////////////////////////
$(function(){
	adiary.init();

	// Emulate jquery.cookie for dynatree
	// "jquery-storage" in "PrefixStorage.js"
	$.storage_init( Storage );
	$.cookie = $.storage;
	$.removeCookie = $.removeStorage;
});

//////////////////////////////////////////////////////////////////////////////
//●<body>にCSSのためのブラウザクラスを設定
//////////////////////////////////////////////////////////////////////////////
adiary.init(function() {
	var x = [];
	var ua = navigator.userAgent;

	     if (ua.indexOf('Edge/')   != -1) x.push('Edge');
	else if (ua.indexOf('WebKit/') != -1) x.push('GC');
	else if (ua.indexOf('Gecko/')  != -1) x.push('Fx');

	var m = ua.match(/MSIE (\d+)/);
	var n = ua.match(/Trident\/\d+.*rv:(\d+)/);
	if (n) { x = []; m = n; }		// IE11
	if (m) {
		x.push('IE', 'IE' + m[1]);
		IE11 = true;
	}

	// adiaryのスマホモード検出
	if (this.$body.hasClass('sp')) {
		SP = 1;
		this.DialogWidth = 320;
	}

	// bodyにクラス設定する
	this.$body.addClass( x.join(' ') );
});

//////////////////////////////////////////////////////////////////////////////
// defer tags
//////////////////////////////////////////////////////////////////////////////
adiary.script_defer_doms=[];
adiary.init(function(){
	const self=this;

	// css-defer
	$('link.css-defer').attr('rel', 'stylesheet');

	// load script		ex) twitter-widget of filter syntax
	$('script-load').each(function(idx, dom) {
		self.load_script(dom.getAttribute('src'));
	});

	// script-defer
	const $scripts = $('script-defer');
	$scripts.each(function(idx, dom) {
		const num = self.script_defer_doms.length;
		self.script_defer_doms.push(dom);

		let script = dom.innerHTML.replace(/^\s*<!--([\s\S]*?)-->\s*$/, "$1");
		eval(
			'try{' + script + "\n}catch(e){ adiary.script_defer_error(e,"+ num + ") }"
		);
	});
	if (!$scripts.length) return;

	// script-defer error trap
	const dom = $scripts[0];
	$(window).on('error', function(evt) {
		const err  = evt.originalEvent;
		const file = err.filename;
		if (file != "" && !file.match(/eval/)) return;

		//evt.preventDefault();
		self.script_defer_error_throw(err.error, err.lineno, err.colno, dom);
	});
	
});
adiary.script_defer_error = function(err, idx) {
	var line = 0;
	var col  = 0;
	var text = err.stack.replace(/^[\s\S]*?([^\n]*:\d+:\d+)/, "$1");
	var ma   = err.stack.match(/^[\s\S]*?:(\d+):(\d+)[^:]*\n/);
	if (ma) {
		line = parseInt(ma[1]);
		col  = parseInt(ma[2]);
	} else {
		throw(err);
	}
	this.script_defer_error_throw(err, line, col, this.script_defer_doms[idx]);
}
adiary.script_defer_error_throw = function(err, line, col, dom) {
	line += 2;	// before <head> lines
	domloop: while(1) {
		while(!dom.previousSibling) {
			if (!dom.parentElement) break domloop;
			dom = dom.parentElement;
		}
		dom = dom.previousSibling;
		line += (dom.outerHTML || dom.nodeValue || "").split("\n").length -1;
	}

	var path = location.href.replace(/#.*/,"");
	if (err.lineNumber)
		 throw new Error(err.message, path, line);
	console.error("<script-defer> error!!\n", err.message + ' at ' + path + ':' + line + ':' + col);
}

//////////////////////////////////////////////////////////////////////////////
//●特殊Queryの処理
//////////////////////////////////////////////////////////////////////////////
adiary.init(function(){
 	if (!this.SpecialQuery) return;
 	const myself   = this.myself;
 	const sp_query = this.SpecialQuery;
 
 	$('a').each( function(idx,dom) {
		var obj = $(dom);
		var url = obj.attr('href');
		if (! url) return;
		if (url.indexOf(myself)!=0) return;
		if (url.match(/\?[\w\/]+$/)) return;		// 管理画面では解除する
		if (url.match(/\?(.+&)?_\w+=/)) return;		// すでに特殊Queryがある

		var ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + sp_query + (ma[3] ? ma[3] : '');
		obj.attr('href', url);
	});
});
