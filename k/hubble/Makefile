SHELL := /bin/bash

VERSION := 1.9.4

menu:
	@perl -ne 'printf("%30s: %s\n","$$1","$$2") if m{^([\w+-\.]+):[^#]+#\s(.+)$$}' Makefile

vendor: # Generate hubble
	$(MAKE) vendor.yaml

.PHONY: vendor.yaml

vendor.yaml: # Generate vendor.yaml
	rm -f vendor.yaml
	curl -sSL -o vendor.yaml https://raw.githubusercontent.com/cilium/cilium/v$(VERSION)/install/kubernetes/quick-hubble-install.yaml
