#!/usr/bin/env bash
# _wiring-lang-adapters.sh — shared "is it actually WIRED?" resolvers (UBS v8.8).
#
# The GATE-WIRE family answers a question the v8.7.2 spec gates never asked:
# not "is this capability/feature DECLARED in .build-anything.json?" but
# "does it leave a real FOOTPRINT in the built repo — a dependency, a code
# symbol, or a config/infra file?".
#
# This is the cure for the audit's core finding (declared-vs-wired): a gate
# that trusts the author's declaration produces vacuous PASS. `stack.ai=
# "openai-sdk"` with an empty internal/ai/ and no SDK in go.mod must FAIL.
#
# Sourced by: capability-wiring-check.sh, feature-wiring-check.sh,
#             stub-detection.sh.
#
# ── CRITICAL INVARIANT ───────────────────────────────────────────────
# The footprint search MUST exclude .build-anything.json and lockfiles.
# A capability that exists ONLY in the config declaration is exactly the
# vacuous PASS we are killing. Footprint must live in:
#   (a) dependency manifests (package.json deps / go.mod / requirements.txt
#       / pyproject.toml / Cargo.toml),  OR
#   (b) source code (*.go/ts/tsx/js/jsx/py/rs/java/rb/kt/swift),  OR
#   (c) infra/config files matched by an explicit glob.
#
# bash 3.2 compatible (macOS default). No mapfile, no globstar, no GNU-only
# find predicates (`-size +0c` used for non-empty, portable on BSD + GNU).

# ── dependency footprint ─────────────────────────────────────────────
# wiring_dep_present <root> <token>  → rc 0 if token appears (case-insensitive,
# fixed-string) in any dependency manifest at root or one level down (monorepo
# backend/ frontend/ layout). go.sum included so a real import is caught even
# when go.mod lists only direct requires.
wiring_dep_present() {
  local root="$1" token="$2"
  [[ -z "$token" ]] && return 1
  local files=() d f
  for f in package.json go.mod go.sum requirements.txt pyproject.toml Pipfile Cargo.toml pom.xml build.gradle Gemfile; do
    [[ -f "$root/$f" ]] && files+=("$root/$f")
  done
  for d in "$root"/*/; do
    for f in package.json go.mod go.sum requirements.txt pyproject.toml Cargo.toml; do
      [[ -f "$d$f" ]] && files+=("$d$f")
    done
  done
  [[ ${#files[@]} -eq 0 ]] && return 1
  grep -qiF -- "$token" "${files[@]}" 2>/dev/null
}

# ── source-symbol footprint ──────────────────────────────────────────
# wiring_symbol_present <root> <token>  → rc 0 if token appears (case-insensitive,
# fixed-string) in any SOURCE file. Excludes vendor/build dirs and — by virtue
# of the --include source-only filter — never matches .build-anything.json.
wiring_symbol_present() {
  local root="$1" token="$2"
  [[ -z "$token" ]] && return 1
  grep -rqiF \
    --include='*.go' --include='*.ts' --include='*.tsx' --include='*.js' \
    --include='*.jsx' --include='*.mjs' --include='*.py' --include='*.rs' \
    --include='*.java' --include='*.rb' --include='*.kt' --include='*.swift' \
    --include='*.cs' --include='*.php' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor \
    --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
    --exclude-dir=target --exclude-dir=__pycache__ \
    -- "$token" "$root" 2>/dev/null
}

# wiring_symbol_count <root> <token>  → echoes # of source files containing token.
# Used for min_impls (e.g. multi-provider AI must show ≥2 distinct providers).
wiring_symbol_count() {
  local root="$1" token="$2"
  [[ -z "$token" ]] && { echo 0; return; }
  grep -rliF \
    --include='*.go' --include='*.ts' --include='*.tsx' --include='*.js' \
    --include='*.jsx' --include='*.mjs' --include='*.py' --include='*.rs' \
    --include='*.java' --include='*.rb' --include='*.kt' --include='*.swift' \
    --include='*.cs' --include='*.php' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor \
    --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
    --exclude-dir=target --exclude-dir=__pycache__ \
    -- "$token" "$root" 2>/dev/null | wc -l | tr -d ' '
}

# ── infra/config-file footprint ──────────────────────────────────────
# wiring_path_glob_present <root> <glob>  → rc 0 if ≥1 NON-EMPTY file matches.
# Glob forms:
#   "k8s/"          directory exists + holds ≥1 non-empty file (recursive)
#   "k8s/*.yaml"    dir prefix + name pattern
#   "*.tf"          bare name pattern anywhere (vendor/git pruned)
# "**" is collapsed to "*" for bash 3.2 (no globstar).
wiring_path_glob_present() {
  local root="$1" glob="$2"
  [[ -z "$glob" ]] && return 1
  case "$glob" in
    */)
      local dir="$root/${glob%/}"
      [[ -d "$dir" ]] || return 1
      find "$dir" -type f -size +0c 2>/dev/null | head -1 | grep -q . ;;
    */*)
      local prefix="${glob%/*}" name="${glob##*/}"
      name="${name//\*\*/\*}"
      [[ -d "$root/$prefix" ]] || return 1
      find "$root/$prefix" -type f -name "$name" -size +0c 2>/dev/null | head -1 | grep -q . ;;
    *)
      find "$root" -type f -name "$glob" -size +0c \
        -not -path '*/node_modules/*' -not -path '*/.git/*' \
        -not -path '*/vendor/*' 2>/dev/null | head -1 | grep -q . ;;
  esac
}

# ── combined footprint resolver ──────────────────────────────────────
# wiring_footprint_present <root> <token>  → rc 0 if token is wired as EITHER a
# dependency OR a source symbol. (Config-glob is checked separately by callers
# that carry explicit globs.) This is the workhorse for capability/feature
# wiring: a declared value with zero dep AND zero source footprint = unwired.
wiring_footprint_present() {
  local root="$1" token="$2"
  wiring_dep_present "$root" "$token" && return 0
  wiring_symbol_present "$root" "$token" && return 0
  return 1
}
