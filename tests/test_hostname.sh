#!/bin/sh
# Unit tests for raspi-config
# shellcheck disable=SC1091

# Mock the id command to pretend we're root (for testing only)
# shellcheck disable=SC2329
id() {
    if [ "$1" = "-u" ]; then
        echo "0"
    else
        command id "$@"
    fi
}

# Mock systemctl to return success for dbus check
systemctl() {
    if [ "$1" = "-q" ] && [ "$2" = "is-active" ] && [ "$3" = "dbus" ]; then
        return 0
    fi
    return 1
}


export INTERACTIVE=False  # Prevent interactive menu from launching

# Source the script under test
. ../raspi-config

# Test setup
setUp() {
    # Create a temporary test directory
    TEST_DIR=$(mktemp -d)
    # Set the mock environment variables
    export MOCK_HOSTNAME_FILE="$TEST_DIR/hostname"
    export MOCK_HOSTS_FILE="$TEST_DIR/hosts"
    INIT=systemd

    ASK_TO_REBOOT=0

    # Mock hostnamectl to record the call
    hostnamectl() {
        if [ "$1" = "hostname" ]; then
            echo "$2" > "$MOCK_HOSTNAME_FILE"
            echo "$2" > "$TEST_DIR/hostnamectl_called"
        fi
    }

    # Mock ischroot to return false (not in chroot)
    ischroot() {
        return 1
    }

    # Initialize test files
    echo "oldhost" > "$MOCK_HOSTNAME_FILE"
}

# Test teardown
tearDown() {
    # Clean up temporary files
    rm -rf "$TEST_DIR"
}

test_get_hostname_simple() {
    assertEquals "$(get_hostname)" "oldhost"
}

# Test get_hostname strips whitespace and comments
test_get_hostname_strips_whitespace() {
    printf " #hostname\n new-host \nanother \n\r\t" > "$MOCK_HOSTNAME_FILE"
    assertEquals "$(get_hostname)" "new-host"
}

test_get_hostname_empty() {
    : > "$MOCK_HOSTNAME_FILE"
    assertEquals "$(get_hostname)" ""
}

test_do_hostname_ask_to_reboot() {
    do_hostname "oldhost"
    assertEquals "0" "$ASK_TO_REBOOT"

    do_hostname "newhost"
    assertEquals "1" "$ASK_TO_REBOOT"
}

# Test do_hostname with systemd path (uses hostnamectl)
test_do_hostname_systemd() {
    do_hostname "newhost-systemd"

    # Verify hostnamectl was called with the new hostname
    assertTrue "hostnamectl should have been called" "[ -f $TEST_DIR/hostnamectl_called ]"
    assertEquals "$(get_hostname)" "newhost-systemd"

    # Mock hostnamectl failure
    hostnamectl() {
        rm -f $TEST_DIR/hostnamectl_called
        return 1
    }

    do_hostname "newhost-systemd2"
    assertFalse "hostnamectl should have failed" "[ -f $TEST_DIR/hostnamectl_called ]"
    assertEquals "$(get_hostname)" "newhost-systemd2"
}

# Test do_hostname falls back to non-systemd path when in chroot
test_do_hostname_systemd_chroot_fallback() {
    # Mock ischroot to return true (in chroot)
    ischroot() {
        return 0
    }

    do_hostname "newhost"

    # Verify hostname was written to file (fallback path)
    assertEquals "$(get_hostname)" "newhost"
}

test_do_hostname_non_systemd() {
    export INIT=sysvinit

    do_hostname "newhost"
    assertEquals "$(get_hostname)" "newhost"
    assertFalse "hostnamectl should not have been called" "[ -f $TEST_DIR/hostnamectl_called ]"
}

test_do_hostname_updates_hosts_existing_entry() {
    cat > "$MOCK_HOSTS_FILE" <<EOF
127.0.0.1	localhost
127.0.1.1	oldhost
::1		localhost ip6-localhost ip6-loopback
EOF

    do_hostname "newhost"

    # Verify hosts file was updated
    grep -q "^127\.0\.1\.1[[:space:]].*newhost" "$MOCK_HOSTS_FILE"
    assertTrue "hosts file should contain new hostname" $?

    grep -q "oldhost" "$MOCK_HOSTS_FILE"
    assertFalse "hosts file should not contain old hostname" $?
}

# Test do_hostname with no existing 127.0.1.1 entry
test_do_hostname_no_hosts_entry() {
    cat > "$MOCK_HOSTS_FILE" <<EOF
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
EOF

    do_hostname "newhost"

    # Verify hosts file was left unchanged (no new entry added)
    grep -q "^127\.0\.1\.1[[:space:]]" "$MOCK_HOSTS_FILE"
    assertFalse "hosts file should not have 127.0.1.1 entry added" $?

    # Verify original entries are still there
    grep -q "^127\.0\.0\.1[[:space:]].*localhost" "$MOCK_HOSTS_FILE"
    assertTrue "hosts file should still contain localhost entry" $?
}

. shunit2

exit 0
