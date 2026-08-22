#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 YutongChenVictor
# CAN interconnect stress test (can0<->can1, can2<->can3) - Based on motor_test_stress.sh

set -u

# ================= Configuration =================
SKIP_INIT=false
# TX -> RX pairing
CAN_TX=("can0" "can2")
CAN_RX=("can1" "can3")
BITRATE=1000000
DBITRATE=5000000
SAMPLEPOINT=0.800
SJW=4
DSAMPLEPOINT=0.750
DSJW=2

CAN_ID="100"
SEND_COUNT=500           # Frames sent per round per pair
SEND_HZ=500              # Send frequency (Hz)
CANFD=true               # true=CANFD 64 bytes, false=CAN 8 bytes

# Test duration configuration
TEST_DURATION_HOURS=4
BURST_INTERVAL=0.5
DMESG_SAVE_INTERVAL=300
STATS_INTERVAL=60
# ============================================

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"; exit 1
fi

# ---- Directory structure ----
TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/home/${SUDO_USER:-$USER}/can_comm_${TS}"
mkdir -p "${LOG_DIR}/dmesg" "${LOG_DIR}/cycles" "${LOG_DIR}/errors" "${LOG_DIR}/stats" "${LOG_DIR}/rx"
chmod -R 777 "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/main.log"
ERROR_LOG="${LOG_DIR}/errors/all_errors.log"
SUMMARY="${LOG_DIR}/summary.log"
STATS_CSV="${LOG_DIR}/stats/stats.csv"
RESCUE_LOG="${LOG_DIR}/rescue.log"

declare -A IF_TX
declare -A IF_RX
declare -A CANDUMP_PID
declare -A RX_FILE_COUNT

TOTAL_SENT=0
TOTAL_FAIL=0
TOTAL_BUS_OFF=0
TOTAL_RESTARTS=0
BURST_ROUND=0
START_EPOCH=0
DMESG_PID=""

# Initialize RX file count
for idx in "${!CAN_RX[@]}"; do
    RX_FILE_COUNT[${CAN_RX[$idx]}]=0
done

# ---- Utility functions ----
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${MAIN_LOG}"; }

