
$(function(){
	var side = $('#side-broken-clock div.hatena-modulebody');
	var dclock = $('span',side);
	var ct = side.data('ct');
	var vt = side.data('vt');
	var hh = side.data('hourhand');
	var mh = side.data('minhand');
	var sh = side.data('sechand');
	var cnvs;
	var context;
	var cnvs_x;
	var cnvs_y;
	var delay = 1000;
	function my_timer(){
		var x = Math.random();
		d = new Date();
		h = d.getHours();
		m = d.getMinutes();
		s = d.getSeconds();
		if(ct == 'normal'){
			// 何もしない普通の時計
		}else if(ct == 'random'){
			// ちょっとだけ乱数で数字が増減する時計
			if(x < 0.1){ // 10%
				s -= 1;
			}else if(x > 0.9){ // 10%
				s += 1;
			}

			x = Math.random();
			if((s > 30 && x < 0.3) || x < 0.1){
				delay = 10000*x;
			}else{
				delay = 1000;
			}
		}

		if(vt == 'analog24'){
			context.clearRect(0,0,cnvs_x*2,cnvs_y*2);

			context.beginPath();
			context.strokeStyle = 'rgb(0,0,0)';
			context.fillStyle = 'rgb(255,255,255)';
			context.arc(cnvs_x, cnvs_y, 0.95*cnvs_x, 0, 2*Math.PI, 0);
			context.fill();
			context.stroke();

// 12方向にマークをつける
			for(i = 0; i < 12; i++){
				context.beginPath();
				x = cnvs_x+0.95*cnvs_x*Math.cos(Math.PI/2 - (i*5/60*2*Math.PI));
				y = cnvs_y-0.95*cnvs_y*Math.sin(Math.PI/2 - (i*5/60*2*Math.PI));
				context.moveTo(x,y);
				x = cnvs_x+0.90*cnvs_x*Math.cos(Math.PI/2 - (i*5/60*2*Math.PI));
				y = cnvs_y-0.90*cnvs_y*Math.sin(Math.PI/2 - (i*5/60*2*Math.PI));
				context.lineTo(x,y);
				context.closePath();
				context.stroke();
			}

if(sh){
			context.beginPath();
			if(s > 30){
				r = Math.floor(255 * (s-30) / 30);
				context.strokeStyle = "rgb("+r+",0,0)";
			}else{
				r = Math.floor(255 * (30-s) / 30);
				context.strokeStyle = "rgb("+r+",0,0)";
			}

			context.moveTo(cnvs_x,cnvs_y);
			x = cnvs_x+0.7*cnvs_x*Math.cos(Math.PI/2 - (s/60*2*Math.PI));
			y = cnvs_y-0.7*cnvs_y*Math.sin(Math.PI/2 - (s/60*2*Math.PI));
			context.lineTo(x,y);
			context.closePath();
			context.stroke();
}
if(mh){
			context.beginPath();
			context.strokeStyle = 'rgb(0,0,0)';
			context.moveTo(cnvs_x,cnvs_y);
			x = cnvs_x+0.9*cnvs_x*Math.cos(Math.PI/2 - ((m+s/60)/60*2*Math.PI));
			y = cnvs_y-0.9*cnvs_y*Math.sin(Math.PI/2 - ((m+s/60)/60*2*Math.PI));
			context.lineTo(x,y);
			context.closePath();
			context.stroke();
}
if(hh){
			context.beginPath();
			context.strokeStyle = 'rgb(0,0,0)';
			context.moveTo(cnvs_x,cnvs_y);
			x = cnvs_x+0.5*cnvs_x*Math.cos(Math.PI/2 - ((h+m/60+s/3600)/24*2*Math.PI));
			y = cnvs_y-0.5*cnvs_y*Math.sin(Math.PI/2 - ((h+m/60+s/3600)/24*2*Math.PI));
			context.lineTo(x,y);
			context.closePath();
			context.stroke();
}
//			dclock.html(cnvs_x+':'+cnvs_y);
		}else{
			h = (100+h).toString().substr(-2);
			m = (100+m).toString().substr(-2);
			s = (100+s).toString().substr(-2);
			side.html(h+':'+m+':'+s);
		}
		setTimeout(my_timer,delay);
	}

	if(vt == 'analog24'){
		cnvs_y = cnvs_x = Math.floor(side.innerWidth() / 2);
		cnvs = $("<canvas></canvas>");
		cnvs.attr('width', cnvs_x*2+'px');
		cnvs.attr('height', cnvs_y*2+'px');
		$(window).resize(function(){
			cnvs_y = cnvs_x = Math.floor(side.innerWidth() / 2);
			cnvs.attr('width', cnvs_x*2+'px');
			cnvs.attr('height', cnvs_y*2+'px');
		});
		// cnvs.css('min-width', cnvs_x*2+'px');
		// cnvs.css('min-height', cnvs_y*2+'px');
		side.empty();
		side.append(cnvs);
		context = cnvs.get(0).getContext('2d');
	}
	my_timer();
});

