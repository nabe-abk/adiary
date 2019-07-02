//############################################################################
// ■スケルトン内部使用ルーチン
//############################################################################
//////////////////////////////////////////////////////////////////////////////
//●セキュリティコードの設定
//////////////////////////////////////////////////////////////////////////////
$(function(){
	var form = $('#comment-form');
	if (!form.length) return;
	var csrf = form.find('[name="csrf_check_key"]');
	if (csrf.length) return;	// secure_id は無用

	var pkey = $('#comment-form-apkey').val() || '';
	var ary  = (form.data('secure') || '').split(',');
	if (!pkey.match(/^\d+$/)) return;
	pkey = pkey & 255;

	var sid = '';
	for(var i=0; i<ary.length-1; i++) {
		if (!ary[i].match(/^\d+$/)) return;
		sid += String.fromCharCode( ary[i] ^ pkey );
	}

	var post = $('#post-comment');
	post.prop('disabled', true);

	// 10key押されるか、10秒経ったら設定
	var cnt=0;
	var tarea = form.find('textarea');
	var hook  = function(){
		cnt++;
		if (cnt<10) return;
		enable_func()
	};
	tarea.on('keydown', hook);

	var enable_func = function(){
		tarea.off('keydown', hook);
		$('#comment-form-sid').val(sid);
		post.prop('disabled', false);
	};
	setTimeout(enable_func, 10000);
});

//////////////////////////////////////////////////////////////////////////////
//●ソーシャルボタンの加工
//////////////////////////////////////////////////////////////////////////////
$( function(){
  $('.social-button').each(function(idx,dom) {
	var obj = $(dom);
	var url_orig = obj.data('url') || '';
	if (0<url_orig || !url_orig.match(/^https?:\/\//i)) return;

	var url = encodeURIComponent( url_orig );
	var share = obj.children('a.share');
	var count = obj.children('a.count');

	var share_link = share.attr('href');
	var count_link = count.attr('href');
	if (obj.hasClass('twitter-share')) {
		share_link += url;
		count_link += url_orig.replace(/^https?:\/\/(?:www\.)?/i, '').replace(/^www\./i, '');
	} else {
		share_link += url;
		count_link += url;
	}
	share.attr('href', share_link);
	count.attr('href', count_link);

	///////////////////////////////////////////////////////////////
	// カウンタ値のロード
	///////////////////////////////////////////////////////////////
	count.text('-');
	function load_and_set_counter(obj, url, key) {
		$.ajax({
			url: url,
			dataType: "jsonp",
			success: function(c) {
				if (key && typeof(c) == 'object') c = c[key];
				c = c || 0;
				obj.text(c);
			}
		})
	}

	// 値のロード
	if (obj.hasClass('twitter-share'))
		return; // load_and_set_counter(count, '//urls.api.twitter.com/1/urls/count.json?url=' + url, 'count');
	if (obj.hasClass('facebook-share'))
		return load_and_set_counter(count, '//graph.facebook.com/?id=' + url, 'shares');
	if (obj.hasClass('hatena-bookmark'))
		return load_and_set_counter(count, 'https://b.hatena.ne.jp/entry.count?url=' + url);	// for SSL
		// return load_and_set_counter(count, '//api.b.st-hatena.com/entry.count?url=' + url);	// Do not work on SSL
	if (obj.hasClass('pocket-bookmark')) {
		count.hide();
		return; // Deleted. Because "query.yahooapis.com" is dead
	}

  });
});

//////////////////////////////////////////////////////////////////////////////
//●twitterウィジェットのデザイン変更スクリプト
//////////////////////////////////////////////////////////////////////////////
window.twitter_css_fix = function(css_text){
	var try_max = 25;
	var try_msec = 200;
	function callfunc() {
		var r=1;
		if (try_max--<1) return;
		try{
			r = css_fix(css_text);
		} catch(e) { ; }
		if (r) setTimeout(callfunc, try_msec);
	}
	setTimeout(callfunc, try_msec);

function css_fix(css_text) {
	var iframes = $('iframe');
	var iframe;
	var $doc;
	for (var i=0; i<iframes.length; i++) {
		iframe = iframes[i];
		if (iframe.id.substring(0, 15) != 'twitter-widget-') continue;
		if (iframe.className.indexOf('twitter-timeline')<0)  continue;

		var $doc = $(iframe.contentDocument || iframe.document);
		break;
	}
	if (!$doc) return -1;

	// wait load tweets
	var tweet = $doc.find('.timeline-Tweet');
	if (tweet.length < 1) return -2;

	$(iframe).css('min-width', 0);
	var css = $('<style>').attr({
		id: 'add-tw-css',
		type: 'text/css'
	});
	css.html(css_text);
	$doc.find('head').append(css);
};
///
}

//////////////////////////////////////////////////////////////////////////////
//●月別過去ログリストのリロード
//////////////////////////////////////////////////////////////////////////////
$(function(){
	var selbox = $('#month-list-select-box');
	selbox.change(function(evt){
		var obj = $(evt.target);
		if(!obj.data('url')) return;	// for security
		var val = obj.val(); 
		if (val=='') return;
		window.location = Vmyself2 + val;
	});
	var cur = $('#yyyymm-cond').data('yyyymm');
	if (!cur || typeof(cur) != 'number') return;
	selbox.val( cur.toString() );
});

