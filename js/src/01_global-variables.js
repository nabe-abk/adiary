/*!
 * adiary.js (C)nabe@abk
 */
'use strict';
var IE11=false;	// IE11
var SP;		// smart phone mode
var Storage;	// Storage object

var adiary = {
	DialogWidth:		640,
	DefaultShowSpeed:	300,	// msec
	TouchDnDTime:		300,	// msec
	DoubleTapTime:		400,	// msec
	PopupDelayTime:		300,	// msec
	PopupOffsetX:		15,
	PopupOffsetY:		10,
	CommentEnableTime:	10000,	// msec
	CommentEnableKeys:	10,
	SyntaxHighlightTheme:	'adiary'
};
/*
 * other variables from _frame.html
 *
 *	adiary.myself
 *	adiary.myself2
 *	adiary.Basepath
  *	adiary.ScriptDir
 *	adiary.PubdistDir
 *	adiary.SpecialQuery
 */



