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
		kpt live init $(1) 2>/dev/null || true; \
	fi
	@attempt=1; \
	while [ $$attempt -le $(KPT_RETRY) ]; do \
		if kpt live apply $(1) $(KPT_LIVE_APPLY_ARGS); then \
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
		yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
			$(EDA_CORE_DIR)/eda-kpt-base/engine-config/EngineConfig.yaml \
			$(PLAYGROUND_DIR)/engine-config-patch.yaml > /tmp/ec-patched.yaml && \
		mv /tmp/ec-patched.yaml $(EDA_CORE_DIR)/eda-kpt-base/engine-config/EngineConfig.yaml; \
		printf "\033[32mEngineConfig patched\033[0m\n"; \
	fi

# Hook into try-eda configuration
.PHONY: configure-try-eda-params
configure-try-eda-params:: patch-wsl-engineconfig

# Inject Zscaler/corporate CA certificates into EDA trust bundles
# This must run AFTER eda-install-core (when Bundles exist)
.PHONY: inject-zscaler-ca
inject-zscaler-ca:
	@printf "\033[34mInjecting Zscaler CA into EDA trust bundles...\033[0m\n"
	@if [ -f /etc/ssl/certs/ca-certificates.crt ]; then \
		kubectl create configmap zscaler-external-ca -n eda-system \
			--from-file=ca-bundle.pem=/etc/ssl/certs/ca-certificates.crt \
			--dry-run=client -o yaml | kubectl apply -f -; \
		kubectl apply -f $(PLAYGROUND_DIR)/zscaler-ca-bundle-patch.yaml; \
		printf "\033[32mZscaler CA injected. Trust bundles will be updated by trust-manager.\033[0m\n"; \
	else \
		printf "\033[33mNo CA bundle found at /etc/ssl/certs/ca-certificates.crt, skipping.\033[0m\n"; \
	fi

# Hook into eda-install-core to inject certs after Bundles are created
.PHONY: eda-install-core
eda-install-core:: inject-zscaler-ca
