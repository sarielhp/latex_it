.PHONY: all install audit gate test fast medium bump

all: install

install:
	./tools/install -v

audit:
	./tools/gate_audit_code

gate:
	./tools/gate --medium

test:
	./tools/gate --fast

fast:
	./tools/gate --fast

medium:
	./tools/gate --medium

bump:
	./tools/bump
