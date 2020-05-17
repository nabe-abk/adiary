//////////////////////////////////////////////////////////////////////////////
// get secure object
//////////////////////////////////////////////////////////////////////////////
window.$secure = function(id) {
	var obj = $(document).find('[id="' + id.substr(1) + '"]');
	if (obj.length >1) {
		console.error('$secure() error! : id="' + id + '" is duplicate.');
		return $([]);
	}
	return obj;
}

//////////////////////////////////////////////////////////////////////////////
// for IE11
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

if (FormData && !FormData.delete)
	FormData.prototype.delete = function(arg) {};

