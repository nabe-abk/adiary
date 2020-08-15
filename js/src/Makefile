#
# Makefile
#
NAME       = adiary
OUT_DIR    = ..

COMPRESSOR = terser
OPTIONS    = -c -m --comments '/^!!/' --source-map "includeSources,filename,url='$(NAME).min.map',base='src/'"

OUTPUT	   = $(OUT_DIR)/$(NAME).min.js
MAP_FILE   = $(OUT_DIR)/$(NAME).min.map
HTML       = $(OUT_DIR)/$(NAME)-js-load.html

FILES = 00u_comment.js		\
	jquery-3.4.1.js		\
	01u_startup.js		\
	10_global-ext.js	\
	11_jquery-ext.js	\
	20_PrefixStorage.js	\
	21_adiary-ui.js		\
	30_init.js		\
	40_dom.js		\
	45_dom-special.js	\
	50_subroutines.js	\
	60_dialog.js		\
	61_ajax.js		\
	62_popup.js		\
	70u_css.js		\
	71u_dom.js		\
	72u_skeleton.js		\
	73u_design-module.js	\
	80u_other.js		\
	99_run_init.js		\
	lightbox.js

all:  $(OUTPUT) $(HTML)
html: $(HTML)

$(OUTPUT): $(FILES) Makefile
	$(COMPRESSOR) $(OPTIONS) $(FILES) -o $(OUTPUT)
	mv $(OUTPUT).map $(MAP_FILE)

$(HTML): Makefile
	echo -n>$(HTML); \
	for file in $(FILES); do \
		echo "<script defer src=\"<@Basepath><@v.script_dir>src/$$file?<@get_lastmodified(v.script_dir . 'src/$$file')>\"></script>" >>$(HTML); \
	done
