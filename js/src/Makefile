#
# Makefile for adiary.min.js
#

COMPRESSOR = uglifyjs
OPTIONS    = -c -m --comments '/^!!/' --source-map includeSources,filename

OUTPUT	   = ../adiary.min.js
MAP_FILE   = ../adiary.min.map
HTML       = ../adiary-js-load.html

FILES = 00_comment.js		\
	jquery-3.4.1.js		\
	01_global.js		\
	10_jquery-ext.js	\
	20_init.js		\
	30_css.js		\
	40_dom.js		\
	45_dom-special.js	\
	50_skeleton.js		\
	60_design-module.js	\
	80_subroutines.js	\
	81_dialog.js		\
	82_ajax.js		\
	83_popup.js		\
	90_PrefixStorage.js	\
	92_adiary-ui.js		\
	99_run_init.js		\
	lightbox.js

all:  $(OUTPUT)
html: $(HTML)

$(OUTPUT): $(FILES) Makefile
	$(COMPRESSOR) $(OPTIONS) $(FILES) -o $(OUTPUT)
	mv $(OUTPUT).map $(MAP_FILE)

$(HTML): $(FILES) Makefile
	echo -n>$(HTML); \
	for file in $(FILES); do \
		echo "<script defer src=\"<@argv#0 || v.script_dir>src/$$file?<@get_lastmodified(v.script_dir . 'src/$$file')>\"></script>" >>$(HTML); \
	done
