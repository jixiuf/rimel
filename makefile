# -*- coding:utf-8 -*-

PREFIX ?= $(CURDIR)
UNAME_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')
EMACS   := $(shell sh -c 'which emacs')

SUFFIX = .so
LIBRIME = -lrime

## MINGW
ifneq (,$(findstring MINGW,$(UNAME_S)))
	SUFFIX = .dll
	LIBRIME = -llibrime
endif

ifdef MODULE_FILE_SUFFIX
	SUFFIX = $(MODULE_FILE_SUFFIX)
endif

VERSION = 1.00
CC = gcc
LDFLAGS += -shared
SRC = src
SOURCES = $(wildcard $(SRC)/*.c)
OBJS = $(patsubst %.c, %.o, $(SOURCES))
TARGET = $(SRC)/librimel-core$(SUFFIX)
CFLAGS += -fPIC -O2 -Wall -DHAVE_RIME_API

ifndef EMACS_MAJOR_VERSION
	EMACS_MAJOR_VERSION := $(shell emacs --batch --eval '(princ emacs-major-version)' 2>/dev/null || echo 26)
endif

CFLAGS += -I emacs-module/$(EMACS_MAJOR_VERSION)
ifdef EMACS_PLUS_PATH
       CFLAGS += -I ${EMACS_PLUS_PATH}
endif

ifdef RIME_PATH
	CFLAGS += -I ${RIME_PATH}/src/
	LDFLAGS += -L ${RIME_PATH}/build/lib/ -L ${RIME_PATH}/build/lib/Release/
	LDFLAGS += -Wl,-rpath,${RIME_PATH}/build/lib/
	LDFLAGS += -Wl,-rpath,${RIME_PATH}/build/lib/Release
	LDFLAGS += $(LIBRIME)
else
	LDFLAGS += $(LIBRIME)
endif


.PHONY:everything objs clean

all:$(TARGET)

objs:$(OBJS)

clean:
	rm -rf $(OBJS) $(TARGET) build test/test_librimel *.elc test/*.elc

$(TARGET):$(OBJS)
	rm -rf build
	$(CC) $(OBJS) $(LDFLAGS) $(LIBS) -o $@

# Run pure Elisp unit tests (no librime needed, mocked C module)
.PHONY: test-rimel
test-rimel:
	emacs --batch -Q -L . -L test \
	  -l ert \
	  -l test/rimel-test.el \
	  -f rimel-test-run

# Run integration tests (requires compiled C module + librime)
.PHONY: test-integration
test-integration: $(TARGET)
	emacs --batch -Q -L . -L test \
	  -l ert \
	  -l test/librimel-test.el \
	  -f librimel-test-run

# Run C unit tests (standalone, no Emacs needed)
.PHONY: test-c
test-c: test/test_librimel
	./test/test_librimel

test/test_librimel: test/test_librimel.c
	$(CC) -O2 -Wall -o $@ $<

# Run all tests
.PHONY: test
test: test test-c test-integration

librimel-build:
	make -f Makefile-librimel-build
install: ${TARGET}
	install -p -m 755 ${TARGET} $(PREFIX)/lib


