# Passthrough vers le Makefile racine. Permet `make <cible>` depuis ce dossier.
ROOT := $(shell git rev-parse --show-toplevel)

.DEFAULT_GOAL := help

%:
	@$(MAKE) -C $(ROOT) $@
