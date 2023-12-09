KIND_VERSION = v0.20.0
KUBECTL_VERSION = v1.28.4
KIND_NODE_IMAGE = kindest/node:v1.28.0
ISTIO_VERSION = 1.17.2

ifeq ($(shell uname -s),Linux)
DL_OS = linux
DL_OSALT = linux
else
DL_OS = darwin
DL_OSALT = osx
endif

ifeq ($(shell uname -p),x86_64)
DL_ARCH = amd64
else ifeq ($(shell uname -p),i386)
DL_ARCH = amd64
else
DL_ARCH = arm64
endif

BIN_DIR := $(shell pwd)/bin

KUBECTL := $(BIN_DIR)/kubectl
KIND := $(BIN_DIR)/kind
ISTIOCTL := $(BIN_DIR)/istioctl
KIND_CLUSTER = test
RUN_KUBECTL = $(KUBECTL) --context kind-$(KIND_CLUSTER)

setup: $(KIND) $(KUBECTL) $(ISTIOCTL)
	$(KIND) create cluster --name $(KIND_CLUSTER) --image=$(KIND_NODE_IMAGE)
	$(ISTIOCTL) install -y --set profile=demo \
		--set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
	while true; do \
		if $(ISTIOCTL) verify-install >/dev/null; then break; fi; \
		sleep 1; \
	done

	$(MAKE) build
	$(MAKE) docker-push
	-$(MAKE) generate-certs

	$(RUN_KUBECTL) label namespace default istio-injection=enabled --overwrite
	$(RUN_KUBECTL) apply -f ./manifests
	$(MAKE) apply-sleep

generate-certs:
	openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=slack.com' -keyout slack.com.key -out slack.com.crt

	openssl req -out my-nginx.mock.svc.cluster.local.csr -newkey rsa:2048 -nodes -keyout my-nginx.mock.svc.cluster.local.key -subj "/CN=my-nginx.mock.svc.cluster.local/O=some organization"
	openssl x509 -req -sha256 -days 365 -CA slack.com.crt -CAkey slack.com.key -set_serial 0 -in my-nginx.mock.svc.cluster.local.csr -out my-nginx.mock.svc.cluster.local.crt

	openssl req -out client.slack.com.csr -newkey rsa:2048 -nodes -keyout client.slack.com.key -subj "/CN=client.slack.com/O=client organization"
	openssl x509 -req -sha256 -days 365 -CA slack.com.crt -CAkey slack.com.key -set_serial 1 -in client.slack.com.csr -out client.slack.com.crt

	$(KUBECTL) create -n mock secret tls nginx-server-certs --key my-nginx.mock.svc.cluster.local.key --cert my-nginx.mock.svc.cluster.local.crt
	$(KUBECTL) create -n mock secret generic nginx-ca-certs --from-file=slack.com.crt
	$(KUBECTL) create secret -n istio-system generic client-credential --from-file=tls.key=client.slack.com.key \
  --from-file=tls.crt=client.slack.com.crt --from-file=ca.crt=slack.com.crt
	$(KUBECTL) create configmap nginx-configmap -n mock --from-file=nginx.conf=./nginx.conf

try:
	$(RUN_KUBECTL) exec -it $(shell $(RUN_KUBECTL) get pod -l app=sleep -o jsonpath='{.items[0].metadata.name}') -- curl -sS http://foo.default.svc:8080
	$(RUN_KUBECTL) logs -l app=foo --tail=1

stop:
	$(KIND) delete cluster --name $(KIND_CLUSTER)

build:
	CGO_ENABLED=0 go build -o bin/foo -gcflags=all="-N -l" main.go
	docker build -t foo:test . --build-arg SERVICE=foo
	CGO_ENABLED=0 go build -o bin/mock -gcflags=all="-N -l" main.go
	docker build -t mock:test . --build-arg SERVICE=mock

reploy:
	$(MAKE) build
	$(MAKE) docker-push
	$(MAKE) restart-deployment

apply-sleep: $(KUBECTL) $(ISTIOCTL)
	$(RUN_KUBECTL) apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/sleep/sleep.yaml

docker-push: $(KIND)
	$(KIND) load docker-image --name $(KIND_CLUSTER) foo:test
	$(KIND) load docker-image --name $(KIND_CLUSTER) mock:test

restart-deployment: $(KUBECTL)
	$(KUBECTL) rollout restart deployment foo
	$(KUBECTL) rollout restart deployment mock -n mock

$(KUBECTL):
	mkdir -p $(BIN_DIR)
	curl -sSLf -o $@ "https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(DL_OS)/$(DL_ARCH)/kubectl"
	chmod a+x $@

$(KIND):
	mkdir -p $(BIN_DIR)
	curl -sSLf -o $@ https://github.com/kubernetes-sigs/kind/releases/download/$(KIND_VERSION)/kind-$(DL_OS)-$(DL_ARCH)
	chmod a+x $@

$(ISTIOCTL):
	mkdir -p $(BIN_DIR)
	curl -sSLf https://github.com/istio/istio/releases/download/$(ISTIO_VERSION)/istioctl-$(ISTIO_VERSION)-$(DL_OSALT)-$(DL_ARCH).tar.gz \
	| tar -C $(BIN_DIR) -xzf -

clean:
	rm *.crt
	rm *.key
	rm *.csr
