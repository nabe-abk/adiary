//##############################################################################
// WebPush ServiceWorker Script
//							(C)2017 nabe@abk
//##############################################################################
//[TAB=8]
//
'use strict';

self.addEventListener('push', function(evt) {
	if (!evt.data) return;
	var data = evt.data.json();
	evt.waitUntil(
		self.registration.showNotification(data.title, data )
		/*	icon: アイコンパス
			body: 通知メッセージ
			tag:  識別用タグ
			data: { <datahash> }		*/
	);
}, false);

self.addEventListener('notificationclick', function(evt) {
  evt.notification.close();
  evt.waitUntil(
  	clients.matchAll({ type: 'window' }).then(function(clist) {
  		// location.href = 'sworker.js' web path
  		var data = evt.notification.data || {};
		var url  = data.url || location.href.replace(/[^\/]*$/, '');

		for(var i=0; i<clist.length; i++) {
			var c = clist[i];
			if (c.url == url) return c.focus();
		}
		clients.openWindow(url);
	})
  );
}, false);

