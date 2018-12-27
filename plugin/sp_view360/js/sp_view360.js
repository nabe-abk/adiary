// 360画像表示用プラグイン
// ver. 1.0
'use strict';

function sp_view360(){
	var me = this;
	me.name = "sp_view360";
	me.version = "1.0";
	me.speed = 0.2; // 速度補正

	me.idptn = /\d+$/; // ^sp_view360_\d+$
	me.lastid = 0;
	me.drag = false;  // drag検出フラグ

// WebGLに必要な要素
	me.elem     = []; // view用 親エレメント
	me.scene    = [];
	me.camera   = [];
	me.renderer = [];
	me.angle    = [];
	me.canvas   = [];

// 視点移動用
	me.target = -1;
	me.mouseStatus =  {x: 0, y: 0, s: 0};

// 初期化
	me.init = function(){
		// 360度画像の要素を探す
		var x = $("a.view360 img");
		var y = $("a:not(.view360) img").filter(function(idx){
			var file = this.getAttribute('src');
			return file && file.match(/[-_]360\./);
		});
		x.each(me.make);
		y.each(me.make);

		// ドキュメントのマウスイベントに登録
		$(document).on("mousemove", me.onMouseMove);
		$(document).on("mouseup", me.onMouseUp);
		$(document).on("mouseleave", me.onMouseUp); // たぶん発生しないイベント
		$(document).on("touchmove", me.onTouchMove);
		$(document).on("touchend", me.onMouseUp);   //mouseと同じ
		$(document).on("touchcancel", me.onMouseUp);//mouseと同じ

	}// init

	me.make = function(idx, elem){
		$(elem).on('load', function(){
			me._make(elem);
		});
	}
	me._make = function(elem){
		var i = $(elem);
		i.wrap("<span style=\"display: inline-block; width: "+i.width()+"px; height:"+i.height()+"px; position: relative: baseline: bottom\" />");
		me.elem.push($(i.parent()));
		var idx = me.lastid;
		me.lastid++;

		// ドラッグイベント(兼 情報表示)用canvas
		me.canvas.push($("<canvas id=\"sp_view360_"+idx+"\" width="+(i.width())+" height="+(i.height())+" style='position: absolute; width: "+i.width()+"px; height:"+i.height()+"px; background-color:rgba(0,0,0,0)'></canvas>"));
		me.elem[idx].append(me.canvas[idx]);

		// 基本オブジェクトの生成と登録
		me.scene.push(new THREE.Scene());
		me.camera.push(new THREE.PerspectiveCamera(70, i.width() / i.height(), 0.1, 1000));
		me.camera[idx].rotation.order = "YXZ";
		me.angle.push({lon: 0, lat: 0});
		me.renderer.push(new THREE.WebGLRenderer(/*{antialias: true}*/));
		me.renderer[idx].setPixelRatio(window.devicePixelRatio);
		me.renderer[idx].setSize(i.width(), i.height());

		// 画像をtextureとして読み込み
//console.log("LoadTexture: "+i.attr("src"));
		var textureLoader = new THREE.TextureLoader();
		textureLoader.load(i.attr("src"), (function(k){
			var idx = k;
			return function(texture){
				// textureの初期設定
				texture.mapping   = THREE.UVMapping;
				texture.minFilter = texture.magFilter = THREE.LinearFilter;
				var mesh = new THREE.Mesh(new THREE.SphereGeometry(200, 32, 32), new THREE.MeshBasicMaterial({map: texture}));
				mesh.scale.x = -1;
				mesh.position.set(0, 0, 0);
				mesh.material.needsUpdate = true;
				mesh.material.side = THREE.BackSide;
				me.scene[idx].add(mesh);

				// 読みだしたら元画像とキャンバスを入れ替えて描画
				$("img", me.elem[idx]).css('display', 'none');
				me.elem[idx].append(me.renderer[idx].domElement);
				me.render(idx);

				// マウスイベントの登録
				me.canvas[idx].on("mousedown", me.onMouseDown);
				me.canvas[idx].on("touchstart", me.onTouchStart);

				// Dragした場合はclickイベントを止める
				me.canvas[idx].on("click", function(e){
					if (!me.drag) return;
					e.preventDefault();
					e.stopPropagation();
				});
			};
		})(idx));// textureLoader.load
	}

	me.render = function(idx) {
		// 念のため上下の角度チェックして、角度を調整する
//		me.angle[idx].lat = Math.max(-89, Math.min(89, me.angle[idx].lat));

		// カメラの首振り
		me.camera[idx].rotation.y = THREE.Math.degToRad(90-me.angle[idx].lon); // 左右首振り
		me.camera[idx].rotation.x = THREE.Math.degToRad(-me.angle[idx].lat);   // 上下首振り

		me.renderer[idx].render(me.scene[idx], me.camera[idx]);
	}

	// ドラッグスタート
	me.onMouseDown  = function(e){ me._dragstart(e, e.pageX, e.pageY); }
	me.onTouchStart = function(e){ me._dragstart(e, e.changedTouches[0].pageX, e.changedTouches[0].pageY); }
	me._dragstart   = function(e, x, y){
		me.drag = false;
		e.preventDefault();
		if(me.mouseStatus.s > 0){ return; }
		me.mouseStatus.s = 1;

		var idx = 1 * e.target.id.match(me.idptn);
		me.target = idx;

		// 基準座標の記録
		me.mouseStatus.x = (x - me.elem[idx].offset().left);
		me.mouseStatus.y = (y - me.elem[idx].offset().top);
	}
	// ドラッグちう
	me.onMouseMove = function(e){ me._dragging(e, e.pageX, e.pageY); }
	me.onTouchMove = function(e){ me._dragging(e, e.changedTouches[0].pageX, e.changedTouches[0].pageY); }
	me._dragging   = function(e, x, y){
		me.drag = true;
		if(me.mouseStatus.s == 0 || me.target < 0){ return ;}
		var idx = me.target;

		// 移動した分だけ画面を動かす
		me.angle[idx].lon = me.angle[idx].lon + (me.mouseStatus.x - (x - me.elem[idx].offset().left)) * me.speed;
		me.angle[idx].lat = me.angle[idx].lat + (me.mouseStatus.y - (y - me.elem[idx].offset().top)) * me.speed;
		me.angle[idx].lat = Math.max(-80, Math.min(80, me.angle[idx].lat)); // 上下に制限をかける

		// 基準座標の更新
		me.mouseStatus.x = x - me.elem[idx].offset().left;
		me.mouseStatus.y = y - me.elem[idx].offset().top;

		// 画面の更新
		me.render(idx);
	}

	// ドラッグ終了
	me.onMouseUp = function(e){
		me.mouseStatus.s = 0;
		me.target = -1;
	}
}

var sp_view360 = new sp_view360();
sp_view360.init();

