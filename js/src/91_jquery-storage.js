//############################################################################
// jQuery.storage
//							(C)2019 nabe@abk
//############################################################################
// Under source is MIT License
//
(function (root, factory) {
	if (typeof define === 'function' && define.amd) {
		define(['jquery'], factory);
	} else if (typeof exports === 'object') {	// CommonJS
		module.exports = factory(require('jquery'));
	} else {
		root.storage   = factory(root.jQuery);	// Browser
	}
}(this, function ($) {
	var ls;
	$.storage_init = function(_ls) {
		ls = _ls;
	}
	$.storage = function(key, val) {
		if (val === undefined) return ls.get(key);
		ls.set(key, val);
	}
	$.removeStorage = function(key) {
		ls.removeItem(key);
	}
}));
