#!/bin/bash
# origin-storage-review.sh — the read-only terminal audit Backspacer grew out of (kept for the
# record; catalog.json is the maintained form of this knowledge). Deletes nothing. Run:
#   bash _meta/origin-storage-review.sh 2>/dev/null | tee ~/Desktop/storage-review.txt

H="$HOME"
AS="$H/Library/Application Support"
kb() { du -skx "$1" 2>/dev/null | cut -f1; }           # size in KB (0 if missing)
hr() { awk -v k="$1" 'BEGIN{ if(k>=1048576) printf "%.1fG", k/1048576; else if(k>=1024) printf "%.0fM", k/1024; else printf "%dK", k }'; }
SAFE=0; REGEN=0; DECIDE=0
row() {  # row <bucket> <path> <label>   bucket: SAFE | REGEN | DECIDE | KEEP | LOCKED
  local b="$1" p="$2" l="$3" k; [ -e "$p" ] || return
  k=$(kb "$p"); [ "${k:-0}" -lt 10240 ] && return                  # skip < 10 MB
  printf "  %-7s %7s  %s\n" "$b" "$(hr "$k")" "$l"
  case $b in SAFE) SAFE=$((SAFE+k));; REGEN) REGEN=$((REGEN+k));; DECIDE) DECIDE=$((DECIDE+k));; esac
}
sec() { echo; echo "── $1"; }

echo "STORAGE REVIEW  $(date '+%Y-%m-%d %H:%M')   host: $(hostname -s)"
echo "Buckets: SAFE = delete now, no cost | REGEN = rebuilds itself, costs one slow build/launch"
echo "         DECIDE = your call | KEEP = needed for current work | LOCKED = SIP-protected"

sec "DISK"
df -h /System/Volumes/Data | tail -1 | awk '{print "  used " $3 "  free " $4 "  (" $5 ")"}'
n=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c TimeMachine); echo "  local snapshots: $n"
pgrep -fq Virtualization && echo "  ⚠ Claude VM process is RUNNING (deletes of vm_bundles won't free space until it exits)" || echo "  Claude VM process: not running"
[ -d "/System/Volumes/Data/macOS Install Data" ] && echo "  ⚠ macOS Install Data present: $(du -sh '/System/Volumes/Data/macOS Install Data' 2>/dev/null | cut -f1)"

sec "REGROWTH SOURCES (the things that kept refilling the disk)"
row DECIDE "$AS/Claude/vm_bundles"                    "Claude Desktop local VM image (re-created while a task is linked to this Mac)"
row SAFE   "$AS/Claude/local-agent-mode-sessions"     "Claude local-agent session data"
row SAFE   "$AS/Claude/claude-code-vm"                "Claude Code VM data"
row SAFE   "$AS/Claude/Cache"                         "Claude app cache"
row SAFE   "$AS/Claude/Code Cache"                    "Claude code cache"
row SAFE   "$AS/Claude/GPUCache"                      "Claude GPU cache"
row REGEN  "/System/Volumes/Data/.Spotlight-V100"     "Spotlight index (rebuilds; exclude ~/Projects & ~/Library to keep small)"
row KEEP   "/private/var/vm"                          "swap"

sec "CACHES — safe, zero cost"
row SAFE   "$H/Library/Caches"                        "~/Library/Caches (all apps rebuild theirs)"
row SAFE   "$H/.cache"                                "~/.cache"
row SAFE   "$H/Library/Developer/Xcode/DerivedData"   "Xcode DerivedData"
row SAFE   "/Library/Developer/CoreSimulator/Caches"  "Simulator dyld caches"
row SAFE   "$AS/Code/Cache"                           "VS Code cache"
row SAFE   "$AS/Code/CachedData"                      "VS Code cached data"
row SAFE   "$AS/Code/CachedExtensionVSIXs"            "VS Code cached extension installers"
row SAFE   "$AS/Code/logs"                            "VS Code logs"
row SAFE   "$AS/Code/User/workspaceStorage"           "VS Code workspace storage (per-folder state; safe)"
row SAFE   "$H/Library/Logs"                          "~/Library/Logs"
row SAFE   "$H/.Trash"                                "your Trash"
find "$H/Projects" -maxdepth 4 -type d -name ".next" 2>/dev/null | while read d; do row SAFE "$d/cache" "Next.js cache: ${d#$H/}"; done

