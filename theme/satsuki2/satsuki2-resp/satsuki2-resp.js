//############################################################################
// sidebarの配置換え
//							(C)2015 nabe@abk
//############################################################################
//[TAB=8]  require jQuery
'use strict';

$(function() {
	if (SP) return;
	var sidebar = $('#sidebar');
	sidebar.insertBefore( 'div .main:first-child' );
});










