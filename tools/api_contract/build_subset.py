"""Build a small, offline contract snapshot from the full ThingsBoard OpenAPI document.

Only the operations the app can call (every '/api/...' literal found in lib/core) and the
schemas those operations use are kept, so CI never needs the 1.8 MB spec or the network.

Usage:
  python -I tools/api_contract/build_subset.py --spec <openapi.json> \
      [--lib lib/core] [--out test/fixtures/contract/tb_pe_4_4_1_subset.json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_endpoints as scan_mod  # noqa: E402
import spec as tb  # noqa: E402


def shallow(spec, schema):
    """type/enum/items of a (possibly $ref-ed) schema, one level deep."""
    if not isinstance(schema, dict):
        return {}
    if "$ref" in schema:
        schema = tb.get_schema(spec, tb.ref_name(schema["$ref"])) or {}
    out = {}
    if "type" in schema:
        out["type"] = schema["type"]
    if "enum" in schema:
        out["enum"] = schema["enum"]
    items = schema.get("items")
    if isinstance(items, dict):
        inner = shallow(spec, items)
        if inner:
            out["items"] = inner
    return out


def resolve_param(spec, param):
    if "$ref" in param:
        name = tb.ref_name(param["$ref"])
        param = spec.get("components", {}).get("parameters", {}).get(name, {})
    entry = {"name": param.get("name"), "in": param.get("in"), "required": bool(param.get("required"))}
    entry.update(shallow(spec, param.get("schema", {})))
    return entry


def body_info(spec, op):
    request = op.get("requestBody")
    if not request:
        return None
    content = request.get("content", {})
    media = content.get("application/json") or next(iter(content.values()), {})
    schema = media.get("schema", {})
    props, required = tb.schema_props(spec, schema)
    items = schema.get("items") if isinstance(schema, dict) else None
    return {
        "required": bool(request.get("required")),
        "array": isinstance(schema, dict) and schema.get("type") == "array",
        "ref": tb.prop_ref(schema) or (tb.ref_name(schema["$ref"]) if "$ref" in schema else None),
        "free": not props,
        "props": {name: shallow(spec, value) for name, value in props.items()},
        "requiredProps": sorted(required),
        "itemsRef": tb.ref_name(items["$ref"]) if isinstance(items, dict) and "$ref" in items else None,
        "node": node_of(spec, schema),
    }


def response_ref(op):
    ok = op.get("responses", {}).get("200", {})
    schema = ok.get("content", {}).get("application/json", {}).get("schema", {})
    if "$ref" in schema:
        return tb.ref_name(schema["$ref"])
    items = schema.get("items", {})
    if "$ref" in items:
        return "array<" + tb.ref_name(items["$ref"]) + ">"
    return schema.get("type")


def response_schema(op):
    ok = op.get("responses", {}).get("200", {})
    return ok.get("content", {}).get("application/json", {}).get("schema")


# ---- compact schema graph (used to validate request bodies and responses) ----

MAX_REF_DEPTH = 4  # schema hops from an operation root; deeper refs are treated as free-form


def _first_type(schema):
    kind = schema.get("type")
    if isinstance(kind, list):  # OpenAPI 3.1 nullable: ["string", "null"]
        kind = next((k for k in kind if k != "null"), None)
    return kind


def node_of(spec, schema):
    """Compact node: {'ref'} | {'free'} | {'type','enum','items','props','required','additional'}."""
    if not isinstance(schema, dict):
        return {"free": True}
    if "$ref" in schema:
        return {"ref": tb.ref_name(schema["$ref"])}
    if "oneOf" in schema or "anyOf" in schema:
        return {"free": True}
    all_of = schema.get("allOf")
    if all_of and len(all_of) == 1 and isinstance(all_of[0], dict) and "$ref" in all_of[0]:
        return {"ref": tb.ref_name(all_of[0]["$ref"])}
    node = {}
    kind = _first_type(schema)
    if kind:
        node["type"] = kind
    if "enum" in schema:
        node["enum"] = schema["enum"]
    if kind == "array":
        node["items"] = node_of(spec, schema.get("items", {}))
    if kind == "object" or "properties" in schema or all_of:
        props, required = tb.schema_props(spec, schema)
        if props:
            node["props"] = {k: node_of(spec, v) for k, v in sorted(props.items())}
            node["required"] = sorted(required)
        extra = schema.get("additionalProperties")
        if isinstance(extra, dict):
            node["additional"] = node_of(spec, extra)
    return node


def compile_schema(spec, name):
    schema = tb.get_schema(spec, name)
    if schema is None:
        return {"free": True}
    if "oneOf" in schema or "anyOf" in schema:
        return {"free": True}
    node = node_of(spec, schema)
    node.pop("ref", None)
    return node


def _refs_in(node):
    if not isinstance(node, dict):
        return
    if "ref" in node:
        yield node["ref"]
    for value in (node.get("props") or {}).values():
        yield from _refs_in(value)
    if "items" in node:
        yield from _refs_in(node["items"])
    if "additional" in node:
        yield from _refs_in(node["additional"])


def build_schema_graph(spec, roots):
    """Schemas reachable from the root nodes, at most MAX_REF_DEPTH hops away."""
    graph, frontier = {}, [(root, 1) for root in roots]
    while frontier:
        node, depth = frontier.pop()
        for ref in _refs_in(node):
            if ref in graph or depth > MAX_REF_DEPTH:
                continue
            graph[ref] = compile_schema(spec, ref)
            frontier.append((graph[ref], depth + 1))
    return graph


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--lib", default="lib/core")
    parser.add_argument("--out", default="test/fixtures/contract/tb_pe_4_4_1_subset.json")
    parser.add_argument(
        "--allow",
        default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "known_deviations.json"),
    )
    args = parser.parse_args()

    spec = tb.load_spec(args.spec)
    with open(args.allow, encoding="utf-8") as handle:
        known_deviations = set(json.load(handle).get("endpoints", {}))
    templates = set()
    for item in scan_mod.scan(args.lib):
        if item["path"] in scan_mod.NON_REST or item["path"].endswith("/"):
            continue
        # Reviewed non-spec paths must not drag a wildcard template into the snapshot,
        # otherwise typos like `/api/tenant/assetInfosTypo` would validate.
        if item["path"] in known_deviations:
            continue
        templates.update(tb.find_templates(spec, item["path"]))

    extra_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extra_operations.json")
    with open(extra_path, encoding="utf-8") as handle:
        for entry in json.load(handle)["operations"]:
            _, template = entry["op"].split(" ", 1)
            if template not in spec["paths"]:
                sys.exit(f"extra operation not in spec: {entry['op']}")
            templates.add(template)

    operations = {}
    for template in sorted(templates):
        path_item = spec["paths"][template]
        shared = [resolve_param(spec, p) for p in path_item.get("parameters", [])]
        for method in tb.HTTP_METHODS:
            op = path_item.get(method)
            if not op:
                continue
            params = shared + [resolve_param(spec, p) for p in op.get("parameters", [])]
            operations[f"{method.upper()} {template}"] = {
                "operationId": op.get("operationId"),
                "parameters": sorted(params, key=lambda p: (p["in"] or "", p["name"] or "")),
                "body": body_info(spec, op),
                "response": response_ref(op),
                "responseNode": node_of(spec, response_schema(op)),
            }

    roots = []
    for op in operations.values():
        roots.append(op["responseNode"])
        if op["body"]:
            roots.append(op["body"]["node"])

    out = {
        "specVersion": spec["info"].get("version"),
        "source": "https://demo.thingsboard.io/v3/api-docs",
        "operations": operations,
        "schemas": build_schema_graph(spec, roots),
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(out, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(f"operations: {len(operations)} -> {args.out} ({os.path.getsize(args.out):,} bytes)")


if __name__ == "__main__":
    main()
