# shellcheck shell=bash

test_config_is_valid_json() {
  check node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' \
    "$ROOT/config/opencode.jsonc"
  assert_exit 0
}
test_config_uses_v2_shapes() {
  check node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(!d.mcp?.servers?.headroom) throw new Error("mcp.servers.headroom");
    if(!d.mcp?.servers?.serena) throw new Error("mcp.servers.serena");
    if(!d.providers?.headroom) throw new Error("providers.headroom");
    if(d.mcp?.headroom) throw new Error("v1 mcp");
    if(d.provider) throw new Error("v1 provider");
  ' "$ROOT/config/opencode.jsonc"; assert_exit 0
}
test_payload_has_no_absolute_home_paths() {
  local dir
  for dir in config plugins skills delegate; do
    check test -d "$ROOT/$dir"; assert_exit 0
  done
  check bash -c '! grep -RE "/(home|Users|root)/" "$@"' _ \
    "$ROOT/config" "$ROOT/plugins" "$ROOT/skills" "$ROOT/delegate"
  assert_exit 0
}
test_plugins_import_v2_package_only() {
  check grep -q '@opencode/plugin' "$ROOT/plugins/rtk.ts"; assert_exit 0
  check grep -q '@opencode/plugin' "$ROOT/plugins/graphify.js"; assert_exit 0
  check grep -q '@opencode-ai/plugin' "$ROOT/config/package.json"; assert_exit 1
}
# npm derives a lockfile root name from the directory when package.json has no
# identity, which rewrites the committed lock in ~/.config/opencode.
test_package_json_has_stable_identity() {
  check node -e '
    const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(p.name!=="opencode") throw new Error("name="+p.name);
    if(p.version!=="0.0.0") throw new Error("version="+p.version);
    if(p.private!==true) throw new Error("private="+p.private);
  ' "$ROOT/config/package.json"; assert_exit 0
}
test_delegate_lanes_are_valid() {
  check node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const lanes=Object.entries(d.lanes||{});
    if(lanes.length!==7) throw new Error("expected 7 lanes");
    for(const [id,l] of lanes) if(!l.implementer) throw new Error(id+" missing implementer");
  ' "$ROOT/delegate/config.json"; assert_exit 0
}
test_vendored_skills_have_frontmatter() {
  for s in graphify orchestrating-spec-pipelines; do
    check grep -q '^name:' "$ROOT/skills/$s/SKILL.md"; assert_exit 0
  done
}