sec "TOOLCHAIN CACHES — regenerable, cost = one slow build"
row REGEN  "$H/.gradle/caches"                        "Gradle dependency cache"
row REGEN  "$H/.gradle/wrapper/dists"                 "Gradle distributions (one per version any project asked for)"
row REGEN  "$H/.nuget"                                ".NET NuGet package cache"
row REGEN  "$H/.npm"                                  "npm cache"
row REGEN  "$H/Library/Caches/Yarn"                   "Yarn cache"
row REGEN  "$H/Library/pnpm"                          "pnpm store"
row REGEN  "$H/Library/Caches/CocoaPods"              "CocoaPods cache"
row REGEN  "$H/.cargo/registry"                       "Rust registry"
row REGEN  "$H/go/pkg/mod"                            "Go modules"
row REGEN  "$H/Library/Caches/Homebrew"               "Homebrew downloads (brew cleanup --prune=all -s)"

sec "AI TOOL SESSION HISTORY — your call"
row DECIDE "$H/.claude/projects"                      "Claude Code session transcripts"
row DECIDE "$H/.claude"                               "~/.claude total"
row DECIDE "$H/.codex"                                "Codex CLI sessions/logs"
row DECIDE "$H/.gemini"                               "Gemini CLI sessions/cache"
row DECIDE "$H/.antigravity"                          "Antigravity"
row DECIDE "$H/.antigravity-ide"                      "Antigravity IDE"
row DECIDE "$H/.cursor"                               "Cursor"
row DECIDE "$H/.kiro"                                 "Kiro"

sec "iOS / XCODE"
row KEEP   "/System/Volumes/Data/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime" "Simulator runtime images (LOCKED path; manage via xcrun simctl runtime delete)"
row DECIDE "$H/Library/Developer/Xcode/iOS DeviceSupport"  "Symbols for every iOS version ever plugged in — keep only current"
row DECIDE "$H/Library/Developer/CoreSimulator/Devices"    "Simulator devices — keep the 1–2 you boot"
row DECIDE "$H/Library/Developer/Xcode/Archives"           "Xcode archives (past builds)"
echo "  runtimes installed:"; xcrun simctl runtime list 2>/dev/null | sed 's/^/    /' | head -12
echo "  simulator devices: $(xcrun simctl list devices 2>/dev/null | grep -c '(')  (unavailable: $(xcrun simctl list devices unavailable 2>/dev/null | grep -c '('))"

sec "ANDROID"
row DECIDE "$H/Library/Android/sdk/system-images"     "Emulator system images (no AVDs exist → unused unless you create one)"
row DECIDE "$H/Library/Android/sdk/emulator"          "Emulator binary (unused without AVDs)"
row DECIDE "$H/Library/Android/sdk/ndk"               "NDK — only if a project uses native code"
row DECIDE "$H/Library/Android/sdk/sources"           "SDK sources (for IDE navigation only)"
row KEEP   "$H/Library/Android/sdk/platforms"         "platforms"
row KEEP   "$H/Library/Android/sdk/build-tools"       "build-tools"
row DECIDE "$H/.android"                              "~/.android (AVDs, adb keys)"
row KEEP   "$H/.gradle/jdks"                          "Gradle-managed JDKs"
[ -d "$H/Library/Android/sdk/ndk" ] && echo "  NDK versions: $(ls "$H/Library/Android/sdk/ndk" 2>/dev/null | tr '\n' ' ')"
[ -d "$H/.nvm/versions/node" ] && echo "  Node versions in nvm: $(ls "$H/.nvm/versions/node" 2>/dev/null | tr '\n' ' ')"

