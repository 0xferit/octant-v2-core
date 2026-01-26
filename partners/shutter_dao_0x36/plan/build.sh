#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 << EOF
import os

script_dir = "$SCRIPT_DIR"
fonts_dir = os.path.join(script_dir, "fonts")
template_path = os.path.join(script_dir, "template.html")
output_path = os.path.join(script_dir, "..", "plan.html")

# Read template
with open(template_path, "r") as f:
    content = f.read()

# Font replacements
fonts = [
    ("FONT_ARCANE_FABLE", "arcane-fable.b64"),
    ("FONT_SPIEGEL_SANS_400", "spiegel-sans-400.b64"),
    ("FONT_SPIEGEL_SANS_600", "spiegel-sans-600.b64"),
    ("FONT_IBM_PLEX_MONO_400", "ibm-plex-mono-400.b64"),
    ("FONT_IBM_PLEX_MONO_500", "ibm-plex-mono-500.b64"),
    ("FONT_IBM_PLEX_MONO_600", "ibm-plex-mono-600.b64"),
]

print("Replacing font placeholders...")
for placeholder, filename in fonts:
    font_path = os.path.join(fonts_dir, filename)
    with open(font_path, "r") as f:
        font_data = f.read()
    content = content.replace("{{" + placeholder + "}}", font_data)
    print(f"  - {placeholder}")

# Write output
with open(output_path, "w") as f:
    f.write(content)

file_size = os.path.getsize(output_path)
print(f"Generated: {output_path} ({file_size} bytes)")
EOF
