# ---------- Project settings ----------
APP       ?= em
CC        ?= cc

# Ignore ambient APP from shell environment. Use APP=... on the
# make command line for intentional overrides.
ifeq ($(origin APP), environment)
APP       := em
endif
ifeq ($(origin APP), environment override)
APP       := em
endif
ifneq ($(findstring /,$(APP)),)
$(error APP must not contain '/': $(APP))
endif
ifneq ($(words $(APP)),1)
$(error APP must not contain whitespace: $(APP))
endif
ifeq ($(strip $(APP)),)
$(error APP must not be empty)
endif
ifneq ($(filter . ..,$(APP)),)
$(error APP must not be '.' or '..': $(APP))
endif

SRC_DIRS  ?= src
BUILD_DIR ?= build
OBJ_DIR   := $(BUILD_DIR)/obj
BIN_DIR   := $(BUILD_DIR)/bin
TARGET    := $(BIN_DIR)/$(APP)
CLEAN_STAMP := $(BUILD_DIR)/.make-created
PREFIX    ?= /usr/local
BINDIR    ?= $(PREFIX)/bin
DESTDIR   ?=
TEST_DIR  ?= test
TEST_RUNNER ?= $(TEST_DIR)/run.sh
PERF_SCRIPT ?= $(TEST_DIR)/perf.sh
PERF_COMPARE ?= $(TEST_DIR)/perf-compare.sh
PERF_RECORD ?= $(TEST_DIR)/perf-record.sh
PERF_SELFCHECK ?= $(TEST_DIR)/perf-selfcheck.sh
PERF_AB ?= $(TEST_DIR)/perf-ab.sh
PERF_BASELINE ?= $(BUILD_DIR)/perf-baseline.txt
PERF_CURRENT ?= $(BUILD_DIR)/perf-current.txt
PERF_HISTORY ?= $(BUILD_DIR)/perf-history.csv
MAKE_CMD_FOR_TEST := $(MAKE)

# ---------- Pretty output / verbosity ----------
V ?= 0
ifeq ($(V),1)
  Q :=
  define log
  endef
else
  Q := @
  define log
	@printf "  %-6s %s\n" "$(1)" "$(2)"
  endef
endif

# ---------- Source discovery ----------
SRCS := $(shell find $(SRC_DIRS) -type f -name '*.c' \
	-not -path '*/$(BUILD_DIR)/*' -not -path '*/.git/*' -print | sed 's|^\./||')

OBJS := $(addprefix $(OBJ_DIR)/,$(SRCS:.c=.o))
DEPS := $(OBJS:.o=.d)

# ---------- Build flags ----------
UNAME_S   ?= $(shell uname -s)

# Keep strict POSIX headers.
# On FreeBSD this hides BSD extensions like SIGWINCH.
CPPFLAGS += -Iinclude -D_POSIX_C_SOURCE=200809L
ifeq ($(UNAME_S),FreeBSD)
  CPPFLAGS += -D__BSD_VISIBLE=1
endif
CFLAGS   += -std=c99 -Wall -Wextra -Werror -pedantic

DEBUG ?= 0
ifeq ($(DEBUG),1)
  CFLAGS += -O0 -g
else
  CFLAGS += -O2
endif

# ---------- ncurses + hunspell discovery ----------
PKG_CONFIG ?= pkg-config
HUNSPELL_LIB ?= hunspell

PKG_CFLAGS := $(shell $(PKG_CONFIG) --cflags hunspell ncursesw 2>/dev/null \
	|| $(PKG_CONFIG) --cflags hunspell ncurses 2>/dev/null)
PKG_LIBS   := $(shell $(PKG_CONFIG) --libs hunspell ncursesw 2>/dev/null \
	|| $(PKG_CONFIG) --libs hunspell ncurses 2>/dev/null)

HOMEBREW_PREFIX ?= $(shell brew --prefix 2>/dev/null)
ifneq ($(strip $(HOMEBREW_PREFIX)),)
  BREW_CPPFLAGS := -I$(HOMEBREW_PREFIX)/include
  BREW_LDFLAGS  := -L$(HOMEBREW_PREFIX)/lib
endif

