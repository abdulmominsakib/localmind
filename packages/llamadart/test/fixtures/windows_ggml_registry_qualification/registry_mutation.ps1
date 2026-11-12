function Invoke-NativeRegistryMappingMutation([string]$SourceFile,[string]$Dart) {
  $original=[IO.File]::ReadAllBytes($SourceFile)
  $before=Hash $SourceFile
  $utf8=New-Object Text.UTF8Encoding($false,$true)
  $text=$utf8.GetString($original)
  $pattern="(?m)(@Native<_GgmlBackendRegCountNative>\(\r?\n\s*assetId: )'package:llamadart/ggml'(,\r?\n\s*symbol: 'ggml_backend_reg_count',\r?\n\)\r?\nexternal int _windowsGgmlBackendRegCount\(\);)"
  $regex=New-Object Text.RegularExpressions.Regex($pattern)
  if($regex.Matches($text).Count -ne 1){throw 'exact unique native_signatures registry-count annotation not found; no mutation applied'}
  $changed=$regex.Replace($text,{param($match) $match.Groups[1].Value+"'package:llamadart/ggml-base'"+$match.Groups[2].Value})
  if($changed.Length -ne $text.Length+5){throw 'unexpected mutation byte scope'}
  $receipt=[ordered]@{sourceFile=$SourceFile;sourceSha256=$before;mutation='ONLY _windowsGgmlBackendRegCount @Native assetId ggml -> ggml-base; symbol unchanged';expectedFailure='Windows backend registration missing required ggml_backend_reg_count';mutantExitCode=$null;causalRefusalVerified=$false;runtimeSubtypeObserved=$false;typedContractEvidence='maintained injected unit plus actual source throw LlamaUnsupportedException; exception text does not expose subtype';sourceRestored=$false}
  [IO.File]::WriteAllBytes("$O\codeasset-mutation-original-native-signatures.dart",$original)
  try {
    [IO.File]::WriteAllBytes($SourceFile,$utf8.GetBytes($changed))
    $receipt.mutantSha256=Hash $SourceFile
    Copy-Item -LiteralPath $SourceFile "$O\codeasset-mutation-mutant-native-signatures.dart"
    $code=InvokeCase 'fixed-codeasset-mapping-mutant' $Dart 'test -p vm -j 1 test/integration/windows_ggml_registry_test.dart' 300
    $receipt.mutantExitCode=$code
    $log=(Get-Content "$O\fixed-codeasset-mapping-mutant.stdout.log" -Raw)+"`n"+(Get-Content "$O\fixed-codeasset-mapping-mutant.stderr.log" -Raw)
    $causal=$code -ne 0 -and $log -match 'LlamaException: Windows llama\.cpp backend registration requires the ggml code asset' -and $log -match 'ggml_backend_reg_count export used by llama\.dll' -and $log -match 'llama_cpp_service\.dart'
    $setup=$log -match 'Failed to load.*(?:hook|test/integration)|Building assets.*failed|Running build hooks.*failed|Could not find.*package|Could not resolve|Compilation failed|Error: Not found|PathNotFoundException'
    if(-not $causal -or $setup){throw 'mutant did not fail at the intended production registry refusal; setup/other failures are not valid mutation evidence'}
    $receipt.causalRefusalVerified=$true
  } finally {
    [IO.File]::WriteAllBytes($SourceFile,$original)
    if((Hash $SourceFile) -cne $before){throw 'native_signatures restoration digest mismatch'}
    $receipt.sourceRestored=$true;$receipt.restoredSha256=Hash $SourceFile
    $receipt | ConvertTo-Json -Depth 6 | Set-Content "$O\codeasset-mutation-receipt.json"
  }
}
