"""Compare the JSON keys each Dart model reads/writes with the OpenAPI schema.

Usage:
  python -I tools/api_contract/audit_models.py --spec <openapi.json> \
      [--models lib/core/models] [--allow tools/api_contract/known_deviations.json] [--md out.md]

Checks per class in model_schema_map.json:
  * fromJson reads a key that is NOT in the schema      -> FAIL (typo / non-existent field)
  * toJson writes a key that is NOT in the schema       -> FAIL (server ignores or rejects it)
  * schema `required` property never read by fromJson   -> WARN
  * schema property ignored by fromJson                 -> INFO (informational only)
Nested keys (`assignee?['firstName']`) are checked against the schema referenced by the
property named like the variable (heuristic; unresolved ones are reported as INFO).
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec as tb  # noqa: E402

INDEX = re.compile(r"\b([A-Za-z_]\w*)\s*\??\s*\[\s*'([^']+)'\s*\]")
HELPER = re.compile(r"\(\s*([A-Za-z_]\w*)\s*,\s*'([^']+)'")
CONTAINS = re.compile(r"\.containsKey\(\s*'([^']+)'\s*\)")
MAP_KEY = re.compile(r"'([A-Za-z_]\w*)'\s*:")


def extract_body(text, start):
    """Return the text of the {...} block that begins at/after index `start`."""
    open_idx = text.index("{", start)
    depth, i = 0, open_idx
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_idx:i + 1]
        i += 1
    return text[open_idx:]


def collect(models_dir):
    """class -> {'read': {var: set(keys)}, 'write': set(keys)}"""
    found = {}
    for name in sorted(os.listdir(models_dir)):
        if not name.endswith(".dart"):
            continue
        with open(os.path.join(models_dir, name), encoding="utf-8") as handle:
            text = handle.read()
        for match in re.finditer(r"factory\s+(\w+)(?:<[^>]*>)?\.fromJson\s*\(", text):
            cls = match.group(1)
            # Skip the parameter list `(...)`, then take the factory body.
            close = text.index(")", match.end())
            body = extract_body(text, close)
            read = {}
            for var, key in INDEX.findall(body):
                read.setdefault(var, set()).add(key)
            for var, key in HELPER.findall(body):
                read.setdefault(var, set()).add(key)
            for key in CONTAINS.findall(body):
                read.setdefault("json", set()).add(key)
            found.setdefault(cls, {"read": {}, "write": set(), "file": name})["read"] = read
        for match in re.finditer(r"Map<String,\s*dynamic>\s+toJson\s*\(\s*\)", text):
            body = extract_body(text, match.end())
            owner = None
            for cm in re.finditer(r"\bclass\s+(\w+)", text[:match.start()]):
                owner = cm.group(1)
            if owner:
                found.setdefault(owner, {"read": {}, "write": set(), "file": name})
                found[owner]["write"].update(MAP_KEY.findall(body))
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--models", default="lib/core/models")
    parser.add_argument("--map", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "model_schema_map.json"))
    parser.add_argument("--allow")
    parser.add_argument("--md")
    args = parser.parse_args()

    spec = tb.load_spec(args.spec)
    mapping = {k: v for k, v in json.load(open(args.map, encoding="utf-8")).items() if not k.startswith("_")}
    allow = {}
    if args.allow:
        allow = json.load(open(args.allow, encoding="utf-8")).get("model_keys", {})
    found = collect(args.models)

    lines, failures = [], 0
    for cls in sorted(mapping):
        schemas = mapping[cls]
        info = found.get(cls)
        if info is None:
            lines.append(f"## {cls} -> {', '.join(schemas)}\n- FAIL: class/fromJson not found in `{args.models}`\n")
            failures += 1
            continue
        props, required = {}, set()
        for schema in schemas:
            if tb.get_schema(spec, schema) is None:
                lines.append(f"## {cls}\n- FAIL: schema `{schema}` not in spec\n")
                failures += 1
                continue
            p, r = tb.schema_props(spec, {"$ref": f"#/components/schemas/{schema}"})
            props.update(p)
            required |= r
        out = [f"## {cls} -> {', '.join(schemas)}  ({info['file']})"]
        top = info["read"].get("json", set())
        for key in sorted(top - set(props)):
            if f"{cls}.{key}" in allow:
                out.append(f"- ACCEPTED: reads `{key}` not in schema — {allow[f'{cls}.{key}']}")
            else:
                out.append(f"- FAIL: fromJson reads `{key}` which is NOT in the schema")
                failures += 1
        for var, keys in sorted(info["read"].items()):
            if var == "json":
                continue
            ref = tb.prop_ref(props.get(var))
            if not ref:
                out.append(f"- INFO: nested `{var}[{', '.join(sorted(keys))}]` could not be resolved to a schema")
                continue
            nested, _ = tb.schema_props(spec, {"$ref": f"#/components/schemas/{ref}"})
            for key in sorted(keys - set(nested)):
                if f"{cls}.{var}.{key}" in allow:
                    out.append(f"- ACCEPTED: nested `{var}.{key}` — {allow[f'{cls}.{var}.{key}']}")
                else:
                    out.append(f"- FAIL: nested `{var}['{key}']` is NOT in schema `{ref}`")
                    failures += 1
        if cls != "PageData":
            for key in sorted(info["write"] - set(props)):
                if f"{cls}.toJson.{key}" in allow:
                    out.append(f"- ACCEPTED: toJson writes `{key}` — {allow[f'{cls}.toJson.{key}']}")
                else:
                    out.append(f"- FAIL: toJson writes `{key}` which is NOT in the schema")
                    failures += 1
        for key in sorted(required - top):
            out.append(f"- WARN: required schema property `{key}` is never read")
        ignored = sorted(set(props) - top - required - set(info["read"]))
        if ignored:
            out.append(f"- INFO: schema properties ignored by the app: {', '.join(ignored)}")
        if len(out) == 1:
            out.append("- OK")
        lines.append("\n".join(out) + "\n")

    report = "\n".join(lines)
    print(report)
    print(f"Total model failures: {failures}")
    if args.md:
        with open(args.md, "w", encoding="utf-8") as handle:
            handle.write(report + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
