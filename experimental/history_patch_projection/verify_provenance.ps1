param([Parameter(Mandatory)][string]$HistoryRoot)
$ErrorActionPreference = 'Stop'
$revision = 'ce3276cf2fb425013df013bcb49e211ca234473a'
function Read-GitFile([string]$path) {
    $lines = & git -C $HistoryRoot show "${revision}:$path"
    if ($LASTEXITCODE -ne 0) { throw "Cannot read pinned History source $path at $revision" }
    return ($lines -join "`n")
}
$model = Read-GitFile 'model.odin'
$parser = Read-GitFile 'git_parse_patch.odin'
$typeStart = $model.IndexOf('Diff_Line_Kind ::')
$typeEnd = $model.IndexOf('Commit_Detail ::')
$destroyStart = $model.IndexOf('diff_line_destroy ::')
$destroyEnd = $model.IndexOf('commit_detail_destroy ::')
$parseEnd = $parser.IndexOf('git_first_parent ::')
$expected = "// Extracted unchanged parser/model routines from alicorn-history $revision. See README.md for provenance.`n" +
    $parser.Substring(0, $parseEnd) + "`n" + $model.Substring($typeStart, $typeEnd-$typeStart) + "`n" +
    $model.Substring($destroyStart, $destroyEnd-$destroyStart) + "`n" +
    'git_owned_error :: proc(value: string) -> string { copy, _ := strings.clone(value); return copy }' + "`n"
$actual = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'history_parser.odin') -Raw
if ($expected.TrimEnd() -cne $actual.Replace("`r`n", "`n").TrimEnd()) { throw 'Parser/model snapshot differs from pinned History source' }
$fixtures = @(
    @('history-toolbar.patch', 'ce3276cf2fb425013df013bcb49e211ca234473a', 'history_view.odin'),
    @('history-scroll.patch', '3a22f387ef4003da82eea53aa27657471c71a899', 'history_view.odin'),
    @('history-parser.patch', '6ca8c476a8ef6cfb9e29d363e31f323fe8929870', 'git_parse_patch.odin')
)
foreach ($fixture in $fixtures) {
    $lines = & git -C $HistoryRoot show --format= --no-ext-diff --no-textconv $fixture[1] -- $fixture[2]
    if ($LASTEXITCODE -ne 0) { throw "Cannot read fixture source $($fixture[1])" }
    $actual = Get-Content -LiteralPath (Join-Path $PSScriptRoot "fixtures/$($fixture[0])") -Raw
    if (($lines -join "`n").TrimEnd() -cne $actual.Replace("`r`n", "`n").TrimEnd()) { throw "Fixture $($fixture[0]) differs from real Git patch" }
}
Write-Output 'PASS pinned History parser/model routines and three real Git patch fixtures'
