#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 YutongChenVictor
# LRO motor long-duration stress test - Fully automated unattended version

set -u

# ================= Configuration =================
SKIP_INIT=false
INTERFACES=("can0")
BITRATE=1000000
DBITRATE=5000000
SAMPLEPOINT=0.800
SJW=4
DSAMPLEPOINT=0.750
DSJW=2

CANID=00008080
NUM_MOTORS=3
MIT_HZ=750

# Test duration configuration
TEST_DURATION_HOURS=4
BURST_COUNT=2000
BURST_INTERVAL=0.5
DMESG_SAVE_INTERVAL=300
STATS_INTERVAL=60

# LRO MIT all-zero data
MOTOR_ZERO_DATA="00000000000007FF"

# Error code mapping
declare -A LRO_ERR_MAP=(
    [01]="MOTOR_OVERHEAT"
    [02]="OVER_CURRENT"
    [03]="UNDER_VOLTAGE"
    [04]="ENCODER_ERROR"
    [06]="BRAKE_OVERVOLT"
    [07]="DRV_ERROR"
)
declare -A IF_TX
declare -A IF_RX
# ============================================

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"; exit 1
fi

# ---- Directory structure ----
TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/home/${SUDO_USER:-$USER}/motor_stress_${TS}"
mkdir -p "${LOG_DIR}/dmesg" "${LOG_DIR}/cycles" "${LOG_DIR}/errors" "${LOG_DIR}/stats"
chmod -R 777 "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/main.log"
ERROR_LOG="${LOG_DIR}/errors/all_errors.log"
SUMMARY="${LOG_DIR}/summary.log"
STATS_CSV="${LOG_DIR}/stats/stats.csv"
RESCUE_LOG="${LOG_DIR}/rescue.log"

CANDUMP_PID=""
TOTAL_SENT=0
TOTAL_FAIL=0
TOTAL_ERRORS=0
TOTAL_BUS_OFF=0
TOTAL_RESTARTS=0
BURST_ROUND=0
START_EPOCH=0

# ---- Utility functions ----
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${MAIN_LOG}"; }
elog() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${ERROR_LOG}"; }

