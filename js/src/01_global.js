/*!
 * adiary.js (C)nabe@abk
 */
'use strict';
var IE11=false;	// IE11
var SP;		// smart phone mode
var Storage;	// Storage object

var $$ = {
	name:			'adiary',	// export global name
	DialogWidth:		640,
	DefaultShowSpeed:	300,	// msec
	TouchDnDTime:		100,	// msec
	DoubleTapTime:		400,	// msec
	PopupDelayTime:		300,	// msec
	PopupOffsetX:		15,
	PopupOffsetY:		10,
	CommentEnableTime:	10000,	// msec
	CommentEnableKeys:	10,
	SyntaxHighlightTheme:	'adiary'
};
window[$$.name] = $$;

/*
 * other variables from _frame.html
 *
 *	$$.myself
 *	$$.myself2
 *	$$.Basepath
 *	$$.ScriptDir
 *	$$.PubdistDir
 *	$$.SpecialQuery
 */

//////////////////////////////////////////////////////////////////////////////
// セキュアなオブジェクト取得
//////////////////////////////////////////////////////////////////////////////
window.$secure = function(id) {
	var obj = $(document).find('[id="' + id.substr(1) + '"]');
	if (obj.length >1) {
		adiary.show_error('Security Error!<p>id="' + id + '" is duplicate.</p>');
		return $([]);		// 2つ以上発見された
	}
	return obj;
}

//////////////////////////////////////////////////////////////////////////////
// for compatibility
//////////////////////////////////////////////////////////////////////////////
window.load_SyntaxHighlight = function() {};


//////////////////////////////////////////////////////////////////////////////
//●for IE11
//////////////////////////////////////////////////////////////////////////////
if (!String.repeat) String.prototype.repeat = function(num) {
	var str='';
	var x = this.toString();
	for(var i=0; i<num; i++) str += x;
	return str;
}

if (!Array.from) Array.from = function(arg) {
	return Array.prototype.slice.call(arg);
}
