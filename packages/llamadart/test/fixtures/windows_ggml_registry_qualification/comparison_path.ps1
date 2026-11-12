function Normalize-ComparisonDirectory([string]$Value) {
  return $Value.Trim().Trim([char]34).Replace('/','\').TrimEnd([char[]]'\/').ToLowerInvariant()
}
function New-ComparisonPath([string]$OriginalPath,[string[]]$PinnedDirectories,[string]$HostDirectory,[string[]]$TaskRuntimeDirectories,[string]$RuntimeDirectory='') {
  $retained=@();$removed=@()
  foreach($component in $OriginalPath.Split([char]';')) {
    $isRuntime=$false
    foreach($runtime in $TaskRuntimeDirectories) {
      if((Normalize-ComparisonDirectory $component) -eq (Normalize-ComparisonDirectory $runtime)){$isRuntime=$true;break}
    }
    if($isRuntime){$removed+=$component}else{
      $directory=$component.Trim().Trim([char]34)
      if([IO.Path]::IsPathRooted($directory) -and [IO.Directory]::Exists($directory)){
        foreach($leaf in @('ggml.dll','llama.dll')){if([IO.File]::Exists((Join-Path $directory $leaf))){throw 'foreign native runtime leaked through original PATH'}}
      }
      $retained+=$component
    }
  }
  $added=@()
  foreach($directory in $PinnedDirectories) {if($directory -and $added -notcontains $directory){$added+=$directory}}
  $hostPresent=$false
  foreach($component in ($retained+$added)) {
    if((Normalize-ComparisonDirectory $component) -eq (Normalize-ComparisonDirectory $HostDirectory)){$hostPresent=$true;break}
  }
  if(-not $hostPresent -and $HostDirectory){$added+=$HostDirectory}
  $normal=[string]::Join(';',[string[]]($added+$retained))
  $effective=$normal
  if($RuntimeDirectory) {
    $allowed=$false
    foreach($runtime in $TaskRuntimeDirectories) {if((Normalize-ComparisonDirectory $runtime) -eq (Normalize-ComparisonDirectory $RuntimeDirectory)){$allowed=$true;break}}
    if(-not $allowed){throw 'runtime directory is outside the explicit task allowlist'}
    $effective="$RuntimeDirectory;$normal"
  }
  return [pscustomobject]@{Path=$effective;NormalPath=$normal;AddedDirectories=$added;RemovedRuntimeDirectories=$removed;OriginalComponentCount=$OriginalPath.Split([char]';').Count;RetainedOriginalComponentCount=$retained.Count;RuntimeDirectory=$RuntimeDirectory;OnlyTaskRuntimeComponentsRemoved=$true}
}
function Invoke-ComparisonPathPreflight([string]$Phase,[string]$EffectivePath,[string]$HostExecutable,[string]$ScriptRoot,[string]$OutputDirectory,[string]$GitExecutable='',[string]$DartExecutable='',[string]$FlutterBatch='') {
  $arguments="-NoLogo -NoProfile -NonInteractive -File `"$ScriptRoot/child_path_probe.ps1`" -Phase `"$Phase`""
  if($GitExecutable){$arguments+=" -GitExecutable `"$GitExecutable`" -DartExecutable `"$DartExecutable`""}
  if($FlutterBatch){$arguments+=" -FlutterBatch `"$FlutterBatch`""}
  $before=$env:Path
  try {
    $env:Path=$EffectivePath
    Must "$Phase-path-preflight" $HostExecutable $arguments 60
  } finally {$env:Path=$before}
}
