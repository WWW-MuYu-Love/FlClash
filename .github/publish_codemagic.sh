#!/bin/bash
# Codemagic 构建完成后自动发版到 GitHub：
# 把 FlClash-unsigned.ipa 传到 WWW-MuYu-Love/FlClash 的正式版
# release（tag = v<version>-ios，如 v0.9.3-ios；不存在则新建并设
# 为 Latest，已存在则只换 IPA 附件，幂等，可重复跑）。
# 需要环境变量 GH_TOKEN（在 Codemagic 里配的加密变量；细粒度
# PAT，只有本仓库 Contents 写权限）。未设置时跳过并以成功退出，
# 不让发版配置缺失拖垮构建产物本身。
# 关键 API 调用失败一律报错退出，末尾回读正文与附件自检；查询/
# 新建 release 与改正文都打印 HTTP 状态码，失败时把 GitHub 的
# 错误正文一并打进日志（照搬 LiveContainer 发布脚本 2026-11-07
# 的硬化教训：令牌错配或 401/404 不可再悄悄报成功）。
set -o pipefail
# 故意不开 set -u（LiveContainer 构建 #5/#6/#8/#9 四次死在
# 「unbound variable」，runner 上原因始终未能实证；关键变量
# 在展开处加 ${VAR:-} 兜底）。

if [ -z "$GH_TOKEN" ]; then  echo "GH_TOKEN 未设置，跳过自动发版（IPA 仍在 Codemagic artifacts 里）"
  exit 0
fi

export REPO="WWW-MuYu-Love/FlClash"
API="https://api.github.com/repos/$REPO"
UPLOADS="https://uploads.github.com/repos/$REPO"
AUTH=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

# 变量先全部给默认值再逐个赋值；提交号优先用 Codemagic
# 自带的 CM_COMMIT，git 只作兜底。
SHA=""
MSG="（无提交信息）"
VER=""
BUILD_LINK="https://codemagic.io"
SHA=${CM_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}
GIT_MSG=$(git log -1 --pretty=%s 2>/dev/null || true)
if [ -n "$GIT_MSG" ]; then MSG="$GIT_MSG"; fi
VER=$(grep -m1 '^version:' pubspec.yaml 2>/dev/null | sed 's/^version: *//; s/+.*//' || true)
if [ -z "$VER" ]; then VER="0.9.3"; fi
TAG="v${VER}-ios"
BUILD_LINK="${CM_BUILD_URL:-https://codemagic.io}"
export SHA MSG VER TAG BUILD_LINK
echo "发版：版本 $VER（tag $TAG）提交 ${SHA:0:7}（${MSG:-（无提交信息）}）"

release_id() {
  local out code
  out=$(curl -s -w $'\n%{http_code}' "${AUTH[@]}" "$API/releases/tags/$1")
  code=$(printf '%s' "$out" | tail -n 1)
  echo "查询 release（tag=$1，$REPO）→ HTTP $code" >&2
  printf '%s' "$out" | sed '$d' | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('id',''))
except Exception:
    print('')"
}

delete_asset_if_exists() {
  local rid="$1" name="$2" aid
  aid=$(curl -s "${AUTH[@]}" "$API/releases/$rid/assets" | ASSET_NAME="$name" python3 -c "import json,os,sys
name = os.environ['ASSET_NAME']
try:
    for a in json.load(sys.stdin):
        if a.get('name') == name:
            print(a['id']); break
except Exception:
    pass")
  if [ -n "$aid" ]; then
    echo "删除旧附件 $name（asset $aid）"
    if ! curl -sf -X DELETE "${AUTH[@]}" "$API/releases/assets/$aid" >/dev/null; then
      echo "错误：删除旧附件 $name 失败（$REPO），终止发版" >&2
      exit 1
    fi
  fi
}

upload_asset() {
  local rid="$1" file="$2" name
  name=$(basename "$file")
  echo "上传 $name → release $rid"
  if ! curl -sf -X POST "${AUTH[@]}" -H "Content-Type: application/octet-stream" \
    --data-binary @"$file" "$UPLOADS/releases/$rid/assets?name=$name" >/dev/null; then
    echo "错误：上传 $name 到 release $rid 失败（$REPO），终止发版" >&2
    exit 1
  fi
}

replace_assets() {
  local rid="$1"; shift
  local f
  for f in "$@"; do
    delete_asset_if_exists "$rid" "$(basename "$f")"
    upload_asset "$rid" "$f"
  done
}

# ---- 正式版 release（tag = v<version>-ios）
REL=$(release_id "$TAG")
if [ -z "$REL" ]; then
  echo "创建正式版 release $TAG"
  CREATE_JSON=$(python3 -c "import json,os
sha = os.environ['SHA']
print(json.dumps({'tag_name': os.environ['TAG'], 'name': os.environ['TAG'],
  'body': f'**Commit:** [{sha}](https://github.com/{os.environ[\"REPO\"]}/commit/{sha})\\n\\n由 Codemagic 自动构建发布。',
  'draft': False, 'prerelease': False, 'make_latest': 'true'}))")
  CREATE_OUT=$(curl -s -w $'\n%{http_code}' -X POST "${AUTH[@]}" "$API/releases" -d "$CREATE_JSON")
  CREATE_CODE=$(printf '%s' "$CREATE_OUT" | tail -n 1)
  echo "新建正式版 release $TAG → HTTP $CREATE_CODE" >&2
  if [[ "$CREATE_CODE" != 2* ]]; then
    echo "新建正式版 release 未成功，GitHub 返回：$(printf '%s' "$CREATE_OUT" | sed '$d')" >&2
  fi
  REL=$(printf '%s' "$CREATE_OUT" | sed '$d' | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('id',''))
except Exception:
    print('')")
fi
if [ -z "$REL" ]; then
  echo "错误：无法定位或新建正式版 release $TAG（$REPO），终止发版" >&2
  exit 1
fi
BODY_JSON=$(python3 -c "import json,os
sha = os.environ['SHA']; msg = os.environ['MSG']
body = f\"**Commit:** [{sha}](https://github.com/{os.environ['REPO']}/commit/{sha})\\n**Version:** {os.environ['VER']}\\n**Message:** {msg}\\n\\n由 Codemagic 自动构建发布。\"
print(json.dumps({'body': body}))")
PATCH_OUT=$(curl -s -w $'\n%{http_code}' -X PATCH "${AUTH[@]}" "$API/releases/$REL" -d "$BODY_JSON")
PATCH_CODE=$(printf '%s' "$PATCH_OUT" | tail -n 1)
echo "更新正式版 release 正文 → HTTP $PATCH_CODE" >&2
if [[ "$PATCH_CODE" != 2* ]]; then
  echo "错误：更新正式版 release 正文失败（$REPO，HTTP $PATCH_CODE）：$(printf '%s' "$PATCH_OUT" | sed '$d')" >&2
  exit 1
fi
replace_assets "$REL" "FlClash-unsigned.ipa"

# ---- 发后自检：回读核对，缺一即报错退出
CHECK=$(curl -s "${AUTH[@]}" "$API/releases/$REL")
echo "$CHECK" | python3 -c "import json,sys
rel = json.load(sys.stdin)
names = [a.get('name') for a in rel.get('assets', [])]
missing = [n for n in ['FlClash-unsigned.ipa'] if n not in names]
if missing:
    print('自检失败：release 缺附件：' + ','.join(missing), file=sys.stderr)
    sys.exit(1)
print('自检通过：release ' + rel.get('tag_name', '') + ' 附件：' + ','.join(names))"
echo "正式版 $TAG 已发布：https://github.com/$REPO/releases/tag/$TAG"
