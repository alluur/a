#!/usr/bin/env bash
# apk.sh - builds an Android APK from an A program. The app is a NativeActivity: its libmain.so is the A program compiled
# with -shared (it exports ANativeActivity_onCreate, see examples/android/hello.a). No Java, Gradle or NDK is needed.
#
#   tools/apk.sh --app FILE.a --id com.example.app --name "App Name" [--version 1.0] [--version-code 1]
#                [--release release] [--abis arm64-v8a,x86_64] [--min-sdk 24] [--target-sdk 34]
#                [--orientation landscape|portrait|any] [--out DIR]
#
# The result is DIR/{Name}-{version-code}-{release}.apk (the name without spaces), aligned and signed with:
#   A_KEYSTORE (or AGE_KEYSTORE)        the keystore file
#   A_KEY_ALIAS (or AGE_KEY_ALIAS)      the key alias (default: release)
#   A_KEYSTORE_PASS / A_KEY_PASS        the passwords (or AGE_KEYSTORE_PASS / AGE_KEY_PASS), read from the environment only
# Without a keystore the APK is left unsigned and named {Name}-{version-code}-unsigned.apk.
#
# Needs: the A compiler (AC, default build/ac or ac), aapt, zip, zipalign, apksigner (when signing) and an android.jar
# (ANDROID_JAR, default the newest /usr/lib/android-sdk/platforms/android-*/android.jar). On Debian / Ubuntu:
#   apt install aapt zipalign apksigner android-sdk-platform-23 zip
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="" ID="" NAME="" VERSION="1.0" VCODE="1" RELEASE="release" ABIS="arm64-v8a,x86_64" MIN_SDK=24 TARGET_SDK=34
ORIENT="landscape" OUT="dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2;;
    --id) ID="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --version-code) VCODE="$2"; shift 2;;
    --release) RELEASE="$2"; shift 2;;
    --abis) ABIS="$2"; shift 2;;
    --min-sdk) MIN_SDK="$2"; shift 2;;
    --target-sdk) TARGET_SDK="$2"; shift 2;;
    --orientation) ORIENT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "apk.sh: unknown option $1" >&2; exit 2;;
  esac
done
die() { echo "apk.sh: $*" >&2; exit 1; }
[[ -n "$APP" && -n "$ID" && -n "$NAME" ]] || die "usage: apk.sh --app FILE.a --id com.example.app --name \"App Name\" [options]"
[[ -f "$APP" ]] || die "no such file: $APP"
[[ "$ID" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] || die "invalid application id '$ID' (use reverse-DNS form like com.example.game)"
[[ "$VCODE" =~ ^[0-9]+$ ]] || die "--version-code must be a number"
case "$ORIENT" in portrait) SCREEN="sensorPortrait";; any|auto) SCREEN="fullSensor";; *) SCREEN="sensorLandscape";; esac

AC="${AC:-}"
if [[ -z "$AC" ]]; then
  if [[ -x "$HERE/../build/ac" ]]; then AC="$HERE/../build/ac"; else AC="$(command -v ac || true)"; fi
fi
[[ -x "$AC" ]] || die "the A compiler was not found (build it with make, or set AC)"
AAPT="$(command -v aapt || true)"; ZIPALIGN="$(command -v zipalign || true)"; APKSIGNER="$(command -v apksigner || true)"
[[ -n "$AAPT" ]] || die "aapt is missing (apt install aapt)"
[[ -n "$ZIPALIGN" ]] || die "zipalign is missing (apt install zipalign)"
command -v zip >/dev/null || die "zip is missing (apt install zip)"
JAR="${ANDROID_JAR:-$(ls /usr/lib/android-sdk/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -n1)}"
[[ -f "$JAR" ]] || die "no android.jar (apt install android-sdk-platform-23, or set ANDROID_JAR)"

FILE_NAME="$(printf '%s' "$NAME" | tr -cd 'A-Za-z0-9_.-')"
[[ -n "$FILE_NAME" ]] || die "the app name has no usable characters for a file name"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# ---- the native library for every ABI
IFS=',' read -ra ABI_LIST <<< "$ABIS"
for abi in "${ABI_LIST[@]}"; do
  case "$abi" in
    arm64-v8a) T=android;;
    x86_64) T=android-x64;;
    riscv64) T=android-riscv64;;
    *) die "unsupported ABI '$abi' (arm64-v8a, x86_64, riscv64)";;
  esac
  mkdir -p "$WORK/lib/$abi"
  "$AC" -t "$T" -shared "$APP" -o "$WORK/lib/$abi/libmain.so" || die "compiling $APP for $abi failed"
done

# ---- the manifest: a NativeActivity without Java code; the libraries are extracted at install time (any page size)
xml_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
cat > "$WORK/AndroidManifest.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$ID" android:versionCode="$VCODE" android:versionName="$(xml_escape "$VERSION")">
    <uses-sdk android:minSdkVersion="$MIN_SDK" android:targetSdkVersion="$TARGET_SDK"/>
    <uses-feature android:glEsVersion="0x00020000" android:required="true"/>
    <application android:label="$(xml_escape "$NAME")" android:hasCode="false" android:extractNativeLibs="true">
        <activity android:name="android.app.NativeActivity" android:exported="true"
            android:screenOrientation="$SCREEN" android:configChanges="orientation|screenSize|keyboardHidden|screenLayout"
            android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
            <meta-data android:name="android.app.lib_name" android:value="main"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
XML

# ---- package, add the libraries, align, sign
"$AAPT" package -f -M "$WORK/AndroidManifest.xml" -I "$JAR" -F "$WORK/base.apk" >/dev/null || die "aapt failed"
(cd "$WORK" && zip -q -r base.apk lib)
"$ZIPALIGN" -f -p 4 "$WORK/base.apk" "$WORK/aligned.apk" || die "zipalign failed"

KS="${A_KEYSTORE:-${AGE_KEYSTORE:-}}"
if [[ -z "$KS" ]]; then
  DEST="$OUT/$FILE_NAME-$VCODE-unsigned.apk"
  cp "$WORK/aligned.apk" "$DEST"
  echo "apk.sh: no keystore (A_KEYSTORE): $DEST is NOT signed and cannot be installed until it is"
  exit 0
fi
[[ -f "$KS" ]] || die "keystore not found: $KS"
[[ -n "$APKSIGNER" ]] || die "apksigner is missing (apt install apksigner)"
export A_SIGN_KS_PASS="${A_KEYSTORE_PASS:-${AGE_KEYSTORE_PASS:-}}" A_SIGN_KEY_PASS="${A_KEY_PASS:-${AGE_KEY_PASS:-${A_KEYSTORE_PASS:-${AGE_KEYSTORE_PASS:-}}}}"
[[ -n "$A_SIGN_KS_PASS" ]] || die "A_KEYSTORE_PASS is not set"
ALIAS="${A_KEY_ALIAS:-${AGE_KEY_ALIAS:-release}}"
DEST="$OUT/$FILE_NAME-$VCODE-$RELEASE.apk"
"$APKSIGNER" sign --ks "$KS" --ks-key-alias "$ALIAS" --ks-pass env:A_SIGN_KS_PASS --key-pass env:A_SIGN_KEY_PASS \
  --v4-signing-enabled false --out "$DEST" "$WORK/aligned.apk" || die "signing failed"
"$APKSIGNER" verify "$DEST" || die "the signature does not verify"
echo "apk.sh: $DEST"
