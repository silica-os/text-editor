#!/bin/sh
# Every file with an asset extension must have a row in ASSETS.md.
status=0
for file in $(git ls-files | grep -Ei '\.(png|jpe?g|svg|webp|gif|ttf|otf|wav|ogg|mp3)$'); do
  grep -q "\`$file\`" ASSETS.md || { echo "no row in ASSETS.md: $file"; status=1; }
done
exit $status
