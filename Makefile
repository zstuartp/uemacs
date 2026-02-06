# ---------- Project settings ----------
APP       ?= em
CC        ?= cc

SRC_DIRS  ?= src
BUILD_DIR ?= build
OBJ_DIR   := $(BUILD_DIR)/obj
BIN_DIR   := $(BUILD_DIR)/bin
TARGET    := $(BIN_DIR)/$(APP)
CLEAN_STAMP := $(BUILD_DIR)/.make-created

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

# Keep strict POSIX headers, but on FreeBSD this hides BSD extensions like SIGWINCH.
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
  LDLIBS   += -lhunspell-1.7 -lncurses
else
  CPPFLAGS += $(PKG_CFLAGS)
  LDLIBS   += $(PKG_LIBS)
endif

# ---------- Targets ----------
.PHONY: all clean run print-vars
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
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

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
		echo "Refusing to clean: missing stamp '$(CLEAN_STAMP)' (not created by this Makefile?)"; \
		echo "If you're sure, run: make clean FORCE=1"; \
		if [ "$${FORCE:-0}" != "1" ]; then exit 1; fi; \
	fi; \
	rm -rf -- "$$dir"

run: $(TARGET)
	$(Q)./$(TARGET)

print-vars:
	@echo "SRCS=$(SRCS)"
	@echo "PKG_CFLAGS=$(PKG_CFLAGS)"
	@echo "PKG_LIBS=$(PKG_LIBS)"
	@echo "HOMEBREW_PREFIX=$(HOMEBREW_PREFIX)"