cleanup() {
    echo ""
    log "=========================================="
    log " Stop signal received, cleaning up..."
    log "=========================================="

    # Stop candump
    for pid in "${CANDUMP_PID[@]}"; do
        kill "$pid" 2>/dev/null
    done
    [[ -n "${DMESG_PID}" ]] && kill "${DMESG_PID}" 2>/dev/null
    kill $(jobs -p) 2>/dev/null

    # Final dmesg snapshot
    dmesg > "${LOG_DIR}/dmesg/dmesg_final.log" 2>&1
    dmesg -T > "${LOG_DIR}/dmesg/dmesg_final_human.log" 2>&1
    dmesg | grep -iE "usb|can|mcp|spi|error|oops|panic|warn" > "${LOG_DIR}/dmesg/dmesg_filtered.log" 2>&1

    # Final interface status
    for idx in "${!CAN_TX[@]}"; do
        ip -d -s link show "${CAN_TX[$idx]}" > "${LOG_DIR}/stats/final_${CAN_TX[$idx]}.txt" 2>&1
        ip -d -s link show "${CAN_RX[$idx]}" > "${LOG_DIR}/stats/final_${CAN_RX[$idx]}.txt" 2>&1
    done

    generate_report
    log " Log directory: ${LOG_DIR}"
    log "=========================================="
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

generate_report() {
    local now duration_s hours mins
    now=$(date +%s)
    duration_s=$(( now - START_EPOCH ))
    hours=$(( duration_s / 3600 ))
    mins=$(( (duration_s % 3600) / 60 ))

    {
        echo "=========================================="
        echo " CAN Interconnect Stress Test Report"
        echo "=========================================="
        echo " Start time:  $(date -d @${START_EPOCH} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
        echo " End time:    $(date '+%Y-%m-%d %H:%M:%S')"
        echo " Duration:    ${hours}h ${mins}m (${duration_s}s)"
        echo " Pairing:     can0->can1  can2->can3"
        echo " Bitrate:     ${BITRATE}/${DBITRATE}"
        echo " CANFD:       ${CANFD}"
        echo "------------------------------------------"
        echo " Burst rounds:  ${BURST_ROUND}"
        echo " Sent success:  ${TOTAL_SENT}"
        echo " Sent failure:  ${TOTAL_FAIL}"
        echo " BUS-OFF:       ${TOTAL_BUS_OFF}"
        echo " Auto recovery: ${TOTAL_RESTARTS}"
        echo "------------------------------------------"
        for idx in "${!CAN_TX[@]}"; do
            printf "  %s->%s  TX=%-8d RX=%-8d\n" \
                "${CAN_TX[$idx]}" "${CAN_RX[$idx]}" \
                "${IF_TX[${CAN_TX[$idx]}]:-0}" "${IF_RX[${CAN_RX[$idx]}]:-0}"
        done
        echo "------------------------------------------"
        echo " Log files:"
        echo "   main:          ${MAIN_LOG}"
        echo "   errors:        ${ERROR_LOG}"
        echo "   stats csv:     ${STATS_CSV}"
        echo "   dmesg:         ${LOG_DIR}/dmesg/"
        echo "   rescue:        ${RESCUE_LOG}"
        echo "=========================================="
    } | tee "${SUMMARY}"
}

# ---- CAN interface initialization ----
if [ "$SKIP_INIT" = false ]; then
    log ">>> Initializing CAN interfaces..."
    for idx in "${!CAN_TX[@]}"; do
        for IF in "${CAN_TX[$idx]}" "${CAN_RX[$idx]}"; do
            ip link set "$IF" down 2>/dev/null
            if ip link set "$IF" type can bitrate $BITRATE sample-point $SAMPLEPOINT sjw $SJW \
                    dbitrate $DBITRATE dsample-point $DSAMPLEPOINT dsjw $DSJW fd on restart-ms 100 2>/dev/null; then
                ip link set "$IF" mtu 72
                ip link set "$IF" txqueuelen 10000
            fi
            ip link set "$IF" up 2>/dev/null
            log "  [${IF}] UP ${BITRATE}/${DBITRATE} restart-ms=100"
        done
    done
fi

# ---- Initial dmesg snapshot ----
dmesg -C
dmesg > "${LOG_DIR}/dmesg/dmesg_initial.log" 2>&1

# ---- Frame data construction ----
# Sequenced test frame for receiver-side verification
build_test_data() {
    local seq=$1
    local seq_hex
    seq_hex=$(printf '%08X' "$seq")
    if $CANFD; then
        # 64 bytes: sequence(4B) + pattern(60B)
        echo "${seq_hex}A5A5A5A512345678DEADBEEFCAFEBABE0102030405060708AABBCCDD11223344556677889900AABB"
    else
        echo "${seq_hex}A5A5A5A5"
    fi
}

if $CANFD; then
    FRAME_FLAG="##1"
    log " Frame format: CANFD 64B"
else
    FRAME_FLAG="#"
    log " Frame format: CAN2.0 8B"
fi
log ""

# ---- candump RX monitor (background, one per RX interface) ----
start_rx_monitor() {
    for idx in "${!CAN_RX[@]}"; do
        rx="${CAN_RX[$idx]}"
        rx_file="${LOG_DIR}/rx/${rx}.log"
        > "$rx_file"
        stdbuf -oL candump -L "$rx" 2>/dev/null >> "$rx_file" &
        CANDUMP_PID[$rx]=$!
        log "  [${rx}] candump started (PID=${CANDUMP_PID[$rx]})"
    done
}

# ---- dmesg periodic snapshot (background) ----
dmesg_snapshot_loop() {
    local idx=0
    while true; do
        sleep "${DMESG_SAVE_INTERVAL}"
        ((idx++))
        dmesg > "${LOG_DIR}/dmesg/dmesg_snap_$(printf '%04d' ${idx}).log" 2>&1
        dmesg | grep -iE "can|mcp|spi|usb|error|oops|warn|panic|bus.off" \
            > "${LOG_DIR}/dmesg/dmesg_filtered_$(printf '%04d' ${idx}).log" 2>&1
    done
}

# ---- Stats CSV header ----
CSV_HEADER="timestamp,round,sent,fail,bus_off,restarts"
for idx in "${!CAN_TX[@]}"; do
    CSV_HEADER+=",${CAN_TX[$idx]}_tx,${CAN_RX[$idx]}_rx"
done
echo "$CSV_HEADER" > "${STATS_CSV}"

# ---- Get interface status summary ----
get_if_states() {
    local states="" IF st
    for idx in "${!CAN_TX[@]}"; do
        for IF in "${CAN_TX[$idx]}" "${CAN_RX[$idx]}"; do
            st=$(ip link show "$IF" 2>/dev/null | grep -oE "ERROR-(ACTIVE|WARNING|PASSIVE)|BUS-OFF|NOARP" | head -1)
            [[ -z "$st" ]] && st="OK"
            states+="${IF}:${st} "
        done
    done
    echo "${states% }"
}

# ---- BUS-OFF auto recovery ----
check_and_rescue() {
    local IF state
    for idx in "${!CAN_TX[@]}"; do
        for IF in "${CAN_TX[$idx]}" "${CAN_RX[$idx]}"; do
            state=$(ip link show "$IF" 2>/dev/null | grep -oE "BUS-OFF|STOPPED" | head -1)
            if [[ -n "$state" ]]; then
                ((TOTAL_BUS_OFF++))
                log "  ** [${IF}] Detected ${state}, auto restart **"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${IF}] BUS-OFF -> restart" >> "${RESCUE_LOG}"
                ip link set "$IF" type can restart 2>/dev/null
                sleep 0.5
                ((TOTAL_RESTARTS++))
            fi
        done
    done
}

