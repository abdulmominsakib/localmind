. "$PSScriptRoot/registry_test_report.ps1"

function CheckSnapshot($name,$requireCoherent) {
  $text=Get-Content "$O\$name.stdout.log" -Raw
  $lines=@($text -split "`r?`n" | Where-Object {$_.StartsWith('PASSIVE_MODULE ')})
  $identities=@($text -split "`r?`n" | Where-Object {$_.StartsWith('REGISTRY_IDENTITY ')})
  if($lines.Count -eq 0 -or $identities.Count -ne 1 -or $text -match 'SNAPSHOT_FAILURE'){return $false}
  $rows=@($lines | ForEach-Object {$_.Substring(15) | ConvertFrom-Json})
  $expected=@{}
  Get-ChildItem $referenceRuntime -Recurse -File -Filter '*.dll' | ForEach-Object {$expected[$_.Name.ToLowerInvariant()]=Hash $_.FullName}
  foreach($row in $rows){
    $leaf=[IO.Path]::GetFileName($row.modulePath).ToLowerInvariant()
    if($expected.ContainsKey($leaf) -and $row.sha256 -ne $expected[$leaf]){return $false}
    if($row.checkpoint -notlike 'after-*' -or $row.machine -ne 34404){return $false}
  }
  $initial=@($rows | Where-Object {$_.checkpoint -in @('after-stock-model-success','after-stock-model-exception')})
  if($initial.Count -eq 0 -or @($initial | Where-Object {$_.registryGettersCalled -ne $false}).Count){return $false}
  $identity=$identities[0].Substring(18) | ConvertFrom-Json
  $coherent=$identity.observerAfterFirstPassiveSnapshot -eq $true -and $identity.primaryMatchesCodeAsset -eq $true -and $identity.noUnintendedDuplicateRegistry -eq $true -and $identity.registryCountAfterOutcome -gt 0
  if($requireCoherent -and -not $coherent){return $false}
  @{identity=$identity;modules=$rows;coherent=$coherent;coherenceRequired=$requireCoherent} | ConvertTo-Json -Depth 18 | Set-Content "$O\$name-identity-verified.json"
  return $true
}
function RecordFiles($root,$name) {
  @(Get-ChildItem $root -Recurse -Force -File | Where-Object { $_.Extension -in @('.dll','.json','.yaml','.lock') } | ForEach-Object { @{path=$_.FullName;bytes=$_.Length;sha256=Hash $_.FullName} }) | ConvertTo-Json -Depth 8 | Set-Content "$O\$name.json"
}