sec "APPLICATIONS — top 15 (delete any you no longer use)"
du -sk /Applications/* 2>/dev/null | sort -rn | head -15 | while read k p; do printf "  %-7s %7s  %s\n" DECIDE "$(hr $k)" "${p#/Applications/}"; done

sec "APP DATA — top 12 in ~/Library/Application Support"
du -sk "$AS"/* 2>/dev/null | sort -rn | head -12 | while read k p; do printf "  %-7s %7s  %s\n" DECIDE "$(hr $k)" "${p#$AS/}"; done
row DECIDE "$H/Library/Containers/com.apple.Safari"        "Safari data (clear via Safari → Clear History)"
row DECIDE "$H/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram" "Telegram media cache (clear in Telegram → Data & Storage)"
row SAFE   "$AS/com.apple.wallpaper"                       "Aerial wallpaper cache (switch to static wallpaper)"

sec "PROJECTS"
du -sk "$H"/Projects/*/* "$H"/Projects/* 2>/dev/null | sort -rn | awk '!seen[$2]++' | head -10 | while read k p; do printf "  %-7s %7s  %s\n" DECIDE "$(hr $k)" "${p#$H/Projects/}"; done
nm=0; for d in $(find "$H/Projects" -maxdepth 4 -type d \( -name node_modules -o -name Pods -o -name build -o -name .gradle -o -name DerivedData \) -prune 2>/dev/null); do nm=$((nm+$(kb "$d"))); done
printf "  %-7s %7s  %s\n" REGEN "$(hr $nm)" "all node_modules / Pods / build / .gradle inside ~/Projects (rebuild with npm install / pod install / gradle)"
echo "  untouched 60+ days:"; find "$H/Projects" -mindepth 2 -maxdepth 2 -type d -mtime +60 -exec du -sk {} \; 2>/dev/null | sort -rn | head -6 | while read k p; do printf "    %7s  %s\n" "$(hr $k)" "${p#$H/Projects/}"; done

sec "USER FILES"
row DECIDE "$H/Screenshots"                           "Screenshots folder"
row DECIDE "$H/Downloads"                             "Downloads"
row DECIDE "$H/Yandex.Disk.localized"                 "Yandex.Disk local copy"
find "$H/Desktop" -maxdepth 1 -name "*.mov" -size +50M 2>/dev/null | while read f; do row DECIDE "$f" "screen recording: $(basename "$f")"; done

sec "SYSTEM (sudo) — mostly fixed cost, listed so the numbers add up"
sudo du -sk /Library/* 2>/dev/null | sort -rn | head -6 | while read k p; do printf "  %-7s %7s  %s\n" INFO "$(hr $k)" "$p"; done
sudo du -sk /private/var/* 2>/dev/null | sort -rn | head -5 | while read k p; do printf "  %-7s %7s  %s\n" INFO "$(hr $k)" "$p"; done
sudo du -sk /System/Volumes/Data/System/Library/AssetsV2/* 2>/dev/null | sort -rn | head -6 | while read k p; do printf "  %-7s %7s  %s\n" LOCKED "$(hr $k)" "${p##*/}"; done
row INFO   "/opt"                                     "/opt (Homebrew; run: brew autoremove && brew cleanup)"
sudo ls -A /var/root/.Trash 2>/dev/null | grep -qv .DS_Store && echo "  ⚠ root's Trash is not empty: $(sudo du -sh /var/root/.Trash 2>/dev/null | cut -f1)"

echo
echo "══ TOTALS ═══════════════════════════════════════"
printf "  SAFE   (delete now, no cost)         %7s\n" "$(hr $SAFE)"
printf "  REGEN  (rebuilds; one slow build)    %7s\n" "$(hr $REGEN)"
printf "  DECIDE (your call)                   %7s\n" "$(hr $DECIDE)"
echo "  Nothing was deleted. Paste this file back into the chat."
