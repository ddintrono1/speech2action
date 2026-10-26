#!/usr/bin/env bash
# Quick llama-server benchmark: prefill t/s, decode t/s, tokens/J, temperatures.
# Needs only bash, curl, awk. Runs inside the container.
# Usage: ./bench.sh llama-server <args...>
# Writes: $OUT_ROOT/<date-time>/{bench.csv, bench.log, bench.txt}
set -u

# port and api key are read from the server args (llama-server defaults otherwise)
PORT=8080; API_KEY=""
ARGS=("$@")
for i in "${!ARGS[@]}"; do
	case "${ARGS[$i]}" in
		--port)    PORT=${ARGS[$((i + 1))]} ;;
		--api-key) API_KEY=${ARGS[$((i + 1))]} ;;
	esac
done

URL=http://localhost:$PORT
RUNS=${RUNS:-3}
N_PREDICT=${N_PREDICT:-256}
OUT=${OUT_ROOT:-/root/output/bench}/$(date +%F_%H-%M-%S)

ENERGY=/rapl/energy_uj   # host's intel-rapl:1 (psys = whole platform), bind-mounted by make bench
CMD=$(echo "$*" | sed 's/--api-key [^ ]*/--api-key ***/')
CPU_TEMP=$(grep -l coretemp /sys/class/hwmon/*/name | head -1 | xargs dirname)/temp1_input

mkdir -p "$OUT"

# --- helpers ---------------------------------------------------------------

now()  { date +%s.%N; }
num()  { grep -o "\"$1\":[0-9.e+-]*" | head -1 | cut -d: -f2; }   # tiny JSON field grab
cpu_t() { echo $(( $(cat "$CPU_TEMP") / 1000 )); }
gpu_t() { nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || echo 0; }
energy() { cat "$ENERGY" 2>/dev/null; }

complete() {  # $1 = prompt, $2 = n_predict
	curl -s "$URL/completion" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
		-d "{\"prompt\":\"$1\",\"n_predict\":$2,\"ignore_eos\":true,\"temperature\":0,\"cache_prompt\":false}"
}

cleanup() {
	kill ${SAMPLER:-} ${SERVER:-} 2>/dev/null
	rm -f "${TMP:-}"
	# container runs as root: give the files back to the host user
	[ -n "${HOST_UID:-}" ] && chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$OUT"
}
trap cleanup EXIT

# --- start server ----------------------------------------------------------

"$@" > "$OUT/bench.log" 2>&1 &
SERVER=$!

echo -n "waiting for server"
for _ in $(seq 120); do
	curl -sf "$URL/health" >/dev/null && break
	echo -n "."; sleep 1
done
echo
curl -sf "$URL/health" >/dev/null || { echo "server not ready, see $OUT/bench.log"; exit 1; }

# --- temperature sampler (max seen, every 1 s) -----------------------------

CPU_IDLE=$(cpu_t); GPU_IDLE=$(gpu_t)
TMP=$(mktemp)
echo "$CPU_IDLE $GPU_IDLE" > "$TMP"
( while sleep 1; do
	read -r c g < "$TMP"
	nc=$(cpu_t); ng=$(gpu_t)
	echo "$(( nc > c ? nc : c )) $(( ng > g ? ng : g ))" > "$TMP"
done ) &
SAMPLER=$!

# --- runs ------------------------------------------------------------------

LONG=$(printf 'The quick brown fox jumps over the lazy dog. %.0s' $(seq 50))   # ~500 tokens
SHORT="Write a long story about a robot learning to cook."

complete "$SHORT" 16 >/dev/null   # warmup

RESULTS=""
for i in $(seq "$RUNS"); do
	# prefill: server timing (not affected by speculative decoding)
	pp=$(complete "$LONG" 1 | num prompt_per_second)

	# decode: client wall clock, so speculative decoding is measured as-is
	e0=$(energy); t0=$(now)
	r=$(complete "$SHORT" "$N_PREDICT")
	t1=$(now); e1=$(energy)
	n=$(echo "$r" | num tokens_predicted)
	pms=$(echo "$r" | num prompt_ms)

	RESULTS+="$pp $n $pms $t0 $t1 ${e0:-0} ${e1:-0}"$'\n'
	echo "run $i/$RUNS done"
done

read -r CPU_MAX GPU_MAX < "$TMP"

# --- report ----------------------------------------------------------------

LINE=$(echo -n "$RESULTS" | awk -v has_e="$(energy)" '
	{
		pp += $1
		dt = $5 - $4 - $3 / 1000;  tg += $2 / dt
		j  = ($7 - $6) / 1e6;      if (j > 0) { tj += $2 / j; w += j / ($5 - $4) }
		k++
	}
	END {
		e = has_e != "" ? sprintf("%.2f,%.1f", tj / k, w / k) : "n/a,n/a"
		printf "%.1f,%.1f,%s", pp / k, tg / k, e
	}')
IFS=, read -r PP TG TJ W <<< "$LINE"
DATE=$(date -Iseconds)

{
	echo "date,command,runs,n_predict,prefill_tps,decode_tps,tok_per_j,watts,cpu_idle_c,cpu_max_c,gpu_idle_c,gpu_max_c"
	echo "$DATE,\"$CMD\",$RUNS,$N_PREDICT,$PP,$TG,$TJ,$W,$CPU_IDLE,$CPU_MAX,$GPU_IDLE,$GPU_MAX"
} > "$OUT/bench.csv"

{
	echo "date        $DATE"
	echo "command     $CMD"
	echo "runs        $RUNS (+1 warmup), $N_PREDICT tokens decoded per run"
	echo
	printf "prefill     %8s  tok/s\n" "$PP"
	printf "decode      %8s  tok/s\n" "$TG"
	printf "efficiency  %8s  tok/J   (%s W avg)\n" "$TJ" "$W"
	printf "CPU temp    %8s  °C      (idle %s)\n" "$CPU_MAX" "$CPU_IDLE"
	printf "GPU temp    %8s  °C      (idle %s)\n" "$GPU_MAX" "$GPU_IDLE"
	[ -r "$ENERGY" ] || echo -e "\nnote: $ENERGY not readable, run via make bench for tok/J"
} > "$OUT/bench.txt"

echo
cat "$OUT/bench.txt"
echo
echo "saved to output/bench/$(basename "$OUT")/"
