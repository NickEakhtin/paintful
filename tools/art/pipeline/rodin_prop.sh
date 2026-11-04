#!/usr/bin/env bash
# Rodin base_basic_pbr.glb -> game prop: weld, simplify, textures 1024, aged brass/dark paint, pivot.
# Usage: rodin_prop.sh in.glb out.glb <name> <seed> <simplify_ratio> <floor|wall>
# Needs: `npm install` in tools/pipeline (package.json); python3 with numpy, Pillow.
set -e
in=$1; out=$2; name=$3; seed=$4; ratio=$5; mode=$6
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d)
"$here/node_modules/.bin/gltf-transform" weld "$in" $tmp/1.glb >/dev/null
"$here/node_modules/.bin/gltf-transform" simplify $tmp/1.glb $tmp/2.glb --ratio $ratio --error 0.001 >/dev/null
"$here/node_modules/.bin/gltf-transform" resize $tmp/2.glb $tmp/3.glb --width 1024 --height 1024 >/dev/null
node "$here/teximg.mjs" get $tmp/3.glb BaseColorTexture $tmp/bc.png >/dev/null
node "$here/teximg.mjs" get $tmp/3.glb MetallicRoughnessTexture $tmp/mr.png >/dev/null
python3 -I "$here/age_brass.py" $tmp/bc.png $tmp/mr.png $tmp/bc.jpg $tmp/mr.jpg $seed
node "$here/teximg.mjs" set $tmp/3.glb BaseColorTexture $tmp/bc.jpg $tmp/4.glb
node "$here/teximg.mjs" set $tmp/4.glb MetallicRoughnessTexture $tmp/mr.jpg $tmp/5.glb
node "$here/pivot.mjs" $tmp/5.glb "$out" $mode $name
rm -rf $tmp
