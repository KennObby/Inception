<<<<<<< HEAD
SHELL := /bin/sh

install:
	UI_POLICY=auto UNATTENDED=1 ./install-vm.sh

run:
	./run-vm.sh

logs:
	. ./.env; \
	mkdir -p "$$LOGS_DIR"; \
	tail -F "$$LOGS_DIR/qemu-host.log" "$$LOGS_DIR/qemu-debug.log" "$$LOGS_DIR/guest-serial.log" 2>/dev/null || true

debug install-vm:
	UNATTENDED=1 sh -x ./install-vm.sh 2>&1 | sed -n '1,20000p'

clean:
	. ./.env; \
	rm -rf "$$LOGS_DIR"; \
	rm -rf "$$IMAGES_DIR/$(DISK_NAME)" "IMAGES_DIR"/*.qcow2
=======

up: 
	docker compose -f srcs/docker-compose.yml up -d --build

down:
	docker compose -f srcs/docker-compose.yml down
>>>>>>> f59ef3f (Initial commit: Inception docker-compose setup)
