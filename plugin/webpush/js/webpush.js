///////////////////////////////////////////////////////////////////////////////
// webpush 登録処理
//							(C)2017 nabe@abk
///////////////////////////////////////////////////////////////////////////////
//[TAB=8]  require jQuery
//
'use strict';
var Vmyself;
var debug = false;
var btnForce = true;

$(function() {
///////////////////////////////////////////////////////////////////////////////
var $span = $('#webpush-data');
var $btn  = $('button.regist-webpush');
var script = Vmyself + '?sworker';
var timer;
var log = debug ? console.log : function(){ return; };

///////////////////////////////////////////////////////////////////////////////
// Send process
///////////////////////////////////////////////////////////////////////////////
// 通知処理による遅延防止のため、クライアントに送信処理を呼び出してもらう
if ($span.data('send')) {
	log('call send process');
	$.post( Vmyself, { action: 'webpush/send' });
}

///////////////////////////////////////////////////////////////////////////////
// ServiceWorker check
///////////////////////////////////////////////////////////////////////////////
if (!navigator.serviceWorker) {
	$btn.prop('disabled', true);
	$btn.attr('title', 'Your browser is not supported');
	return;
}
// システム画面など
if (! $span.data('spub')) return $btn.prop('disabled', true);

///////////////////////////////////////////////////////////////////////////////
// Automatic regist
///////////////////////////////////////////////////////////////////////////////
function init() {
	var str  = (String)($span.data('wait') || '5');
	var wait = parseInt( str.replace(/[^\d]/, '') );
	if (wait && !$("#body").hasClass('system'))
		timer = setTimeout(regist_sworker, wait*1000);
	$btn.click( regist_sworker );
}
init();

///////////////////////////////////////////////////////////////////////////////
// Regist ServiceWorker
///////////////////////////////////////////////////////////////////////////////
function regist_sworker(evt) {
	var force = btnForce && evt && evt.target && true;

	if (timer) {
		clearTimeout(timer);
		timer = null;
	}
	if (!navigator.serviceWorker) return;

	Notification.requestPermission( function(permission) {
		log('requestPermission', permission);
		if (permission !== 'granted') return;

		log('serviceWorker.register()');
		navigator.serviceWorker.register(script).then( function(reg) {
			push_subscribe(reg, force);
		}).catch(function(error) {
			log(error);
		});
	});
}

///////////////////////////////////////////////////////////////////////////////
// Unregist ServiceWorker
///////////////////////////////////////////////////////////////////////////////
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

///////////////////////////////////////////////////////////////////////////////
// Update ServiceWorker
///////////////////////////////////////////////////////////////////////////////
function update_registration() {
	log('update_registration()');
	navigator.serviceWorker.getRegistration(script).then(function(registration){
		if (!registration)
			return log('Do not registration!');
		registration.update();
	});
}

///////////////////////////////////////////////////////////////////////////////
// pushManager subscribe
///////////////////////////////////////////////////////////////////////////////
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
			} else {
				if (force) postSubscription(subscription);
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

///////////////////////////////////////////////////////////////////////////////
// post to webapplication
///////////////////////////////////////////////////////////////////////////////
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

	fetch(Vmyself, {
		credentials: 'include',		// cookie
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: $.param(form)

	}).then(function(res) {
		if (res.ok) return res.text();
		throw('HTTP Error : Status ' + res.status);

	}).then(function(text) {
		if (!text.match(/^0(?:\n|$)/)) throw('Subscribe error : ' + text);

	}).catch(function(err) {
		console.error('fetch()', err);
		unregist_sworker();
	});
}

///////////////////////////////////////////////////////////////////////////////
// subroutine
///////////////////////////////////////////////////////////////////////////////
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

//////////////////////////////////////////////////////////////////////////////
});
