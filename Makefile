.PHONY: default install test gate bump setup clean

default: test

install:
	@./tools/install

test: gate

gate:
	@./tools/gate

bump:
	@./tools/bump

setup:
	@./tools/setup_ruby_dev

clean:
	@./latex_it -C
