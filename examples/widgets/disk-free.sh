#!/bin/sh
# dylan: interval=5m
# Example Dylan script widget: free space on the data volume.
# Copy to ~/.config/dylan/widgets/ and make it executable (chmod +x).
# Output: one JSON object {title, value, state, progress, url, activity}.
vol=/System/Volumes/Data
[ -d "$vol" ] || vol=/
df -k "$vol" | awk 'NR==2 {
  used = $3 / ($3 + $4)
  state = used >= 0.9 ? "warn" : "ok"
  printf "{\"title\":\"Disk\",\"value\":\"%.0f GB free\",\"state\":\"%s\",\"progress\":%.2f,\"activity\":false}\n", $4 / 1000000, state, used
}'
