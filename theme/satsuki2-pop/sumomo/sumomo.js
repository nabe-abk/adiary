'use strict';
$(function(){
	const DEBUG = 0;

	const TARGET    = '.main article.article figure, .main article.article table, .main article.article div.math, .main article.article blockquote, .main article.article pre, .main article.article iframe';
	const baseWidth = $('.main div.body-main').width() * 0.9;
	const minMargin = 8;

	function alian_lineheight(dom) {
		const $obj = $(dom);
		if ($obj.parents(TARGET).length) return;

		let line_h = parseInt($obj.css('line-height'));
		line_h = isNaN(line_h) ? 24 : line_h;		// default 24px;

		const _objs = [$obj];
		const cssfl = $obj.css('float');
		while(true) {
			const $y = _objs[0].prev(TARGET);
			if (!$y.length || $y.css('float') != cssfl) break;
			_objs.unshift($y);
		}
		while(true) {
			const $y = _objs[_objs.length-1].next(TARGET);
			if (!$y.length || $y.css('float') != cssfl) break;
			_objs.push($y);
		}

		// 横に並ぶ要素を除外する
		let $c  = _objs.shift();
		const objs = [$c];
		for(const $o of _objs) {
			const top    = $c[0].offsetTop;
			const bottom = top + $c.outerHeight();
			if (bottom < $o[0].offsetTop) {
				// 横に並んでない
				objs.push($o);
				continue;
			}
			// 横に並んでいて、既存のものより縦に長い
			if (bottom < $o[0].offsetTop + $o.outerHeight()) {
				objs.pop();
				objs.push($o);
			}
		}

		let height = (objs.length-1) * minMargin;
		for(const $o of objs) {
			height += $o.outerHeight();
			$o.css({
				'margin-top':    '0px',
				'margin-bottom': minMargin + 'px',
				'vertical-align':'middle'
			});
			// CSSの条件によっては、マージンの相殺が発生しないため、マージンは片側だけ設定する。
		}

		const mul  = Math.ceil( (height + minMargin*2) /line_h );
		if (mul < 2) return;
		const diff = line_h * mul - height;

		const m = (diff/2) + 'px';
		objs[0]            .css('margin-top',    m);
		objs[objs.length-1].css('margin-bottom', m);

		if (DEBUG) console.log(dom, 'len=', objs.length, height, line_h * mul, diff, m);
	}

	const observer = new MutationObserver(function(list){
		const targets = [];
		for(const x of list) {
			const tar = $(x.target).parents(TARGET).last()[0] || x.target;
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

	$('.main div.body-main img, .main div.body-main iframe').on('load', evt => {
		let dom = evt.target;
		if (dom.tagName === 'IMG') {
			const $fig = $(dom).parents('figure').last();
			if (!$fig.length) return;
			dom = $fig[0];
		}
		if (DEBUG) console.log('load', dom);
		alian_lineheight(dom);
	});

	for(const dom of $(TARGET)) {
		alian_lineheight(dom);

		observer.observe(dom, { childList: true, subtree: true });
	}

});
