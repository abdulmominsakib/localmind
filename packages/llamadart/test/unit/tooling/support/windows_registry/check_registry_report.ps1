param([string]$BundleRoot,[string]$ReportsRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $BundleRoot 'registry_test_report.ps1')
$results=@()
Push-Location "$ReportsRoot/core"
try{
  foreach($variant in @('pass','skip','failure','empty','wrong-name','multiple','setup-failure','missing-done','duplicate-done','duplicate-test','wrong-suite','hidden-only','error-event','missing-completion','invalid-json','missing-report')){
    $O=Join-Path $ReportsRoot "proofs/$variant";New-Item -ItemType Directory $O -Force | Out-Null
    $report=Join-Path $ReportsRoot "$variant.events.json"
    if($variant -in @('missing-done','duplicate-done','duplicate-test','wrong-suite','hidden-only','error-event','missing-completion')){
      $events=@(Get-Content "$ReportsRoot/pass.events.json" | ForEach-Object {ConvertFrom-Json -InputObject $_})
      switch($variant){
        'missing-done' {$events=@($events | Where-Object type -CNE 'done')}
        'duplicate-done' {$events+=@($events[-1])}
        'duplicate-test' {$events=@($events[0..($events.Count-2)])+@(($events | Where-Object type -CEQ 'testStart')[0])+@($events[-1])}
        'wrong-suite' {($events | Where-Object type -CEQ 'suite')[0].suite.path='foreign/test/integration/windows_ggml_registry_test.dart'}
        'hidden-only' {foreach($event in @($events | Where-Object type -CEQ 'testDone')){$event.hidden=$true}}
        'error-event' {$events=@($events[0..($events.Count-2)])+@(@{type='error';testID=3;error='unexpected error'})+@($events[-1])}
        'missing-completion' {$events=@($events | Where-Object {$_.type -cne 'testDone' -or $_.hidden})}
      }
      $events | ForEach-Object {ConvertTo-Json -InputObject $_ -Depth 12 -Compress} | Set-Content $report
    }
    if($variant -eq 'invalid-json'){'invalid report' | Set-Content $report}
    $rejected=$false;try{Assert-MaintainedRegistryReport $report}catch{$rejected=$true}
    if($rejected -ne ($variant -ne 'pass')){throw "report classification wrong $variant"}
    $receipt="$O/fixed-maintained-registry-integration-result.json"
    if(($variant -eq 'pass') -ne (Test-Path -LiteralPath $receipt)){throw 'false reporter success receipt'}
    $results+=@{variant=$variant;rejected=$rejected}
  }
}finally{Pop-Location}
@{realPinnedRunnerReportsChecked=$true;realCases=@('pass','skip','failure','empty','wrong-name','multiple','setup-failure');cases=$results} | ConvertTo-Json -Depth 6 | Set-Content $OutputPath
