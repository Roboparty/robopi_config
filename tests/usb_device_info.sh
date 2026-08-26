#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 YutongChenVictor
# USB device information query script - Query device info for VID:PID 1209:2323

# Check if lsusb command exists
if ! command -v lsusb >/dev/null 2>&1; then
    echo "Error: lsusb command not found, please install usbutils package"
    exit 1
fi

# Define target device VID and PID
VID_PID="1209:2323"

echo "Querying USB device ${VID_PID} information..."
echo "========================================"

# Execute lsusb command and filter key information
lsusb -v -d "${VID_PID}" | grep -E 'bcdUSB|bcdDevice'

# Check if there is output
if [ $? -ne 0 ]; then
    echo "Device ${VID_PID} not found or not connected"
    exit 1
fi

echo "========================================"
echo "Query completed"
