.PHONY: help check build test test-mock test-full validate clean

# Default target: show help
help:
	@echo "Google Antigravity AppImage Build System"
	@echo ""
	@echo "Available commands:"
	@echo "  make check       - Check upstream for latest Antigravity 2.x release"
	@echo "  make test        - Run local build test (validates AppDir & pipeline)"
	@echo "  make test-mock   - Run mock build test with synthetic payload (offline)"
	@echo "  make test-full   - Run full build test with live upstream download"
	@echo "  make build       - Build AppImage for the latest upstream release"
	@echo "  make validate    - Validate desktop entry, Python code, and workflow YAML"
	@echo "  make clean       - Remove build artifacts and temporary files"

# Check latest upstream version
check:
	@python3 scripts/check-version.py --check-only

# Validate desktop entry, YAML, and scripts
validate:
	@echo "Validating desktop file..."
	@if command -v desktop-file-validate >/dev/null 2>&1; then \
		desktop-file-validate assets/antigravity.desktop; \
	fi
	@echo "Validating workflow YAML..."
	@python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-appimage.yml'))"
	@echo "Validating Python scripts..."
	@python3 -m py_compile scripts/check-version.py
	@echo "Validation passed!"

# Local build test (default: dry run / mock)
test:
	@./scripts/test-local-build.sh --dry-run

# Local build test with mock payload (full packaging if appimagetool present)
test-mock:
	@./scripts/test-local-build.sh --mock

# Full local build test fetching upstream tarball
test-full:
	@./scripts/test-local-build.sh --full

# Build the latest upstream release into ./dist
build:
	@./scripts/build-appimage.sh --latest --output-dir ./dist

# Clean build artifacts
clean:
	@rm -rf dist/ build/ *.AppImage *.zsync SHA256SUMS.txt /tmp/antigravity-* 2>/dev/null || true
	@echo "Cleaned build artifacts."
