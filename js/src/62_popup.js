//////////////////////////////////////////////////////////////////////////////
// popup for mouseenter
//////////////////////////////////////////////////////////////////////////////
// mouseover event
$$.popup = function(evt) {	// event function なので this は使わない!
	const self  = this;
	const $obj  = $(evt.target);
	let   delay = $obj.data('delay') || this.PopupDelayTime;
	if (delay<1) delay=1;

	// set default div
	evt.data.$div = evt.data.$div || this.$popup_div;

	$obj.on('mouseout', evt.data, function(evt){ self.popup_hide(evt) });
	$obj.data('timer', setTimeout(function()   { self.popup_show(evt) }, delay));
}

$$.popup_show = function(evt) {
	const $obj = $(evt.target);
	const $div = evt.data.$div;
	const func = evt.data.func;
	if ($div.is(":animated")) return;

	if (func) func($obj, $div);
	$div.css("left", (SP ? 0 : (evt.pageX + this.PopupOffsetX)));
	$div.css("top" ,            evt.pageY + this.PopupOffsetY);
	$div.showDelay();
}
// mouseout event
$$.popup_hide = function(evt) {
	const $obj = $(evt.target);
	const $div = evt.data.$div;
	if ($obj.data('timer')) {
		clearTimeout( $obj.data('timer') );
		$obj.data('timer', null);
	}
	$obj.off('mouseout');
	$div.hide();
}

