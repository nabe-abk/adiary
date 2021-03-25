//////////////////////////////////////////////////////////////////////////////
// initalize
//////////////////////////////////////////////////////////////////////////////
$$.init_funcs  = [];
$$.init = function(func, priority) {
	if (func)
		return this.init_funcs.push({
			func:	func,
			p:	priority || 100
		});

	// other initlize functions
	const funcs = this.init_funcs;
	funcs.sort(function(a,b) {
		return a.p - b.p;
	});

	for(var i=0; i<funcs.length; i++)
		funcs[i].func.call(this);
};

//////////////////////////////////////////////////////////////////////////////
// load message
//////////////////////////////////////////////////////////////////////////////
$$.msg = function(key, _default) {
	if (!this.msgs) {
		const msgs = this.msgs = this.msgs || {};
		if (this.load_msg) this.load_msg();
	}
	const val = this.msgs[key];
	return (val === undefined) ? (_default || key.toUpperCase()) : val;
}
$$.set_msg = function(obj, msg) {
	const msgs = this.msgs = this.msgs || {};

	if (typeof(obj) != 'object') {
		msgs[obj] = msg;
		return;
	}
	const keys = Object.keys(obj);
	for(let i=0; i<keys.length; i++) {
		msgs[ keys[i] ] = obj[ keys[i] ];
	}
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
