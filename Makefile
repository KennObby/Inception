SHELL := /bin/sh

install:
	UI_POLICY=gtk UNATTENDED=1 ./install-vm.sh

run:
	./run-vm.sh

logs:
	. ./.env; \
	mkdir -p "$$LOGS_DIR"; \
	tail -F "$$LOGS_DIR/qemu-host.log" "$$LOGS_DIR/qemu-debug.log" "$$LOGS_DIR/guest-serial.log" 2>/dev/null || true

clean:
	. ./.env; \
	rm -rf "$$LOGS_DIR"; \
	rm -rf "$$IMAGES_DIR/$(DISK_NAME)" "IMAGES_DIR"/*.qcow2
