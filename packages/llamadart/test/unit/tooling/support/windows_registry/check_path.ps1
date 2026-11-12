param([string]$BundleRoot,[string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $BundleRoot 'comparison_path.ps1')
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $BundleRoot 'child_path_probe.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'child PATH probe parse error'}
foreach($definition in @($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false))){Invoke-Expression $definition.Extent.Text}
$work=Join-Path (Split-Path $OutputPath) 'path-controls';New-Item -ItemType Directory $work | Out-Null
New-PSDrive -Name WP -PSProvider FileSystem -Root $work | Out-Null
$where='Fixture-Where';$foundPaths=@();$whereExit=0
function Fixture-Where([string]$Name){$global:LASTEXITCODE=$whereExit;return $foundPaths}
$cases=@()
foreach($command in @('git.exe','dart.exe','flutter.bat')){
  $directory="stage/$command/bin";New-Item -ItemType Directory "$work/$directory","$work/foreign/$command" -Force | Out-Null
  [IO.File]::WriteAllText("$work/$directory/$command",'same fixture bytes')
  [IO.File]::WriteAllText("$work/foreign/$command/$command",'same fixture bytes')
  [IO.File]::WriteAllText("$work/$directory/other.exe",'same fixture bytes')
  $expected="WP:\$directory/$command";$selected=$expected.Replace('/','\')
  $foundPaths=@($selected);$whereExit=0
  $positive=Find-PathCommand $command $expected
  if(-not $positive.pinnedMatch -or -not $positive.selectedIdentity -or $positive.selectedIdentity -cne $positive.expectedIdentity){throw 'canonical pinned command identity missing'}
  $cases+=@{command=$command;variant='mixed-separators';passed=$true;selectedIdentity=$positive.selectedIdentity;expectedIdentity=$positive.expectedIdentity}
  $foundPaths=@($selected.Replace('WP:','wp:'))
  if(-not (Find-PathCommand $command $expected).pinnedMatch){throw 'equivalent filesystem drive case refused'}
  $cases+=@{command=$command;variant='drive-case';passed=$true}
  foreach($variant in @('same-name-foreign','different-leaf','first-wrong','missing-command','missing-expected')){
    $want=$expected;$whereExit=0
    switch($variant){
      'same-name-foreign' {$foundPaths=@("WP:\foreign/$command/$command")}
      'different-leaf' {$foundPaths=@("WP:\$directory/other.exe")}
      'first-wrong' {$foundPaths=@("WP:\foreign/$command/$command",$selected)}
      'missing-command' {$foundPaths=@();$whereExit=1}
      'missing-expected' {$foundPaths=@($selected);$want="WP:\missing/$command"}
    }
    $refused=$false;try{Find-PathCommand $command $want | Out-Null}catch{$refused=$true}
    if(-not $refused){throw "unpinned or missing command accepted $command $variant"}
    $cases+=@{command=$command;variant=$variant;refused=$true}
  }
  if($IsWindows){
    $where="$env:WINDIR/System32/where.exe";$before=$env:Path
    try{
      $env:Path=(Get-Item -LiteralPath "WP:\$directory").FullName
      if(-not (Find-PathCommand $command $expected).pinnedMatch){throw 'actual Windows where selected the wrong pinned file'}
      $cases+=@{command=$command;variant='native-windows-where';passed=$true}
    }finally{$env:Path=$before;$where='Fixture-Where'}
  }
}
$plan=New-ComparisonPath 'C:\Windows\System32;"D:\task/runtime\";C:\shell' @('C:\sdk') 'c:/shell' @('d:/task/runtime')
if($plan.NormalPath.ToLowerInvariant().Contains('runtime') -or $plan.AddedDirectories.Count -ne 1){throw 'equivalent runtime removal/host-directory identity changed'}
$allowed=New-ComparisonPath 'C:\Windows' @() '' @('D:\task\runtime') 'd:/task/runtime'
if(-not $allowed.RuntimeDirectory){throw 'canonical allowed runtime prefix refused'}
$refused=$false;try{New-ComparisonPath 'C:\Windows' @() '' @('D:\task\runtime') 'D:/foreign/runtime' | Out-Null}catch{$refused=$true}
if(-not $refused){throw 'foreign same-name runtime prefix accepted'}
# The wrapper must pass the optional Flutter pin to the real child probe.
$originalPath=$env:Path;$captured=''
function Must($name,$exe,$arguments,$seconds=180){$script:captured=$arguments}
Invoke-ComparisonPathPreflight 'fixture-sdk' $originalPath 'NOT_EXECUTED' $BundleRoot $work 'git-pin' 'dart-pin' 'flutter-pin'
if(-not $captured.Contains('-FlutterBatch "flutter-pin"') -or $env:Path -cne $originalPath){throw 'child preflight lost Flutter pin or changed caller PATH'}
Remove-PSDrive WP
@{actualPinnedCommandFunctionExecuted=$true;whereLeafSimulated=$true;nativeWindowsWhereExercised=[bool]$IsWindows;filesystemIdentityResolved=$true;environmentDumped=$false;cases=$cases} | ConvertTo-Json -Depth 6 | Set-Content $OutputPath
