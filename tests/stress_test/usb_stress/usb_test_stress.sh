#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 YutongChenVictor
#=============================================================
# USB Hub hot-plug stress test
# Controls Hub RESET pin via GPIO to simulate physical plug/unplug
#=============================================================

TOTAL_CYCLES=100
HUB_RESET="/sys/class/leds/usb_hub_reset/brightness"
OFF_TIME=2       # Disconnect hold time (seconds)
ON_TIME=5        # Wait time after recovery for enumeration (seconds)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/home/${SUDO_USER:-$USER}/usb_stress_${TIMESTAMP}"
mkdir -p "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/main.log"
RESULT="${LOG_DIR}/result.log"
FAIL_COUNT=0
PASS_COUNT=0

log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${MAIN_LOG}"; }
save() {
    local d="${LOG_DIR}/cycle_$(printf '%03d' "$1")"
    mkdir -p "$d"
    dmesg > "$d/dmesg.txt" 2>&1
    lsusb > "$d/lsusb.txt" 2>&1
    lsusb -t > "$d/lsusb_tree.txt" 2>&1
    ls /dev/ttyUSB* /dev/ttyACM* /dev/video* 2>/dev/null > "$d/devices.txt"
}

hub_off() { echo 1 | sudo tee "${HUB_RESET}" > /dev/null; }
hub_on()  { echo 0 | sudo tee "${HUB_RESET}" > /dev/null; }

cleanup() {
    log "Interrupted, restoring Hub..."
    hub_on
    echo -e "\n===== Summary: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} =====" | tee -a "${RESULT}"
    exit 0
}
trap cleanup SIGINT SIGTERM

#--- Initialization ---
if ! sudo test -w "${HUB_RESET}"; then
    echo "ERROR: ${HUB_RESET} is not writable"; exit 1
fi
sudo dmesg -C
dmesg > "${LOG_DIR}/dmesg_initial.txt" 2>&1
lsusb > "${LOG_DIR}/lsusb_initial.txt" 2>&1

log "========== USB Hot-Plug Stress Test =========="
log "  Cycles:  ${TOTAL_CYCLES}"
log "  Off:     ${OFF_TIME}s  On: ${ON_TIME}s"
log "  Log dir: ${LOG_DIR}"
log "==============================================="

BEFORE=$(lsusb | sort)

for i in $(seq 1 "${TOTAL_CYCLES}"); do
    log "---- Round ${i}/${TOTAL_CYCLES} ----"

    # Disconnect
    hub_off
    log "  Hub disconnected"
    sleep "${OFF_TIME}"

    # Recover
    hub_on
    log "  Hub recovered, waiting for enumeration..."
    sleep "${ON_TIME}"

    # Verify
    AFTER=$(lsusb | sort)
    BEFORE_CNT=$(echo "${BEFORE}" | wc -l)
    AFTER_CNT=$(echo "${AFTER}" | wc -l)

    # Check for kernel anomalies
    OOPS=$(dmesg | grep -ciE "oops|panic|call trace|bug:" || true)

    if [[ "${AFTER_CNT}" -ge "${BEFORE_CNT}" && "${OOPS}" -eq 0 ]]; then
        log "  PASS (devices ${BEFORE_CNT}->${AFTER_CNT})"
        echo "[${i}] PASS  devices=${AFTER_CNT}" >> "${RESULT}"
        ((PASS_COUNT++))
    else
        log "  ** FAIL ** (devices ${BEFORE_CNT}->${AFTER_CNT}, oops=${OOPS})"
        echo "[${i}] FAIL  devices=${BEFORE_CNT}->${AFTER_CNT} oops=${OOPS}" >> "${RESULT}"
        ((FAIL_COUNT++))
        save "$i"
    fi

    # Save snapshot every 10 rounds
    if (( i % 10 == 0 )); then
        save "$i"
        log ">>> Progress ${i}/${TOTAL_CYCLES}  PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} <<<"
    fi

    BEFORE="${AFTER}"
done

#--- Finalization ---
hub_on
dmesg > "${LOG_DIR}/dmesg_final.txt" 2>&1
lsusb -v > "${LOG_DIR}/lsusb_final_verbose.txt" 2>&1

echo "" | tee -a "${RESULT}"
echo "======================================" | tee -a "${RESULT}"
echo " Test complete: ${TOTAL_CYCLES} rounds" | tee -a "${RESULT}"
echo " PASS: ${PASS_COUNT}" | tee -a "${RESULT}"
echo " FAIL: ${FAIL_COUNT}" | tee -a "${RESULT}"
echo " Log dir: ${LOG_DIR}" | tee -a "${RESULT}"
echo "======================================" | tee -a "${RESULT}"
