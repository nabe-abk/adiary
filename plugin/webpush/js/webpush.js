////////////////////////////////////////////////////////////////////////////////
// webpush 登録処理
//							(C)2017 nabe@abk
////////////////////////////////////////////////////////////////////////////////
//[TAB=8]  require jQuery
//
'use strict';

$(function() {
////////////////////////////////////////////////////////////////////////////////
// Global setting
////////////////////////////////////////////////////////////////////////////////
var debug = false;
var btnForce = true;
var rePostDays = 30;
var Storage = adiary.Storage;

////////////////////////////////////////////////////////////////////////////////
var $span = $('#webpush-data');
var $btn  = $('button.regist-webpush');
var script  = adiary.myself + '?sworker';
var timer;
var log = debug ? console.log : function(){ return; };
var tm  = Math.floor((new Date()).getTime() / 1000);	// msec to sec

////////////////////////////////////////////////////////////////////////////////
// Send process
////////////////////////////////////////////////////////////////////////////////
// 通知処理による遅延防止のため、クライアントに送信処理を呼び出してもらう
if ($span.data('send')) {
	log('call send process');
	$.post( adiary.myself, { action: 'webpush/send' });
}

////////////////////////////////////////////////////////////////////////////////
// ServiceWorker check
////////////////////////////////////////////////////////////////////////////////
if (!navigator.serviceWorker) {
	$btn.prop('disabled', true);
	$btn.attr('title', 'Your browser is not supported');
	return;
}
// システム画面など
if (! $span.data('spub')) return $btn.prop('disabled', true);

////////////////////////////////////////////////////////////////////////////////
// Automatic regist
////////////////////////////////////////////////////////////////////////////////
function init() {
	var str  = (String)($span.data('wait') || '5');
	var wait = parseInt( str.replace(/[^\d]/, '') );
	if (wait && !$("#body").hasClass('system'))
		timer = setTimeout(regist_confirm, wait*1000);
	$btn.click( regist_sworker );
}
init();

function clear_timer() {
	if (timer) clearTimeout(timer);
	timer = null;
}
////////////////////////////////////////////////////////////////////////////////
// ServiceWorker Ready? (installed?)
////////////////////////////////////////////////////////////////////////////////
navigator.serviceWorker.ready.then(function(registration){
	regist_sworker();
});

////////////////////////////////////////////////////////////////////////////////
// Regist ServiceWorker
////////////////////////////////////////////////////////////////////////////////
function regist_confirm() {
	var msg = $span.html();
	if (!msg) return regist_sworker();

	// 通知を2重に出さない。
	var cancel_tm = (Storage.get('webpush-stop') || 0)*1;
	var days = ($span.data('days') || 0)*1;
	if (!days && cancel_tm || days && (cancel_tm + days*86400)>tm) return;

	// 登録前メッセージの表示
	var $div = $('<div>').addClass('foot-message-transion');
	msg = msg.replace(/\n/g, "<br>");
	var $buttons = $('<div>');
	var $yes = $('<span>').text( adiary.msg('ok')     ).data('flag', 1);
	var $no  = $('<span>').text( adiary.msg('cancel') ).data('flag', 0);
	$buttons.append($yes, $no);

	var click = function(evt) {
		var $obj = $(evt.target);
		var flag =  $obj.data('flag');
		$div.remove();
		if (flag != 0) return regist_sworker();
		Storage.set('webpush-stop', tm);
	};
	$yes.click( click );
	$no .click( click );

	// 表示
	$div.html( msg );
	$div.append( $buttons );
	$('#body').append( $div );

	setTimeout(function(){	// for transition
		$div.addClass('foot-message');
		$buttons.addClass('fm-buttons');
	}, 10);
}

////////////////////////////////////////////////////////////////////////////////
// Regist ServiceWorker
////////////////////////////////////////////////////////////////////////////////
var regist_sworker_flag;
function regist_sworker(evt) {
	clear_timer();
	$btn.prop('disabled', true);

	if (regist_sworker_flag) return;
	regist_sworker_flag = 1;
	Storage.remove('webpush-stop');

	var force = btnForce && evt && evt.target && true;

	Notification.requestPermission( function(permission) {
		log('requestPermission', permission);
		if (permission !== 'granted') return unregist_sworker();

		log('serviceWorker.register()');
		navigator.serviceWorker.register(script).then( function(registration) {
			push_subscribe(registration, force);
		}).catch(function(error) {
			log(error);
		});
	});
}

////////////////////////////////////////////////////////////////////////////////
// Unregist ServiceWorker
////////////////////////////////////////////////////////////////////////////////
function unregist_sworker() {
	log('unregist_sworker()');

	navigator.serviceWorker.getRegistration(script).then(function(registration){
		if (!registration)
			return log('not regist ServiceWorker');
		registration.unregister().then(function(flag) {
			if (!flag) log('unregister() failed!');
		});
	});
}

////////////////////////////////////////////////////////////////////////////////
// Update ServiceWorker
////////////////////////////////////////////////////////////////////////////////
function update_registration() {
	log('update_registration()');
	navigator.serviceWorker.getRegistration(script).then(function(registration){
		if (!registration)
			return log('Do not registration!');
		registration.update();
	});
}

////////////////////////////////////////////////////////////////////////////////
// pushManager subscribe
////////////////////////////////////////////////////////////////////////////////
function push_subscribe(registration, force) {
	if (debug) update_registration();

	registration.pushManager.getSubscription().then(function(subscription){
		log('getSubscription()');

		if (subscription) {	// Registered
			var skey = base64( arybuf2str(subscription.options.applicationServerKey || []) );
			if (skey != $span.data('spub')) {
				log('ServerKey changed!');
				subscription.unsubscribe();
				log('unsubscribe()');
				postSubscription(subscription);
			} else {
				var elapsed = tm - (Storage.get('webpush-regist') || 0);	// 登録時からの経過時間
				log("elapsed time (regist)", elapsed);
				if (force || elapsed>rePostDays*86400) postSubscription(subscription);
			}
			return;
		}

		var str  = base64decode($span.data('spub'));
		var spub = new Uint8Array(Uint8Array.from(str.split(""), function(e){ return e.charCodeAt(0) }));

		registration.pushManager.subscribe({
			userVisibleOnly: true,
			applicationServerKey: spub
		}).then(postSubscription, function(err){
			console.error('registration.pushManager.subscribe()', err);
			unregist_sworker();
		});
	});
}

////////////////////////////////////////////////////////////////////////////////
// post to webapplication
////////////////////////////////////////////////////////////////////////////////
function postSubscription(subscription) {
	var key  = arybuf2bin( subscription.getKey('p256dh') );
	var auth = arybuf2bin( subscription.getKey('auth')   );

	log('endpoint',   subscription.endpoint);
	log('client key', base64(key)  );
	log('serverKey ', base64( arybuf2str(subscription.options.applicationServerKey || []) ) );
	log('auth      ', base64(auth) );

	var form = {
		action: 'webpush/regist',
		endp_txt: subscription.endpoint,
		key_txt:  base64(key),
		auth_txt: base64(auth)
	};

	fetch(adiary.myself, {
		credentials: 'include',		// cookie
		method: 'POST',
		body: $.param(form)

	}).then(function(res) {
		if (res.ok) return res.text();
		throw('HTTP Error : Status ' + res.status);

	}).then(function(text) {
		if (!text.match(/^0(?:\n|$)/)) throw('Subscribe error : ' + text);

		log('fetch() success');
		Storage.set('webpush-regist', tm);

	}).catch(function(err) {
		console.error('fetch()', err);
		unregist_sworker();
	});
}

////////////////////////////////////////////////////////////////////////////////
// subroutine
////////////////////////////////////////////////////////////////////////////////
function arybuf2str(arybuf) {
	return String.fromCharCode.apply(null, new Uint8Array(arybuf));
}
function arybuf2bin(arybuf) {
	return String.fromCharCode.apply(null, new Uint8Array(arybuf));
}
function base64(bin) {
	var str = btoa(bin).replace(/=+$/, '');
	return str.replace(/\+/g,'-').replace(/\//g,'_');
}
function base64decode(str) {
	return atob( str.replace(/-/g,'+').replace(/_/g,'/') );
}

////////////////////////////////////////////////////////////////////////////////
});
