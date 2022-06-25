//##############################################################################
// 記事ヘッダ加工用
//							(C)2015 nabe@abk
//##############################################################################
//[TAB=8]  require jQuery
'use strict';

$(function() {
	$('#main-first article.article').each(function(idx,dom){
		var obj = $(dom);
		var h2   = obj.find('h2');
		var date = h2.find('a.date');
		var head = obj.find('div.body-header');
		if (h2.length && head.length) {
			h2.append(date);
			h2.append(head);
		}
		var title    = obj.find('h2');
		var bookmark = h2.find('a.http-bookmark');
		if (title.length && bookmark.length) {
			title.append(bookmark);
		}
	});
});










