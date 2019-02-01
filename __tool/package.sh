#!/bin/sh

# Version check
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

# if not exist RELEASE dir, exit
if [ ! -e $RELEASE/ ]
then
	echo $RELEASE/ not exists.
	exit
fi

# Windows zip
if [ `which zip` ]; then
	echo zip -q adiary-windows_x64.zip -r $RELEASE/
	     zip -q adiary-windows_x64.zip -r $RELEASE/
fi
rm -f $RELEASE/*.exe

#------------------------------------------------------------------
TAR="tar jcf"
EXT="bz2"
# TAR="tar Jcf"
# EXT="xz"

# Release file
echo $TAR $RELEASE.tar.$EXT $RELEASE/
     $TAR $RELEASE.tar.$EXT $RELEASE/

# no font package
<< COMMENT
rm -rf $RELEASE/pub-dist/VL-PGothic-Regular.ttf $RELEASE/VLGothic/

echo tar $TAR $RELEASE-nofont.tar.$EXT $RELEASE/
     tar $TAR $RELEASE-nofont.tar.$EXT $RELEASE/
COMMENT

rm -rf $RELEASE
