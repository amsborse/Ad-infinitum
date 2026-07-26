# Ad-infinitum — out-of-tree F2FS kernel module build wrapper
#
# Usage:
#   make                  Build f2fs.ko against running kernel
#   make KERNEL_SRC=/path/to/linux-4.1.8  Build against specific tree
#   make clean            Remove build artifacts
#   make install-kernel KERNEL_TREE=/path/to/linux  Copy sources into tree

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
MODULE_DIR := $(CURDIR)/fs/f2fs

.PHONY: all clean install install-kernel help docs docs-docker verify lab-docker

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) modules

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) clean

install: all
	$(MAKE) -C $(KERNEL_SRC) M=$(MODULE_DIR) modules_install
	depmod -a

install-kernel:
	@test -n "$(KERNEL_TREE)" || (echo "Usage: make install-kernel KERNEL_TREE=/path/to/linux"; exit 1)
	./scripts/install-to-kernel.sh "$(KERNEL_TREE)"

help:
	@echo "Ad-infinitum F2FS module build targets:"
	@echo "  make                         Build out-of-tree module (f2fs.ko)"
	@echo "  make clean                   Remove build artifacts"
	@echo "  make install                 Install module to running kernel"
	@echo "  make install-kernel KERNEL_TREE=...  Copy fs/f2fs into kernel source"
	@echo ""
	@echo "Local verification (any OS):"
	@echo "  make docs                    Serve landing page at http://localhost:8080"
	@echo "  make docs-docker             Same, via Docker nginx"
	@echo "  make verify                  Run local structure checks"
	@echo "  make lab-docker              F2FS smoke test in privileged container"
	@echo ""
	@echo "Variables:"
	@echo "  KERNEL_SRC   Kernel build dir (default: /lib/modules/\$$(uname -r)/build)"
	@echo "  KERNEL_TREE  Full Linux source tree for install-kernel"

docs:
	@echo "Serving docs at http://localhost:8080 (Ctrl+C to stop)"
	@cd docs && python3 -m http.server 8080 2>/dev/null || cd docs && python -m http.server 8080

docs-docker:
	docker compose up --build docs

verify:
	@if [ -f scripts/verify-local.sh ]; then bash scripts/verify-local.sh; \
	else powershell -File scripts/verify-local.ps1; fi

lab-docker:
	docker compose --profile lab run --rm lab