function Invoke-RegistryQualification {
  $referenceRuntime="$S\published-reference-runtime"
  $referenceManifest=@(Get-ChildItem $referenceRuntime -Recurse -File | ForEach-Object {@{path=$_.FullName;sha256=Hash $_.FullName}})
  $referenceManifest | ConvertTo-Json | Set-Content "$O\published-reference-files.json"
  $roots=@{};$overlays=@{};$externalHash=''
  foreach($revision in @('original','fixed')) { foreach($hook in @(0,1)) {
    $mode="$revision-H$hook";$root="$W\$mode";$roots[$mode]=$root
    New-Item -ItemType Directory $root,"$root\tmp","$root\core" | Out-Null
    $source=$C.candidateSourceRoot;$manifest=$C.candidateSourceFiles
    if($revision -eq 'original'){$source=$C.baselineSourceRoot;$manifest=$C.baselineSourceFiles}
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {Copy-Item -LiteralPath $_.FullName "$root\core" -Recurse -Force}
    Copy-Item "$FixtureRoot\payload\*.dart" "$root\core"
    Set-Location "$root\core";$env:TEMP="$root\tmp";$env:TMP="$root\tmp"
    $env:Path=$cleanPath
    Remove-Item Env:LLAMADART_NATIVE_LIB_DIR,Env:LLAMADART_BACKEND_MODULE_DIR -ErrorAction SilentlyContinue
    foreach($entry in (Get-Content $manifest -Raw | ConvertFrom-Json)){Verify (Join-Path "$root\core" $entry.path) $entry.sha256}
    $native='';if($hook -eq 1){$native="      llamadart_native_path: $($referenceRuntime.Replace('\','/'))`n"}
    Add-Content "$root\core\pubspec.yaml" "`nhooks:`n  user_defines:`n    llamadart:`n${native}      llamadart_native_runtimes: [llama_cpp]`n      llamadart_native_backends:`n        platforms:`n          windows-x64: [cpu, cuda]"
    $overlays[$mode]=Hash "$root\core\pubspec.yaml"
    Copy-Item "$root\core\pubspec.yaml" "$O\$mode-runtime-overlay-pubspec.yaml"
    Must "$mode-pub-get" $dart 'pub get' 600
    foreach($entry in (Get-Content $manifest -Raw | ConvertFrom-Json)){if($entry.path -ne 'pubspec.yaml'){Verify (Join-Path "$root\core" $entry.path) $entry.sha256}}
    Must "$mode-dependency-receipt" $dart "run dependency_receipt.dart pubspec.lock $O\$mode-external-resolution.json"
    $current=Hash "$O\$mode-external-resolution.json"
    if(-not $externalHash){$externalHash=$current}elseif($externalHash -ne $current){throw 'external dependency versions/content differ across original/fixed/hook trees'}
    Copy-Item "$root\core\pubspec.lock" "$O\$mode-pubspec.lock"
    RecordFiles "$root" "$mode-before-consumers"
    Copy-Item "$root/core/pubspec.lock" "$O/$mode-root-lock-before"
  } }
  function SelectMatrix($revision,$hook,$environment,$prefix,$alias=$false) {
    $mode="$revision-H$hook";Set-Location "$($roots[$mode])\core"
    Remove-Item Env:LLAMADART_NATIVE_LIB_DIR,Env:LLAMADART_BACKEND_MODULE_DIR -ErrorAction SilentlyContinue
    if($environment -eq 1){if($alias){$env:LLAMADART_BACKEND_MODULE_DIR=$referenceRuntime}else{$env:LLAMADART_NATIVE_LIB_DIR=$referenceRuntime}}
    $runtimePrefix='';if($prefix -eq 1){$runtimePrefix=$referenceRuntime}
    $path=New-ComparisonPath $originalWindowsPath @((Split-Path $git),(Split-Path $dart)) $hostDirectory $taskRuntimeDirectories $runtimePrefix
    if($path.NormalPath -cne $cleanPath){throw 'unexpected base PATH difference'}
    $env:Path=$path.Path
    $label="$revision-H${hook}E${environment}P${prefix}";if($alias){$label+='-alias'}
    @{revision=$revision;hook=$hook;environment=$environment;prefix=$prefix;alias=$alias;nativeDirectory=$env:LLAMADART_NATIVE_LIB_DIR;backendModuleDirectory=$env:LLAMADART_BACKEND_MODULE_DIR;runtimePrefix=$runtimePrefix;normalBaseMatches=$true;freshProcess=$true;sourceRoot=(Get-Location).Path;pubCache=$env:PUB_CACHE} | ConvertTo-Json | Set-Content "$O\$label-inputs.json"
    return $label
  }
  $matrix=@();$requiredFailures=@()
  foreach($revision in @('original','fixed')) { foreach($hook in @(0,1)) { foreach($environment in @(0,1)) { foreach($prefix in @(0,1)) {
    $name=SelectMatrix $revision $hook $environment $prefix
    $code=InvokeCase $name $dart "run load_stock.dart $($C.modelPath)" 180
    $stdout=Get-Content "$O\$name.stdout.log" -Raw
    $outcomes=@($stdout -split "`r?`n" | Where-Object {$_.StartsWith('MODEL_OUTCOME ')})
    $success=$code -eq 0 -and $stdout -match 'LOAD_SUCCESS' -and $stdout -match 'unloadCompleted=true' -and $outcomes.Count -eq 1 -and $outcomes[0] -eq 'MODEL_OUTCOME success'
    $observed=$outcomes.Count -eq 1 -and $stdout -match 'PASSIVE_MODULE ' -and $stdout -notmatch 'SNAPSHOT_FAILURE'
    $identity=CheckSnapshot $name ($revision -eq 'fixed' -or $name -eq 'original-H0E0P0')
    $required=$revision -eq 'fixed' -or $name -eq 'original-H0E0P0'
    if(-not $observed -or -not $identity -or ($required -and -not $success)){$requiredFailures+=$name}
    $matrix+=@{name=$name;revision=$revision;hook=$hook;environment=$environment;prefix=$prefix;exitCode=$code;productionOutcomeRecorded=$observed;loadedCpuZero=$success;identityValid=$identity;requiredPass=$required;originalNonNormalOutcomeIsData=$revision -eq 'original' -and -not $required}
  } } } }
  foreach($aliasHook in @(0,1)) {
  $name=SelectMatrix 'fixed' $aliasHook 1 0 $true
  $code=InvokeCase $name $dart "run load_stock.dart $($C.modelPath)" 180
  $stdout=Get-Content "$O\$name.stdout.log" -Raw
  $outcomes=@($stdout -split "`r?`n" | Where-Object {$_.StartsWith('MODEL_OUTCOME ')})
  if($outcomes.Count -ne 1 -or $outcomes[0] -cne 'MODEL_OUTCOME success'){throw 'alias production outcome missing/duplicate'}
  $identity=CheckSnapshot $name $true
  if($code -ne 0 -or $stdout -notmatch 'LOAD_SUCCESS' -or $stdout -notmatch 'unloadCompleted=true' -or -not $identity){$requiredFailures+=$name}
  $matrix+=@{name=$name;alias='LLAMADART_BACKEND_MODULE_DIR';loadedCpuZero=$code -eq 0 -and $stdout -match 'LOAD_SUCCESS' -and $stdout -match 'unloadCompleted=true';productionOutcomeRecorded=$true;exitCode=$code;identityValid=$identity;requiredPass=$true}
  }
  $matrix | ConvertTo-Json -Depth 10 | Set-Content "$O\override-matrix.json"
  if($matrix.Count -ne 18 -or $requiredFailures.Count){throw "required matrix/oracle failures: $($requiredFailures -join ',')"}
  SelectMatrix 'fixed' 0 0 0 | Out-Null
  # This disposable copy owns the only deliberately changed production file.
  $mutantCore="$W\fixed-codeasset-control\core"
  New-Item -ItemType Directory $mutantCore | Out-Null
  Get-ChildItem -LiteralPath $C.candidateSourceRoot -Force | ForEach-Object {Copy-Item -LiteralPath $_.FullName $mutantCore -Recurse -Force}
  foreach($entry in (Get-Content $C.candidateSourceFiles -Raw | ConvertFrom-Json)){Verify (Join-Path $mutantCore $entry.path) $entry.sha256}
  Copy-Item "$($roots['fixed-H0'])\core\pubspec.yaml" "$mutantCore\pubspec.yaml"
  if((Hash "$mutantCore\pubspec.yaml") -cne $overlays['fixed-H0']){throw 'mutant control normal hook overlay mismatch'}
  Set-Location $mutantCore
  Copy-Item "$FixtureRoot\payload\dependency_receipt.dart" $mutantCore
  Must 'fixed-codeasset-control-pub-get' $dart 'pub get' 600
  Must 'fixed-codeasset-control-dependency-receipt' $dart "run dependency_receipt.dart pubspec.lock $O\fixed-codeasset-control-external-resolution.json"
  if((Hash "$O\fixed-codeasset-control-external-resolution.json") -cne $externalHash){throw 'mutant control dependency resolution differs'}
  Copy-Item "$mutantCore\pubspec.lock" "$O\fixed-codeasset-control-pubspec.lock"
  $report="$O/fixed-maintained-registry-integration.events.json"
  if((Test-Path -LiteralPath $report) -or (Test-Path -LiteralPath "$O/fixed-maintained-registry-integration-result.json")){throw 'maintained integration requires fresh reporter evidence'}
  Must 'fixed-maintained-registry-integration' $dart "test -p vm -j 1 --file-reporter `"json:$report`" test/integration/windows_ggml_registry_test.dart" 300
  Assert-MaintainedRegistryReport $report
  Invoke-NativeRegistryMappingMutation "$mutantCore\lib\src\backends\llama_cpp\native_signatures.dart" $dart
  foreach($entry in (Get-Content $C.candidateSourceFiles -Raw | ConvertFrom-Json)){if($entry.path -ne 'pubspec.yaml'){Verify (Join-Path $mutantCore $entry.path) $entry.sha256}}
  RecordFiles $mutantCore 'codeasset-control-after-restoration'
  SelectMatrix 'fixed' 0 0 0 | Out-Null
  Must 'fixed-maintained-binding-refusals' $dart 'test -p vm -j 1 test/unit/backends/llama_cpp/library_probe_call_sites_test.dart' 180
  Must 'fixed-normal-AOT-build' $dart 'build cli -o build/stock -t load_stock.dart' 600
  $allSourceRoots=@($roots.Values)+@("$W\fixed-codeasset-control",$C.candidateSourceRoot,$C.baselineSourceRoot)
  Invoke-AotShippingDistribution "$($roots['fixed-H0'])\core\build\stock\bundle" "$W\shipping-distribution\bundle" "$W\shipping-empty-cwd" $allSourceRoots $C.modelPath
  foreach($revision in @('original','fixed')) { foreach($hook in @(0,1)) {
    $mode="$revision-H$hook";$root=$roots[$mode];$manifest=$C.candidateSourceFiles
    if($revision -eq 'original'){$manifest=$C.baselineSourceFiles}
    foreach($entry in (Get-Content $manifest -Raw | ConvertFrom-Json)){if($entry.path -ne 'pubspec.yaml'){Verify (Join-Path "$root\core" $entry.path) $entry.sha256}}
    if((Hash "$root\core\pubspec.yaml") -ne $overlays[$mode]){throw "hook overlay mutated $mode"}
    SelectMatrix $revision $hook 0 0 | Out-Null
    Must "$mode-final-dependency-receipt" $dart "run dependency_receipt.dart pubspec.lock $O\$mode-final-external-resolution.json"
    if((Hash "$O\$mode-final-external-resolution.json") -ne $externalHash){throw "dependency resolution changed $mode"}
    RecordFiles "$root" "$mode-after-consumers"
    $maps="$O/$mode-native-asset-maps";New-Item -ItemType Directory $maps | Out-Null
    Get-ChildItem "$root/core/.dart_tool" -Recurse -Force -File | Where-Object {$_.Name -eq 'native_assets.yaml' -or ($_.Name -in @('input.json','output.json') -and $_.FullName -match 'hooks_runner')} | ForEach-Object {
      $relative=$_.FullName.Substring(("$root/core/.dart_tool").Length+1)
      $target=Join-Path $maps $relative;New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null;Copy-Item -LiteralPath $_.FullName $target
    }
  } }
  foreach($entry in $referenceManifest){Verify $entry.path $entry.sha256}
  @{matrixCases=16;fixedAliasCases=2;fixedNormalAotPassed=$true;maintainedRegistryIntegrationPassed=$true;actualCodeAssetMappingMutationRefusedAndRestored=$true;maintainedBindingRefusalTestsPassed=$true;actualMissingRequiredBinaryAssetNotMutated=$true;cpuHardwareOnly=$true;gpuQualified=$false;qualificationPendingIndependentReview=$true} | ConvertTo-Json | Set-Content "$O\windows1649-summary.json"

}