ifeq ($(strip $(PKG_CFLAGS)),)
  CPPFLAGS += $(BREW_CPPFLAGS)
  LDFLAGS  += $(BREW_LDFLAGS)
  LDLIBS   += -l$(HUNSPELL_LIB) -lncurses
else
  CPPFLAGS += $(PKG_CFLAGS)
  LDLIBS   += $(PKG_LIBS)
endif

# ---------- Targets ----------
.PHONY: all clean install install-user uninstall uninstall-user run
.PHONY: test test-perf perf perf-mini perf-baseline perf-compare perf-record
.PHONY: perf-selfcheck perf-ab
.PHONY: print-vars
all: $(TARGET)

$(TARGET): $(OBJS) | $(BIN_DIR)
	$(call log,LD,$@)
	$(Q)$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BIN_DIR):
	$(call log,MKDIR,$@)
	$(Q)mkdir -p $@
	$(Q)mkdir -p $(BUILD_DIR)
	$(Q)touch $(CLEAN_STAMP)

$(OBJ_DIR)/%.o: %.c
	$(call log,CC,$<)
	$(Q)mkdir -p $(@D)
	$(Q)mkdir -p $(BUILD_DIR)
	$(Q)touch $(CLEAN_STAMP)
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(DEPS)

# ---------- Safer clean ----------
clean:
	$(call log,CLEAN,$(BUILD_DIR))
	@set -eu; \
	dir="$(BUILD_DIR)"; \
	case "$$dir" in \
		""|"/"|"~"|"."|".."|"../"*|"/Users"|"/home"|"/root") \
			echo "Refusing to clean unsafe BUILD_DIR='$$dir'"; exit 1 ;; \
	esac; \
	if [ ! -f "$(CLEAN_STAMP)" ]; then \
		echo "Refusing to clean: missing stamp '$(CLEAN_STAMP)'."; \
		echo "Not created by this Makefile?"; \
		echo "If you're sure, run: make clean FORCE=1"; \
		if [ "$${FORCE:-0}" != "1" ]; then exit 1; fi; \
	fi; \
	rm -rf -- "$$dir"

install: $(TARGET)
	$(call log,INSTALL,$(DESTDIR)$(BINDIR)/$(APP))
	$(Q)set -eu; \
	dest="$(DESTDIR)$(BINDIR)"; \
	file="$$dest/$(APP)"; \
	if ! mkdir -p "$$dest"; then \
		echo "Install failed: cannot create '$$dest'."; \
		echo "Try: make install PREFIX=\"$${HOME:-/path/to/home}/.local\""; \
		echo "Or run with elevated permissions."; \
		exit 1; \
	fi; \
	if [ ! -w "$$dest" ]; then \
		echo "Install failed: '$$dest' is not writable."; \
		echo "Try: make install PREFIX=\"$${HOME:-/path/to/home}/.local\""; \
		echo "Or run with elevated permissions."; \
		exit 1; \
	fi; \
	if ! install -m 0755 "$(TARGET)" "$$file"; then \
		echo "Install failed: cannot install to '$$file'."; \
		echo "Try: make install PREFIX=\"$${HOME:-/path/to/home}/.local\""; \
		echo "Or run with elevated permissions."; \
		exit 1; \
	fi

install-user: $(TARGET)
	$(Q)set -eu; \
	if [ -z "$${HOME:-}" ]; then \
		echo "Install failed: HOME is not set."; \
		echo "Try: make install PREFIX=\"/path/to/prefix\""; \
		exit 1; \
	fi; \
	$(MAKE) --no-print-directory install PREFIX="$$HOME/.local"; \
	echo "Installed to $$HOME/.local/bin/$(APP)."; \
	echo "If needed, add '$$HOME/.local/bin' to PATH."

uninstall:
	$(call log,RM,$(DESTDIR)$(BINDIR)/$(APP))
	$(Q)set -eu; \
	dest="$(DESTDIR)$(BINDIR)"; \
	file="$$dest/$(APP)"; \
	case "$$dest" in \
		""|"/"|"//"|"///"*|"~"|"."|".."|"../"*|"/Users"|"/home"|"/root") \
			echo "Refusing unsafe uninstall directory '$$dest'."; \
			exit 1 ;; \
	esac; \
	case "$$file" in \
		""|"/"|"//"|"///"*|"~"|"."|"..") \
			echo "Refusing unsafe uninstall path '$$file'."; \
			exit 1 ;; \
	esac; \
	if [ -d "$$file" ]; then \
		echo "Refusing to uninstall directory '$$file'."; \
		exit 1; \
	fi; \
	if [ ! -e "$$file" ] && [ ! -L "$$file" ]; then \
		echo "Nothing to uninstall at '$$file'."; \
		exit 0; \
	fi; \
	rm -f -- "$$file"; \
	echo "Uninstalled '$$file'."

