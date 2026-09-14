.PHONY: all install test audit check gate bundle bump clean

all: test

install:
	@./tools/install

test:
	@./tools/gate

audit:
	@./tools/gate_audit_code

check:
	@./tools/gate --fast

gate:
	@./tools/gate --full

bundle:
	@./tools/bundle --check

bump:
	@./tools/bump
