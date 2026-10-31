#!/usr/bin/env bash
# Deploy the latest commit of the configured branch to this server (after setup-server.sh).
#
#   sudo optics-update                 # pull, install deps, back up if migrations are pending,
#                                      # migrate, collectstatic, restart, health check
#   sudo optics-update --no-pull       # redeploy the code that is checked out now (rollback:
#                                      #   cd /srv/optics/app && sudo -u optics git checkout <commit>
#                                      #   sudo optics-update --no-pull)
#   sudo optics-update --no-backup     # skip the automatic pre-migration backup
set -euo pipefail

main() {
  local here pull=1 backup=1 before
  here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  # shellcheck source=deploy/lib.sh
  . "$here/lib.sh"
  require_root
  cd /
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-pull) pull=0 ;;
      --no-backup) backup=0 ;;
      -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [ -f "$DEPLOY_CONF" ] || die "$DEPLOY_CONF missing: run deploy/setup-server.sh first"
  # shellcheck disable=SC1090
  . "$DEPLOY_CONF"

  if [ "$pull" -eq 1 ]; then
    step "Pulling $BRANCH"
    before="$(sudo -u optics git -C "$APP_DIR" rev-parse --short HEAD)"
    sudo -u optics env GIT_TERMINAL_PROMPT=0 git -C "$APP_DIR" fetch --quiet origin "$BRANCH"
    sudo -u optics git -C "$APP_DIR" checkout --quiet "$BRANCH"
    sudo -u optics git -C "$APP_DIR" merge --ff-only --quiet "origin/$BRANCH" \
      || die "local changes or diverged history in $APP_DIR; fix by hand (git status)"
    ok "$before → $(sudo -u optics git -C "$APP_DIR" rev-parse --short HEAD)"
    echo "    (rollback: cd $APP_DIR && sudo -u optics git checkout $before && sudo optics-update --no-pull)"
    # Continue with the freshly pulled version of this script.
    local args=(--no-pull); [ "$backup" -eq 0 ] && args+=(--no-backup)
    exec bash "$APP_DIR/deploy/update.sh" "${args[@]}"
  fi

  step "Deploying $(sudo -u optics git -C "$APP_DIR" log -1 --format='%h %s')"
  check_env_file

  step "Python packages"
  sudo -H -u optics "$VENV/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt"
  ensure_layout
  ok "installed from requirements.txt"

  step "Database migrations"
  if manage migrate --check >/dev/null 2>&1; then
    ok "no pending migrations"
  else
    manage showmigrations --plan | grep '^\[ \]' || true
    if [ "$backup" -eq 1 ] && backups_configured; then
      echo "    taking a backup first..."
      systemctl start optics-backup.service || die "backup failed (journalctl -u optics-backup); nothing was migrated"
      ok "backup uploaded"
    elif [ "$backup" -eq 1 ]; then
      warn "R2 backups are not configured: migrating without a backup"
    fi
    manage migrate --noinput
    ok "migrated"
  fi

  step "Static files and checks"
  manage collectstatic --noinput -v 0
  manage check --deploy --fail-level WARNING
  ok "done"

  step "Services"
  install_units
  render_nginx
  systemctl restart optics-api
  ok "optics-api restarted"
  if backups_configured; then systemctl enable --now optics-backup.timer >/dev/null; fi

  step "Health check"
  health_check || die "the new version does not answer: check the logs, or roll back (see above)"
  echo
  echo "${G}${B}Update finished.${N}"
}

main "$@"