uninstall-user:
	$(Q)set -eu; \
	if [ -z "$${HOME:-}" ]; then \
		echo "Uninstall failed: HOME is not set."; \
		echo "Try: make uninstall PREFIX=\"/path/to/prefix\""; \
		exit 1; \
	fi; \
	$(MAKE) --no-print-directory uninstall PREFIX="$$HOME/.local"

run: $(TARGET)
	$(Q)./$(TARGET)

test: $(TARGET)
	$(call log,TEST,$(TEST_RUNNER))
	$(Q)ROOT="$(CURDIR)" MAKE_CMD="$(MAKE_CMD_FOR_TEST)" APP="$(APP)" \
		TARGET="$(CURDIR)/$(TARGET)" sh "$(TEST_RUNNER)"

test-perf: $(TARGET)
	$(call log,PERF,$(PERF_SCRIPT))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_OUT="$(PERF_CURRENT)" sh "$(PERF_SCRIPT)"
	$(Q)cat "$(PERF_CURRENT)"

perf: $(TARGET)
	$(call log,PERF,$(PERF_SCRIPT))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_OUT="$(PERF_CURRENT)" PERF_INCLUDE_CLI=0 \
		PERF_TRIALS=1 PERF_MIN_SECONDS=1 PERF_MAX_ITERS=4096 \
		STARTUP_EMPTY_ITERS=2 STARTUP_LOAD_ITERS=2 \
		TYPE_ITERS=4 KEY_ITERS=4 MAIN_ITERS=6 DISPATCH_ITERS=10 \
		MAIN_COMMANDS=200 DISPATCH_COMMANDS=120 \
		sh "$(PERF_SCRIPT)"
	$(Q)cat "$(PERF_CURRENT)"

perf-mini: perf

perf-baseline: $(TARGET)
	$(call log,PERF,$(PERF_BASELINE))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_OUT="$(PERF_BASELINE)" sh "$(PERF_SCRIPT)"
	$(Q)echo "Wrote baseline: $(PERF_BASELINE)"

perf-compare: $(TARGET)
	$(call log,PERF,$(PERF_COMPARE))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_BASELINE="$(PERF_BASELINE)" sh "$(PERF_COMPARE)"

perf-record: $(TARGET)
	$(call log,PERF,$(PERF_RECORD))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_HISTORY="$(PERF_HISTORY)" sh "$(PERF_RECORD)"

perf-selfcheck: $(TARGET)
	$(call log,PERF,$(PERF_SELFCHECK))
	$(Q)ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		PERF_BASELINE="$(PERF_BASELINE)" sh "$(PERF_SELFCHECK)"

perf-ab: $(TARGET)
	$(Q)set -eu; \
	echo "perf-ab is experimental and disabled by default."; \
	echo "Use PERF_AB_ENABLE=1 to run it explicitly."; \
	if [ "$${PERF_AB_ENABLE:-0}" != "1" ]; then exit 0; fi; \
	ROOT="$(CURDIR)" APP="$(APP)" TARGET="$(CURDIR)/$(TARGET)" \
		sh "$(PERF_AB)"

print-vars:
	@echo "APP=$(APP)"
	@echo "SRCS=$(SRCS)"
	@echo "PKG_CFLAGS=$(PKG_CFLAGS)"
	@echo "PKG_LIBS=$(PKG_LIBS)"
	@echo "HOMEBREW_PREFIX=$(HOMEBREW_PREFIX)"
	@echo "PREFIX=$(PREFIX)"
	@echo "BINDIR=$(BINDIR)"
	@echo "DESTDIR=$(DESTDIR)"
	@echo "TEST_DIR=$(TEST_DIR)"
	@echo "PERF_BASELINE=$(PERF_BASELINE)"
	@echo "PERF_HISTORY=$(PERF_HISTORY)"
