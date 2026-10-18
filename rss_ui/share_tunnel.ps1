# W.O.F web arayüzünü localtunnel ile paylaşır.
# Kullanım (proje klasöründe):  powershell -ExecutionPolicy Bypass -File .\share_tunnel.ps1
# Yeniden derlemek için:        powershell -ExecutionPolicy Bypass -File .\share_tunnel.ps1 -Build
# Ziyaretçilerin tarayıcısı "localhost"a ulaşamaz; derleme sunucunun tünel
# adresiyle yapılır (-ApiUrl ile değiştirilebilir).

param(
    [int]$Port = 8080,
    [string]$Subdomain = "wof-rss-ui",
    [string]$ApiUrl = "https://agentic-news-backend.loca.lt",
    [switch]$Build
)

$root = $PSScriptRoot
$web = Join-Path $root "build\web"
$serverLog = Join-Path $env:TEMP "wof_http_server.log"

if ($Build -or -not (Test-Path (Join-Path $web "index.html"))) {
    Write-Host "Flutter web derleniyor..." -ForegroundColor Cyan
    Push-Location $root
    flutter build web --release --dart-define=API_BASE_URL=$ApiUrl
    $ok = $?
    Pop-Location
    if (-not $ok) { Write-Host "Derleme başarısız." -ForegroundColor Red; exit 1 }
}

function Start-Server {
    Write-Host "Yerel sunucu başlatılıyor: http://127.0.0.1:$Port (log: $serverLog)" -ForegroundColor Cyan
    Start-Process python -ArgumentList "-m", "http.server", "$Port", "--bind", "127.0.0.1" `
        -WorkingDirectory $web -NoNewWindow -PassThru `
        -RedirectStandardError $serverLog -RedirectStandardOutput "$serverLog.out"
}

# localtunnel eski ad henüz serbest kalmadığı için rastgele bir adres verirse
# (paylaşılan link çalışmaz) tünel kapatılıp 30 sn sonra tekrar denenir.
function Start-Tunnel {
    $wanted = "https://$Subdomain.loca.lt"
    $log = Join-Path $env:TEMP "wof_ui_tunnel_$Port.log"
    while ($true) {
        Write-Host "Tünel açılıyor: $wanted" -ForegroundColor Cyan
        Remove-Item $log -ErrorAction SilentlyContinue
        $p = Start-Process npx.cmd -ArgumentList "-y", "localtunnel", "--port", "$Port", "--subdomain", $Subdomain `
            -NoNewWindow -PassThru -RedirectStandardOutput $log
        $url = $null
        for ($i = 0; $i -lt 45 -and -not $url -and -not $p.HasExited; $i++) {
            Start-Sleep -Seconds 1
            $m = Select-String -Path $log -Pattern "your url is: (\S+)" -ErrorAction SilentlyContinue
            if ($m) { $url = $m.Matches[0].Groups[1].Value }
        }
        if ($url -eq $wanted) {
            Write-Host "Tünel hazır: $url" -ForegroundColor Green
            return $p
        }
        Write-Host "İstenen adres alınamadı ($url); 30 sn sonra tekrar denenecek..." -ForegroundColor Yellow
        if (-not $p.HasExited) { taskkill /PID $p.Id /T /F | Out-Null }
        Start-Sleep -Seconds 30
    }
}

try {
    $password = (Invoke-RestMethod -Uri "https://loca.lt/mytunnelpassword" -TimeoutSec 15)
    Write-Host "Tunnel password (ziyaretçiler girecek): $password" -ForegroundColor Yellow
} catch {
    Write-Host "Şifre alınamadı; https://loca.lt/mytunnelpassword adresinden bakın." -ForegroundColor Yellow
}

$server = Start-Server
Start-Sleep -Seconds 2
$tunnel = Start-Tunnel
Write-Host "Durdurmak için Ctrl+C. Sunucu ya da tünel kapanırsa otomatik yeniden açılır." -ForegroundColor Cyan

try {
    while ($true) {
        Start-Sleep -Seconds 5
        if ($server.HasExited) {
            Write-Host "Yerel sunucu kapandı (kod $($server.ExitCode)), yeniden açılıyor..." -ForegroundColor Red
            $server = Start-Server
        }
        if ($tunnel.HasExited) {
            # Eski alt alan adının sunucuda serbest kalması için biraz beklenir;
            # yoksa localtunnel rastgele bir adres verir.
            Write-Host "Tünel kapandı, 15 sn sonra yeniden açılıyor..." -ForegroundColor Red
            Start-Sleep -Seconds 15
            $tunnel = Start-Tunnel
        }
    }
} finally {
    foreach ($p in @($server, $tunnel)) {
        if ($p -and -not $p.HasExited) { taskkill /PID $p.Id /T /F | Out-Null }
    }
    Write-Host "Sunucu ve tünel kapatıldı." -ForegroundColor Cyan
}
