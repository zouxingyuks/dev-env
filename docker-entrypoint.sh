#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(id -u)" != 0 ]]; then
	exec sudo --preserve-env env "DEVBOX_USER=$(id -un)" "$0" "$@"
fi

install -d --owner="${DEVBOX_USER:-dev}" --group="${DEVBOX_USER:-dev}" \
	"/home/${DEVBOX_USER:-dev}/.cache" \
	"/home/${DEVBOX_USER:-dev}/.config" \
	"/home/${DEVBOX_USER:-dev}/.local" \
	"/home/${DEVBOX_USER:-dev}/.local/share" \
	"/home/${DEVBOX_USER:-dev}/.local/state"
install --owner="${DEVBOX_USER:-dev}" --group="${DEVBOX_USER:-dev}" \
	/usr/local/share/dev-env/zshrc "/home/${DEVBOX_USER:-dev}/.zshrc"

cleanup() {
	trap '' TERM INT
	kill -TERM "${COMMAND_PID:-}" "${DOCKERD_PID:-}" 2>/dev/null || true
	wait "${COMMAND_PID:-}" "${DOCKERD_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

mkdir -p /var/run/docker /var/lib/docker /var/lib/containerd
# These files can survive an unclean stop; the daemon is private to this container.
rm -f /var/run/docker.pid /var/run/docker.sock
dockerd --host=unix:///var/run/docker.sock --pidfile=/var/run/docker.pid &
DOCKERD_PID=$!

for attempt in {1..60}; do
	if timeout 2 docker --host=unix:///var/run/docker.sock info >/dev/null 2>&1; then
		runuser --user "${DEVBOX_USER:-dev}" -- "$@" &
		COMMAND_PID=$!
		# Poll both children: short commands must exit promptly, and a daemon
		# crash must stop the container instead of leaving it half-alive.
		while true; do
			running=$'\n'"$(jobs -pr)"$'\n'
			[[ "$running" == *$'\n'"${COMMAND_PID}"$'\n'* ]] || break
			[[ "$running" == *$'\n'"${DOCKERD_PID}"$'\n'* ]] || break
			sleep 1
		done
		if ! kill -0 "${DOCKERD_PID}" 2>/dev/null; then
			wait "${DOCKERD_PID}" || true
			exit 1
		fi
		status=0
		wait "${COMMAND_PID}" || status=$?
		exit "${status}"
	fi
	if ! kill -0 "${DOCKERD_PID}" 2>/dev/null; then
		wait "${DOCKERD_PID}" || true
		exit 1
	fi
	sleep 1
done

echo 'Docker daemon did not become ready after 60 attempts.' >&2
exit 1
