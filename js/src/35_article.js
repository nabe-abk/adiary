//////////////////////////////////////////////////////////////////////////////
//●MathJaxの自動ロード
//////////////////////////////////////////////////////////////////////////////
{
	const MathJaxURL = 'https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS_HTML';

	adiary.init(function(){
		var mj_span = $('span.math');
		var mj_div  = $('div.math');
		if (!mj_span.length && !mj_div.length) return;

		window.MathJax = {
			TeX: { equationNumbers: {autoNumber: "AMS"} },
			tex2jax: {
				inlineMath: [],
				displayMath: [],
				processEnvironments: false,
				processRefs: false
			},
			extensions: ['jsMath2jax.js']
		};
		this.load_script( MathJaxURL );
	});
}
