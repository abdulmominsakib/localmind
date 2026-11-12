function Get-AotAbsolutePath([string]$Path) {
  if(-not [IO.Path]::IsPathRooted($Path)){throw 'AOT distribution requires absolute paths'}
  $absolute=[IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
  return $absolute
}
function Assert-AotNoReparseAncestors([string]$Path) {
  $absolute=Get-AotAbsolutePath $Path
  $ancestor=$absolute
  while($ancestor){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'AOT path has a reparse-point ancestor'}
    $parent=[IO.Path]::GetDirectoryName($ancestor)
    if($parent -eq $ancestor){break};$ancestor=$parent
  }
}
function Test-AotWithin([string]$Path,[string]$Root) {
  $p=Get-AotAbsolutePath $Path;$r=Get-AotAbsolutePath $Root
  return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Assert-AotOutsideSources([string]$Distribution,[string]$WorkingDirectory,[string[]]$SourceRoots) {
  if($SourceRoots.Count -lt 5){throw 'all matrix and mutation source roots required'}
  foreach($source in $SourceRoots){
    foreach($path in @($Distribution,$WorkingDirectory)){
      if((Test-AotWithin $path $source) -or (Test-AotWithin $source $path)){throw 'AOT distribution/working directory overlaps a source tree'}
    }
  }
  if((Test-AotWithin $Distribution $WorkingDirectory) -or (Test-AotWithin $WorkingDirectory $Distribution)){throw 'AOT distribution and empty working directory must be separate'}
}
function Get-AotBundleManifest([string]$Root) {
  $absolute=Get-AotAbsolutePath $Root
  Assert-AotNoReparseAncestors $absolute
  if(-not (Test-Path -LiteralPath $absolute -PathType Container)){throw 'AOT bundle directory missing'}
  $entries=@(Get-Item -LiteralPath $absolute)+@(Get-ChildItem -LiteralPath $absolute -Recurse -Force)
  if(@($entries | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count){throw 'AOT bundle contains a reparse point'}
  $files=@(Get-ChildItem -LiteralPath $absolute -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
    @{relativePath=$_.FullName.Substring($absolute.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
  })
  if($files.Count -eq 0){throw 'AOT bundle contains no distribution files'}
  return [pscustomobject]@{root=$absolute;files=$files}
}
function Assert-AotManifestEqual($Expected,$Actual) {
  if($Expected.files.Count -ne $Actual.files.Count){throw 'AOT distribution file count changed or copied sidecar missing'}
  $want=@{};foreach($file in $Expected.files){if($want.ContainsKey($file.relativePath)){throw 'duplicate AOT inventory path'};$want[$file.relativePath]=$file}
  $seen=@{}
  foreach($file in $Actual.files){
    if($seen.ContainsKey($file.relativePath)){throw 'duplicate AOT inventory path'};$seen[$file.relativePath]=$true
    if(-not $want.ContainsKey($file.relativePath) -or $file.bytes -ne $want[$file.relativePath].bytes -or $file.sha256 -cne $want[$file.relativePath].sha256){throw 'AOT distribution file/path/hash differs from complete built bundle'}
  }
}
function New-AotDistribution([string]$BuiltBundle,[string]$Distribution,[string]$WorkingDirectory,[string[]]$SourceRoots) {
  Assert-AotOutsideSources $Distribution $WorkingDirectory $SourceRoots
  foreach($path in @($Distribution,$WorkingDirectory)+$SourceRoots){Assert-AotNoReparseAncestors $path}
  if((Test-Path -LiteralPath $Distribution) -or (Test-Path -LiteralPath $WorkingDirectory)){throw 'AOT distribution and empty working directory must be fresh; no rerun'}
  $built=Get-AotBundleManifest $BuiltBundle
  if(-not (Test-Path -LiteralPath (Join-Path $BuiltBundle 'bin/load_stock.exe') -PathType Leaf)){throw 'built AOT executable missing'}
  New-Item -ItemType Directory $Distribution,$WorkingDirectory | Out-Null
  Get-ChildItem -LiteralPath $BuiltBundle -Force | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $Distribution -Recurse -Force}
  $copied=Get-AotBundleManifest $Distribution
  Assert-AotManifestEqual $built $copied
  Assert-AotManifestEqual $built (Get-AotBundleManifest $BuiltBundle)
  return [pscustomobject]@{built=$built;distributed=$copied;workingDirectory=(Get-AotAbsolutePath $WorkingDirectory);sourceRoots=$SourceRoots}
}
function Assert-AotConsumerEnvironment($Plan,[string]$ActualWorkingDirectory,[string]$CleanPath,[string]$RuntimeDirectory) {
  Assert-AotOutsideSources $Plan.distributed.root $ActualWorkingDirectory $Plan.sourceRoots
  if((Get-AotAbsolutePath $ActualWorkingDirectory) -cne $Plan.workingDirectory){throw 'AOT actual child working directory differs from designated empty directory'}
  if(@(Get-ChildItem -LiteralPath $ActualWorkingDirectory -Force).Count){throw 'AOT child working directory is not empty'}
  if($env:Path -cne $CleanPath -or $env:LLAMADART_NATIVE_LIB_DIR -or $env:LLAMADART_BACKEND_MODULE_DIR){throw 'normal AOT PATH/environment has runtime override'}
  if(@($env:Path.Split([char]';') | Where-Object {$_ -and (Normalize-ComparisonDirectory $_) -eq (Normalize-ComparisonDirectory $RuntimeDirectory)}).Count){throw 'normal AOT PATH contains reference runtime'}
}
function Assert-AotLoadedProviders([string]$Name,$Plan) {
  $text=Get-Content "$O\$Name.stdout.log" -Raw
  $rows=@($text -split "`r?`n" | Where-Object {$_.StartsWith('PASSIVE_MODULE ')} | ForEach-Object {$_.Substring(15) | ConvertFrom-Json})
  $initial=@($rows | Where-Object {$_.checkpoint -eq 'after-stock-model-success'})
  if($initial.Count -eq 0){throw 'normal AOT initial post-outcome module map missing'}
  $nativeNames=@{};foreach($entry in $referenceManifest){if([IO.Path]::GetFileName($entry.path) -match '^(?:llama(?:dart)?|ggml(?:-.*)?|mtmd)\.dll$'){$nativeNames[[IO.Path]::GetFileName($entry.path).ToLowerInvariant()]=$true}}
  function Assert-DistributedProvider([string]$Path) {
    if(-not (Test-AotWithin $Path $Plan.distributed.root)){throw "normal AOT loaded foreign provider outside distributed bundle: $Path"}
    $absolute=Get-AotAbsolutePath $Path
    $relative=$absolute.Substring($Plan.distributed.root.Length+1).Replace('\','/')
    $files=@($Plan.distributed.files | Where-Object {$_.relativePath -ieq $relative})
    $mapped=@($initial | Where-Object {(Get-AotAbsolutePath $_.modulePath) -ieq $absolute})
    if($files.Count -ne 1 -or $mapped.Count -ne 1 -or $files[0].sha256 -cne $mapped[0].sha256){throw 'normal AOT provider lacks exact copied-file and loaded-module hash binding'}
  }
  $verified=@()
  foreach($row in $initial){
    $leaf=[IO.Path]::GetFileName($row.modulePath).ToLowerInvariant()
    if($nativeNames.ContainsKey($leaf)){
      Assert-DistributedProvider $row.modulePath
      $verified+=$row.modulePath
      foreach($symbol in @($row.exports)+@($row.imports)){
        if($symbol.symbol -match '^(ggml_backend_|llama_model_load|sd_dart_llama_model_load|llama_dart_model_load)'){Assert-DistributedProvider $symbol.ownerPath}
      }
    }
  }
  foreach($nameRequired in @('llama.dll','ggml.dll','ggml-base.dll','ggml-cpu.dll')){
    if(@($verified | Where-Object {[IO.Path]::GetFileName($_).ToLowerInvariant() -eq $nameRequired}).Count -eq 0){throw "normal AOT distributed native provider missing $nameRequired"}
  }
  $identityLines=@($text -split "`r?`n" | Where-Object {$_.StartsWith('REGISTRY_IDENTITY ')})
  if($identityLines.Count -ne 1){throw 'normal AOT code-asset identity missing'}
  $identity=$identityLines[0].Substring(18) | ConvertFrom-Json
  foreach($provider in @($identity.codeAssetProvider)+@($identity.primaryRegistryImports)){Assert-DistributedProvider $provider.ownerPath}
  @{normalAotOnly=$true;distributedRoot=$Plan.distributed.root;workingDirectory=$Plan.workingDirectory;verifiedActualNativeProviders=$verified;identity=$identity;otherHookOverrideRowsUnrestricted=$true} | ConvertTo-Json -Depth 18 | Set-Content "$O\normal-AOT-distributed-providers.json"
}
function Invoke-AotShippingDistribution([string]$BuiltBundle,[string]$Distribution,[string]$WorkingDirectory,[string[]]$SourceRoots,[string]$ModelPath) {
  $plan=New-AotDistribution $BuiltBundle $Distribution $WorkingDirectory $SourceRoots
  $plan | ConvertTo-Json -Depth 10 | Set-Content "$O\normal-AOT-distribution-before.json"
  $env:Path=$cleanPath
  Remove-Item Env:LLAMADART_NATIVE_LIB_DIR,Env:LLAMADART_BACKEND_MODULE_DIR -ErrorAction SilentlyContinue
  $succeeded=$false
  try {
    Push-Location -LiteralPath $WorkingDirectory
    try {
      Assert-AotConsumerEnvironment $plan (Get-Location).Path $cleanPath $referenceRuntime
      @{workingDirectory=(Get-Location).Path;distributedExecutable=(Join-Path $Distribution 'bin/load_stock.exe');normalPathMatches=$true;nativeEnvironmentOverridesAbsent=$true} | ConvertTo-Json | Set-Content "$O\normal-AOT-distributed-process-inputs.json"
      Must 'fixed-normal-AOT-load' (Join-Path $Distribution 'bin/load_stock.exe') $ModelPath 180
      if(-not (CheckSnapshot 'fixed-normal-AOT-load' $true)){throw 'normal published-assets AOT identity failed'}
      Assert-AotLoadedProviders 'fixed-normal-AOT-load' $plan
      Assert-AotConsumerEnvironment $plan (Get-Location).Path $cleanPath $referenceRuntime
      $succeeded=$true
    } finally {Pop-Location}
  } finally {
    $after=Get-AotBundleManifest $Distribution
    $builtAfter=Get-AotBundleManifest $BuiltBundle
    @{consumerSucceeded=$succeeded;distributed=$after;built=$builtAfter} | ConvertTo-Json -Depth 10 | Set-Content "$O\normal-AOT-distribution-after.json"
    Assert-AotManifestEqual $plan.distributed $after
    Assert-AotManifestEqual $plan.built $builtAfter
  }
}
