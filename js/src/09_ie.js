//////////////////////////////////////////////////////////////////////////////
//●for IE11
//////////////////////////////////////////////////////////////////////////////
if (!String.repeat) String.prototype.repeat = function(num) {
	var str='';
	var x = this.toString();
	for(var i=0; i<num; i++) str += x;
	return str;
}

if (!Array.from) Array.from = function(arg) {
	return Array.prototype.slice.call(arg);
}