# ---- Start background tasks ----
start_rx_monitor
log ">>> RX monitor started"

dmesg_snapshot_loop &
DMESG_PID=$!

# ---- Clear error log ----
echo "--- CAN Interconnect Stress Test Log Start: $(date) ---" > "$ERROR_LOG"
> "$RESCUE_LOG"

START_EPOCH=$(date +%s)
TEST_END=$(( START_EPOCH + TEST_DURATION_HOURS * 3600 ))
SLEEP_US=$(( 1000000 / SEND_HZ ))
command -v usleep &>/dev/null && HAS_USLEEP=true || HAS_USLEEP=false

log "=========================================="
log " CAN Interconnect Stress Test Started"
log " Pairing: can0->can1  can2->can3"
log " Per round: ${SEND_COUNT} frames/pair @ ${SEND_HZ}Hz"
log " Expected duration: ${TEST_DURATION_HOURS} hours"
log " Deadline: $(date -d @${TEST_END} '+%H:%M:%S' 2>/dev/null || echo 'N/A')"
log " Ctrl+C to stop and save logs at any time"
log "=========================================="
echo ""

SEQ=0
LAST_STATS_PRINT=0

# ================ Main loop ================
while [[ $(date +%s) -lt ${TEST_END} ]]; do
    ((BURST_ROUND++))

    ROUND_START=$(date +%s%N)
    ROUND_SENT=0
    ROUND_FAIL=0

    # -- Send per pair --
    for idx in "${!CAN_TX[@]}"; do
        tx="${CAN_TX[$idx]}"
        pair_sent=0

        for ((n=1; n<=SEND_COUNT; n++)); do
            ((SEQ++))
            DATA=$(build_test_data "$SEQ")

            if cansend "$tx" "${CAN_ID}${FRAME_FLAG}${DATA}" 2>/dev/null; then
                ((pair_sent++))
                ((TOTAL_SENT++))
            else
                ((ROUND_FAIL++))
                ((TOTAL_FAIL++))
            fi

            if $HAS_USLEEP; then
                usleep "$SLEEP_US" 2>/dev/null
            else
                sleep 0.002
            fi
        done

        IF_TX[$tx]=$(( ${IF_TX[$tx]:-0} + pair_sent ))
        ((ROUND_SENT += pair_sent))
    done

    ROUND_END=$(date +%s%N)
    ROUND_MS=$(( (ROUND_END - ROUND_START) / 1000000 ))

    # -- Update RX count --
    for idx in "${!CAN_RX[@]}"; do
        rx="${CAN_RX[$idx]}"
        rx_file="${LOG_DIR}/rx/${rx}.log"
        if [[ -f "$rx_file" ]]; then
            IF_RX[$rx]=$(wc -l < "$rx_file")
        fi
    done

    # -- Auto check BUS-OFF and recover --
    check_and_rescue

    # -- Periodic status print --
    NOW=$(date +%s)
    if (( NOW - LAST_STATS_PRINT >= STATS_INTERVAL )); then
        LAST_STATS_PRINT=$NOW
        ELAPSED=$(( NOW - START_EPOCH ))
        REMAINING=$(( TEST_END - NOW ))

        # Write CSV
        CSV_LINE="$(date '+%Y-%m-%d %H:%M:%S'),${BURST_ROUND},${TOTAL_SENT},${TOTAL_FAIL},${TOTAL_BUS_OFF},${TOTAL_RESTARTS}"
        for idx in "${!CAN_TX[@]}"; do
            CSV_LINE+=",${IF_TX[${CAN_TX[$idx]}]:-0},${IF_RX[${CAN_RX[$idx]}]:-0}"
        done
        echo "$CSV_LINE" >> "${STATS_CSV}"

        hrs=$(( ELAPSED / 3600 ))
        rem_hrs=$(( REMAINING / 3600 ))
        rem_mins=$(( (REMAINING % 3600) / 60 ))
        IF_STATES=$(get_if_states)

        log "------ Status @ ${hrs}h ------"
        log "  Round:      ${BURST_ROUND}"
        log "  Sent:       ${TOTAL_SENT}  Failed: ${TOTAL_FAIL}"
        log "  BUS-OFF:    ${TOTAL_BUS_OFF}  Recovered: ${TOTAL_RESTARTS}"
        log "  Interfaces: ${IF_STATES}"
        log "  Remaining:  ${rem_hrs}h${rem_mins}m"
        log "  Last round: ${ROUND_MS}ms (${SEND_COUNT} frames x ${#CAN_TX[@]} pairs)"

        for idx in "${!CAN_TX[@]}"; do
            tx="${CAN_TX[$idx]}"
            rx="${CAN_RX[$idx]}"
            diff=$(( ${IF_TX[$tx]:-0} - ${IF_RX[$rx]:-0} ))
            log "  [${tx}->${rx}] TX=${IF_TX[$tx]:-0} RX=${IF_RX[$rx]:-0} diff=${diff}"
        done

        # CAN-related errors in dmesg
        dmesg_err_count=$(dmesg | tail -500 | grep -ciE "can.*error|bus.off|mcp.*err|spi.*err" || true)
        if [[ $dmesg_err_count -gt 0 ]]; then
            log "  [WARN] CAN-related errors in dmesg: ${dmesg_err_count} entries"
            dmesg | tail -500 | grep -iE "can.*error|bus.off" | tail -3 >> "${MAIN_LOG}"
        fi
    fi

    # -- Log progress every 10 rounds --
    if (( BURST_ROUND % 10 == 0 )); then
        echo "[$(date '+%H:%M:%S')] round=${BURST_ROUND} sent=${TOTAL_SENT} fail=${TOTAL_FAIL}" \
            >> "${LOG_DIR}/cycles/progress.log"
    fi

    sleep "${BURST_INTERVAL}"
done

# Normal exit
log ">>> Test time elapsed, normal exit <<<"
