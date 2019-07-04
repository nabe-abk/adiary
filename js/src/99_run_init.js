$(function(){
	adiary.init();

	// Emulate jquery.cookie for dynatree
	$.storage_init( Storage );
	$.cookie = $.storage;
	$.removeCookie = $.removeStorage;
});
