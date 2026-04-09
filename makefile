# -*- coding:utf-8 -*-
.PHONY: test build clean

test:
	emacs --batch -Q -L . -L test \
	  -l ert \
	  -l test/rimel-test.el \
	  -f rimel-test-run

