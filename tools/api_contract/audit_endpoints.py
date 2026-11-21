"""Cross-check every '/api/...' endpoint literal in the Dart code with the OpenAPI spec.

Usage:
  python -I tools/api_contract/audit_endpoints.py --spec <openapi.json> [--lib lib/core] [--md out.md]

Exit code 1 when a path is missing from the spec, or an inferred HTTP method is not
defined for that path. Method inference is best-effort and flagged as such.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec as tb  # noqa: E402

CALL = re.compile(r"\.(get|post|put|delete|patch)\w*\s*(?:<[^()]*>)?\s*\(", re.S)
# Not REST resources in the OpenAPI document.
NON_REST = {"/api/ws"}
SKIP_DIRS = {"mock"}


def iter_api_literals(text):
    """Yield (start, end, content) for Dart string literals starting with '/api/'.

    Handles escapes and `${...}` interpolation (including nested quotes and braces).
    """
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in "'\"" and text.startswith("/api/", i + 1):
            quote, j, depth, buf = ch, i + 1, 0, []
            while j < n:
                c = text[j]
                if depth == 0 and c == "\\":
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if depth == 0 and c == quote:
                    break
                if c == "$" and j + 1 < n and text[j + 1] == "{":
                    depth, buf = depth + 1, buf + ["${"]
                    j += 2
                    continue
                if depth > 0:
                    if c == "{":
                        depth += 1
                    elif c == "}":
                        depth -= 1
                buf.append(c)
                j += 1
            yield i, j + 1, "".join(buf)
            i = j + 1
        else:
            i += 1


def normalize(raw):
    # Collapse `${ ... }` blocks (which may contain nested braces/quotes) to `{}`.
    out, i, n = [], 0, len(raw)
    while i < n:
        if raw.startswith("${", i):
            depth, j = 1, i + 2
            while j < n and depth:
                depth += (raw[j] == "{") - (raw[j] == "}")
                j += 1
            out.append("{}")
            i = j
        else:
            out.append(raw[i])
            i += 1
    path = re.sub(r"\$[A-Za-z_]\w*", "{}", "".join(out))
    return path.split("?", 1)[0]


def infer_method(text, start, end):
    back = text[max(0, start - 200):start]
    last = None
    for match in CALL.finditer(back):
        last = match
    if last and ";" not in back[last.end():]:
        return last.group(1), "call-before"
    fwd = text[end:end + 400]
    match = CALL.search(fwd)
    if match and ";" not in fwd[:match.start()]:
        return match.group(1), "call-after"
    return None, "unknown"


def scan(lib_dir):
    results = []
    for root, dirs, files in os.walk(lib_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            full = os.path.join(root, name)
            with open(full, encoding="utf-8") as handle:
                text = handle.read()
            for start, end, content in iter_api_literals(text):
                line = text.count("\n", 0, start) + 1
                method, how = infer_method(text, start, end)
                results.append(
                    {
                        "file": os.path.relpath(full).replace("\\", "/"),
                        "line": line,
                        "raw": content,
                        "path": normalize(content),
                        "method": method,
                        "how": how,
                    }
                )
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--lib", default="lib/core")
    parser.add_argument("--allow")
    parser.add_argument("--md")
    args = parser.parse_args()

    spec = tb.load_spec(args.spec)
    allow = {}
    if args.allow:
        with open(args.allow, encoding="utf-8") as handle:
            allow = json.load(handle).get("endpoints", {})
    rows, failures = [], 0
    for item in scan(args.lib):
        if item["path"] in NON_REST:
            status = "SKIP (non-REST)"
        elif item["path"].endswith("/"):
            status = "SKIP (prefix check)"
        else:
            templates = tb.find_templates(spec, item["path"])
            if not templates:
                status, failures = "NO_PATH", failures + 1
            else:
                allowed = sorted(
                    {m for t in templates for m in spec["paths"][t] if m in tb.HTTP_METHODS}
                )
                if item["method"] and item["method"] not in allowed:
                    status, failures = f"NO_METHOD (spec: {','.join(allowed)})", failures + 1
                else:
                    # `WARN` = a literal code segment only matched a spec path parameter
                    # (value-like, e.g. `general`->{type}, or a path the spec lacks).
                    notes = tb.literal_for_param(item["path"], templates[0])
                    tag = "OK"
                    if notes and item["path"] in allow:
                        tag = "ACCEPTED"
                    elif notes:
                        tag, failures = "WARN", failures + 1
                    status = f"{tag} [{templates[0]}]" + (f" literal: {', '.join(notes)}" if notes else "")
        rows.append((item, status))

    # Operations whose path is assembled at runtime must still exist in the spec.
    extra_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extra_operations.json")
    with open(extra_path, encoding="utf-8") as handle:
        for entry in json.load(handle)["operations"]:
            method, template = entry["op"].split(" ", 1)
            exists = template in spec["paths"] and method.lower() in spec["paths"][template]
            if not exists:
                failures += 1
            rows.append(
                (
                    {"file": "tools/api_contract/extra_operations.json", "line": 0,
                     "raw": template, "path": template, "method": method.lower(), "how": "declared"},
                    f"OK [{template}] (declared)" if exists else "NO_PATH (declared extra)",
                )
            )

    lines =["| Status | Method | Path in code | Location |", "|---|---|---|---|"]
    for item, status in sorted(rows, key=lambda r: (r[1].startswith(("OK", "SKIP")), r[0]["file"], r[0]["line"])):
        method = (item["method"] or "?").upper()
        hint = "" if item["how"] != "unknown" else " (method unknown)"
        lines.append(
            f"| {status} | {method}{hint} | `{item['raw']}` | {item['file']}:{item['line']} |"
        )
    report = "\n".join(lines)
    print(report)
    print(f"\nTotal literals: {len(rows)}  |  failures: {failures}")
    if args.md:
        with open(args.md, "w", encoding="utf-8") as handle:
            handle.write(report + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
