NAME    = pgbackup
VERSION = 2.0.0
PREFIX ?= /usr/local
DESTDIR ?=

BIN_DIR       = $(DESTDIR)$(PREFIX)/bin
LIB_DIR       = $(DESTDIR)$(PREFIX)/lib/$(NAME)
SHARE_DIR     = $(DESTDIR)$(PREFIX)/share/$(NAME)
TEMPLATES_DIR = $(SHARE_DIR)/templates
BUILD_DIR     = build

.PHONY: all install uninstall tarball deb test clean

all: tarball

install:
	install -d -m755 $(BIN_DIR) $(LIB_DIR) $(TEMPLATES_DIR)
	install -d -m750 $(DESTDIR)/etc/$(NAME)
	install -m755 src/$(NAME)                        $(BIN_DIR)/$(NAME)
	install -m644 src/lib/common.sh                  $(LIB_DIR)/
	install -m644 src/lib/full_backup.sh             $(LIB_DIR)/
	install -m644 src/lib/restore.sh                 $(LIB_DIR)/
	install -m644 src/lib/check_backup.sh            $(LIB_DIR)/
	install -m644 src/lib/stanza_setup.sh            $(LIB_DIR)/
	install -m644 src/lib/systemd_install.sh         $(LIB_DIR)/
	install -m644 templates/backup.env.template      $(TEMPLATES_DIR)/
	@echo "✓ Installed. Run: pgbackup help"

uninstall:
	rm -f  $(BIN_DIR)/$(NAME)
	rm -rf $(LIB_DIR) $(SHARE_DIR)
	@echo "✓ Uninstalled (configs in /etc/$(NAME) kept)"

tarball:
	mkdir -p $(BUILD_DIR)
	tar -czf $(BUILD_DIR)/$(NAME)-$(VERSION).tar.gz \
	    --transform 's|^|$(NAME)-$(VERSION)/|' \
	    src/ templates/ docker/ install.sh Makefile README.md
	@echo "✓ $(BUILD_DIR)/$(NAME)-$(VERSION).tar.gz"

deb:
	@command -v dpkg-deb >/dev/null || { echo "Need dpkg-deb"; exit 1; }
	mkdir -p $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all/{DEBIAN,usr/bin,usr/lib/$(NAME),usr/share/$(NAME)/templates,etc/$(NAME)}
	install -m755 src/$(NAME) $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all/usr/bin/$(NAME)
	install -m644 src/lib/*.sh $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all/usr/lib/$(NAME)/
	install -m644 templates/backup.env.template $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all/usr/share/$(NAME)/templates/
	printf "Package: $(NAME)\nVersion: $(VERSION)\nArchitecture: all\nDepends: pgbackrest, postgresql-client\nDescription: PostgreSQL Backup CLI (pgBackRest edition)\n" \
	    > $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all/DEBIAN/control
	dpkg-deb --build $(BUILD_DIR)/deb/$(NAME)_$(VERSION)_all \
	         $(BUILD_DIR)/$(NAME)_$(VERSION)_all.deb
	@echo "✓ $(BUILD_DIR)/$(NAME)_$(VERSION)_all.deb"
	@echo "  sudo dpkg -i $(BUILD_DIR)/$(NAME)_$(VERSION)_all.deb"

test:
	@bash -n src/$(NAME) && echo "✓ pgbackup"
	@for f in src/lib/*.sh; do bash -n "$$f" && echo "✓ $$f"; done

clean:
	rm -rf $(BUILD_DIR)
