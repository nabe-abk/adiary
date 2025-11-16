'use strict';
$(function(){
	const TARGET    = '.main div.body-main figure, .main div.body-main table, .main div.body-main div, .main div.body-main blockquote, .main div.body-main pre, .main div.body-main iframe';
	const baseWidth = $('.main div.body-main').width() * 0.9;
	const minMargin = 8;

	function alian_lineheight(dom) {
		const $obj = $(dom);
		if ($obj.parents(TARGET).length) return;

		let line_h = parseInt($obj.css('line-height'));
		line_h = isNaN(line_h) ? 24 : line_h;		// default 24px;

		const objs = [$obj];
		if ($obj.outerWidth() > baseWidth) {	// 横に複数並ぶ figure を除外する
			while(true) {
				const $y = objs[0].prev(TARGET);
				if (!$y.length) break;
				const w  = $y.outerWidth();
				if (w < baseWidth) break;
				objs.unshift($y);
			}
			while(true) {
				const $y = objs[objs.length-1].next(TARGET);
				if (!$y.length) break;
				const w  = $y.outerWidth();
				if (w < baseWidth) break;
				objs.push($y);
			}
		}

		let height = (objs.length-1) * minMargin;
		for(const $o of objs) {
			height += $obj.outerHeight();
			$obj.css({
				'margin-top':    minMargin + 'px',
				'margin-bottom': minMargin + 'px',
				'vertical-align':'middle'
			});
		}

		const mul  = Math.ceil( (height + minMargin*2) /line_h );
		if (mul < 2) return;
		const diff = line_h * mul - height;

		const m = (diff/2) + 'px';
		objs[0]            .css('margin-top',    m);
		objs[objs.length-1].css('margin-bottom', m);
	}

	const observer = new MutationObserver(function(list){
		const targets = [];
		for(const x of list) {
			const tar = $(x.target).closest(TARGET)[0];
			if (!tar) continue;

			let f;
			for(const y of targets) {
				if (tar.isEqualNode(y)) { f=true; break; }
			}
			if (f) continue;
			targets.push(tar);
		}

		for(const dom of targets) {
			alian_lineheight(dom)
		}
	});

	for(const dom of $(TARGET)) {
		alian_lineheight(dom);

		observer.observe(dom, { childList: true, subtree: true });
	}

	$('.main div.body-main img, .main div.body-main iframe').on('load', evt => {
		let dom = evt.target;
		if (dom.tagName === 'IMG') {
			const $fig = $(dom).closest('figure');
			if (!$fig.length) return;
			dom = $fig[0];
		}
		// console.log('load', dom);
		alian_lineheight(dom);
	});
});
