SHELL := /bin/bash

.PHONY: cutout

PET := katt

first = $(word 1, $(subst -, ,$@))
second = $(word 2, $(subst -, ,$@))

k := kubectl
ks := kubectl -n kube-system
km := kubectl -n metallb-system
kt := kubectl -n traefik
kx := kubectl -n external-secrets
kc := kubectl -n cert-manager
kld := kubectl -n linkerd

kk := kubectl -n kuma-system
kg := kubectl -n kong
kv := kubectl -n knative-serving
kd := kubectl -n external-dns

menu:
	@perl -ne 'printf("%20s: %s\n","$$1","$$2") if m{^([\w+-]+):[^#]+#\s(.+)$$}' Makefile

test: # Test manifests with kubeval
	for a in k/*/; do kustomize build $$a | kubeval --skip-kinds IngressRoute; done

tilt:
	tilt up --context kind-katt

zero:
	$(MAKE) clean

one:
	$(MAKE) setup
	$(MAKE) katt
	$(MAKE) vpn
	$(MAKE) up
	$(MAKE) site

socat:
	docker exec katt-control-plane apt-get update
	docker exec katt-control-plane apt-get install -y dnsutils lsof net-tools iputils-{ping,arping} curl socat
	docker exec katt-control-plane socat tcp4-listen:8443,reuseaddr,fork TCP:127.0.0.1:443 &
	docker exec katt-control-plane socat tcp4-listen:8000,reuseaddr,fork TCP:127.0.0.1:80 &

vpn:
	docker exec katt-control-plane apt-get update
	docker exec katt-control-plane apt-get install -y gnupg2
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/groovy.gpg | docker exec -i katt-control-plane apt-key add -
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/groovy.list | docker exec -i katt-control-plane tee /etc/apt/sources.list.d/tailscale.list
	curl -fsSL https://install.zerotier.com | docker exec -i katt-control-plane bash
	docker exec -i katt-control-plane apt-get install -y tailscale || true
	docker exec -i katt-control-plane systemctl start tailscaled

setup: # Setup requirements for katt
	asdf install
	$(MAKE) network

network:
	sudo mount bpffs /sys/fs/bpf -t bpf
	if test -z "$$(docker network inspect kind 2>/dev/null | jq -r '.[].IPAM.Config[].Subnet')"; then \
		docker network create --subnet 172.25.1.0/24 --ip-range 172.25.1.0/24 \
			-o com.docker.network.bridge.enable_ip_masquerade=true \
			-o com.docker.network.bridge.enable_icc=true \
			-o com.docker.network.bridge.name=kind0 \
			kind; fi

katt nice mean: # Bring up a kind cluster
	$(MAKE) clean-$@
	cue export --out yaml c/site.cue c/$@.cue c/kind.cue | kind create cluster --name $@ --config -
	$(MAKE) registry
	$(MAKE) use-$@
	$(MAKE) cilium wait
	$(MAKE) cert-manager wait
	$(MAKE) linkerd wait
	env PET=$@ $(MAKE) extras-$@
	$(k) get --all-namespaces pods
	$(k) cluster-info

extras-%:
	$(MAKE) traefik wait
	$(MAKE) metal wait
	$(MAKE) hubble wait

use-%:
	$(k) config use-context kind-$(second)
	$(k) get nodes

clean: # Teardown
	$(MAKE) clean-katt
	$(MAKE) clean-nice
	$(MAKE) clean-mean
	$(MAKE) down
	docker network rm kind
	sudo systemctl restart docker

clean-%:
	-kind delete cluster --name $(second)

wait:
	sleep 5
	while [[ "$$($(k) get -o json --all-namespaces pods | jq -r '(.items//[])[].status | "\(.phase) \((.containerStatuses//[])[].ready)"' | sort -u | grep -v 'Succeeded false')" != "Running true" ]]; do \
		$(k) get --all-namespaces pods; sleep 5; echo; done

cilium:
	helm install cilium cilium/cilium --version 1.9.3 \
		--namespace kube-system \
		--set nodeinit.enabled=true \
		--set kubeProxyReplacement=partial \
		--set hostServices.enabled=false \
		--set externalIPs.enabled=true \
		--set nodePort.enabled=true \
		--set hostPort.enabled=true \
		--set bpf.masquerade=false \
		--set image.pullPolicy=IfNotPresent \
		--set ipam.mode=kubernetes
	while $(ks) get nodes | grep NotReady; do \
		sleep 5; done

linkerd:
	linkerd check --pre
	linkerd install | perl -pe 's{enforced-host=.*}{enforced-host=}' | $(k) apply -f -
	linkerd check
	$(kld) apply -f k/linkerd/ingress.yaml

metal:
	cue export --out yaml c/site.cue c/$(PET).cue c/metal.cue > k/metal/config/config
	kustomize build k/metal | $(km) apply -f -

traefik:
	cue export --out yaml c/site.cue c/$(PET).cue c/traefik.cue > k/traefik/config/traefik.yaml
	$(kt) apply -f k/traefik/crds
	kustomize build k/traefik | $(kt) apply -f -

external-secrets:
	$(kx) apply -f k/external-secrets/crds
	kustomize build --enable_alpha_plugins k/external-secrets | $(kx) apply -f -

kubernetes-dashboard:
	kustomize build --enable_alpha_plugins k/kubernetes-dashboard | $(k) apply -f -

cert-manager:
	kustomize build --enable_alpha_plugins k/cert-manager | $(k) apply -f -

hubble:
	kustomize build k/hubble | $(ks) apply -f -

home:
	kustomize build --enable_alpha_plugins k/home | $(k) apply -f -

site:
	kustomize build k/site | $(k) apply -f -

zerotier:
	kustomize build --enable_alpha_plugins k/zerotier/$(PET) | $(k) apply -f -

up: # Bring up homd
	docker-compose up -d --remove-orphans

down: # Bring down home
	docker-compose down --remove-orphans

recreate: # Recreate home container
	$(MAKE) down
	$(MAKE) up

recycle: # Recycle home container
	$(MAKE) pull
	$(MAKE) recreate

pull:
	docker-compose pull

logs:
	docker-compose logs -f

registry: # Run a local registry
	k apply -f k/registry.yaml

kong:
	$(k) apply -f https://bit.ly/k4k8s

knative:
	kubectl apply --filename https://github.com/knative/serving/releases/download/v0.16.0/serving-crds.yaml
	kubectl apply --filename https://github.com/knative/serving/releases/download/v0.16.0/serving-core.yaml
	kubectl patch configmap/config-network --namespace knative-serving --type merge --patch '{"data":{"ingress.class":"kong"}}'
	kubectl patch configmap/config-domain --namespace knative-serving --type merge --patch '{"data":{"$(PET).defn.jp":""}}'

external-dns:
	kustomize build --enable_alpha_plugins k/external-dns | $(k) apply -f -

kuma:
	kumactl install control-plane --mode=remote --zone=$(PET) --kds-global-address grpcs://192.168.195.116:5685 | $(k) apply -f -
	$(MAKE) wait
	kumactl install dns | $(k) apply -f -
	sleep 10; kumactl install ingress | $(k) apply -f - || (sleep 30; kumactl install ingress | $(k) apply -f -)
	$(MAKE) wait
	$(MAKE) kuma-inner

kuma-inner:
	echo "---" | yq -y --arg pet "$(PET)" --arg address "$(shell pass katt/$(PET)/ip)" \
	'{type: "Zone", name: $$pet, ingress: { address: "\($$address):10001" }}' \
		| kumactl apply -f -

