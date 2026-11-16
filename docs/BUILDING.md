# Building and releasing

## Local development

`python3 tools/setup.py` downloads the pinned Godot into `.tools/`, builds the
native Iroh library for this CPU, and imports the project. It needs Python 3.11+
and Rust (rustup). Nothing is installed outside the checkout.

```sh
python3 tools/godot.py            # run the game
python3 tools/godot.py --editor   # open the editor
python3 tools/godot.py -- --solo  # jump straight into a solo launch
python3 tools/check.py            # all tests
python3 tools/check.py --rules-only   # unit tests only, no Iroh processes
```

Without the native library the game still runs; only party mode is disabled.
After changing Rust code, close the game and editor and run
`python3 tools/build_native.py --host-only`.

Screenshots of every screen, for eyeballing layout at a given size:

```sh
python3 tools/godot.py --resolution 1170x540 --script res://tests/render.gd
```

They land in `build/shots/`. This opens a real window and is not part of CI.

## Assets and Git LFS

Images, audio, fonts and native binaries are tracked by Git LFS (see
`.gitattributes`). Install LFS before cloning (`git lfs install`), or run
`git lfs pull` afterwards. A clone without LFS has pointer files where the art
should be and Godot will fail to import them.

## Desktop exports

Run on the operating system you are building for:

```sh
python3 tools/export.py linux
python3 tools/export.py windows
python3 tools/export.py macos
```

The script downloads matching export templates, builds the native library
(both architectures on macOS), exports, launches the exported game headless to
prove the native library loads, and writes a zip plus SHA-256 into
`build/artifacts/`. macOS builds are ad hoc signed and not notarized; Windows
builds are unsigned.

## Android

Install JDK 17 and the Android SDK, then:

```sh
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/Android/sdk
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;35.0.1' 'ndk;28.1.13356709'
python3 tools/export.py android
adb install -r build/artifacts/cannonauts-android.apk
```

The build cross-compiles the Iroh library for ARM64, packages the small
`IrohAndroid` Java bridge (it gives Iroh an application context so DNS works),
and produces a debug-signed APK for Android 10+. The game is locked to
landscape and runs in immersive mode.

### Signing key

Android only installs an update over an existing app when both are signed with
the same key. CI signs every APK with one development key, supplied through the
`ANDROID_KEYSTORE_BASE64` repository secret (alias `androiddebugkey`, password
`android`), so each release installs over the previous one. Builds up to
`v0.1.2` predate that key: uninstall one of those once before updating.

The keystore itself is not in the repository. To sign local exports with the
same key, so they install over CI builds and the other way round, point the
export at the file:

```sh
ANDROID_KEYSTORE_FILE=/path/to/cannonauts-dev.keystore python3 tools/export.py android
```

Without either variable the export generates a throwaway debug key in `.tools/`.

If the secret is ever lost, create a new key and set it again; everyone then
has to uninstall once:

```sh
keytool -genkeypair -keystore cannonauts-dev.keystore -storepass android -keypass android \
  -alias androiddebugkey -dname "CN=Cannonauts Development" -keyalg RSA -keysize 2048 -validity 10000
base64 < cannonauts-dev.keystore | gh secret set ANDROID_KEYSTORE_BASE64
```

This is a development identity, guarded only by who can read the secret. For a
store release, use a proper release keystore with a real password, Godot's
release signing settings and an AAB.

## GitHub Actions

`.github/workflows/build.yml` runs on every push to `main`, on pull requests,
and on manual dispatch:

1. Stamp the build number: `tools/stamp.py N` writes version `0.1.N` into
   `project.godot` and `export_presets.cfg` (Android `versionCode` = N), where N
   is the workflow run number. It only ever goes up.
2. Build the native library on Linux, Windows and macOS, and cross-compile it
   for Android.
3. Run `tools/check.py`: rules tests, protocol tests, and a real match between
   one host and two client processes over Iroh.
4. Export and package each platform.
5. On `main` only, publish a GitHub release tagged `v0.1.N` with the APK and the
   three desktop zips, marked as latest. Pull requests build but do not release.

A release appears only if all four platform jobs pass. Re-running a workflow
keeps its number and replaces that release's files.

`relay-smoke.yml` is a manual workflow that forces relay-only connections, kept
separate so a public relay outage does not look like a broken commit.

## Updating tools

Change Godot's version and all four download hashes in `tools/versions.json`
together, and match the feature version in `project.godot`. Change Iroh or
gdext in `native/iroh/Cargo.toml`, regenerate `Cargo.lock`, rebuild every
platform, and rerun both the direct and relay tests. Regenerate dependency
notices with `python3 tools/licenses.py`.
