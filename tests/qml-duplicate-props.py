#!/usr/bin/env python3
"""Fail if a QML file assigns the same property twice in one object (#48).

QML refuses such a file ("Property value set multiple times"), and every
component that imports it becomes unavailable. Line-based on purpose: it is
the regression a one-line edit produces, and it needs nothing but Python.
"""

import re
import sys

ASSIGN = re.compile(r"^\s*([A-Za-z_][\w.]*)\s*:(?!:)\s*(.*)$")
SKIP = ("property ", "signal ", "function ", "readonly ", "required ", "//")

found = 0
for path in sys.argv[1:]:
    blocks = [{}]
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            code = line.split("//", 1)[0]
            stripped = code.strip()
            match = ASSIGN.match(code)
            if match and not stripped.startswith(SKIP):
                name, value = match.group(1), match.group(2).strip()
                # `name: Type {` opens a nested object; its name is not a
                # property of this block in the sense QML checks.
                if not re.match(r"^[A-Z]\w*(\.\w+)*\s*\{", value):
                    seen = blocks[-1]
                    if name in seen:
                        print(
                            f"{path}:{number}: '{name}' already set at line {seen[name]}"
                        )
                        found += 1
                    else:
                        seen[name] = number
            for char in code:
                if char == "{":
                    blocks.append({})
                elif char == "}" and len(blocks) > 1:
                    blocks.pop()

sys.exit(1 if found else 0)
