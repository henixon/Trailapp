.PHONY: generate open clean check

generate:
	xcodegen generate

open: generate
	xed .

clean:
	rm -rf *.xcodeproj

check:
	@command -v xcodegen >/dev/null || (echo "xcodegen not found: brew install xcodegen" && exit 1)
	@echo "xcodegen OK"
