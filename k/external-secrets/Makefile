menu:
	@perl -ne 'printf("%30s: %s\n","$$1","$$2") if m{^([\w+-\.]+):[^#]+#\s(.+)$$}' Makefile

vendor: # Add external-secrets repo
	helm repo add external-secrets https://external-secrets.github.io/kubernetes-external-secrets/ --force-update
	helm repo update
	helm template external-secrets/kubernetes-external-secrets | sed 's#RELEASE-NAME-kubernetes-external-secrets#external-secrets#g' > external-secrets.yaml.vendor
	rm -rf crds kubernetes-external-secrets
	git clone https://github.com/external-secrets/kubernetes-external-secrets
	mv kubernetes-external-secrets/charts/kubernetes-external-secrets/crds .
	rm -rf kubernetes-external-secrets

