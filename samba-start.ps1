# Sobe o container Samba (Windows). Execute com:
#   powershell -ExecutionPolicy Bypass -File .\samba-start.ps1
#
# Variaveis de ambiente (todas opcionais):
#   SAMBA_HOST_DIR   pasta do host a compartilhar            (padrao: %USERPROFILE%)
#   SAMBA_PASSWORD   senha do usuario smbuser                (padrao: gera 12 caracteres aleatorios e exibe)
#   SAMBA_PORT       porta SMB publicada no host             (padrao: 445)
#   SAMBA_READ_ONLY  1 = cliente so le (monta com :ro)       (padrao: 0, leitura e escrita)
#   SAMBA_IMAGE      nome da imagem                          (padrao: my-samba-server:1.0)
#   SAMBA_CONTAINER  nome do container                       (padrao: samba)
#
# No Windows a porta 445 costuma estar ocupada pelo servico "Servidor" (LanmanServer);
# se o docker falhar ao publicar a porta, defina SAMBA_PORT com outro valor.

function Get-Setting([string]$Value, [string]$Default) {
    if ([string]::IsNullOrEmpty($Value)) { $Default } else { $Value }
}

$ScriptDir = $PSScriptRoot
$HostDir   = Get-Setting $env:SAMBA_HOST_DIR $env:USERPROFILE
$Port      = Get-Setting $env:SAMBA_PORT '445'
$ReadOnly  = Get-Setting $env:SAMBA_READ_ONLY '0'
$Image     = Get-Setting $env:SAMBA_IMAGE 'my-samba-server:1.0'
$Container = Get-Setting $env:SAMBA_CONTAINER 'samba'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error 'docker nao encontrado no PATH.'; exit 1
}
if (-not (Test-Path -LiteralPath $HostDir -PathType Container)) {
    Write-Error "pasta '$HostDir' nao existe (SAMBA_HOST_DIR)."; exit 1
}
$HostDir = (Resolve-Path -LiteralPath $HostDir).Path

docker container inspect $Container 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Error "o container '$Container' ja existe. Execute samba-stop.ps1 antes."; exit 1
}

# Inteiro uniforme em [0, Max) sem vies de modulo
$script:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
function Get-RandomInt([int]$Max) {
    $buf = New-Object byte[] 4
    $limit = [uint64](4294967296 - (4294967296 % $Max))
    do {
        $script:Rng.GetBytes($buf)
        $v = [uint64][BitConverter]::ToUInt32($buf, 0)
    } while ($v -ge $limit)
    [int]($v % $Max)
}

# 12 caracteres; repete ate conter maiuscula, minuscula, numero e simbolo
function New-SambaPassword {
    $charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%^*_+=-'
    do {
        $pw = -join (1..12 | ForEach-Object { $charset[(Get-RandomInt $charset.Length)] })
    } until ($pw -cmatch '[A-Z]' -and $pw -cmatch '[a-z]' -and $pw -match '[0-9]' -and $pw -match '[^A-Za-z0-9]')
    $pw
}

$Generated = $false
$Password = $env:SAMBA_PASSWORD
if ([string]::IsNullOrEmpty($Password)) {
    $Password = New-SambaPassword
    $Generated = $true
}

docker image inspect $Image 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Imagem '$Image' nao encontrada; construindo..."
    docker build -t $Image -f (Join-Path $ScriptDir 'samba.dockerfile') $ScriptDir
    if ($LASTEXITCODE -ne 0) { Write-Error 'falha ao construir a imagem.'; exit 1 }
}

$Mount = "${HostDir}:/media/shared"
if ($ReadOnly -eq '1') { $Mount += ':ro' }

# A senha vai so no ambiente do processo docker (-e sem valor herda), nunca na linha de comando
$env:SMB_PASSWORD = $Password
try {
    docker run -d --name $Container -p "${Port}:445" -v $Mount -e SMB_PASSWORD $Image | Out-Null
    $RunExit = $LASTEXITCODE
} finally {
    Remove-Item Env:SMB_PASSWORD -ErrorAction SilentlyContinue
}
if ($RunExit -ne 0) { Write-Error 'falha ao iniciar o container.'; exit 1 }

Start-Sleep -Seconds 2
$Running = docker inspect -f '{{.State.Running}}' $Container 2>$null
if ($Running -ne 'true') {
    Write-Host 'Erro: o container nao permaneceu em execucao. Logs:'
    docker logs $Container
    docker rm -f $Container 2>$null | Out-Null
    exit 1
}

$Mode = if ($ReadOnly -eq '1') { 'somente leitura (:ro)' } else { 'leitura e escrita' }
Write-Host 'Samba em execucao.'
Write-Host "  Share:   \\<ip-do-host>\SHARED_FOLDER (porta $Port)"
Write-Host '  Usuario: smbuser'
Write-Host "  Pasta:   $HostDir ($Mode)"
if ($Generated) { Write-Host "  Senha gerada: $Password" }
