"""Appbox helper for BookBridge: create the first admin, or reset its password.

Uses BookBridge's own database layer (same schema migrations, same password
hashing) instead of writing SQL by hand.

    python /appbox_admin.py create   # USERNAME and PASSWORD from the environment
    python /appbox_admin.py reset    # NEW_PASSWORD (and optionally USERNAME)

Exit codes: 0 = done (or nothing to do), 1 = failed.
"""

import logging
import os
import sys

APP_DIR = os.environ.get("BOOKBRIDGE_APP_DIR", "/app")
sys.path.insert(0, APP_DIR)
os.chdir(APP_DIR)

logging.basicConfig(level=logging.WARNING)

from src.db.migration_utils import get_database_service  # noqa: E402


def create(db) -> int:
    username = (os.environ.get("USERNAME") or "").strip()
    password = os.environ.get("PASSWORD") or ""

    # Setup is only allowed while no users exist.
    if db.count_users() != 0:
        print("An account already exists; skipping admin creation.")
        return 0
    if not username or not password:
        print("USERNAME and PASSWORD must be set to create the admin account.")
        return 1

    from src.db.user_bootstrap import create_initial_admin_user

    user, _counts = create_initial_admin_user(db, username, password)
    print(f"Admin user created: {user.username}")
    return 0


def reset(db) -> int:
    password = os.environ.get("NEW_PASSWORD") or ""
    wanted = (os.environ.get("USERNAME") or "").strip().lower()
    if not password:
        print("NEW_PASSWORD must be set.")
        return 1

    admins = [u for u in db.list_users() if u.role == "admin"]
    if not admins:
        print("No admin account found to update.")
        return 1

    # Prefer the named admin; fall back to the first one if it was renamed.
    target = next((u for u in admins if u.username.lower() == wanted), admins[0])

    if not db.set_user_password(target.id, password):
        print("Password update failed.")
        return 1
    db.set_user_active(target.id, True)
    print(f"Password updated for user: {target.username}")
    return 0


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action not in ("create", "reset"):
        print("Usage: appbox_admin.py create|reset")
        return 1
    db = get_database_service(os.environ.get("DATA_DIR", "/data"))
    return create(db) if action == "create" else reset(db)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - report and fail, never hang the install
        print(f"appbox_admin failed: {exc}")
        sys.exit(1)
