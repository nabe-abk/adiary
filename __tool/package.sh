#!/bin/sh

#-----------------------------------------------------------
# get Version
#-----------------------------------------------------------
VERSION=`head -20 lib/SatsukiApp/adiary.pm | grep "\\$OUTVERSION" | sed "s/[^=]*=[^\"']*\([\"']\)\([^\"']*\)\1.*/\2/"`

if [ "$VERSION" = "" -o "`echo $VERSION | grep ' '`" ]
then
	echo "Version detection failed: $VERSION"
	exit
fi
RELEASE=adiary-$VERSION

#-----------------------------------------------------------
# RELEASE files check
#-----------------------------------------------------------
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
