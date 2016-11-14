#!/bin/sh

# Version判別
if [ "$1" != '' ]
then
	VERSION=$1
else
	VERSION=`   head -20 lib/SatsukiApp/adiary.pm | grep "\\$VERSION"    | sed "s/.*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/"`
	OUTVERSION=`head -20 lib/SatsukiApp/adiary.pm | grep "\\$OUTVERSION" | sed "s/.*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/"`
	SUBVERISON=`head -20 lib/SatsukiApp/adiary.pm | grep "\\$SUBVERSION" | sed "s/.*'\([A-Za-z0-9\.-]*\)'.*/\1/"`
	if [ "$OUTVERSION" != '' ]
	then
		VERSION=$OUTVERSION
	fi
	if [ "$SUBVERISON" != '' ]
	then
		VERSION=$VERSION$SUBVERISON
	fi
fi

#CPFLAGS=-v

RELEASE=adiary-$VERSION
EXCLUSIVE_LIST=__tool/norelease.list

BASE="
	adiary.cgi
	adiary.fcgi
	adiary.speedy.cgi
	adiary.env.cgi.sample
	adiary.conf.cgi.sample
	README.md
	CHANGES.txt
	index.html
	dot.htaccess
"



#-----------------------------------------------------------
# 必要なディレクトリを作成
#-----------------------------------------------------------
if [ ! -e $RELEASE ]
then
	mkdir $RELEASE
fi

#-----------------------------------------------------------
# ファイルのコピー
#-----------------------------------------------------------
# システムのコピー
cp -Rp $CPFLAGS skel pub-dist info js lib theme $RELEASE/

# ベースファイル
cp -Rp $CPFLAGS $BASE $RELEASE/

# プラグイン
cp -Rp $CPFLAGS plugin $RELEASE/
rm -rf $RELEASE/plugin/\@*

#-----------------------------------------------------------
# 個別ディレクトリの生成
#-----------------------------------------------------------
# __cache
mkdir $RELEASE/__cache
cp -p $CPFLAGS __cache/.htaccess  $RELEASE/__cache/
cp -p $CPFLAGS __cache/index.html $RELEASE/__cache/

# data
mkdir $RELEASE/data
cp -p $CPFLAGS data/.htaccess  $RELEASE/data/
cp -p $CPFLAGS data/index.html $RELEASE/data/

# pub
mkdir $RELEASE/pub
cp -p $CPFLAGS pub/.gitkeep $RELEASE/pub/

# skel.local
mkdir $RELEASE/skel.local
cp -p $CPFLAGS skel.local/.htaccess  $RELEASE/skel.local/
cp -p $CPFLAGS skel.local/README.txt $RELEASE/skel.local/

#-----------------------------------------------------------
# リリースしないファイルを削除
#-----------------------------------------------------------
if [ -r $EXCLUSIVE_LIST ] 
then
	cd $RELEASE
	echo rm -rf `cat ../$EXCLUSIVE_LIST`
	rm -rf `cat ../$EXCLUSIVE_LIST`
	cd ..
fi

#-----------------------------------------------------------
# end
#-----------------------------------------------------------
echo RELEASED : $RELEASE/

#-----------------------------------------------------------
# Release checker
#-----------------------------------------------------------
cd $RELEASE
../__tool/checker.pl
cd ..

