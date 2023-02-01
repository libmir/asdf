/++
$(H2 ASDF Package)

Publicly imports $(SUBMODULE _asdf), $(SUBMODULE jsonparser), and $(SUBMODULE serialization).

Copyright: Tamedia Digital, 2016

Authors: Ilia Ki

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, _asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf;

public import asdf.asdf;
public import asdf.jsonparser;
public import asdf.serialization;
public import asdf.transform;
