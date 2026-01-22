# WSL-specific overrides for EDA playground
# Adapted from eda-labs/codespaces

# KPT configuration with retry logic
KPT_RETRY ?= 5
KPT_RECONCILE_TIMEOUT ?= 3m
KPT_LIVE_APPLY_ARGS := --reconcile-timeout=$(KPT_RECONCILE_TIMEOUT)

# Override INSTALL_KPT_PACKAGE with retry logic for more resilience
define INSTALL_KPT_PACKAGE
	@printf "\033[34mApplying package $(1)...\033[0m\n"
	@if [ ! -f "$(1)/resourcegroup.yaml" ]; then \
		$(KPT) live init $(1) 2>/dev/null || true; \
	fi
	@attempt=1; \
	while [ $$attempt -le $(KPT_RETRY) ]; do \
		if $(KPT) live apply $(1) $(KPT_LIVE_APPLY_ARGS); then \
			printf "\033[32mPackage $(1) applied successfully\033[0m\n"; \
			break; \
		else \
			printf "\033[33mAttempt $$attempt/$(KPT_RETRY) failed, retrying in 2s...\033[0m\n"; \
			sleep 2; \
			attempt=$$((attempt + 1)); \
		fi; \
	done; \
	if [ $$attempt -gt $(KPT_RETRY) ]; then \
		printf "\033[31mFailed to apply package $(1) after $(KPT_RETRY) attempts\033[0m\n"; \
		exit 1; \
	fi
endef

# Patch EngineConfig with WSL-specific settings
.PHONY: patch-wsl-engineconfig
patch-wsl-engineconfig:
	@if [ -f "$(PLAYGROUND_DIR)/engine-config-patch.yaml" ]; then \
		printf "\033[34mPatching EngineConfig with WSL settings...\033[0m\n"; \
		$(YQ) eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
			$(EDA_CORE_DIR)/eda-kpt-base/engine-config/EngineConfig.yaml \
			$(PLAYGROUND_DIR)/engine-config-patch.yaml > /tmp/ec-patched.yaml && \
		mv /tmp/ec-patched.yaml $(EDA_CORE_DIR)/eda-kpt-base/engine-config/EngineConfig.yaml; \
		printf "\033[32mEngineConfig patched\033[0m\n"; \
	fi

# Inject Zscaler/corporate CA certificates into EDA trust bundles
# Uses kubectl patch to add the CA source to existing Bundles
.PHONY: inject-zscaler-ca
inject-zscaler-ca: | $(KUBECTL)
	@printf "\033[34mInjecting corporate CA certificates into EDA trust bundles...\033[0m\n"
	@if [ -f /etc/ssl/certs/ca-certificates.crt ]; then \
		$(KUBECTL) create configmap zscaler-external-ca -n $(EDA_CORE_NAMESPACE) \
			--from-file=ca-bundle.pem=/etc/ssl/certs/ca-certificates.crt \
			--dry-run=client -o yaml | $(KUBECTL) apply -f - ; \
		for bundle in eda-internal-trust-bundle eda-api-trust-bundle eda-node-trust-bundle; do \
			if $(KUBECTL) get bundle $$bundle >/dev/null 2>&1; then \
				if ! $(KUBECTL) get bundle $$bundle -o jsonpath='{.spec.sources[*].configMap.name}' | grep -q zscaler-external-ca; then \
					$(KUBECTL) patch bundle $$bundle --type='json' \
						-p='[{"op": "add", "path": "/spec/sources/-", "value": {"configMap": {"name": "zscaler-external-ca", "key": "ca-bundle.pem"}}}]' && \
					printf "\033[32mPatched bundle $$bundle\033[0m\n"; \
				else \
					printf "\033[33mBundle $$bundle already has zscaler-external-ca source\033[0m\n"; \
				fi; \
			else \
				printf "\033[33mBundle $$bundle not found, skipping\033[0m\n"; \
			fi; \
		done; \
		printf "\033[32mCorporate CA certificates injected into trust bundles.\033[0m\n"; \
	else \
		printf "\033[33mNo CA bundle found at /etc/ssl/certs/ca-certificates.crt, skipping.\033[0m\n"; \
	fi

# Hook inject-zscaler-ca to run BEFORE eda-is-core-ready checks pods
# This ensures pods get the CA certs in their trust bundles before they're verified
# Order: eda-install-core (creates Bundles) -> inject-zscaler-ca -> eda-is-core-ready (waits for pods)
eda-is-core-ready: inject-zscaler-ca

# Make configure-try-eda-params depend on WSL engine config patch
configure-try-eda-params: patch-wsl-engineconfig