cleanup() {
    echo ""
    log "=========================================="
    log " Stop signal received, cleaning up..."
    log "=========================================="

    [[ -n "${CANDUMP_PID}" ]] && kill "${CANDUMP_PID}" 2>/dev/null
    [[ -n "${DMESG_PID:-}" ]] && kill "${DMESG_PID}" 2>/dev/null
    kill $(jobs -p) 2>/dev/null

    dmesg > "${LOG_DIR}/dmesg/dmesg_final.log" 2>&1
    dmesg -T > "${LOG_DIR}/dmesg/dmesg_final_human.log" 2>&1
    dmesg | grep -iE "usb|can|mcp|spi|error|oops|panic|warn" > "${LOG_DIR}/dmesg/dmesg_filtered.log" 2>&1

    for IF in "${INTERFACES[@]}"; do
        ip -d -s link show "$IF" > "${LOG_DIR}/stats/final_${IF}.txt" 2>&1
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
        echo " LRO Motor Stress Test Report"
        echo "=========================================="
        echo " Start time:  $(date -d @${START_EPOCH} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
        echo " End time:    $(date '+%Y-%m-%d %H:%M:%S')"
        echo " Duration:    ${hours}h ${mins}m (${duration_s}s)"
        echo " Interfaces:  ${INTERFACES[*]}"
        echo " Motor count: ${NUM_MOTORS}"
        echo " MIT freq:    ${MIT_HZ} Hz"
        echo "------------------------------------------"
        echo " Burst rounds:  ${BURST_ROUND}"
        echo " Sent success:  ${TOTAL_SENT}"
        echo " Sent failure:  ${TOTAL_FAIL}"
        echo " Motor errors:  ${TOTAL_ERRORS}"
        echo " BUS-OFF:       ${TOTAL_BUS_OFF}"
        echo " Auto recovery: ${TOTAL_RESTARTS}"
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
    for IF in "${INTERFACES[@]}"; do
        ip link set "$IF" down 2>/dev/null
        if ip link set "$IF" type can bitrate $BITRATE sample-point $SAMPLEPOINT sjw $SJW \
                dbitrate $DBITRATE dsample-point $DSAMPLEPOINT dsjw $DSJW fd on restart-ms 100 2>/dev/null; then
            ip link set "$IF" mtu 72
            ip link set "$IF" txqueuelen 10000
        fi
        ip link set "$IF" up 2>/dev/null
        log "  [${IF}] UP ${BITRATE}/${DBITRATE} restart-ms=100"
    done
fi

# ---- Initial dmesg snapshot ----
dmesg -C
dmesg > "${LOG_DIR}/dmesg/dmesg_initial.log" 2>&1

# ---- Motor enable + zero calibration ----
CMD_ENABLE="06"
CMD_ZERO="03"

log ">>> Enable + zero calibration for ${NUM_MOTORS} motors..."
for IF in "${INTERFACES[@]}"; do
    for ((m=1; m<=NUM_MOTORS; m++)); do
        MID=$(printf '%04X' $m)
        cansend "$IF" "7FF#${MID}00${CMD_ENABLE}" 2>/dev/null
        sleep 0.3
        cansend "$IF" "7FF#${MID}00${CMD_ZERO}" 2>/dev/null
        sleep 0.2
        cansend "$IF" "7FF#${MID}00${CMD_ENABLE}" 2>/dev/null
        sleep 0.3
        log "  [${IF}] Motor ${m} enable + zero calibration done"
    done
done
log ">>> Motor initialization complete"
echo ""

# ---- Build frame ----
build_frame() {
    local frame="" remaining i
    for ((i=0; i<NUM_MOTORS; i++)); do
        frame+="$MOTOR_ZERO_DATA"
    done
    remaining=$((8 - NUM_MOTORS))
    for ((i=0; i<remaining; i++)); do
        frame+="0000000000000000"
    done
    echo "$frame"
}
FRAME_DATA=$(build_frame)
log " Frame data: ${FRAME_DATA}"

# ---- candump error monitor (background) ----
start_error_monitor() {
    local ifs="" IF
    for IF in "${INTERFACES[@]}"; do
        ifs+="${IF},"
    done
    ifs="${ifs%,}"

    stdbuf -oL candump -L "${ifs}" 2>/dev/null | \
    stdbuf -oL grep -E '^$$[0-9.]+$$\s+can[0-9]+\s+00[1-7]#' | \
    while read -r line; do
        local ts iface midhex data err_byte err_code mid err_hex err_name msg
        ts=$(echo "$line" | awk '{print $1}' | tr -d '()')
        iface=$(echo "$line" | awk '{print $2}')
        midhex=$(echo "$line" | awk '{print $3}' | cut -d'#' -f1)
        data=$(echo "$line" | awk '{print $3}' | cut -d'#' -f2)

        err_byte=$((16#${data:0:2}))
        err_code=$(( err_byte & 0x1F ))

        if [[ $err_code -ne 0 ]]; then
            mid=$((16#$midhex))
            err_hex=$(printf '%02X' $err_code)
            err_name="${LRO_ERR_MAP[$err_hex]:-UNKNOWN(0x${err_hex})}"
            msg="[${ts}] ${iface} motor_${mid}: ${err_name} | raw=${data}"
            echo "${msg}" >> "${ERROR_LOG}"
            echo "${msg}"
        fi
    done >> "${LOG_DIR}/errors/candump_stream.log" 2>/dev/null &
    CANDUMP_PID=$!
}

stop_error_monitor() {
    [[ -n "${CANDUMP_PID}" ]] && kill "${CANDUMP_PID}" 2>/dev/null
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
echo "timestamp,burst_round,total_sent,total_fail,total_errors,bus_off,restarts" \
    > "${STATS_CSV}"

# ---- Get interface status summary ----
get_if_states() {
    local states="" IF st
    for IF in "${INTERFACES[@]}"; do
        st=$(ip link show "$IF" 2>/dev/null | grep -oE "ERROR-(ACTIVE|WARNING|PASSIVE)|BUS-OFF|NOARP" | head -1)
        [[ -z "$st" ]] && st="UP"
        states+="${st} "
    done
    echo "${states% }"
}

# ---- BUS-OFF auto recovery ----
check_and_rescue() {
    local IF state
    for IF in "${INTERFACES[@]}"; do
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
}

# ---- Start background tasks ----
start_error_monitor
dmesg_snapshot_loop &
DMESG_PID=$!

START_EPOCH=$(date +%s)
TEST_END=$(( START_EPOCH + TEST_DURATION_HOURS * 3600 ))
SLEEP_US=$(( 1000000 / MIT_HZ ))

command -v usleep &>/dev/null && HAS_USLEEP=true || HAS_USLEEP=false

log "=========================================="
log " Stress test started"
log " Expected duration: ${TEST_DURATION_HOURS} hours"
log " Burst per round: ${BURST_COUNT} frames @ ${MIT_HZ}Hz"
log " Deadline: $(date -d @${TEST_END} '+%H:%M:%S' 2>/dev/null || echo 'N/A')"
log " Ctrl+C to stop and save logs at any time"
log "=========================================="
echo ""

LAST_STATS_PRINT=0

# ================ Main loop ================
while [[ $(date +%s) -lt ${TEST_END} ]]; do
    ((BURST_ROUND++))

    ROUND_START=$(date +%s%N)
    ROUND_SENT=0
    ROUND_FAIL=0

    # -- Burst send --
    for ((i=1; i<=BURST_COUNT; i++)); do
        if cansend "${INTERFACES[0]}" "${CANID}##1${FRAME_DATA}" 2>/dev/null; then
            ((ROUND_SENT++))
            ((TOTAL_SENT++))
        else
            ((ROUND_FAIL++))
            ((TOTAL_FAIL++))
        fi
        if $HAS_USLEEP; then
            usleep "$SLEEP_US" 2>/dev/null
        else
            sleep 0.00134
        fi
    done

    ROUND_END=$(date +%s%N)
    ROUND_MS=$(( (ROUND_END - ROUND_START) / 1000000 ))

    # -- Auto check BUS-OFF and recover --
    check_and_rescue

    # -- Periodic status print --
    NOW=$(date +%s)
    if (( NOW - LAST_STATS_PRINT >= STATS_INTERVAL )); then
        LAST_STATS_PRINT=$NOW
        ELAPSED=$(( NOW - START_EPOCH ))
        REMAINING=$(( TEST_END - NOW ))

        # Interface stats
        for IF in "${INTERFACES[@]}"; do
            IF_TX[$IF]=$(cat /sys/class/net/${IF}/statistics/tx_packets 2>/dev/null || echo 0)
            IF_RX[$IF]=$(cat /sys/class/net/${IF}/statistics/rx_packets 2>/dev/null || echo 0)
        done

        IF_STATES=$(get_if_states)
        echo "$(date '+%Y-%m-%d %H:%M:%S'),${BURST_ROUND},${TOTAL_SENT},${TOTAL_FAIL},${TOTAL_ERRORS},${TOTAL_BUS_OFF},${TOTAL_RESTARTS}" \
            >> "${STATS_CSV}"

        # ---- Fix: no local, direct assignment in main loop ----
        hrs=$(( ELAPSED / 3600 ))
        rem_hrs=$(( REMAINING / 3600 ))
        rem_mins=$(( (REMAINING % 3600) / 60 ))

        log "------ Status @ ${hrs}h ------"
        log "  Round:      ${BURST_ROUND}"
        log "  Sent:       ${TOTAL_SENT}  Failed: ${TOTAL_FAIL}"
        log "  Motor err:  ${TOTAL_ERRORS}"
        log "  BUS-OFF:    ${TOTAL_BUS_OFF}  Recovered: ${TOTAL_RESTARTS}"
        log "  Interfaces: ${IF_STATES}"
        log "  Remaining:  ${rem_hrs}h${rem_mins}m"
        log "  Last round: ${ROUND_MS}ms (${BURST_COUNT} frames)"

        for IF in "${INTERFACES[@]}"; do
            log "  [${IF}] TX=${IF_TX[$IF]:-0} RX=${IF_RX[$IF]:-0}"
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
        echo "[$(date '+%H:%M:%S')] round=${BURST_ROUND} sent=${TOTAL_SENT} fail=${TOTAL_FAIL} errors=${TOTAL_ERRORS}" \
            >> "${LOG_DIR}/cycles/progress.log"
    fi

    sleep "${BURST_INTERVAL}"
done

# Normal exit
log ">>> Test time elapsed, normal exit <<<"
