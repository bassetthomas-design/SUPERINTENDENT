param([ValidateSet("TailLog","CmdClean","CmdUpdate")]$Action="TailLog")

$base = "$env:ProgramData\Virgil"
$log  = Join-Path $base "logs\$(Get-Date -Format yyyy-MM-dd).log"
$cmd  = Join-Path $base "ipc\commands"
New-Item -ItemType Directory -Force -Path $cmd | Out-Null

switch($Action){
  "TailLog" {
    if(Test-Path $log){ Get-Content $log -Wait -Tail 200 }
    else{ Write-Host "No log file yet: $log" -ForegroundColor Yellow }
  }
  "CmdClean" {
    $id=[guid]::NewGuid().ToString("N")
    $obj=[pscustomobject]@{ Type="Clean"; CorrelationId=$id; AtUtc=(Get-Date).ToUniversalTime() }
    $json=$obj|ConvertTo-Json -Depth 4
    $path=Join-Path $cmd "$id.json"
    $json|Out-File $path -Encoding UTF8
    Write-Host "Clean command sent: $path" -ForegroundColor Cyan
  }
  "CmdUpdate" {
    $id=[guid]::NewGuid().ToString("N")
    $obj=[pscustomobject]@{ Type="UpdateAll"; CorrelationId=$id; AtUtc=(Get-Date).ToUniversalTime() }
    $json=$obj|ConvertTo-Json -Depth 4
    $path=Join-Path $cmd "$id.json"
    $json|Out-File $path -Encoding UTF8
    Write-Host "UpdateAll command sent: $path" -ForegroundColor Cyan
  }
}
