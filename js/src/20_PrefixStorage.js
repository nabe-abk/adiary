//############################################################################
// Prefix付DOM Storageライブラリ
//							(C)2019 nabe@abk
//############################################################################
// PrefixStorage's source is MIT License
//
// ・pathを適切に設定することで、同一ドメイン内で住み分けることができる。
// ・ただし紳士協定に過ぎないので過剰な期待は禁物
//
//（利用可能メソッド） set(), get(), remove(), clear()
//
window.PrefixStorage = function(path) {
	// ローカルストレージのロード
	this.ls = this.load_storage();

	// プレフィックス
	this.prefix = String(path) + '::';
}
//-------------------------------------------------------------------
// init
//-------------------------------------------------------------------
PrefixStorage.prototype.load_storage = function() {
	var ls;
	// LocalStorage
	try{
		ls = localStorage;
		ls.removeItem('$$$');	// test
	} catch(e) {
		ls = null;
	}
	if (!ls) return new StorageDummy();
	return ls;
}

//-------------------------------------------------------------------
// Storage Dummy Class
//-------------------------------------------------------------------
window.StorageDummy = function() {
	// メンバ関数
	StorageDummy.prototype.setItem = function(key, val) { this[key] = val; };
	StorageDummy.prototype.getItem = function(key) { return this[key]; };
	StorageDummy.prototype.removeItem = function(key) { delete this[key]; };
	StorageDummy.prototype.clear = function() {
		for(var k in this) {
			if(typeof(this[k]) == 'function') continue;
			delete this[k];
		}
	}
}

//-------------------------------------------------------------------
// メンバ関数
//-------------------------------------------------------------------
PrefixStorage.prototype.set = function (key,val) {
	this.ls[this.prefix + key] = val;
};
PrefixStorage.prototype.get = function (key) {
	return this.ls[this.prefix + key];
};
PrefixStorage.prototype.getInt = function (key) {
	var v = this.ls[this.prefix + key];
	if (v==undefined) return 0;
	return Number(v);
};
PrefixStorage.prototype.defined = function (key) {
	return (this.ls[this.prefix + key] !== undefined);
};
PrefixStorage.prototype.remove = function(key) {
	this.ls.removeItem(this.prefix + key);
};
PrefixStorage.prototype.allclear = function() {
	this.ls.clear();
};
PrefixStorage.prototype.clear = function(key) {
	var ls = this.ls;
	var pf = this.prefix;
	var len = pf.length;

	if (ls.length != undefined) {
		var ary = new Array();
		for(var i=0; i<ls.length; i++) {
			var k = ls.key(i);
			if (k.substr(0,len) === pf) ary.push(k);
		}
		// forでkey取り出し中には削除しない
		//（理由はDOM Storage仕様書参照のこと）
		for(var i in ary) {
			delete ls[ ary[i] ];
		}
	} else {
		// DOMStorageDummy
		for(var k in ls) {
			if (k.substr(0,len) === pf)
				delete ls[k];
		}
	}
};

//############################################################################
// jQuery.storage
//							(C)2019 nabe@abk
//############################################################################
(function (root, factory) {
	if (typeof define === 'function' && define.amd) {
		define(['jquery'], factory);
	} else if (typeof exports === 'object') {	// CommonJS
		module.exports = factory(require('jquery'));
	} else {
		root.storage   = factory(root.jQuery);	// Browser
	}
}(this, function($) {
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
