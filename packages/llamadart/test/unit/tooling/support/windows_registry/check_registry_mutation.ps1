param([string]$BundleRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $BundleRoot 'registry_mutation.ps1')
function Hash($path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
$reference=Join-Path $BundleRoot '../../../lib/src/backends/llama_cpp/native_signatures.dart'
$referenceBytes=[IO.File]::ReadAllBytes($reference)
$utf8=New-Object Text.UTF8Encoding($false,$true)
$results=@()
foreach($lineEnding in @("`n","`r`n")) {
$fixtureBytes=$utf8.GetBytes($utf8.GetString($referenceBytes).Replace("`r`n","`n").Replace("`n",$lineEnding))
foreach($variant in @('causal-refusal','unexpected-pass','wrong-error','setup-error','timeout','missing-needle','duplicate-needle')) {
  $work=Join-Path (Split-Path $OutputPath) ('mutation-test-'+[Guid]::NewGuid().ToString('N'));$O=Join-Path $work 'out';New-Item -ItemType Directory $O | Out-Null
  $file=Join-Path $work 'native_signatures.dart';[IO.File]::WriteAllBytes($file,$fixtureBytes)
  if($variant -eq 'missing-needle'){$text=[IO.File]::ReadAllText($file).Replace('external int _windowsGgmlBackendRegCount();','external int _unrelated();');[IO.File]::WriteAllText($file,$text)}
  if($variant -eq 'duplicate-needle'){[IO.File]::WriteAllBytes($file,($fixtureBytes+$fixtureBytes))}
  $before=Hash $file;$beforeBytes=[IO.File]::ReadAllBytes($file);$beforeText=[IO.File]::ReadAllText($file);$calls=0
  function InvokeCase($name,$dart,$arguments,$seconds=180) {
    $calls++
    if($name -ne 'fixed-codeasset-mapping-mutant' -or $arguments -ne 'test -p vm -j 1 test/integration/windows_ggml_registry_test.dart' -or $seconds -ne 300){throw 'wrong actual maintained invocation'}
    $mutated=[IO.File]::ReadAllText($file)
    $mapping="assetId: 'package:llamadart/ggml',${lineEnding}  symbol: 'ggml_backend_reg_count'"
    $mutantMapping="assetId: 'package:llamadart/ggml-base',${lineEnding}  symbol: 'ggml_backend_reg_count'"
    if($mutated.Length -ne $beforeText.Length+5 -or -not $mutated.Contains($mutantMapping)){throw 'mutation did not change only intended native asset mapping'}
    $restored=$mutated.Replace($mutantMapping,$mapping)
    if($restored -cne $beforeText){throw 'mutation changed unrelated source bytes'}
    if($variant -eq 'timeout'){throw 'synthetic process timeout'}
    $message='LlamaException: Windows llama.cpp backend registration requires the ggml code asset emitted by the llamadart build hook, including the ggml_backend_reg_count export used by llama.dll. Use a complete, ABI-compatible native bundle through llamadart_native_path.'+"`npackage:llamadart/src/backends/llama_cpp/llama_cpp_service.dart:2860"
    if($variant -eq 'wrong-error'){$message='Unrelated failure'}
    if($variant -eq 'setup-error'){$message+="`nRunning build hooks failed"}
    $message | Set-Content "$O\$name.stdout.log";'' | Set-Content "$O\$name.stderr.log"
    if($variant -eq 'unexpected-pass'){return 0};return 1
  }
  $failed=$false;try{Invoke-NativeRegistryMappingMutation $file 'NOT_EXECUTED_DART'}catch{$failed=$true}
  $expectedFailure=$variant -ne 'causal-refusal'
  if($failed -ne $expectedFailure){throw "mutation classification wrong $variant"}
  if((Hash $file) -cne $before -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) -cne [Convert]::ToBase64String($beforeBytes)){throw "source not byte-exact restored $variant"}
  $receiptPath=Join-Path $O 'codeasset-mutation-receipt.json'
  if($variant -notin @('missing-needle','duplicate-needle')){
    $receipt=Get-Content $receiptPath -Raw | ConvertFrom-Json
    if($receipt.sourceRestored -ne $true -or $receipt.runtimeSubtypeObserved -ne $false){throw 'restoration/subtype honesty receipt failure'}
    if($receipt.causalRefusalVerified -ne ($variant -eq 'causal-refusal')){throw 'incorrect causal refusal receipt'}
  }elseif(Test-Path $receiptPath){throw 'ambiguous source got mutation receipt'}
  $results+=@{variant=$variant;lineEnding=if($lineEnding -ceq "`n"){'LF'}else{'CRLF'};expectedFailure=$expectedFailure;failed=$failed;sourceByteExactAfter=$true;sourceBeforeSha256=$before}
  Remove-Item $work -Recurse -Force
}
}
[ordered]@{offlineOnly=$true;actualMutationHelperExecuted=$true;actualDeclarationFixtureSha256=(Hash $reference);helperSha256=(Hash (Join-Path $BundleRoot 'registry_mutation.ps1'));cases=$results;modelNativeSdkProcessesExecuted=0;providerActions=0;noObservedRuntimeSubtypeClaim=$true} | ConvertTo-Json -Depth 8 | Set-Content $OutputPath
