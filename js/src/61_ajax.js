//############################################################################
// Ajax
//############################################################################
//////////////////////////////////////////////////////////////////////////////
// send_ajax
//////////////////////////////////////////////////////////////////////////////
$$.send_ajax = function(opt) {
	const self=this;

	function error_default(h) {
		if (opt.error) opt.error(h);

		let msg = '';
		if (h) {
			if (h.ret && h._develop) msg += 'ret = ' + h.ret;
			if (h.msg)    msg += '<p>' + self.tag_esc(h.msg.toString())    + '</p>';
			if (h.errs) {
				const ary = [];
				const e = h.errs;
				const o = e._order || Object.keys(e);
				for(let i in o)
					ary.push(e[o[i]]);
				msg += '<p class="ni">' + ary.join("<br>") + '</p>';
			}
			if (h._debug) msg += '<p class="ni">' + h._debug.replace(/\n/g, '<br>') + '</p>';
		} else {
			msg = '<p>' + self.msg('server_response_error', 'response data error!') + '</p>';
		}
		self.show_error(msg, opt.error_callback);
	}
	const data = opt.data;
	return $.ajax(opt.url || self.myself || './', {
		method:		'POST',
		data:		data.toString() == '[object Object]' ? $.param(data) : data,
		processData:	false,
		contentType:	false,
		dataType:	'json',
		error:		function(e) { error_default(undefined,e); },
		success:	function(h) {
			if (h.ret != '0' || h._debug) return error_default(h);
			if (opt.success) opt.success(h);
		},
		complete:	opt.complite,
	});
};

//////////////////////////////////////////////////////////////////////////////
//●promise of ajax
//////////////////////////////////////////////////////////////////////////////
$$.send_ajax_promise = function(opt) {
	const self=this;

	return new Promise( (resolve, reject) => {
		opt.error_callback = function(){
			reject();
		};
		opt.success = function(h) {
			resolve(h);
		};
		self.send_ajax(opt);
	});
}
