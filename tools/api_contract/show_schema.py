"""Print schema properties or an operation from the ThingsBoard OpenAPI (for fixtures).

Usage:
  python -I tools/api_contract/show_schema.py --spec <openapi.json> schema AlarmInfo [Other ...]
  python -I tools/api_contract/show_schema.py --spec <openapi.json> op GET /api/v2/alarms
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec as tb  # noqa: E402


def describe(prop):
    ref = tb.prop_ref(prop)
    kind = prop.get("type") or ref or "object"
    if prop.get("enum"):
        kind += " enum(" + "|".join(map(str, prop["enum"])) + ")"
    elif ref and not prop.get("type"):
        target = tb.get_schema(SPEC, ref) or {}
        if target.get("enum"):
            kind += " enum(" + "|".join(map(str, target["enum"])) + ")"
    if prop.get("type") == "array" and ref:
        kind = f"array<{ref}>"
    return kind


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("what", choices=["schema", "op"])
    parser.add_argument("names", nargs="+")
    args = parser.parse_args()
    global SPEC
    SPEC = tb.load_spec(args.spec)

    if args.what == "schema":
        for name in args.names:
            props, required = tb.schema_props(SPEC, {"$ref": f"#/components/schemas/{name}"})
            print(f"{name}  (required: {', '.join(sorted(required)) or '-'})")
            for prop, value in props.items():
                print(f"  {prop}: {describe(value)}")
    else:
        method, path = args.names[0].lower(), args.names[1]
        op = SPEC["paths"][path][method]
        print(f"{method.upper()} {path}  operationId={op.get('operationId')}")
        for param in op.get("parameters", []):
            if "$ref" in param:
                param = SPEC["components"]["parameters"][tb.ref_name(param["$ref"])]
            schema = param.get("schema", {})
            print(f"  {param['in']}: {param['name']} {'REQUIRED' if param.get('required') else 'optional'} {describe(schema)}")
        body = op.get("requestBody")
        if body:
            media = next(iter(body.get("content", {}).values()), {})
            print(f"  body: {media.get('schema')}")
        print(f"  200: {op.get('responses', {}).get('200', {}).get('content')}")


if __name__ == "__main__":
    main()
