#
# Makefile for adiary.min.js
#

# You can set these variables from the command line.
COMPRESSOR = uglifyjs
OPTIONS    = -c -m --comments '/^!/' --source-map includeSources

OUTPUT	   = ../adiary.min.js
MAP_FILE   = ../adiary.min.map
HTML       = ../adiary-js-load.html

FILES = \
	jquery-3.4.1.js		\
	01_global-variables.js	\
	10_jquery-ext.js	\
	20_init.js		\
	30_css.js		\
	40_dom-class.js		\
	50_skeleton.js		\
	60_design-module.js	\
	80_subroutines.js	\
	81_dialog.js		\
	82_ajax.js		\
	90_PrefixStorage.js	\
	91_jquery-storage.js	\
	lightbox.js

all:  $(OUTPUT)
html: $(HTML)

$(OUTPUT): $(FILES) Makefile
	$(COMPRESSOR) $(OPTIONS) $(FILES) -o $(OUTPUT)
	mv $(OUTPUT).map $(MAP_FILE)

$(HTML): $(FILES) Makefile
	echo -n>$(HTML); \
	for file in $(FILES); do \
		echo "<script defer src=\"<@Basepath><@v.script_dir>src/$$file?<@get_lastmodified(v.script_dir . 'src/$$file')>\"></script>" >>$(HTML); \
	done
