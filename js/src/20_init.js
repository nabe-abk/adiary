//////////////////////////////////////////////////////////////////////////////
//●初期化処理
//////////////////////////////////////////////////////////////////////////////
$$.init_funcs  = [];
$$.init = function(func) {
	if (func)
		return this.init_funcs.push(func);

	this.$head = $('head');
	this.$body = $('#body');

	// load adiary vars
	let $obj = $secure('#' + this.name + '-vars');
	let data;
	if ($obj && $obj.existsData('secure')) {
		const json = $obj.html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
		      data = JSON.parse(json);
		const ary  = ['myself', 'myself2', 'Basepath', 'ScriptDir', 'PubdistDir', 'SpecialQuery', 'Static'];
		for(var i in ary) {
			this[ary[i]] = data[ary[i]];
		}
      	}

	// remove #rss-tm hash
	if (window.location.hash.indexOf('#rss-tm') == 0) {
		history.pushState("", document.title, location.pathname + location.search);
	}

	// Smartphone mode
	if (this.$body.hasClass('sp')) {
		SP = 1;
		this.DialogWidth = 320;
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
// load message
//////////////////////////////////////////////////////////////////////////////
$$.msg = function(key) {
	if (!this.msgs) this.load_msg();
	const val = this.msgs[key];
	return (val === undefined) ? key.toUpperCase() : val;
}
$$.load_msg = function(key) {
	const msgs = {};

	$('[data-secure].' + this.name + '-msgs').each(function(idx,dom) {
		try {
			const json = $(dom).html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			for(var i in data)
				msgs[i] = data[i];
		} catch(e) {
			console.error(e);
		}
	});
	this.msgs = msgs;
}

//////////////////////////////////////////////////////////////////////////////
// <script-defer> tag
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const self=this;

	// css-defer
	$('link.css-defer').attr('rel', 'stylesheet');

	// load script		ex) twitter-widget of filter syntax
	$('script-load').each(function(idx, dom) {
		self.load_script(dom.getAttribute('src'));
	});

	// script-defer
	const $scripts = $('script-defer');
	const line = [];
	$scripts.each(function(idx, dom) {
		line[idx] = self.get_line_number(dom);
	});
	$scripts.each(function(idx, dom) {
		const scr     = document.createElement('script');
		scr.innerHTML = "\n".repeat(line[idx]) + dom.innerHTML;
		dom.innerHTML = '';
		dom.appendChild(scr);
	});
});

$$.get_line_number = function(dom) {
	let line = 2;	// before <head> lines
	domloop: while(1) {
		while(!dom.previousSibling) {
			if (!dom.parentElement) break domloop;
			dom = dom.parentElement;
		}
		dom = dom.previousSibling;
		line += (dom.outerHTML || dom.nodeValue || "").split("\n").length -1;
	}
	return line;
}

//////////////////////////////////////////////////////////////////////////////
//●特殊Queryの処理
//////////////////////////////////////////////////////////////////////////////
$$.init(function(){
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
