param([string]$Phase,[string]$GitExecutable='',[string]$DartExecutable='',[string]$FlutterBatch='')
$ErrorActionPreference='Stop'
$where="$env:WINDIR\System32\where.exe"
if(-not (Test-Path -LiteralPath $where)){throw 'Windows where.exe is unavailable'}
$rows=@()
function Resolve-PathCommandIdentity([string]$Value) {
  $item=Get-Item -LiteralPath $Value.Trim().Trim([char]34) -Force
  if($item.PSIsContainer){throw 'pinned command must resolve to a file'}
  return [IO.Path]::GetFullPath($item.FullName)
}
function Find-PathCommand([string]$Name,[string]$Expected='') {
  $found=@(& $where $Name 2>$null)
  if($LASTEXITCODE -ne 0 -or $found.Count -eq 0){throw "child-effective PATH is missing $Name"}
  $row=[ordered]@{command=$Name;present=$true;pinnedMatch=$false}
  if($Expected){
    $row.selectedPath=$found[0].Trim();$row.expectedPath=$Expected
    try{
      $row.selectedIdentity=Resolve-PathCommandIdentity $row.selectedPath
      $row.expectedIdentity=Resolve-PathCommandIdentity $Expected
      $row.pinnedMatch=$row.selectedIdentity.Equals($row.expectedIdentity,[StringComparison]::OrdinalIgnoreCase)
    }catch{
      $row.identityResolutionFailed=$true
      [Console]::Out.WriteLine('PINNED_COMMAND_IDENTITY '+($row | ConvertTo-Json -Compress))
      throw "child-effective PATH cannot resolve the pinned $Name identity"
    }
    [Console]::Out.WriteLine('PINNED_COMMAND_IDENTITY '+($row | ConvertTo-Json -Compress))
    if(-not $row.pinnedMatch){throw "child-effective PATH selected an unpinned $Name"}
  }
  return [pscustomobject]$row
}
foreach($name in @('cmd.exe','where.exe','curl.exe','tar.exe','taskkill.exe','timeout.exe')){$rows+=Find-PathCommand $name}
$selectedShell=''
& $where /Q pwsh.exe
if($LASTEXITCODE -eq 0){$selectedShell='pwsh.exe'}else{
  & $where /Q PowerShell.exe
  if($LASTEXITCODE -eq 0){$selectedShell='PowerShell.exe'}
}
if(-not $selectedShell){throw 'child-effective PATH cannot resolve pwsh.exe or PowerShell.exe required by Flutter3.47.1'}
if($GitExecutable){
  $rows+=Find-PathCommand 'git.exe' $GitExecutable
  $rows+=Find-PathCommand 'dart.exe' $DartExecutable
  if($FlutterBatch){$rows+=Find-PathCommand 'flutter.bat' $FlutterBatch}
}
[ordered]@{phase=$Phase;childEffectivePathChecked=$true;requiredCommands=$rows;flutterPowerShellCommand=$selectedShell;pathOrEnvironmentDumped=$false} | ConvertTo-Json -Depth 6
