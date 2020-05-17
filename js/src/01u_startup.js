/*!
 * adiary.js (C)nabe@abk
 */
'use strict';
let SP;		// smart phone mode
let Storage;	// Storage object

let $$ = {
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

//////////////////////////////////////////////////////////////////////////////
// compatibility for old article
//////////////////////////////////////////////////////////////////////////////
window.load_SyntaxHighlight = function() {};

//////////////////////////////////////////////////////////////////////////////
// initalize
//////////////////////////////////////////////////////////////////////////////
$$.user_init = function(func) {
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
		Storage = new PrefixStorage( this.myself );

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
};

//////////////////////////////////////////////////////////////////////////////
// load message
//////////////////////////////////////////////////////////////////////////////
$$.load_msg = function() {
	const msgs = this.msgs;

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
}
