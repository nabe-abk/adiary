#!/bin/sh


if [ "$1" != '' ]
then
	EXCLUSIVE_LIST=$1
else
	EXCLUSIVE_LIST=__tool/norelease.list
fi

#-----------------------------------------------------------
# get Version
#-----------------------------------------------------------
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

#-----------------------------------------------------------
# set variables
#-----------------------------------------------------------
RELEASE=adiary-$VERSION

BASE="
	adiary.cgi
	adiary.fcgi
	adiary.mod.cgi
	adiary.speedy.cgi
	adiary.env.cgi.sample
	adiary.conf.cgi.sample
	README.md
	CHANGES.txt
	index.html
	dot.htaccess
"
EXE=adiary.exe

#-----------------------------------------------------------
# make release directory
#-----------------------------------------------------------
if [ ! -e $RELEASE ]
then
	mkdir $RELEASE
fi

#-----------------------------------------------------------
# copy files to release directory
#-----------------------------------------------------------
cp -Rp $CPFLAGS skel pub-dist info js lib theme $RELEASE/

cp -Rp $CPFLAGS $BASE $RELEASE/

cp -Rp $CPFLAGS plugin $RELEASE/
rm -rf $RELEASE/plugin/\@*

cp -p $EXE $RELEASE/

#-----------------------------------------------------------
# make other directory
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
# remove exclusive files
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

#-----------------------------------------------------------
echo "Use exclusive list : $EXCLUSIVE_LIST"
