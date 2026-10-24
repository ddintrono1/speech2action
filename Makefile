-include .env

#############################################
# Vars
#############################################

# docker
IMAGE_NAME := speech2action
IMAGE_TAG := 1.0
IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)
CONTAINER_NAME := s2a_container

# paths
MODELS_PATH_EXT		:= models/
MODELS_PATH_HOST 	:= ./volume/$(MODELS_PATH_EXT)
MODELS_PATH_CONT	:= /root/volume/$(MODELS_PATH_EXT)


# automatically offload to RAM if VRAM is not enough
N_VRAM ?= auto
CONTEXT ?= 4096

# docker run common flags
DOCKER_RUN := docker run \
		--rm \
		-v ./volume:/root/volume \
		-v $(XDG_RUNTIME_DIR)/pulse/native:/run/pulse/native \
		-v $(HOME)/.config/pulse/cookie:/root/.config/pulse/cookie:ro \
		-e PULSE_SERVER=unix:/run/pulse/native \
		-e IS_CONTAINER=1 \
		-p $(PORT):$(PORT) \
		--gpus 'all,"capabilities=compute,utility,graphics"' \
		--name $(CONTAINER_NAME)

# llama-server common flags
LLAMA_SERVE := llama-server \
		--host $(HOST) \
		--port $(PORT) \
		--api-key $(API_KEY) \
		-ngl $(N_VRAM) \
		-c $(CONTEXT) \
		-np 1 -fa on

WHISPER_STREAM := whisper-stream \
	  	-t 8 \
		--step 500 \
		--length 5000 \
		--vad \
		--print-colors 


.PHONY: \
 build test-llama test-whisper shell serve-llama serve-whisper run kill

#############################################
# Macros
#############################################

require=if [ -z "$($(1))" ]; then \
		echo "No argument supplied"; \
		echo "Usage: make $@ $(1)=$(2)"; \
		exit 1; \
	fi

#############################################
# Targets
#############################################

# Build container and llama.cpp
build:
	@docker build \
	-f Dockerfile \
	--network host \
	--build-arg N_JOBS=$(N_JOBS) \
	--build-arg CUDA_ARCH=$(CUDA_ARCH) \
    -t $(IMAGE) \
	.

# Test llama with a dummy model (TODO)
test-llama:
	@mkdir -p $(MODELS_PATH_HOST)
	@curl -fL -C - -o $(MODELS_PATH_HOST)Qwen3.5-0.8B-Q4_K_M.gguf \
		"https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true"

download-llama-Qwen3.5-4B-Q4_0:
	@mkdir -p $(MODELS_PATH_HOST) 
	@curl -fL -C - -o $(MODELS_PATH_HOST)Qwen3.5-4B-Q4_0.gguf \						
		"https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_0.gguf?download=true"

# Test whisper with a dummy model
test-whisper:
	@mkdir -p $(MODELS_PATH_HOST)
	@$(DOCKER_RUN) $(IMAGE) curl -fL -C - -o $(MODELS_PATH_CONT)ggml-base.en-q8_0.bin \
		"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q8_0.bin"
	@$(DOCKER_RUN) $(IMAGE) whisper-cli -m $(MODELS_PATH_CONT)ggml-base.en-q8_0.bin -f whisper.cpp/samples/jfk.wav --print-colors

shell:
	@$(DOCKER_RUN) -it $(IMAGE) bash

run:
	@$(call require,CMD,<shell command>);
	@$(DOCKER_RUN) $(IMAGE) $(CMD)

serve-llama:
	@$(call require,MODEL,<model>.gguf);
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)$(MODEL)

serve-llama-Qwen3.5-0.8B-Q4_K_M:
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)Qwen3.5-0.8B-Q4_K_M.gguf

serve-llama-Qwen3.5-4B-Q4_0:
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)Qwen3.5-4B-Q4_0.gguf 

serve-whisper:
	@$(DOCKER_RUN) $(IMAGE) $(WHISPER_STREAM) -m $(MODELS_PATH_CONT)ggml-base.en-q8_0.bin

kill:
	@docker kill $(CONTAINER_NAME) 
