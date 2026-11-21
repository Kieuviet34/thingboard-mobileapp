"""Small helpers to read the ThingsBoard OpenAPI (3.x) document. Stdlib only."""

import json
import re

HTTP_METHODS = ("get", "post", "put", "delete", "patch")


def load_spec(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def ref_name(ref):
    return ref.rsplit("/", 1)[-1]


def get_schema(spec, name):
    return spec["components"]["schemas"].get(name)


def _merge(spec, schema, props, required, seen):
    """Collect properties/required from `schema`, following $ref/allOf/oneOf/anyOf."""
    if not isinstance(schema, dict):
        return
    ref = schema.get("$ref")
    if ref:
        name = ref_name(ref)
        if name in seen:
            return
        seen.add(name)
        _merge(spec, get_schema(spec, name), props, required, seen)
        return
    for key in ("allOf", "oneOf", "anyOf"):
        for part in schema.get(key, []) or []:
            _merge(spec, part, props, required, seen)
    for prop, value in (schema.get("properties") or {}).items():
        props.setdefault(prop, value)
    required.update(schema.get("required") or [])


def schema_props(spec, schema):
    """Return (properties, required) of a schema or $ref-ed schema (merged)."""
    props, required = {}, set()
    _merge(spec, schema, props, required, set())
    return props, required


def prop_ref(prop_schema):
    """Schema name referenced by a property (directly or as array items), else None."""
    if not isinstance(prop_schema, dict):
        return None
    if "$ref" in prop_schema:
        return ref_name(prop_schema["$ref"])
    items = prop_schema.get("items")
    if isinstance(items, dict) and "$ref" in items:
        return ref_name(items["$ref"])
    for key in ("allOf", "oneOf", "anyOf"):
        for part in prop_schema.get(key, []) or []:
            if isinstance(part, dict) and "$ref" in part:
                return ref_name(part["$ref"])
    return None


def path_regex(template):
    """Regex that matches a concrete path against an OpenAPI path template."""
    parts = [
        r"[^/]+" if re.fullmatch(r"\{[^}]+\}", seg) else re.escape(seg)
        for seg in template.split("/")
    ]
    return re.compile("^" + "/".join(parts) + "$")


def literal_for_param(code_path, template):
    """Code literals that landed on a template parameter, e.g. ['general->{type}']."""
    pairs = zip(code_path.strip("/").split("/"), template.strip("/").split("/"))
    return [f"{c}->{t}" for c, t in pairs if c != "{}" and t.startswith("{")]


def find_templates(spec, code_path):
    """Best-matching spec path templates for a code path where params are `{}`.

    A `{}` in the code matches any template segment; a literal code segment matches an
    equal literal or a template parameter. Only the templates with the most exact
    literal matches are returned, so `/api/alarm/info/{}` never binds to
    `/api/alarm/{alarmId}/comment`.
    """
    code_segments = code_path.strip("/").split("/")
    best_score, best = -1, []
    for template in spec["paths"]:
        tpl_segments = template.strip("/").split("/")
        if len(tpl_segments) != len(code_segments):
            continue
        score, ok = 0.0, True
        for code_seg, tpl_seg in zip(code_segments, tpl_segments):
            if code_seg == "{}":
                if tpl_seg.startswith("{"):
                    score += 0.5  # param-for-param beats param-for-literal
                continue
            if tpl_seg.startswith("{"):
                continue
            if code_seg == tpl_seg:
                score += 1
            else:
                ok = False
                break
        if not ok:
            continue
        if score > best_score:
            best_score, best = score, [template]
        elif score == best_score:
            best.append(template)
    return best
