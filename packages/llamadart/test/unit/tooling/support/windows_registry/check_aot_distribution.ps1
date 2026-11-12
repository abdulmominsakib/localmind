param([string]$BundleRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $BundleRoot 'comparison_path.ps1')
. (Join-Path $BundleRoot 'aot_distribution.ps1')
function Hash($path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $BundleRoot 'runtime.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'guest parse error'}
$checker=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'CheckSnapshot'},$false))
if($checker.Count -ne 1){throw 'actual identity checker missing'}
Invoke-Expression $checker[0].Extent.Text
function Flow([string]$Variant) {
  $work=Join-Path (Split-Path $OutputPath) ('aot-test-'+[Guid]::NewGuid().ToString('N'))
  $O=Join-Path $work 'out';New-Item -ItemType Directory $O | Out-Null
  $sources=@('original-H0','original-H1','fixed-H0','fixed-H1','fixed-codeasset-control' | ForEach-Object {Join-Path $work $_})
  foreach($source in $sources){New-Item -ItemType Directory $source | Out-Null}
  $built=Join-Path $sources[2] 'core/build/stock/bundle';$distribution=Join-Path $work 'shipping-distribution/bundle';$cwd=Join-Path $work 'shipping-empty-cwd'
  New-Item -ItemType Directory (Join-Path $built 'bin'),(Join-Path $built 'lib/nested') | Out-Null
  'synthetic executable bytes' | Set-Content (Join-Path $built 'bin/load_stock.exe')
  foreach($dll in @('ggml.dll','ggml-base.dll','ggml-cpu.dll','llama.dll')){"synthetic $dll bytes" | Set-Content (Join-Path $built "lib/$dll")}
  'sidecar' | Set-Content (Join-Path $built 'lib/nested/asset.json');'hidden sidecar' | Set-Content (Join-Path $built '.hidden-sidecar')
  $referenceRuntime=Join-Path $built 'lib'
  $referenceManifest=@(Get-ChildItem -LiteralPath $referenceRuntime -Recurse -File | ForEach-Object {@{path=$_.FullName;sha256=Hash $_.FullName}})
  $cleanPath='C:\Windows\System32;C:\pinned-sdk';$env:Path='old runtime path';$env:LLAMADART_NATIVE_LIB_DIR='old override';$env:LLAMADART_BACKEND_MODULE_DIR='old alias'
  $trace=[Collections.Generic.List[object]]::new()
  function Copy-Item([string]$LiteralPath,[string]$Destination,[switch]$Recurse,[switch]$Force) {
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
    if($Variant -eq 'missing-copied-sidecar'){
      $missing=Join-Path $Destination 'lib/ggml-base.dll';if(Test-Path -LiteralPath $missing){Remove-Item -LiteralPath $missing}
    }
  }
  function Must($name,$exe,$arguments,$seconds=180) {
    if($name -ne 'fixed-normal-AOT-load' -or $seconds -ne 180 -or $arguments -ne 'synthetic-model.gguf'){throw 'AOT invocation arguments changed'}
    if((Get-Location).Path -cne $cwd -or $exe -cne (Join-Path $distribution 'bin/load_stock.exe')){throw 'actual function failed isolated cwd/copied executable wiring'}
    if($env:Path -cne $cleanPath -or $env:LLAMADART_NATIVE_LIB_DIR -or $env:LLAMADART_BACKEND_MODULE_DIR){throw 'actual function retained runtime override'}
    $trace.Add(@{cwd=(Get-Location).Path;exe=$exe;cleanPath=$true;nativeOverridesAbsent=$true})
    $rows=@();$ggml=Join-Path $distribution 'lib/ggml.dll';$base=Join-Path $distribution 'lib/ggml-base.dll'
    if($Variant -eq 'foreign-registry-provider'){$ggml=Join-Path $built 'lib/ggml.dll'}
    if($Variant -eq 'foreign-base-provider'){$base=Join-Path $built 'lib/ggml-base.dll'}
    foreach($dll in @('ggml.dll','ggml-base.dll','ggml-cpu.dll','llama.dll')){
      if($Variant -eq 'missing-provider-map' -and $dll -eq 'ggml-base.dll'){continue}
      $path=Join-Path $distribution "lib/$dll";if($dll -eq 'ggml.dll'){$path=$ggml};if($dll -eq 'ggml-base.dll'){$path=$base}
      $exports=@();$imports=@()
      if($dll -eq 'ggml.dll'){$exports=@(@{symbol='ggml_backend_reg_count';ownerPath=$ggml})}
      if($dll -eq 'ggml-base.dll'){$exports=@(@{symbol='ggml_backend_reg_name';ownerPath=$base})}
      if($dll -eq 'llama.dll'){$imports=@(@{symbol='ggml_backend_reg_count';ownerPath=$ggml},@{symbol='ggml_backend_reg_name';ownerPath=$base})}
      $rows+=@{checkpoint='after-stock-model-success';registryGettersCalled=$false;modulePath=$path;sha256=Hash $path;machine=34404;exports=$exports;imports=$imports}
    }
    $identity=@{observerAfterFirstPassiveSnapshot=$true;primaryMatchesCodeAsset=$true;noUnintendedDuplicateRegistry=$true;registryCountAfterOutcome=1;codeAssetProvider=@(@{ownerPath=$ggml});primaryRegistryImports=@(@{ownerPath=$ggml})}
    $lines=@($rows | ForEach-Object {'PASSIVE_MODULE '+($_ | ConvertTo-Json -Depth 12 -Compress)})
    $lines+='REGISTRY_IDENTITY '+($identity | ConvertTo-Json -Depth 12 -Compress)
    $lines -join "`n" | Set-Content "$O\$name.stdout.log"
    if($Variant -eq 'distribution-tampered-after-run'){'changed' | Add-Content (Join-Path $distribution 'lib/nested/asset.json')}
    if($Variant -eq 'source-bundle-tampered-after-run'){'changed' | Add-Content (Join-Path $built 'bin/load_stock.exe')}
    if($Variant -eq 'working-directory-written'){'unexpected' | Set-Content (Join-Path $cwd 'fallback-file')}
  }
  if($Variant -eq 'in-source-cwd'){$cwd=Join-Path $sources[0] 'source-cwd'}
  if($Variant -eq 'source-distribution'){$distribution=Join-Path $sources[2] 'shipping-bundle'}
  $failed=$false;$message=''
  try{Invoke-AotShippingDistribution $built $distribution $cwd $sources 'synthetic-model.gguf'}catch{$failed=$true;$message=$_.Exception.Message}
  try{
    if($failed -ne ($Variant -ne 'valid')){throw "AOT classification wrong $Variant : $message"}
    if($Variant -in @('in-source-cwd','source-distribution','missing-copied-sidecar') -and $trace.Count){throw 'invalid isolation/copy reached consumer'}
    if($Variant -eq 'valid'){
      $before=Get-Content "$O\normal-AOT-distribution-before.json" -Raw | ConvertFrom-Json
      $after=Get-Content "$O\normal-AOT-distribution-after.json" -Raw | ConvertFrom-Json
      if($before.distributed.files.Count -ne 7 -or $after.consumerSucceeded -ne $true -or -not (Test-Path "$O\normal-AOT-distributed-providers.json")){throw 'complete hidden/nested bundle or provider receipts missing'}
      Assert-AotManifestEqual $before.distributed $after.distributed
    }
    return @{variant=$Variant;failed=$failed;failureMessage=$message;syntheticConsumers=$trace.Count;actualInvocation=$trace.ToArray()}
  } finally {Remove-Item $work -Recurse -Force}
}
$results=@();foreach($variant in @('valid','in-source-cwd','source-distribution','missing-copied-sidecar','foreign-registry-provider','foreign-base-provider','missing-provider-map','distribution-tampered-after-run','source-bundle-tampered-after-run','working-directory-written')){$results+=Flow $variant}
[ordered]@{offlineOnly=$true;actualDistributionAndIsolationAndProviderFunctionsExecuted=$true;actualGuestIdentityCheckerExecuted=$true;completeHiddenNestedAndSidecarCopyVerified=$true;actualMustProcessLeafStubbedOnly=$true;cases=$results;helperSha256=(Hash (Join-Path $BundleRoot 'aot_distribution.ps1'));actualNativeModelWindowsOrCloudExecutions=0} | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
