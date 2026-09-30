#!/usr/bin/env bash

set -Eeuo pipefail

current_major="${PG_MAJOR:?}"
old_major="${OLD_PG_MAJOR:-13}"
pgdata="${PGDATA:?}"
# pg_upgrade must run as the install user of the old cluster, which the
# init script creates as POSTGRES_USER
upgrade_user="${PG_UPGRADE_USER:-${POSTGRES_USER:-postgres}}"
old_bindir="/opt/postgresql${old_major}/bin"
new_bindir="/usr/libexec/postgresql${current_major}"
backup_dir="${pgdata}-v${old_major}"
upgrade_root="/config/db_check/pg_upgrade-${old_major}-to-${current_major}"
socket_dir="/tmp/pg_upgrade"
success=0
moved=0

# Run as root so PGDATA can be moved inside /config (owned by root); the
# PostgreSQL tools themselves must run as the postgres system user
as_postgres() {
    if [ "$(id -u)" = "0" ]; then
        gosu postgres "$@"
    else
        "$@"
    fi
}

if [ ! -s "${pgdata}/PG_VERSION" ]; then
    echo "No PG_VERSION file found, skipping migration."
    exit 0
fi

detected_major="$(cat "${pgdata}/PG_VERSION")"
echo "Detected PG_VERSION: ${detected_major}"

if [ "${detected_major}" = "${current_major}" ]; then
    echo "Data directory is already PostgreSQL ${current_major}, skipping migration."
    exit 0
fi

if [ "${detected_major}" != "${old_major}" ]; then
    echo "Unsupported PostgreSQL data version ${detected_major}. Expected ${old_major} or ${current_major}." >&2
    exit 1
fi

if [ -e "${backup_dir}" ]; then
    echo "Migration cannot continue because backup directory ${backup_dir} already exists." >&2
    echo "Resolve or remove that directory before retrying startup." >&2
    exit 1
fi

if [ ! -w "$(dirname "${pgdata}")" ]; then
    echo "Migration cannot continue because $(dirname "${pgdata}") is not writable by $(id -un)." >&2
    echo "PGDATA was left untouched." >&2
    exit 1
fi

if [ ! -x "${old_bindir}/postgres" ] || [ ! -x "${new_bindir}/pg_upgrade" ] || [ ! -x "${new_bindir}/initdb" ]; then
    echo "Required PostgreSQL upgrade binaries are missing." >&2
    exit 1
fi

cleanup() {
    local exit_code=$?

    rm -rf "${socket_dir}"
    if [ -n "${pwfile:-}" ] && [ -f "${pwfile}" ]; then
        rm -f "${pwfile}"
    fi

    # Only touch PGDATA once the original data has been moved to backup_dir;
    # before that, PGDATA still holds the original cluster
    if [ "${success}" -ne 1 ] && [ "${moved}" -eq 1 ] && [ -d "${backup_dir}" ]; then
        echo "PostgreSQL major upgrade failed. Restoring original PGDATA." >&2
        rm -rf "${pgdata}"
        mv "${backup_dir}" "${pgdata}"
    elif [ "${success}" -ne 1 ]; then
        echo "PostgreSQL major upgrade failed. PGDATA was left in place." >&2
    fi

    exit "${exit_code}"
}

trap cleanup EXIT

echo "Detected PostgreSQL ${old_major} data directory. Starting automated upgrade to ${current_major}."
echo "Using PostgreSQL superuser '${upgrade_user}' for upgrade operations."

mkdir -p "${upgrade_root}" "${socket_dir}"
chown postgres:postgres "${upgrade_root}" "${socket_dir}" 2>/dev/null || :
chmod 700 "${socket_dir}"

# pg_upgrade requires a cleanly shut down old cluster. Start and stop it once
# with the old binaries, which also completes any crash recovery.
echo "Ensuring PostgreSQL ${old_major} cluster was shut down cleanly..."
rm -f "${pgdata}/postmaster.pid"
as_postgres "${old_bindir}/pg_ctl" -D "${pgdata}" -w -t 120 \
    -o "-c listen_addresses='' -c unix_socket_directories=${socket_dir}" \
    -l "${upgrade_root}/old-cluster-shutdown.log" start
as_postgres "${old_bindir}/pg_ctl" -D "${pgdata}" -w -t 120 -m fast stop

mv "${pgdata}" "${backup_dir}"
moved=1
mkdir -p "${pgdata}"
chown postgres:postgres "${pgdata}" 2>/dev/null || :
chmod 700 "${pgdata}"

pwfile="$(mktemp)"
printf '%s\n' "${POSTGRES_PASSWORD:-}" > "${pwfile}"
chown postgres:postgres "${pwfile}" 2>/dev/null || :

as_postgres "${new_bindir}/initdb" \
    --username="${upgrade_user}" \
    --pwfile="${pwfile}" \
    -D "${pgdata}"

cd "${upgrade_root}"

echo "Running pg_upgrade in copy mode from ${backup_dir} to ${pgdata}."

as_postgres "${new_bindir}/pg_upgrade" \
    --old-bindir="${old_bindir}" \
    --new-bindir="${new_bindir}" \
    --old-datadir="${backup_dir}" \
    --new-datadir="${pgdata}" \
    --copy \
    --username="${upgrade_user}" \
    --jobs="$(getconf _NPROCESSORS_ONLN)" \
    --retain \
    --socketdir="${socket_dir}" \
    --old-options="-c listen_addresses='' -c unix_socket_directories=${socket_dir}" \
    --new-options="-c listen_addresses='' -c unix_socket_directories=${socket_dir}" \
    --verbose

# Keep the authentication rules of the old cluster; initdb defaults differ
cp -p "${backup_dir}/pg_hba.conf" "${pgdata}/pg_hba.conf"

success=1

echo "PostgreSQL upgrade completed successfully."
echo "Old PostgreSQL ${old_major} data remains at ${backup_dir} until you remove it."
if [ -f "${upgrade_root}/analyze_new_cluster.sh" ]; then
    echo "Analyze script generated at ${upgrade_root}/analyze_new_cluster.sh"
fi