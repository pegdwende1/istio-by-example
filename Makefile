# Istio Teaching Manifests - Makefile
#
# WARNING: These manifests use example domains, certs, and service accounts.
# Do NOT apply to a real cluster without reviewing and customizing values.
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - istioctl installed
#   - Namespace 'shopk8s' must exist

NAMESPACE := shopk8s

.PHONY: help namespace apply-core apply-observability apply-egress apply-advanced apply-chaos apply-vm apply-all delete-all validate status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

namespace: ## Create the shopk8s namespace with Istio injection
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite

apply-core: namespace ## Apply core Istio resources (gateway, routing, auth, mTLS)
	kubectl apply -f core/ -n $(NAMESPACE)

apply-observability: namespace ## Apply telemetry configuration
	kubectl apply -f observability/ -n $(NAMESPACE)

apply-egress: namespace ## Apply egress control (ServiceEntry + egress gateway)
	kubectl apply -f egress/ -n $(NAMESPACE)

apply-advanced: namespace ## Apply advanced resources (sidecar, envoy filter, rate limiting, etc.)
	kubectl apply -f advanced/ -n $(NAMESPACE)

apply-chaos: namespace ## Apply chaos testing resources (fault injection, mirroring)
	kubectl apply -f chaos/ -n $(NAMESPACE)

apply-vm: namespace ## Apply VM workload resources
	kubectl apply -f vm/ -n $(NAMESPACE)

apply-all: apply-core apply-observability apply-egress apply-advanced apply-vm ## Apply everything (except chaos)
	@echo "All resources applied. Use 'make apply-chaos' separately for fault injection."

delete-all: ## Delete all Istio resources from shopk8s
	@echo "Deleting all Istio resources from $(NAMESPACE)..."
	-kubectl delete -f core/ -n $(NAMESPACE) --ignore-not-found
	-kubectl delete -f observability/ -n $(NAMESPACE) --ignore-not-found
	-kubectl delete -f egress/ -n $(NAMESPACE) --ignore-not-found
	-kubectl delete -f advanced/ -n $(NAMESPACE) --ignore-not-found
	-kubectl delete -f chaos/ -n $(NAMESPACE) --ignore-not-found
	-kubectl delete -f vm/ -n $(NAMESPACE) --ignore-not-found

validate: ## Run istioctl analyze against the manifests
	istioctl analyze core/ observability/ egress/ advanced/ vm/

status: ## Show proxy sync status and mesh health
	@echo "=== Proxy Status ==="
	istioctl proxy-status
	@echo ""
	@echo "=== Mesh Analysis ==="
	istioctl analyze -n $(NAMESPACE)
