param([switch]$Prepare,[switch]$Seal,[switch]$FunctionsOnly)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$FixtureRoot=$PSScriptRoot
. "$FixtureRoot/comparison_path.ps1"
. "$FixtureRoot/aot_distribution.ps1"
. "$FixtureRoot/registry_mutation.ps1"
. "$FixtureRoot/runtime.ps1"
function Hash($Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Verify($Path,$Expected) {
  if($Expected -cnotmatch '^[0-9a-f]{64}$' -or (Hash $Path) -cne $Expected){throw 'input/source SHA256 mismatch'}
}
function Assert-FreeSpace([long]$Available,[long]$Required,[string]$Phase) {
  @{phase=$Phase;availableBytes=$Available;requiredPeakAdditionalBytes=$Required;fits=$Available -ge $Required} | ConvertTo-Json | Set-Content "$O/disk-$Phase.json"
  if($Available -lt $Required){throw "INSUFFICIENT_STOCK_RUNNER_SPACE phase=$Phase available=$Available required=$Required"}
}
function FreeBytes { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($W))).AvailableFreeSpace }
function InvokeCase($name,$exe,$arguments,$seconds=180) {
  if($name -cnotmatch '^[a-zA-Z0-9-]+$'){throw 'invalid case name'}
  $caseTemp=Join-Path "$W/case-tmp" $name
  if(Test-Path $caseTemp){throw 'case temporary directory already exists; no rerun'}
  New-Item -ItemType Directory $caseTemp -Force | Out-Null
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$exe;$psi.Arguments=$arguments;$psi.WorkingDirectory=(Get-Location).Path
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  foreach($key in @('TEMP','TMP','TMPDIR')){$psi.EnvironmentVariables[$key]=$caseTemp}
  @{name=$name;executable=$exe;arguments=$arguments;workingDirectory=$psi.WorkingDirectory;temporaryDirectory=$caseTemp;pubCache=$env:PUB_CACHE;freshProcess=$true;normalPathMatches=$env:Path -ceq $cleanPath;nativeOverride=$env:LLAMADART_NATIVE_LIB_DIR;aliasOverride=$env:LLAMADART_BACKEND_MODULE_DIR} | ConvertTo-Json | Set-Content "$O/$name-process-environment.json"
  $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
  $code=-1;$timedOut=$false
  try {
    if(-not $process.Start()){throw "process start failed $name"}
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    $timedOut= -not $process.WaitForExit($seconds*1000)
    if($timedOut){$process.Kill($true);$process.WaitForExit()}
    [IO.File]::WriteAllText("$O/$name.stdout.log",$stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText("$O/$name.stderr.log",$stderr.GetAwaiter().GetResult())
    $code=$process.ExitCode
  } finally {
    @{name=$name;exitCode=$code;timeout=$timedOut;utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress | Add-Content "$O/cases.jsonl"
    $process.Dispose()
  }
  if($timedOut){throw "process timeout $name; no retries"}
  return $code
}
function Must($name,$exe,$arguments,$seconds=180) {
  if((InvokeCase $name $exe $arguments $seconds) -ne 0){throw "required process failure $name"}
}
function Save-Asset($Asset) {
  $target=Join-Path $S $Asset.name
  if((Test-Path $target) -or (Test-Path "$target.part")){throw 'asset already exists; no warmed reuse'}
  Must "download-$($Asset.name.Replace('.','-'))" "$env:WINDIR/System32/curl.exe" "-fsSL --max-time 600 -o `"$target.part`" `"$($Asset.url)`"" 610
  Verify "$target.part" $Asset.sha256
  $bytes=(Get-Item "$target.part").Length
  if($Asset.bytes -and $bytes -ne $Asset.bytes){throw 'pinned input byte length mismatch'}
  Move-Item "$target.part" $target
  @{name=$Asset.name;url=$Asset.url;sha256=$Asset.sha256;bytes=$bytes} | ConvertTo-Json | Set-Content "$O/$($Asset.name)-input.json"
  return $target
}
function Export-BoundSource([string]$Revision,[string]$Name,[string]$Git,[string]$Repository) {
  if($Revision -cnotmatch '^[0-9a-f]{40}$'){throw 'invalid source commit binding'}
  Must "$Name-source-commit" $Git "-C `"$Repository`" rev-parse $Revision^{commit}"
  $resolved=(Get-Content "$O/$Name-source-commit.stdout.log" -Raw).Trim()
  if($resolved -cne $Revision){throw 'wrong source commit'}
  Must "$Name-source-tree" $Git "-C `"$Repository`" rev-parse $Revision^{tree}"
  $tree=(Get-Content "$O/$Name-source-tree.stdout.log" -Raw).Trim()
  Must "$Name-source-inventory" $Git "-C `"$Repository`" ls-tree -r --full-tree $Revision"
  $tracked=@(Get-Content "$O/$Name-source-inventory.stdout.log")
  if($tracked.Count -eq 0){throw 'source inventory unavailable'}
  $archive="$S/$Name.tar"
  # Archive honors checkout conversion; the manifest requires the stored blobs.
  Must "$Name-git-export" $Git "-c core.autocrlf=false -c core.eol=lf -C `"$Repository`" archive --format=tar --output=`"$archive`" $Revision" 180
  $root="$S/$Name-source";New-Item -ItemType Directory $root | Out-Null
  Must "$Name-source-extract" "$env:WINDIR/System32/tar.exe" "-xf `"$archive`" -C `"$root`"" 180
  $manifest=@();$seen=@{}
  foreach($line in $tracked){
    if($line -cnotmatch '^([0-9]{6}) blob ([0-9a-f]{40})\t(.+)$'){throw 'unrecognized Git inventory entry'}
    $mode=$Matches[1];$blob=$Matches[2];$relative=$Matches[3]
    if($mode -notin @('100644','100755') -or $relative -match '(^/|(^|/)\.\.(/|$)|\\)' -or $seen.ContainsKey($relative)){throw 'unsafe or duplicate source path/mode'}
    $seen[$relative]=$true;$path=Join-Path $root $relative
    $bytes=[IO.File]::ReadAllBytes($path)
    $header=[Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $sha=[Security.Cryptography.SHA1]::Create()
    try{$actual=[Convert]::ToHexString($sha.ComputeHash([byte[]]($header+$bytes))).ToLowerInvariant()}finally{$sha.Dispose()}
    if($actual -cne $blob){throw 'exported source differs from Git blob'}
    $manifest+=@{path=$relative;mode=$mode;gitBlob=$blob;bytes=$bytes.Length;sha256=Hash $path}
  }
  if(@(Get-ChildItem $root -Recurse -File -Force).Count -ne $manifest.Count){throw 'export has extra/missing source files'}
  $manifest | ConvertTo-Json -Depth 5 | Set-Content "$O/$Name-source-files.json"
  @{commit=$Revision;tree=$tree;trackedFiles=$manifest.Count;manifestSha256=Hash "$O/$Name-source-files.json";archiveSha256=Hash $archive} | ConvertTo-Json | Set-Content "$O/$Name-source-binding.json"
  return $root
}
function Assert-QualificationTerminal($Terminal,$Summary,$Matrix) {
  if($Terminal.harnessFailed -ne $false -or $Terminal.completed -ne $true -or $Terminal.phase -ne 'complete'){throw 'failed/incomplete terminal'}
  $expected=@();foreach($r in @('original','fixed')){foreach($h in 0,1){foreach($e in 0,1){foreach($p in 0,1){$expected+="$r-H${h}E${e}P${p}"}}}}
  $expected+=@('fixed-H0E1P0-alias','fixed-H1E1P0-alias')
  if($Matrix.Count -ne 18 -or @($Matrix.name | Select-Object -Unique).Count -ne 18){throw 'missing/duplicate qualification row'}
  foreach($name in $expected){
    $rows=@($Matrix | Where-Object {$_.name -ceq $name})
    if($rows.Count -ne 1){throw 'wrong matrix identity'}
    if(($name -like 'fixed-*' -or $name -ceq 'original-H0E0P0') -and ($rows[0].exitCode -ne 0 -or $rows[0].identityValid -ne $true -or $rows[0].loadedCpuZero -ne $true)){throw 'required row failed'}
  }
  foreach($key in @('fixedNormalAotPassed','maintainedRegistryIntegrationPassed','actualCodeAssetMappingMutationRefusedAndRestored','maintainedBindingRefusalTestsPassed')){if($Summary.$key -ne $true){throw 'incomplete required runtime controls'}}
  if($Summary.gpuQualified -ne $false){throw 'GPU qualification claim is out of scope'}
}
function Seal-Evidence {
  $zip="$W/evidence.zip"
  if((Test-Path $zip) -or (Test-Path "$O/evidence-manifest.json")){throw 'evidence archive/manifest must not be overwritten'}
  if(-not (Test-Path "$O/terminal.json")){
    @{harnessFailed=$true;completed=$false;phase='incomplete';head=$env:GITHUB_SHA;runId=$env:GITHUB_RUN_ID;runAttempt=$env:GITHUB_RUN_ATTEMPT} | ConvertTo-Json | Set-Content "$O/terminal.json"
  }
  $fixture=Get-Content "$FixtureRoot/transport-selftest.json" -Raw | ConvertFrom-Json
  Copy-Item "$FixtureRoot/transport-selftest.bin" "$O/transport-selftest.bin"
  Verify "$O/transport-selftest.bin" $fixture.sha256
  $inventory=Get-AotBundleManifest $O
  $inventory.files | ConvertTo-Json -Depth 5 | Set-Content "$O/evidence-manifest.json"
  [IO.Compression.ZipFile]::CreateFromDirectory($O,$zip)
  $check="$W/archive-check";[IO.Compression.ZipFile]::ExtractToDirectory($zip,$check)
  $actual=Get-AotBundleManifest $check
  $expected=[pscustomobject]@{files=@($inventory.files)+@(@{relativePath='evidence-manifest.json';bytes=(Get-Item "$O/evidence-manifest.json").Length;sha256=Hash "$O/evidence-manifest.json"})}
  Assert-AotManifestEqual $expected $actual
  Remove-Item $check -Recurse -Force
  @{sha256=Hash $zip;bytes=(Get-Item $zip).Length;completeManifestChecked=$true} | ConvertTo-Json | Set-Content "$W/archive-receipt.json"
}
if($FunctionsOnly){return}
$W=$env:LLAMADART_WINDOWS_QUALIFICATION
if(-not $W -or -not [IO.Path]::IsPathRooted($W)){throw 'set absolute LLAMADART_WINDOWS_QUALIFICATION evidence root'}
$S=Join-Path $W 'stage';$O=Join-Path $W 'out'
if($Seal){New-Item -ItemType Directory $O -Force | Out-Null;Seal-Evidence;exit 0}
if($Prepare -and (Test-Path $W)){throw 'fresh qualification root required; existing evidence preserved'}
if(-not $Prepare -and (Test-Path "$O/terminal.json")){throw 'terminal already exists; no rerun or evidence overwrite'}
$failed=$true;$phase='setup';$completed=$false
try {
  if(-not $IsWindows){throw 'Windows host required'}
  if($Prepare){
    New-Item -ItemType Directory $S,$O | Out-Null
  } elseif(-not (Test-Path "$S/sdk-ready.json")){throw 'pinned SDK preparation missing'}
  $cleanPath=$env:Path
  $spec=Get-Content "$FixtureRoot/inputs.json" -Raw | ConvertFrom-Json
  $runtime="$S/published-reference-runtime";$taskRuntimeDirectories=@($runtime)
  $originalWindowsPath=$env:Path;$hostExecutable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;$hostDirectory=Split-Path $hostExecutable
  if($Prepare){
    @{os=[Environment]::OSVersion.VersionString;imageOS=$env:ImageOS;imageVersion=$env:ImageVersion;processors=[Environment]::ProcessorCount;memoryBytes=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory;freeBytes=FreeBytes} | ConvertTo-Json | Set-Content "$O/host.json"
    # SDK compressed bytes plus Dart-only extraction and staging margin, before downloads.
    Assert-FreeSpace (FreeBytes) 5GB 'before-sdk'
    foreach($asset in @($spec.assets | Where-Object {$_.name -in @('flutter.zip','git.zip')})){Save-Asset $asset | Out-Null}
    $archive=[IO.Compression.ZipFile]::OpenRead("$S/flutter.zip")
    try {
      $entries=@($archive.Entries | Where-Object {$_.FullName.StartsWith('flutter/bin/cache/dart-sdk/',[StringComparison]::Ordinal) -and $_.Name})
      if($entries.Count -lt 100){throw 'pinned Flutter archive Dart SDK subtree missing'}
      $expanded=[long]($entries | Measure-Object Length -Sum).Sum
      Assert-FreeSpace (FreeBytes) ($expanded+1GB) 'dart-extraction'
      $sdkFiles=@()
      foreach($entry in $entries){
        if($entry.FullName -match '(^/|(^|/)\.\.(/|$)|\\)'){throw 'unsafe SDK ZIP entry'}
        $target=Join-Path $S $entry.FullName;New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$entryHash=[Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
        Verify $target $entryHash
        if((Get-Item $target).Length -ne $entry.Length){throw 'SDK entry extraction length mismatch'}
        $sdkFiles+=@{relativePath=$entry.FullName;bytes=$entry.Length;sha256=Hash $target}
      }
      $sdkFiles | ConvertTo-Json -Depth 4 | Set-Content "$O/sdk-extracted-files.json"
      @{archiveSha256=Hash "$S/flutter.zip";frameworkVersion='3.47.1';dartVersion='3.13.1';extraction='every file in exact archived flutter/bin/cache/dart-sdk/ subtree, unmodified';expandedBytes=$expanded;flutterToolNotExecuted=$true} | ConvertTo-Json | Set-Content "$O/sdk-identity.json"
    } finally {$archive.Dispose()}
    [IO.Compression.ZipFile]::ExtractToDirectory("$S/git.zip","$S/git")
    $dart="$S/flutter/bin/cache/dart-sdk/bin/dart.exe";$git="$S/git/cmd/git.exe"
    Must 'sdk-dart-version' $dart '--version'
    Must 'sdk-git-version' $git '--version'
    if((Get-Content "$O/sdk-dart-version.stdout.log" -Raw) -notmatch '3\.13\.1 '){throw 'pinned Dart version mismatch'}
    $pathPlan=New-ComparisonPath $originalWindowsPath @((Split-Path $git),(Split-Path $dart)) $hostDirectory $taskRuntimeDirectories
    Invoke-ComparisonPathPreflight 'prepared-sdk' $pathPlan.NormalPath $hostExecutable $FixtureRoot $O $git $dart
    @{dartPath=$dart;gitPath=$git;dartSha256=Hash $dart;gitSha256=Hash $git;version='3.13.1'} | ConvertTo-Json | Set-Content "$S/sdk-ready.json"
    Copy-Item "$S/sdk-ready.json" "$O/sdk-executables.json"
    $failed=$false
  } else {
    $dart="$S/flutter/bin/cache/dart-sdk/bin/dart.exe";$git="$S/git/cmd/git.exe"
    $ready=Get-Content "$S/sdk-ready.json" -Raw | ConvertFrom-Json;Verify $dart $ready.dartSha256;Verify $git $ready.gitSha256
    $pathPlan=New-ComparisonPath $originalWindowsPath @((Split-Path $git),(Split-Path $dart)) $hostDirectory $taskRuntimeDirectories
    $cleanPath=$pathPlan.NormalPath;$env:Path=$cleanPath
    Remove-Item Env:LLAMADART_NATIVE_LIB_DIR,Env:LLAMADART_BACKEND_MODULE_DIR -ErrorAction SilentlyContinue
    Invoke-ComparisonPathPreflight 'qualification-sdk' $cleanPath $hostExecutable $FixtureRoot $O $git $dart
    $repo=(Resolve-Path "$FixtureRoot/../../..").Path
    Must 'checkout-head' $git "-C `"$repo`" rev-parse HEAD"
    $head=(Get-Content "$O/checkout-head.stdout.log" -Raw).Trim()
    if($head -cne $env:GITHUB_SHA){throw 'workflow SHA differs from checked-out HEAD'}
    Must 'checkout-status' $git "-C `"$repo`" status --porcelain --untracked-files=all"
    if([IO.File]::ReadAllText("$O/checkout-status.stdout.log").Trim()){throw 'source checkout must be clean'}
    $candidate=Export-BoundSource $head 'candidate' $git $repo
    $baseline=Export-BoundSource $spec.baselineCommit 'baseline' $git $repo
    Assert-FreeSpace (FreeBytes) 4GB 'before-native'
    New-Item -ItemType Directory $runtime | Out-Null
    $archives=@();foreach($asset in @($spec.assets | Where-Object {$_.name -like 'candidate-*.tgz'})){
      $file=Save-Asset $asset;$archives+=$file
      Must "extract-$($asset.name.Replace('.','-'))" "$env:WINDIR/System32/tar.exe" "-xzf `"$file`" -C `"$runtime`"" 180
    }
    $nativeBytes=[long](Get-ChildItem $runtime -Recurse -File -Force | Measure-Object Length -Sum).Sum
    $sourceBytes=[long](Get-ChildItem $candidate,$baseline -Recurse -File -Force | Measure-Object Length -Sum).Sum
    # Four hook trees, disposable control, AOT build+copy, source copies, Pub+build margin and model.
    $peak=[long](8*$nativeBytes+3*$sourceBytes+2GB+1117320736)
    @{nativeExpandedBytes=$nativeBytes;sourceExpandedBytes=$sourceBytes;nativeCopiesBudget=8;pubAndBuildMarginBytes=2GB;modelBytes=1117320736;additionalPeakBytes=$peak} | ConvertTo-Json | Set-Content "$O/peak-space-budget.json"
    Assert-FreeSpace (FreeBytes) $peak 'before-model-and-cases'
    $model=Save-Asset ($spec.assets | Where-Object {$_.name -eq 'qwen.gguf'})
    if(@(Get-CimInstance Win32_PnPEntity | Where-Object {$_.DeviceID -like '*VEN_10DE*'}).Count -or (Test-Path "$env:WINDIR/System32/nvcuda.dll")){throw 'CPU-only hardware/driver required'}
    $C=[pscustomobject]@{candidateSourceRoot=$candidate;baselineSourceRoot=$baseline;candidateSourceFiles="$O/candidate-source-files.json";baselineSourceFiles="$O/baseline-source-files.json";modelPath=$model;candidateRuntimeArchives=$archives;flutterBat=''}
    $env:PUB_CACHE="$W/pub-cache";$env:CI='true';$env:FLUTTER_SUPPRESS_ANALYTICS='true'
    New-Item -ItemType Directory $env:PUB_CACHE,"$W/case-tmp" -Force | Out-Null
    $phase='runtime'
    Invoke-RegistryQualification
    foreach($asset in $spec.assets){Verify (Join-Path $S $asset.name) $asset.sha256}
    foreach($entry in @(Get-Content "$O/sdk-extracted-files.json" -Raw | ConvertFrom-Json)){Verify (Join-Path $S $entry.relativePath) $entry.sha256}
    $completed=$true;$phase='complete';$failed=$false
  }
} catch {
  New-Item -ItemType Directory $O -Force | Out-Null
  $_ | Out-String | Set-Content "$O/$phase-failure.txt"
} finally {
  if(-not $Prepare){
    foreach($mode in @('original-H0','original-H1','fixed-H0','fixed-H1','fixed-codeasset-control')){
      $generated="$W/$mode/core/.dart_tool"
      if(Test-Path $generated){
        foreach($file in @(Get-ChildItem $generated -Recurse -Force -File | Where-Object {$_.Name -eq 'native_assets.yaml' -or ($_.Name -in @('input.json','output.json') -and $_.FullName -match 'hooks_runner')})){
          $relative=$file.FullName.Substring((Get-Item $generated).FullName.Length+1)
          $target=Join-Path "$O/$mode-native-asset-maps" $relative
          New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null;Copy-Item -LiteralPath $file.FullName $target -Force
        }
      }
    }
  }
  if(-not $Prepare -or $failed){
    @{harnessFailed=$failed;completed=$completed;phase=$phase;head=$env:GITHUB_SHA;runId=$env:GITHUB_RUN_ID;runAttempt=$env:GITHUB_RUN_ATTEMPT;qualificationPendingIndependentReview=$true} | ConvertTo-Json | Set-Content "$O/terminal.json"
  }
}
if($failed){exit 1}
if(-not $Prepare){
  try{Assert-QualificationTerminal (Get-Content "$O/terminal.json" -Raw | ConvertFrom-Json) (Get-Content "$O/windows1649-summary.json" -Raw | ConvertFrom-Json) @(Get-Content "$O/override-matrix.json" -Raw | ConvertFrom-Json)}catch{$_ | Out-String | Set-Content "$O/terminal-validation-failure.txt";@{harnessFailed=$true;completed=$false;phase='terminal-validation';head=$env:GITHUB_SHA;runId=$env:GITHUB_RUN_ID;runAttempt=$env:GITHUB_RUN_ATTEMPT} | ConvertTo-Json | Set-Content "$O/terminal.json";exit 1}
}
