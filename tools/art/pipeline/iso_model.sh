#!/bin/bash
# iso_model.sh model.glb out.png [az] [el] [ppm]
S=/tmp/claude-0/-home-claude/7ce1b33a-a892-5d10-b2ef-b07352f1bb43/scratchpad
T=$(mktemp -d -p $S); mkdir -p $T/scenes $T/m; cp "$1" $T/m/x.glb
printf '[ext_resource type="PackedScene" path="res://m/x.glb" id="1"]\n\n[node name="Models" type="Node3D" parent="."]\n\n[node name="%s" parent="Models" instance=ExtResource("1")]\n' "${6:-Model}" > $T/scenes/main.tscn
python3 -I $S/scene_iso.py $T "$2" ${3:-45} ${4:-30} ${5:-300}; rm -rf $T
