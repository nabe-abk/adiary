//////////////////////////////////////////////////////////////////////////////
//●初期化処理
//////////////////////////////////////////////////////////////////////////////
$(function(){
	// init
	if (Vmyself) Storage = new PrefixStorage( Vmyself );
	set_browser_class_into_body();

	// DB time, Total time
	$('#system-info-db-time')   .text( DBTime );
	$('#system-info-total-time').text( TotalTime );

	// Google Analytics
	if (GA_ID) {
		ga=function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
		ga('create', GA_ID, 'auto');
		ga('send', 'pageview');
		load_script('https://www.google-analytics.com/analytics.js');
	}

	// css-defer
	$('link.css-defer').attr('rel', 'stylesheet');

	// load script
	$('script-load').each(function(idx, dom) {
		load_script(dom.getAttribute('src'));
	});

	// script-defer
	$('script-defer').each(function(idx, dom) {
		function get_script_line_number(d) {
			var line = 2;	// before <head> lines
			domloop: while(1) {
				while(!d.previousSibling) {
					if (!d.parentElement) break domloop;
					d = d.parentElement;
				}
				d = d.previousSibling;
				line += (d.outerHTML || d.nodeValue || "").split("\n").length -1;
			}
			return line;
		}

		try {
			if (IE11) return eval( dom.innerHTML.replace(/^\s*<!--([\s\S]*)-->\s*$/, "$1") );
			eval( dom.innerHTML );
		} catch(e) {
			// analyze error info
			var line = 0;
			var col  = 0;
			var text = e.stack.replace(/^[\s\S]*?([^\n]*:\d+:\d+)/, "$1");
			var ma   = text.match(/^[^\n]*eval[^\n]*:(\d+):(\d+)\s*/);
			if (ma) {
				line = parseInt(ma[1]);
				col  = parseInt(ma[2]);
			} else {
				throw(e);
			}
			line += get_script_line_number(dom);

			var path = location.href.replace(/#.*/,"");
			if (e.lineNumber)
				 throw new Error(e.message, path, line);
			console.error("<script-defer> error!!\n", e.message + ' at ' + path + ':' + line + ':' + col);
		}
	});
});

//////////////////////////////////////////////////////////////////////////////
//●RSSからのリンクhashを消す
//////////////////////////////////////////////////////////////////////////////
{
	if (window.location.hash.indexOf('#rss-tm') == 0) {
		history.pushState("", document.title, location.pathname + location.search);
	}
}

//////////////////////////////////////////////////////////////////////////////
//●for IE
//////////////////////////////////////////////////////////////////////////////
// for IE11
if (!String.repeat) String.prototype.repeat = function(num){
	var str='';
	var x = this.toString();
	for(var i=0; i<num; i++) str += x;
	return str;
}

//////////////////////////////////////////////////////////////////////////////
//●<body>にCSSのためのブラウザクラスを設定
//////////////////////////////////////////////////////////////////////////////
function set_browser_class_into_body() {
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
	var body = $('#body');
	if (body.hasClass('sp')) {
		SP = 1;
		DialogWidth = 320;
	}

	// bodyにクラス設定する
	body.addClass( x.join(' ') );
}

//////////////////////////////////////////////////////////////////////////////
//●特殊Queryの処理
//////////////////////////////////////////////////////////////////////////////
$(function(){
  if (SpecialQuery) {
	$('#body').find('a').each( function(idx,dom){
		var obj = $(dom);
		var url = obj.attr('href');
		if (! url) return;
		if (url.indexOf(Vmyself)!=0) return;
		if (url.match(/\?[\w\/]+$/)) return;	// 管理画面では解除する
		if (url.match(/\?(.+&)?_\w+=/)) return;	// すでに特殊Queryがある

		var ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + SpecialQuery + (ma[3] ? ma[3] : '');
		obj.attr('href', url);
	});
  }
});
