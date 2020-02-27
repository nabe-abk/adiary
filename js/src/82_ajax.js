//############################################################################
// ■Ajaxライブラリ
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// ●セッションを保持して随時データをロードする
//////////////////////////////////////////////////////////////////////////////
$$.session = function(btn, opt){
  $(btn).click( function(evt){
	var $btn = $(evt.target);
	var myself = opt.myself || this.myself;
	var $log   = opt.$log   || $btn.rootfind($btn.data('log-target') || '#session-log');

	var load_session = myself + '?etc/load_session';
	var interval = opt.interval || $log.data('interval') || 300;
	var snum;

	if (opt.load_log) $log = opt.load_log(evt);
	$log.showDelay();
	if (opt.init) opt.init(evt);

	// セッション初期化
	$.post( load_session, {
			action: 'etc/init_session',
			csrf_check_key: opt.csrf_key || $('#csrf-key').val()
		}, function(data) {
			var reg = data.match(/snum=(\d+)/);
			if (reg) {
				snum = reg[1];
				ajax_session();
				return;
			}
			console.warn(error);
		}, 'text'
	);

	// Ajaxセッション開始
	function ajax_session(){
		log_start();
		var fd;
		if (opt.load_formdata) fd = opt.load_formdata($btn);
				else   fd = new FormData( opt.form );
		var ctype;
		if (typeof(fd) == 'string') fd += '&snum=' + snum;
		else {
			fd.append('snum', snum);
			ctype = false;
		}
		$.ajax(myself + '?etc/ajax_dummy', {
			method: 'POST',
			contentType: ctype,
			processData: false,
			data: fd,
			dataType: opt.dataType || 'text',
			error: function(jqXHR, status, msg) {
				const e_msg = '[' + $$.name + '.session()] Ajax fail: ' + msg;
				console.warn(e_msg);
				log_stop(function(){
					$log.text($log.text() + "\n" + e_msg + "\n");
					$log.scrollTop( $log.prop('scrollHeight') );
					if (opt.error) opt.error(jqXHR, status, msg);
				});
			},
			success: function(data) {
				log_stop(function(){
					if (opt.success) opt.success(data);
				});
			},
			complete:	opt.complete,
			xhr:		opt.xhr
		});
	}

	/// ログ表示タイマー
	var log_timer;
	function log_start( snum ) {
		$btn.prop('disabled', true);
		$log.data('snum', snum);
		log_timer = setInterval(log_load, interval);
	}
	function log_stop(func) {
		if (log_timer) clearInterval(log_timer);
		log_timer = 0;
		log_load(func);
		$btn.prop('disabled', false);
	}
	function log_load(func) {
		var url = load_session + '&snum=' + snum;
		$log.load(url, function(data){
			$log.scrollTop( $log.prop('scrollHeight') );
			if (func) func();
		});
	}
  });
};

