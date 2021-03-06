accessLog: {}

log: {
	level:  "INFO"
	format: "json"
}

api: dashboard: "true"

ping: "true"

providers: kubernetesCRD: {}

providers: kubernetesIngress: {
	ingressClass: "traefik"
	ingressEndpoint:
		publishedService: "traefik/traefik"
}

entryPoints: {
	traefik: address:   ":9000/tcp"
	websecure: address: ":8443/tcp"
	pubsecure: address: ":9443/tcp"
}
