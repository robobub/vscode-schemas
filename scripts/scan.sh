#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2129

VSCODE_TAG="$1"
VSCODE_COMMIT=""

if [[ "${OSTYPE}" == "msys"* || "${OSTYPE}" == "cygwin"* ]]; then
  echo "Windows is not supported"
  exit 1
fi

if [ -n "$VSCODE_TAG" ]; then
  response=$(curl -s "https://vscode.luxass.dev/releases/${VSCODE_TAG}")
  if [ -z "$response" ] || [ "$response" = "null" ]; then
    echo "VSCODE_TAG: $VSCODE_TAG is not a valid tag"
    exit 1
  fi
  VSCODE_COMMIT=$(echo "$response" | jq -r '.commit')
fi

if [ -z "$VSCODE_TAG" ]; then
  response=$(curl -s "https://vscode.luxass.dev/releases/latest")
  VSCODE_TAG=$(echo "$response" | jq -r '.tag')
  VSCODE_COMMIT=$(echo "$response" | jq -r '.commit')
fi

if [[ "${OSTYPE}" == "darwin"* ]]; then
  if ! command -v sg &> /dev/null; then
    echo "Error: ast-grep is not installed."
    echo "Please install ast-grep by running: brew install ast-grep"
    exit 1
  fi
else
  if ! command -v ast-grep &> /dev/null; then
    echo "Error: ast-grep is not installed."
    echo "Please install ast-grep by running either:"
    echo "  cargo install ast-grep --locked"
    echo "  or"
    echo "  npm i @ast-grep/cli -g"
    exit 1
  fi
fi

if [ -d ".vscode-src" ]; then
  rm -rf .vscode-src
fi

mkdir -p .vscode-src

cd .vscode-src || exit 1

git init -q
git remote add origin https://github.com/microsoft/vscode.git
git fetch --depth 1 origin "${VSCODE_COMMIT}"
git checkout FETCH_HEAD

echo "cloned vscode to .vscode-src"

cat <<EOF > "./sgconfig.yml"
ruleDirs:
  - ./ast-grep-rules
EOF
echo "wrote sgconfig.yml"

mkdir -p "./ast-grep-rules"

cat <<EOF > "./ast-grep-rules/vscode-schemas-ts-rule.yaml"
id: vscode-schemas-detect-ts
language: typescript
rule:
  regex: "^vscode:\/\/schemas\/"
  kind: string_fragment
EOF

cat <<EOF > "./ast-grep-rules/vscode-schemas-js-rule.yaml"
id: vscode-schemas-detect-js
language: javascript
rule:
  regex: "^vscode:\/\/schemas\/"
  kind: string_fragment
EOF

cat <<EOF > "./ast-grep-rules/vscode-schemas-json-rule.yaml"
id: vscode-schemas-detect-json
language: json
rule:
  regex: "^vscode:\/\/schemas\/"
  kind: string_content
EOF


echo "wrote ast grep rules"

sg_output=$(sg scan --json=compact)

echo "${sg_output}" > "./sg_output.json"

if [ ! -d "../schemas/${VSCODE_TAG}" ]; then
  mkdir -p "../schemas/${VSCODE_TAG}"
fi

UNIQUE_SCHEMAS=$(echo "${sg_output}" | jq -r '
  .[]
  | .text
  | select(
    (contains("#/definitions") | not) and
    (contains("vscode://schemas/custom/") | not)
  )
  ' | sort -u)

echo "${UNIQUE_SCHEMAS}" | jq -R . | jq -s . > "../schemas/${VSCODE_TAG}/schema-list.json"
