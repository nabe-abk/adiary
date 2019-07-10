//############################################################################
// run init
//############################################################################
$(function(){
	adiary.init();

	// Emulate jquery.cookie for dynatree
	// "jquery-storage" in "PrefixStorage.js"
	$.storage_init( Storage );
	$.cookie = $.storage;
	$.removeCookie = $.removeStorage;
});
