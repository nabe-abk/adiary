
$(function(){
	var ta = $('#side-serika-memo textarea');

	function loadMemo(){
	    var i;
	    var t = ' '+document.cookie;
	    var cs = t.split(';');
	    for(i = 0; i < cs.length; i++){
	    	t = cs[i].trim();
	    	if(t.indexOf('serikamemo=')==0){
	    		return decodeURIComponent(t.substring(11, t.length));
	    	}
	    }
	    return '自由にメモしておけるテキストエリアです。\r\nメモは、cookieに保存されます。';
	}

	function saveMemo(){
		var d = ta.val();
		var exp = new Date();
		if(d != ""){
			exp.setTime( exp.getTime() + 1000 * 3600 * 24 * 365);
		}else{
			exp.setTime(0);
		}

		document.cookie = 'serikamemo='+encodeURIComponent(d)+'; expires=' + exp.toUTCString()+'; path='+Blogpath;
	}

	function init(){
		ta.text(loadMemo());
		ta.change(saveMemo);
	}

	init();
});

