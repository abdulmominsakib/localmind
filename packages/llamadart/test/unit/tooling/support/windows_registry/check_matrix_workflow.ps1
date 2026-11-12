param([string]$BundleRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
function Check($yes,$message){if(-not $yes){throw "matrix smoke failed $message"}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $BundleRoot 'runtime.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'actual guest parses'
$body=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-RegistryQualification'},$false))[0].Body.EndBlock.Statements
$selected=@();$inside=$false
foreach($statement in $body){if($statement.Extent.Text -eq '$matrix=@()'){$inside=$true};if($inside){$selected+=$statement.Extent.Text}}
Check ($selected.Count -gt 12) 'actual matrix-to-summary block extracted'
$code=[string]::Join("`n",$selected)
. (Join-Path $BundleRoot 'registry_test_report.ps1')
function Flow($badFixed=$false,$badIdentity=$false,$badDistribution=$false,$badOriginalIdentity=$false,$staleReport=$false){
  $work=Join-Path (Split-Path $OutputPath) ('matrix-test-'+[Guid]::NewGuid().ToString('N'));$O=Join-Path $work 'out';New-Item -ItemType Directory $O | Out-Null
  $W=$work;$manifest=Join-Path $work 'files.json';'[]' | Set-Content $manifest
  $C=[pscustomobject]@{modelPath='qwen.gguf';candidateSourceFiles=$manifest;baselineSourceFiles=$manifest;candidateSourceRoot=(Join-Path $work 'staged-fixed');baselineSourceRoot=(Join-Path $work 'staged-original')};$dart='pinned-dart';$referenceManifest=@();$externalHash='bound';$roots=@{};$overlays=@{}
  foreach($revision in @('original','fixed')){foreach($hook in @(0,1)){$mode="$revision-H$hook";$roots[$mode]=Join-Path $work $mode;$overlays[$mode]='bound'}}
  $trace=[Collections.Generic.List[object]]::new()
  function SelectMatrix($revision,$hook,$environment,$prefix,$alias=$false){$name="$revision-H${hook}E${environment}P${prefix}";if($alias){$name+='-alias'};return $name}
  function InvokeCase($name,$exe,$arguments,$seconds=180){
    $trace.Add([pscustomobject]@{name=$name;arguments=$arguments;seconds=$seconds})
    $failed=$name -eq 'original-H1E1P1' -or ($badFixed -and $name -eq 'fixed-H0E1P0')
    if($failed){$stdout="MODEL_OUTCOME exception no backends loaded`nPASSIVE_MODULE {}";$exit=1}else{$stdout="MODEL_OUTCOME success`nPASSIVE_MODULE {}`nLOAD_SUCCESS CPU gpuLayers=0 unloadCompleted=true";$exit=0}
    $stdout | Set-Content "$O\$name.stdout.log";return $exit
  }
  function CheckSnapshot($name,$required){return -not (($badIdentity -and $name -eq 'fixed-H1E0P1') -or ($badOriginalIdentity -and $name -eq 'original-H1E1P1'))}
  function Must($name,$exe,$arguments,$seconds=180){
    $trace.Add([pscustomobject]@{name=$name;arguments=$arguments;seconds=$seconds})
    if($name -eq 'fixed-maintained-registry-integration'){
      Check ($arguments.Contains("--file-reporter `"json:$O/fixed-maintained-registry-integration.events.json`"")) 'file reporter bound to process'
      @(
        @{type='start';protocolVersion='0.1.1'},
        @{type='suite';suite=@{id=0;platform='vm';path=(Join-Path (Get-Location).Path 'test/integration/windows_ggml_registry_test.dart')}},
        @{type='testStart';test=@{id=1;suiteID=0;name='an external module directory does not open another ggml registry';metadata=@{skip=$false}}},
        @{type='testDone';testID=1;result='success';skipped=$false;hidden=$false},
        @{type='done';success=$true}
      ) | ForEach-Object {ConvertTo-Json -InputObject $_ -Depth 8 -Compress} | Set-Content "$O/fixed-maintained-registry-integration.events.json"
    }
  }
  function Get-ChildItem {}
  function New-Item {}
  function Copy-Item {}
  function Set-Location {}
  function Invoke-AotShippingDistribution($built,$distributed,$cwd,$sources,$model){
    if(-not $built.Replace('\','/').EndsWith('/fixed-H0/core/build/stock/bundle') -or -not $distributed.Replace('\','/').EndsWith('/shipping-distribution/bundle') -or -not $cwd.Replace('\','/').EndsWith('/shipping-empty-cwd') -or $sources.Count -ne 7){throw 'wrong actual guest distribution/root/cwd wiring'}
    $trace.Add([pscustomobject]@{name='distributed-AOT-control';arguments=$distributed;workingDirectory=$cwd;seconds=180})
    if($badDistribution){throw 'injected distributed AOT qualification refusal'}
  }
  function Invoke-NativeRegistryMappingMutation($source,$exe){$trace.Add([pscustomobject]@{name='declaration-mutation-control';arguments=$source;seconds=300})}

  function Hash($path){return 'bound'}
  function Verify($path,$expected){}
  function RecordFiles($path,$name){}
  if($staleReport){'stale evidence' | Set-Content "$O/fixed-maintained-registry-integration.events.json"}
  $failed=$false;$message='';try{Invoke-Expression $code}catch{$failed=$true;$message=$_.Exception.Message}
  $rows=Get-Content "$O\override-matrix.json" -Raw | ConvertFrom-Json
  Check (@($rows).Count -eq 18) 'all matrix/alias outcomes collected without retries'
  Check (@($trace | Where-Object {$_.name -match '^(original|fixed)-H[01]E[01]P[01]$'}).Count -eq 16) 'two full2^3matrices'
  Check (@($rows | Where-Object {$_.name -eq 'original-H1E1P1' -and $_.loadedCpuZero -eq $false -and $_.requiredPass -eq $false}).Count -eq 1) 'original triple override failure retained as data'
  if($badFixed -or $badIdentity -or $badDistribution -or $badOriginalIdentity -or $staleReport){Check $failed 'fixed failure prevents summary';Check (-not (Test-Path "$O\windows1649-summary.json")) 'no synthetic pass';if(-not $badDistribution){Check (@($trace | Where-Object name -eq 'fixed-normal-AOT-build').Count -eq 0) 'failed matrix blocks shippingpositive'}}
  else{
    Check (-not $failed) "complete actual matrix body ($message)"
    Check (Test-Path "$O\windows1649-summary.json") 'summary after all required checks'
    Check (@($trace | Where-Object name -eq 'fixed-maintained-registry-integration').Count -eq 1) 'maintained integration once'
    Check (@($trace | Where-Object name -eq 'declaration-mutation-control').Count -eq 1) 'actual declaration mutation control wired after unmutated positive'
    Check (@($trace | Where-Object name -eq 'distributed-AOT-control').Count -eq 1) 'normal AOT invokes only distributed isolated control'
    Check (($trace | Where-Object name -eq 'fixed-normal-AOT-build').arguments -eq 'build cli -o build/stock -t load_stock.dart') 'actual CLI target wiring'
    Check (@($trace | Where-Object {$_.name -match '^fixed-H[01]E1P0-alias$'}).Count -eq 2) 'alias alone and hookoverride fresh rows'
  }
  if($staleReport){Check (@($trace | Where-Object name -eq 'fixed-maintained-registry-integration').Count -eq 0) 'stale report rejected before actual process'}
  $r=@{fixedFailureInjected=$badFixed;identityFailureInjected=$badIdentity;distributionFailureInjected=$badDistribution;failed=$failed;matrixRows=@($rows).Count;caseNames=@($trace | ForEach-Object {$_.name})}
  Remove-Item $work -Recurse -Force;return $r
}
$results=@(Flow;Flow $true;Flow $false $true;Flow $false $false $true;Flow $false $false $false $true;Flow $false $false $false $false $true)
[ordered]@{offlineOnly=$true;actualGuestMatrixAstExecuted=$true;onlyProcessAndFilesystemLeavesStubbed=$true;successAndOriginalFailureDataAndFixedFailures=$results;providerActions=0;modelExecutions=0} | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
