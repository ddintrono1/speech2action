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
MODELS_PATH_CONT	:= /root/volume/models/

# automatically offload to RAM if VRAM is not enough
N_VRAM ?= auto
CONTEXT_LENGHT ?= 4096

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
		-c $(CONTEXT_LENGHT) \
		-np 1 -fa on

WHISPER_STREAM := whisper-stream \
	  	-t 8 \
		--step 500 \
		--length 5000 \

.PHONY: \
 build shell run kill \
 test-llama serve-llama bench \
 serve-llama-Qwen3.5-0.8B-Q4_K_M serve-llama-Qwen3.5-4B-Q4_K_M \
 serve-llama-functiongemma-270m-it-Q4_K_M \
 download-llama-Qwen3.5-0.8B-Q4_K_M download-llama-Qwen3.5-4B-Q4_K_M \
 download-llama-functiongemma-270m-it-Q4_K_M \
 test-whisper download-whisper-ggml-base.en-q8_0 stream-whisper-ggml-base.en-q8_0


#############################################
# Macros
#############################################

require=if [ -z "$($(1))" ]; then \
		echo "No argument supplied"; \
		echo "Usage: make $@ $(1)=$(2)"; \
		exit 1; \
	fi

download=$(DOCKER_RUN) $(IMAGE) bash -c \
	"mkdir -p $(MODELS_PATH_CONT) && \
	curl -fL -C - -o $(MODELS_PATH_CONT)$(1) '$(2)'"


#############################################
# Generic targets
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

shell:
	@$(DOCKER_RUN) -it $(IMAGE) bash

run:
	@$(call require,CMD,<shell command>);
	@$(DOCKER_RUN) $(IMAGE) $(CMD)

kill:
	@docker kill $(CONTAINER_NAME)

#############################################
# llama.cpp
#############################################

# Test llama with a dummy model
test-llama:
	@$(call download,Qwen3.5-0.8B-Q4_K_M.gguf,https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true)
	@$(DOCKER_RUN) $(IMAGE) llama-cli -m $(MODELS_PATH_CONT)Qwen3.5-0.8B-Q4_K_M.gguf \
		-c $(CONTEXT_LENGHT) -p "Turn on the kitchen lights. Reply with a short JSON action."

serve-llama:
	@$(call require,MODEL,<model>.gguf);
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)$(MODEL)

download-llama-Qwen3.5-0.8B-Q4_K_M:
	@$(call download,Qwen3.5-0.8B-Q4_K_M.gguf,https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true)

serve-llama-Qwen3.5-0.8B-Q4_K_M:
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)Qwen3.5-0.8B-Q4_K_M.gguf

download-llama-Qwen3.5-4B-Q4_K_M:
	@$(call download,Qwen3.5-4B-Q4_K_M.gguf,https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf?download=true)

serve-llama-Qwen3.5-4B-Q4_K_M:
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)Qwen3.5-4B-Q4_K_M.gguf

download-llama-functiongemma-270m-it-Q4_K_M:
	@$(call download,functiongemma-270m-it-Q4_K_M.gguf,https://huggingface.co/unsloth/functiongemma-270m-it-GGUF/resolve/main/functiongemma-270m-it-Q4_K_M.gguf?download=true)

serve-llama-functiongemma-270m-it-Q4_K_M:
	@$(DOCKER_RUN) $(IMAGE) $(LLAMA_SERVE) -m $(MODELS_PATH_CONT)functiongemma-270m-it-Q4_K_M.gguf

# Benchmark: prefill t/s, decode t/s, tok/J, temps. 
# CMD is everything after "llama-server"
bench:
	@$(call require,CMD,'-m /root/volume/models/<model>.gguf ...');
	@mkdir -p ./output/bench
	@$(DOCKER_RUN) -v ./output:/root/output -v /etc/localtime:/etc/localtime:ro \
		--mount type=bind,src=/sys/class/powercap/intel-rapl:1,dst=/rapl,readonly \
		-e HOST_UID=$(shell id -u) -e HOST_GID=$(shell id -g) \
		$(IMAGE) \
		./bench.sh llama-server $(CMD)


#############################################
# whisper
#############################################

# Test whisper with a dummy model
test-whisper:
	@$(call download,ggml-base.en-q8_0.bin,https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q8_0.bin)
	@$(DOCKER_RUN) $(IMAGE) whisper-cli -m $(MODELS_PATH_CONT)ggml-base.en-q8_0.bin -f whisper.cpp/samples/jfk.wav --print-colors

download-whisper-ggml-base.en-q8_0:
	@$(call download,ggml-base.en-q8_0.bin,https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q8_0.bin)

stream-whisper-ggml-base.en-q8_0:
	@$(DOCKER_RUN) $(IMAGE) $(WHISPER_STREAM) -m $(MODELS_PATH_CONT)ggml-base.en-q8_0.bin


