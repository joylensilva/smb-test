# Para e remove o container Samba (Windows). Execute com:
#   powershell -ExecutionPolicy Bypass -File .\samba-stop.ps1
# Variavel opcional: SAMBA_CONTAINER (padrao: samba)

$Container = if ([string]::IsNullOrEmpty($env:SAMBA_CONTAINER)) { 'samba' } else { $env:SAMBA_CONTAINER }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'docker nao encontrado no PATH.'; exit 1
}

docker container inspect $Container 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Container '$Container' nao existe; nada a fazer."
    exit 0
}

docker stop $Container | Out-Null
docker rm $Container | Out-Null
Write-Host "Container '$Container' parado e removido."
