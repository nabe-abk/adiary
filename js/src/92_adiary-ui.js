//############################################################################
// adiary UI
//							(C)2019 nabe@abk
//############################################################################
$.fn.extend({
//////////////////////////////////////////////////////////////////////////////
// dialog
//////////////////////////////////////////////////////////////////////////////
// The "modal" option ignore, this option exists for jQuery UI compatiblity.
//
adiaryDialog: function(opt) {
	if ( opt === 'open' )	return this.adiaryDialogOpen();
	if ( opt === 'close' )	return this.adiaryDialogClose();
	if (!$.adiary_ui_zindex)
		$.adiary_ui_zindex = 100;

	const self = this;
	//////////////////////////////////////////////////////////////////////
	// init dialog div
	//////////////////////////////////////////////////////////////////////
	const $win = $(window);
	const $dialog = $('<div>').addClass('ui-dialog aui-dialog');
	const width = opt.width || 300;
	const min_h = opt.minHeight || 150;
	const x = $win.scrollLeft() + ($win.width()  - width )/2;
	$dialog.css({
		width:  width,
		left:   x
	});
	if (opt.maxHeight) $dialog.css('max-height', opt.maxHeight);
	if (opt.dialogClass)
		$dialog.addClass( opt.dialogClass );

	//////////////////////////////////////////////////////////////////////
	// header
	//////////////////////////////////////////////////////////////////////
	{
		const $title = $('<div>').addClass('ui-dialog-titlebar ui-widget-header');
		const $span  = $('<span>').addClass('ui-dialog-title')
			.html( opt.title || this.attr('title') || '&ensp;' );
		$title.append( $span );
		const $close = $('<button>').addClass('ui-button').attr('title', 'Close');
		$close.append( $('<span>').addClass('ui-icon ui-icon-closethick') );
		$title.append( $close );
		$dialog.append( $title );
		
		$close.on('click', function(){
			self.adiaryDialogClose();
		})
	}

	//////////////////////////////////////////////////////////////////////
	// main
	//////////////////////////////////////////////////////////////////////
	this.addClass('ui-dialog-content');
	$dialog.append( this );

	//////////////////////////////////////////////////////////////////////
	// button
	//////////////////////////////////////////////////////////////////////
	{
		const $footer = $('<div>').addClass('ui-dialog-buttonpane ui-dialog-content');
		const $btnset = $('<div>').addClass('ui-dialog-buttonset');
		const btns = opt.buttons;
		
		for(let i in btns) {
			let $btn = $('<button>')
					.addClass('ui-button')
					.attr('type', 'button')
					.text( i );
			$btn.on('click', btns[i]);
			$btnset.append($btn);
		}
		$footer.append( $btnset );
		$dialog.append( $footer );
	}

	//////////////////////////////////////////////////////////////////////
	// append dialog obj
	//////////////////////////////////////////////////////////////////////
	const $overlay = $('<div>').addClass('aui-overlay');

	const data = this.adiaryUIData();
	const objs = data.dialog_objs = data.dialog_objs || [];
	objs.push($overlay);
	objs.push($dialog);
	data.min_h = min_h;
	data.beforeClose = opt.beforeClose;

	if (opt && !opt.autoOpen && 'autoOpen' in opt) return this;

	return this.adiaryDialogOpen();
},
adiaryDialogOpen: function() {
	const data = this.adiaryUIData();
	const objs = data.dialog_objs;
	if (!objs || !objs.length) throw("Do not open dialog!");

	for(let i=0; i<objs.length; i++)
		this.adiaryUIAppend( objs[i] );

	// set css
	const $win = $(window);
	const $dialog = objs[ objs.length-1 ];
	this.css('min-height', data.min_h + this.height() - $dialog.height());

	const y = $win.scrollTop()  + ($win.height() - $dialog.height())/2;
	$dialog.css('top', y);
	$dialog.adiaryDraggable({
		cancel:	".ui-dialog-content, .ui-button"
	});
	return this;
},
adiaryDialogClose: function() {
	const data = this.adiaryUIData();
	if (data.beforeClose) data.beforeClose();

	const objs = data.dialog_objs;
	for(let i=0; i<objs.length; i++)
		this.adiaryUIRemove( objs[i] );
	data.dialog_objs = [];
	return this;
},
//////////////////////////////////////////////////////////////////////////////
// dialog sub functions
//////////////////////////////////////////////////////////////////////////////
adiaryUIData: function(key, val) {
	const data = this.aui_data = this.aui_data || {};
	if (arguments.length==1) return data[key];
	if (arguments.length==2) data[key] = val;
	return data;
},
adiaryUIAppend: function($obj) {
	const data = this.adiaryUIData();
	$obj.css('z-index', $.adiary_ui_zindex++);
	$('body').append( $obj );
},
adiaryUIRemove: function($obj) {
	$.adiary_ui_zindex--;
	$obj.remove();
},

//////////////////////////////////////////////////////////////////////////////
// draggable
//////////////////////////////////////////////////////////////////////////////
adiaryDraggable: function(opt) {
	const self=this;
	let sx;
	let sy;

	this.on('mousedown', function(evt){
		if (opt && opt.cancel) {
			const $obj = $(evt.target);
			if ($obj.filter(opt.cancel).length ) return;
			if ($obj.parents(opt.cancel).length) return;
		}
		self.addClass('drag');
		const p = self.offset();
		sx = p.left - evt.pageX;
		sy = p.top  - evt.pageY;
		$(document).on('mousemove', move);
		evt.preventDefault();
		return;
	});

	this.on('mouseup', function(evt){
		$(document).off('mousemove', move);
		evt.preventDefault();
	});

	function move(evt) {
		const x = sx + evt.pageX;
		const y = sy + evt.pageY;

		self.css({
			position:	'absolute',
			left:		x + 'px',
			top:		y + 'px'
		});
		evt.preventDefault();
	}
}
//////////////////////////////////////////////////////////////////////////////
});
