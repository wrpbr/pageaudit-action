#!/usr/bin/env bash
# PageAudit preview check. It audits production and the preview with the same owner, so PageAudit can compare the
# two by finding code (`compare_with`), and writes what got worse in the job summary. It reports only, unless
# fail-on asks it to fail the step.
set -uo pipefail

resumo="${GITHUB_STEP_SUMMARY:-/dev/null}"
saida="${GITHUB_OUTPUT:-/dev/null}"

aviso() {
  echo "::warning title=PageAudit::$1"
  printf '### PageAudit\n\n%s\n' "$1" >> "$resumo"
  exit 0
}

command -v jq > /dev/null 2>&1 || aviso "This step needs \`jq\` on the runner."
[ -n "${PA_URL:-}" ] || aviso "Set \`url\`: the page to check, usually the preview URL."
base="${PA_BASE:-https://pageaudit.online}"
base="${base%/}"
umask 077
dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/pageaudit.XXXXXX")"
trap 'rm -rf "$dir"' EXIT

# Credentials go to curl through a file, never on its command line.
: > "$dir/headers"
if [ -n "${PA_KEY:-}" ]; then
  echo "::add-mask::$PA_KEY"
  printf 'X-Api-Key: %s\n' "$PA_KEY" > "$dir/headers"
fi

# One POST to PageAudit: path, JSON body, file for the answer. Prints the HTTP status.
pede() {
  curl -sS --max-time 120 -X POST "$base$1" -H @"$dir/headers" -H 'content-type: application/json' \
    -H 'user-agent: pageaudit-action/1' --data "$2" -o "$3" -w '%{http_code}' || echo 000
}

# Without a key, a guest owns both audits for this run: the comparison needs one owner.
guest=""
if [ -z "${PA_KEY:-}" ]; then
  codigo="$(pede /api/guest '{}' "$dir/guest.json")"
  [[ "$codigo" == 2* ]] || aviso "PageAudit did not give a guest token (HTTP $codigo)."
  guest="$(jq -r '.token // empty' "$dir/guest.json")"
  echo "::add-mask::$guest"
fi

corpo() { jq -cn --arg url "$1" --arg g "$guest" --arg base "${2:-}" \
  '{url: $url} + (if $g == "" then {} else {guest_token: $g} end) + (if $base == "" then {} else {compare_with: $base} end)'; }

producao=""
if [ -n "${PA_PRODUCAO:-}" ] && [ "${PA_PRODUCAO%/}" != "${PA_URL%/}" ]; then
  codigo="$(pede /api/audit "$(corpo "$PA_PRODUCAO")" "$dir/producao.json")"
  if [ "$codigo" = "200" ]; then
    producao="$(jq -r '.id // empty' "$dir/producao.json")"
  else
    echo "::warning title=PageAudit::Production audit answered HTTP $codigo; checking the page without a comparison."
  fi
fi

codigo="$(pede /api/audit "$(corpo "$PA_URL" "$producao")" "$dir/audit.json")"
erro="$(jq -r '.error // empty' "$dir/audit.json" 2> /dev/null)"
case "$codigo" in
  200) ;;
  402) aviso "The free daily allowance of audits is spent. Plans and credit: $base/pricing" ;;
  502) aviso "PageAudit could not read $PA_URL: ${erro:-the site did not answer}." ;;
  *) aviso "PageAudit answered HTTP $codigo${erro:+ ($erro)}." ;;
esac

j() { jq -r "$1" "$dir/audit.json"; }
score="$(j '.score')"
erros="$(j '.counts.errors // 0')"
alertas="$(j '.counts.warnings // 0')"
regressao="$(j '.comparison.regression // false')"
novos="$(j '(.comparison.broke // []) | length')"
linhas='.[] | "| \(.severity) | `\(.code)` | \(.message | gsub("[|]"; "/") | gsub("\n"; " ")) |"'

{
  echo "### PageAudit"
  echo
  echo "$PA_URL scored **$score**/100: $erros errors and $alertas warnings."
  echo
  if [ "$(j 'has("comparison")')" = "true" ]; then
    echo "Compared with production ($PA_PRODUCAO, $(j '.comparison.from // "?"')/100): $(j '.comparison.score // 0') points, $novos new findings, $(j '(.comparison.fixed // []) | length') fixed."
    echo
    if [ "$novos" -gt 0 ]; then
      echo "| Severity | Finding | Detail |"
      echo "|---|---|---|"
      jq -r "(.comparison.broke // [])[:20] | $linhas" "$dir/audit.json"
    else
      echo "Nothing got worse."
    fi
  else
    if [ -n "$producao" ]; then printf 'The comparison with production was not available.\n\n'; fi
    if [ "$erros" -gt 0 ]; then
      echo "| Severity | Finding | Detail |"
      echo "|---|---|---|"
      jq -r "[.issues[] | select(.severity == \"error\")][:10] | $linhas" "$dir/audit.json"
    fi
  fi
  echo
  echo "Fixes and the full report: $base"
} >> "$resumo"
{
  echo "score=$score"
  echo "regression=$regressao"
  echo "new-findings=$novos"
} >> "$saida"

case "${PA_FAIL_ON:-none}" in
  regression)
    if [ "$regressao" = "true" ]; then
      echo "::error title=PageAudit::The page is worse than production: $novos new findings."
      exit 1
    fi
    ;;
  error)
    if [ "$erros" -gt 0 ]; then
      echo "::error title=PageAudit::The page has $erros error-level findings."
      exit 1
    fi
    ;;
esac
echo "PageAudit: $PA_URL scored $score/100."
