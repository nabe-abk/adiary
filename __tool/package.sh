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
RELEASE=adiary-$VERSION

# ディリクトリが存在しなければ終了
if [ ! -e $RELEASE/ ]
then
	echo $RELEASE/ not exists.
	exit
fi

echo tar jcvf $RELEASE.tar.bz2 $RELEASE/
     tar jcvf $RELEASE.tar.bz2 $RELEASE/

# フォントなしパッケージ
<< COMMENT
rm -rf $RELEASE/pub-dist/VL-PGothic-Regular.ttf $RELEASE/VLGothic/

echo tar jcvf $RELEASE-nofont.tar.bz2 $RELEASE/
     tar jcvf $RELEASE-nofont.tar.bz2 $RELEASE/
COMMENT

rm -rf $RELEASE
