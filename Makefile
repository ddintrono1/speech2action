-include .env

IMAGE_NAME := "speech2action"
IMAGE_TAG := ":1.0"
CONTAINER_NAME := "s2a_container"

.PHONY: 
	build shell run

build:
	docker build \
	-f Dockerfile \
	--network host \
	--build-arg N_JOBS=$(N_JOBS) \
    -t $(IMAGE_NAME)$(IMAGE_TAG) \
	.

shell:
	@docker run \
		-it \
		--rm \
		-v ./volume:/root/volume \
		-e IS_CONTAINER=1 \
		--network host \
		--gpus 'all,"capabilities=compute,utility,graphics"' \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME)$(IMAGE_TAG) bash

run:
	@echo "tbd"

kill:
	@docker kill $(CONTAINER_NAME)
