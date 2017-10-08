###########################################################
# This file builds the asdf documentation.
###########################################################

# tags
LATEST:=$(git describe --abbrev=0 --tags | tr -d v)

# binaries
DMD=dmd
RDMD=rdmd
DDOC=$(DMD) -w -c -o- -version=StdDdoc

# folders
DOC_OUTPUT_DIR=web
DOC_SOURCE_DIR=doc
GENERATED=.generated
ASDF_DIR=source
DLANGORG_DIR=$(DOC_SOURCE_DIR)/dlang.org
ARTWORK_DIR=$(DOC_SOURCE_DIR)/artwork

###########################################################
# setup packages
##########################################################

# Packages in asdf. Just mention the package name here. The contents of package
# xy/zz is in variable PACKAGE_xy_zz. This allows automation in iterating
# packages and their modules.
ASDF_PACKAGES = asdf

PACKAGE_asdf = asdf jsonparser serialization transform package

MOD_EXCLUDES= $(addprefix --ex=asdf., utility jsonbuffer outputarray simd)

###########################################################
# Setup macros + generate dynamic info needed
###########################################################

all: html

DLANGORG_MACROS=$(addprefix $(DLANGORG_DIR)/, macros html dlang.org)
STDDOC=$(addsuffix .ddoc, ${DLANGORG_MACROS} ${GENERATED}/${LATEST} $(DLANGORG_DIR)/std $(DOC_SOURCE_DIR)/custom ${GENERATED}/asdf) $(NODATETIME)

${GENERATED}/${LATEST}.ddoc :
	mkdir -p $(dir $@)
	echo "LATEST=${LATEST}" >$@

${GENERATED}/asdf.ddoc : $(DOC_SOURCE_DIR)/gen_modlist.d $(ASDF_DIR)
	mkdir -p $(dir $@)
	$(RDMD) $< $(ASDF_DIR) $(MOD_EXCLUDES) >$@

###########################################################
# Makefile bootstrapping
# It's mostly about the conversion from asdf.foo -> asdf_foo
###########################################################

# Given one or more packages, returns the modules they contain
P2MODULES=$(foreach P,$1,$(addprefix $P/,$(PACKAGE_$(subst /,_,$P))))
ASDF_MODULES=$(call P2MODULES,$(ASDF_PACKAGES))
SRC_DOCUMENTABLES = $(addsuffix .d,$(ASDF_MODULES))

# D file to html, e.g. asdf/combinatorics -> asdf_combinatorics.html
# But "package.d" is special cased: std/range/package.d -> std_range.html
D2HTML=$(foreach p,$1,$(if $(subst package.d,,$(notdir $p)),$(subst /,_,$(subst .d,.html,$p)),$(subst /,_,$(subst /package.d,.html,$p))))

HTMLS=$(addprefix $(DOC_OUTPUT_DIR)/, \
	$(call D2HTML, $(SRC_DOCUMENTABLES)))

$(DOC_OUTPUT_DIR)/. :
	mkdir -p $@

# everything except index.d needs a source path
ADDSOURCE=$(if $(subst index.d,,$1),$(ASDF_DIR)/$1,$1)

# For each module, define a rule e.g.:
# ../web/phobos/std_conv.html : std/conv.d $(STDDOC) ; ...
$(foreach p,$(SRC_DOCUMENTABLES),$(eval \
$(DOC_OUTPUT_DIR)/$(call D2HTML,$p) : $(call ADDSOURCE,$p) $(STDDOC) ;\
  $(DDOC) $(STDDOC) -I$(ASDF_DIR) -Df$$@ $$<))

###########################################################
# Setup all other resources needed by dlang.org
###########################################################

IMAGES=favicon.ico

JAVASCRIPT=$(addsuffix .js, $(addprefix js/, \
	dlang ddox listanchors run run-main-website jquery-1.7.2.min))

STYLES=$(addsuffix .css, $(addprefix css/, \
	style print custom ))

ALL_FILES = $(addprefix $(DOC_OUTPUT_DIR)/, \
	$(STYLES) $(IMAGES) $(JAVASCRIPT))

$(DOC_OUTPUT_DIR)/css/custom.css: $(DOC_SOURCE_DIR)/custom.css
	@mkdir -p $(dir $@)
	cp $< $@

$(DOC_OUTPUT_DIR)/% : $(DLANGORG_DIR)/%
	@mkdir -p $(dir $@)
	cp $< $@

html : $(DOC_OUTPUT_DIR)/. $(HTMLS) $(ALL_FILES)

clean:
	rm -rf $(DOC_OUTPUT_DIR)
	rm -rf $(GENERATED)

# prints the listed modules and sources
debug:
	@echo $(SRC_DOCUMENTABLES)
	@echo $(STDDOC)
