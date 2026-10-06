# BookBridge for Appbox

Packaged [BookBridge](https://github.com/cporcellijr/bookbridge), which syncs reading and listening progress across Audiobookshelf, KOReader, Storyteller, Grimmory, BookOrbit, Kavita and others. Follows the [Appbox example app](https://github.com/appbox-co/example-app) guide.

This is an unofficial community package. It runs the official BookBridge image unmodified; BookBridge is MIT licensed.

## Layout

BookBridge is one process with an embedded SQLite database, so this follows the guide's single-process pattern: no s6-overlay, no extra services.

The `Dockerfile` adds gosu, a UID 1000 user and three scripts to the upstream image. `entrypoint.sh` fixes ownership, creates the admin on a fresh install, fires the Appbox callback and then starts the app as 1000:1000. `appbox_admin.py` and `moduser.sh` handle admin creation and password resets using BookBridge's own database code. `icon.png` is BookBridge's icon resized to 512x512.

Notes for reviewers:

- The upstream image runs as root, so this adds a UID 1000 account and drops to it with gosu. Everything BookBridge writes lives under `/data`.
- BookBridge's first-run setup is a CSRF-protected browser form, so the admin is created before the server starts by calling its own `create_initial_admin_user`. There is no public registration; the admin adds other readers.
- `data` is mounted at `/data` and holds the SQLite database, the key that encrypts stored service credentials, caches, Whisper models and logs.
- The user's home is mounted read-only at `/APPBOX_DATA`. The "Ebook Folder" install field seeds BookBridge's Books Directory setting, which can be changed later in Settings. Switch `permissions` to `rw` if a feature ever needs to write there.
- The dashboard and the KOReader sync API share port 5757 behind the platform's reverse proxy. Split-port mode (`KOSYNC_PORT`) isn't used.
- `SESSION_COOKIE_SECURE=true` is set in `appbox.yml` because the platform serves the app over HTTPS.
- To upgrade, bump `BOOKBRIDGE_VERSION` in the `Dockerfile` and `image.version` / `image.tag` in `appbox.yml`. BookBridge migrates its database on start.

## Build and test

```bash
docker build --platform linux/amd64 -t bookbridge-appbox .

docker volume create bb-data
mkdir -p books

# Fresh install
docker run -d --name bookbridge --platform linux/amd64 \
  -e USERNAME=admin -e PASSWORD='TestPass123!' \
  -e BOOKS_DIR=/APPBOX_DATA \
  -e INSTANCE_ID=test -e SKIP_APPBOX_CALLBACK=1 \
  -v bb-data:/data -v "$PWD/books:/APPBOX_DATA:ro" \
  -p 5757:5757 bookbridge-appbox
docker logs -f bookbridge       # look for "Admin user created: admin"
# open http://localhost:5757 and log in

# Restart (must skip setup)
docker restart bookbridge

# Every process should show UID 1000 (the image has no ps, so read /proc)
docker exec bookbridge sh -c 'for p in /proc/[0-9]*; do echo "$(stat -c %u $p) $(tr "\0" " " < $p/cmdline)"; done'

# Password reset
docker exec bookbridge /moduser.sh 'NewPass456!'
docker exec bookbridge /moduser.sh; echo "exit=$?"   # usage, exit=1

# Clean shutdown within 10s
time docker stop bookbridge

# Upgrade (same volume, new container; must skip admin creation)
docker rm -f bookbridge   # then repeat the docker run above
```

Do not set `SESSION_COOKIE_SECURE` when testing over plain `http://localhost`, or the login will not stick.
