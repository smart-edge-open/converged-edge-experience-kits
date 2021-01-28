# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

# Provide `ANSIBLE_LINT_VERBOSITY=-v make ansible-lint` to enable verbose output.
# Switch required to verify CI.
ANSIBLE_LINT_VERBOSITY?=

install-dependencies:
	pip install --user pipenv
	pipenv sync

ansible-lint:
	pipenv run ansible-lint *.yml --parseable-severity  -c .ansible-lint $(ANSIBLE_LINT_VERBOSITY)
