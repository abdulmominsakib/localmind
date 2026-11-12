param([string]$BundleRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
. "$BundleRoot/qualification.ps1" -FunctionsOnly
$W=Join-Path (Split-Path $OutputPath) 'protocol';$O=Join-Path $W 'out'
New-Item -ItemType Directory $O | Out-Null
function Reject([scriptblock]$Action,[string]$Name){$refused=$false;try{& $Action}catch{$refused=$true};if(-not $refused){throw "negative accepted: $Name"}}
$phase='controls';$cleanPath=$env:Path
# Execute the real child owner: nonzero and timeout cannot turn into a successful Must.
$hostExe=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
Must 'child-positive' $hostExe '-NoProfile -Command "Write-Output good; [Console]::Error.WriteLine(''informational''); exit 0"' 20
if((Get-Content "$O/child-positive.stdout.log" -Raw) -notmatch 'good' -or (Get-Content "$O/child-positive.stderr.log" -Raw) -notmatch 'informational'){throw 'raw streams missing'}
Reject {Must 'child-failure' $hostExe '-NoProfile -Command "exit 7"' 20} 'process failure'
Reject {Must 'child-timeout' $hostExe '-NoProfile -Command "Start-Sleep -Seconds 10"' 1} 'process timeout'
$cases=@(Get-Content "$O/cases.jsonl" | ForEach-Object {$_ | ConvertFrom-Json})
if($cases.Count -ne 3 -or $cases[1].exitCode -ne 7 -or $cases[2].timeout -ne $true){throw 'process receipt lost failure/timeout'}
Assert-FreeSpace 100 99 'fits'
Reject {Assert-FreeSpace 98 99 'fails'} 'stock runner disk blocker'
$input=Join-Path $W 'input.bin';[IO.File]::WriteAllBytes($input,[byte[]](1,2,3))
Verify $input (Hash $input)
Reject {Verify $input ('0'*64)} 'wrong input digest'
# Exercise the real PATH planner with mixed case and quoted components.
$path=New-ComparisonPath 'C:\Windows\System32;"c:\RUNTIME\";C:\git' @('C:\sdk') 'C:\shell' @('C:\runtime')
if($path.NormalPath.ToLowerInvariant().Contains('runtime') -or -not $path.NormalPath.Contains('C:\Windows\System32')){throw 'PATH runtime leak/removal of OS commands'}
$leak=Join-Path $W 'leaking-runtime';New-Item -ItemType Directory $leak | Out-Null
'foreign dll' | Set-Content "$leak/ggml.dll"
Reject {New-ComparisonPath $leak @() '' @()} 'original PATH runtime leakage'
Reject {New-ComparisonPath 'C:\Windows' @() '' @('C:\runtime') 'C:\foreign'} 'foreign PATH prefix'
# Source commit and every tracked blob are checked against actual Git output.
$repo=Join-Path $W 'repository';New-Item -ItemType Directory $repo | Out-Null
$git=(Get-Command git).Source
& $git -C $repo init -q
& $git -C $repo config user.name Fixture
& $git -C $repo config user.email fixture@example.invalid
[IO.File]::WriteAllText("$repo/.gitattributes","*.txt text`nliteral-crlf.txt -text`npayload.bin -text`n")
[IO.File]::WriteAllText("$repo/source.txt","bound source bytes`nsecond line`n")
[IO.File]::WriteAllText("$repo/literal-crlf.txt","literal CRLF bytes`r`nsecond line`r`n")
[IO.File]::WriteAllBytes("$repo/payload.bin",[byte[]](0,255,13,10,10,128))
& $git -C $repo config core.autocrlf false
& $git -C $repo add .
& $git -C $repo commit -qm fixture
$head=(& $git -C $repo rev-parse HEAD).Trim()
$S=Join-Path $W 'stage';New-Item -ItemType Directory $S | Out-Null
$originalMust=${function:Must}
$mutate=$false
function Must($name,$exe,$arguments,$seconds=180){
  if($name -like '*-source-extract' -and -not $IsWindows){$exe=(Get-Command tar).Source}
  & $originalMust $name $exe $arguments $seconds
  if($mutate -and $name -like '*-source-extract'){[IO.File]::AppendAllText("$S/wrong-source/source.txt",'corruption')}
}
foreach($autocrlf in @('false','true')){
  & $git -C $repo config core.autocrlf $autocrlf
  & $git -C $repo config core.eol crlf
  Export-BoundSource $head "good-$autocrlf" $git $repo | Out-Null
  foreach($name in @('source.txt','literal-crlf.txt','payload.bin')){
    if((Hash "$S/good-$autocrlf-source/$name") -cne (Hash "$repo/$name")){throw "source export changed literal bytes $autocrlf $name"}
  }
}
Reject {Export-BoundSource ('0'*40) 'wrong-commit' $git $repo} 'wrong source commit'
$mutate=$true
Reject {Export-BoundSource $head 'wrong' $git $repo} 'wrong exported source bytes'
# A legitimate original split registry remains data; malformed/hash-skewed maps do not.
$referenceRuntime=Join-Path $W 'reference-runtime';New-Item -ItemType Directory $referenceRuntime | Out-Null
'published DLL bytes' | Set-Content "$referenceRuntime/ggml.dll"
$row=@{checkpoint='after-stock-model-exception';registryGettersCalled=$false;modulePath="$referenceRuntime/ggml.dll";sha256=Hash "$referenceRuntime/ggml.dll";machine=34404}
$identity=@{observerAfterFirstPassiveSnapshot=$true;primaryMatchesCodeAsset=$false;noUnintendedDuplicateRegistry=$false;registryCountAfterOutcome=1}
function Write-Snapshot { @('MODEL_OUTCOME exception known split',('PASSIVE_MODULE '+($row | ConvertTo-Json -Compress)),('REGISTRY_IDENTITY '+($identity | ConvertTo-Json -Compress))) -join "`n" | Set-Content "$O/original-snapshot.stdout.log" }
Write-Snapshot
if(-not (CheckSnapshot 'original-snapshot' $false)){throw 'original split outcome discarded'}
if(CheckSnapshot 'original-snapshot' $true){throw 'fixed split registry accepted'}
$row.sha256='wrong';Write-Snapshot
if(CheckSnapshot 'original-snapshot' $false){throw 'original malformed module hash accepted'}
# Actual terminal validator: missing/duplicate identity, nonzero fixed, false completion.
$matrix=@();foreach($r in 'original','fixed'){foreach($h in 0,1){foreach($e in 0,1){foreach($p in 0,1){$matrix+=@{name="$r-H${h}E${e}P${p}";exitCode=0;identityValid=$true;loadedCpuZero=$true}}}}}
$matrix+=@(@{name='fixed-H0E1P0-alias';exitCode=0;identityValid=$true;loadedCpuZero=$true},@{name='fixed-H1E1P0-alias';exitCode=0;identityValid=$true;loadedCpuZero=$true})
$terminal=@{harnessFailed=$false;completed=$true;phase='complete'}
$summary=@{fixedNormalAotPassed=$true;maintainedRegistryIntegrationPassed=$true;actualCodeAssetMappingMutationRefusedAndRestored=$true;maintainedBindingRefusalTestsPassed=$true;gpuQualified=$false}
Assert-QualificationTerminal $terminal $summary $matrix
Reject {Assert-QualificationTerminal $terminal $summary $matrix[0..16]} 'missing model case'
$dup=@($matrix[0..16]) + @($matrix[0]);Reject {Assert-QualificationTerminal $terminal $summary $dup} 'duplicate model case'
$matrix[8].exitCode=1;Reject {Assert-QualificationTerminal $terminal $summary $matrix} 'failed fixed case';$matrix[8].exitCode=0
$terminal.completed=$false;Reject {Assert-QualificationTerminal $terminal $summary $matrix} 'false success incomplete';$terminal.completed=$true
$terminal.harnessFailed=$true;Reject {Assert-QualificationTerminal $terminal $summary $matrix} 'caught runtime failure';$terminal.harnessFailed=$false
$summary.maintainedRegistryIntegrationPassed=$false;Reject {Assert-QualificationTerminal $terminal $summary $matrix} 'missing control'
# AOT reparse points and duplicated manifest paths must fail before a consumer.
$bundle=Join-Path $W 'reparse-bundle';New-Item -ItemType Directory $bundle | Out-Null
'payload' | Set-Content "$bundle/original.txt"
$linkTarget=Join-Path $W 'link-target';New-Item -ItemType Directory $linkTarget | Out-Null
$linkType='SymbolicLink';if($IsWindows){$linkType='Junction'}
New-Item -ItemType $linkType -Path "$bundle/link" -Target $linkTarget | Out-Null
Reject {Get-AotBundleManifest $bundle} 'AOT reparse point'
$alias=Join-Path $W 'directory-alias';New-Item -ItemType $linkType -Path $alias -Target $bundle | Out-Null
Reject {Assert-AotNoReparseAncestors "$alias/child/bundle"} 'AOT reparse ancestor'
$dup=[pscustomobject]@{files=@(@{relativePath='a';bytes=1;sha256='x'},@{relativePath='a';bytes=1;sha256='x'})}
Reject {Assert-AotManifestEqual $dup $dup} 'duplicate AOT manifest'

# Reusing an evidence root/terminal refuses without overwriting prior bytes.
$reuse=Join-Path $W 'existing-evidence';New-Item -ItemType Directory "$reuse/out" | Out-Null
[IO.File]::WriteAllText("$reuse/out/terminal.json",'retained terminal bytes')
$env:LLAMADART_WINDOWS_QUALIFICATION=$reuse
foreach($mode in @('Prepare','Run')){
  $argument="-NoProfile -File `"$BundleRoot/qualification.ps1`"";if($mode -eq 'Prepare'){$argument+=' -Prepare'}
  if((InvokeCase "reused-root-$mode" $hostExe $argument 20) -eq 0){throw 'existing evidence root accepted'}
  if([IO.File]::ReadAllText("$reuse/out/terminal.json") -cne 'retained terminal bytes'){throw 'prior evidence overwritten'}
}
# Run the real inner archive writer, including hidden files and the incompressible fixture.
@{harnessFailed=$true;completed=$false;phase='controls';head=('a'*40);runId='12';runAttempt='1'} | ConvertTo-Json | Set-Content "$O/terminal.json"
'hidden evidence' | Set-Content "$O/.hidden-evidence"
Seal-Evidence
$sealedHash=Hash "$W/evidence.zip";$manifestHash=Hash "$O/evidence-manifest.json"
Reject {Seal-Evidence} 'sealed archive overwrite'
if((Hash "$W/evidence.zip") -cne $sealedHash -or (Hash "$O/evidence-manifest.json") -cne $manifestHash){throw 'sealed evidence changed on repeat'}
if(-not (Test-Path "$W/evidence.zip") -or (Get-Content "$W/archive-receipt.json" -Raw | ConvertFrom-Json).completeManifestChecked -ne $true){throw 'actual archive manifest verification incomplete'}
@{processFailuresAndTimeoutsRejected=$true;sourceBlobAndInputHashesVerified=$true;pathLeaksRejected=$true;terminalNegativesRejected=$true;reparseRejected=$true} | ConvertTo-Json | Set-Content $OutputPath
