$(function() {
	var baseID = "side-serika-clock";
	var show, caltype;

	var ly, ly10, lmo, lmo10, ld, ld10;
	var lh, lh10, lm, lm10, ls, ls10;
	var ymd = '123456';

	function init(){
		var svg=$('#'+baseID+'-svg');
		show = svg.data('show') || 'yt';
		caltype = svg.data('caltype') || 'ymd';

if(show=='y'){
	svg.get(0).setAttribute("viewBox", "0 0 165 40");
}
if(show=='t'){
	svg.get(0).setAttribute("viewBox", "175 0 165 40");
}

		ly = ly10 = lmo= lmo10= ld = ld10 = -1;
		lh = lh10 = lm = lm10 = ls = ls10 = -1;

		if(caltype=='ymd'){
			ymd = '123456';
		}
		if(caltype=='dmy'){
			ymd = '563412';
		}
		if(caltype=='mdy'){
			ymd = '345612';
		}

setInterval(function(){
		var t = new Date();
		var a,b;
if(show=='yt'||show=='y'){
		var y, mo,d;
		y = t.getYear() % 100;
		mo= t.getMonth() + 1;
		d = t.getDate();
		if(y != ly){
			a = Math.floor(y/10);
			b = y % 10;
			ly = y;
			if(a != ly10){
				document.getElementById(baseID+"-c"+ymd.charAt(0)+"a"+a).beginElement();
				ly10 = a;
			}
			document.getElementById(baseID+"-c"+ymd.charAt(1)+"a"+b).beginElement();
		}
		if(mo != lmo){
			a = Math.floor(mo/10);
			b = mo % 10;
			lmo = mo;
			if(a != lmo10){
				document.getElementById(baseID+"-c"+ymd.charAt(2)+"a"+a).beginElement();
				lmo10 = a;
			}
			document.getElementById(baseID+"-c"+ymd.charAt(3)+"a"+b).beginElement();
		}
		if(d != ld){
			a = Math.floor(d/10);
			b = d % 10;
			ld = d;
			if(a != ld10){
				document.getElementById(baseID+"-c"+ymd.charAt(4)+"a"+a).beginElement();
				ld10 = a;
			}
			document.getElementById(baseID+"-c"+ymd.charAt(5)+"a"+b).beginElement();
		}
}
if(show=='yt'||show=='t'){
		var h, m, s;
		h = t.getHours();
		m = t.getMinutes();
		s = t.getSeconds();
		if(h != lh){
			a = Math.floor(h/10);
			b = h % 10;
			lh = h;
			if(a != lh10){
				document.getElementById(baseID+"-d1a"+a).beginElement();
				lh10 = a;
			}
			document.getElementById(baseID+"-d2a"+b).beginElement();
		}
		if(m != lm){
			a = Math.floor(m/10);
			b = m % 10;
			lm = m;
			if(a != lm10){
				document.getElementById(baseID+"-d3a"+a).beginElement();
				lm10 = a;
			}
			document.getElementById(baseID+"-d4a"+b).beginElement();
		}
		if(s != ls){
			a = Math.floor(s/10);
			b = s % 10;
			ls = s;
			if(a != ls10){
				document.getElementById(baseID+"-d5a"+a).beginElement();
				ls10 = a;
			}
			document.getElementById(baseID+"-d6a"+b).beginElement();
		}
}
},100);
	}

	init();

});
