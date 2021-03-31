# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

# Provide `ANSIBLE_LINT_VERBOSITY=-v make ansible-lint` to enable verbose output.
# Switch required to verify CI.
ANSIBLE_LINT_ARGS?=
PIPENV_INSTALL_ARGS?=--user
PIPENV_VERSION?=2020.11.15

install-dependencies:
	pip install $(PIPENV_INSTALL_ARGS) pipenv==$(PIPENV_VERSION)
	pipenv sync

lint: ansible-lint pylint shellcheck

ansible-lint:
	@pipenv run ansible-lint --version || (echo "pipenv is required, please run 'make install-dependencies'"; exit 1)
	pipenv run ansible-lint network_edge*.yml single_node_network_edge.yml --parseable-severity  -c .ansible-lint $(ANSIBLE_LINT_VERBOSITY)

pylint:
	@pipenv run pylint --version || (echo "pipenv is required, please run 'make install-dependencies'"; exit 1)
	find . -type f -name "*.py" | xargs pipenv run pylint

shellcheck:
	@shellcheck --version || (echo "shellcheck is required, please install it from https://github.com/koalaman/shellcheck/releases/download/v0.7.1/shellcheck-v0.7.1.linux.x86_64.tar.xz"; exit 1)
	find . -type f -name "*.sh" | xargs shellcheck
