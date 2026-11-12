function Assert-MaintainedRegistryReport([string]$ReportPath) {
  $events=@(Get-Content -LiteralPath $ReportPath | Where-Object {$_.Trim()} | ForEach-Object {ConvertFrom-Json -InputObject $_})
  $start=@($events | Where-Object type -CEQ 'start');$finish=@($events | Where-Object type -CEQ 'done')
  if($events.Count -eq 0 -or $events[0].type -cne 'start' -or $start.Count -ne 1 -or $start[0].protocolVersion -cne '0.1.1' -or $finish.Count -ne 1 -or $finish[0].success -isnot [bool] -or $finish[0].success -ne $true -or $events[-1].type -cne 'done'){throw 'maintained integration reporter is unfinished or unsuccessful'}
  if(@($events | Where-Object type -CEQ 'error').Count){throw 'maintained integration reporter contains errors'}
  $starts=@($events | Where-Object type -CEQ 'testStart');$ends=@($events | Where-Object type -CEQ 'testDone')
  if($starts.Count -eq 0 -or $starts.Count -ne $ends.Count -or @($starts.test.id | Select-Object -Unique).Count -ne $starts.Count -or @($ends.testID | Select-Object -Unique).Count -ne $ends.Count){throw 'maintained integration has missing or duplicate test events'}
  foreach($end in $ends){
    $matching=@($starts | Where-Object {$_.test.id -eq $end.testID})
    if($matching.Count -ne 1 -or $end.skipped -isnot [bool] -or $end.skipped -ne $false -or $end.result -cne 'success' -or $end.hidden -isnot [bool] -or $matching[0].test.metadata.skip -isnot [bool] -or $matching[0].test.metadata.skip -ne $false){throw 'maintained integration did not execute every reported test without skips'}
  }
  $visible=@($ends | Where-Object hidden -EQ $false)
  if($visible.Count -ne 1){throw 'maintained integration must execute exactly one visible test'}
  $test=@($starts | Where-Object {$_.test.id -eq $visible[0].testID})[0].test
  $name='an external module directory does not open another ggml registry'
  if($test.name -cne $name){throw 'maintained integration executed a different test'}
  $suites=@($events | Where-Object {$_.type -ceq 'suite' -and $_.suite.id -eq $test.suiteID})
  $directory=(Get-Location).Path
  $expected=[IO.Path]::GetFullPath('test/integration/windows_ggml_registry_test.dart',$directory)
  if($suites.Count -ne 1 -or $suites[0].suite.platform -cne 'vm'){throw 'maintained integration suite identity is missing or duplicated'}
  $actual=[IO.Path]::GetFullPath($suites[0].suite.path,$directory)
  if(-not $actual.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'maintained integration executed outside the current source tree'}
  @{caseName='fixed-maintained-registry-integration';head=$env:GITHUB_SHA;runId=$env:GITHUB_RUN_ID;runAttempt=$env:GITHUB_RUN_ATTEMPT;workingDirectory=$directory;reportPath=$ReportPath;suitePath=$actual;testName=$name;executedTests=1;skippedTests=0;success=$true;reportSha256=(Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content "$O/fixed-maintained-registry-integration-result.json"
}
