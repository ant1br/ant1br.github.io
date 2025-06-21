# Configurações
$threshold_disk = 70  # Alerta se uso >70% (livre <30%)
$threshold_cpu = 90   # Alerta se CPU >90%
$threshold_temp = 85  # Alerta se temp >85°C
$email_to = "suporte@empresa.com"
$telegram_token = "7552066559:AAFVj4e8xpcY75OaUFuQzN490PNdOONrg1U"
$telegram_chat_id = "1746230419"

# Função para enviar alertas
function Send-Alert {
    param($message)
    # Telegram
    $url = "https://api.telegram.org/bot$telegram_token/sendMessage"
    $body = @{ chat_id = $telegram_chat_id; text = $message }
    Invoke-RestMethod -Uri $url -Method Post -Body $body

    # Email
    Send-MailMessage -From "alerta@servidor.com" -To $email_to -Subject "ALERTA DE SISTEMA" -Body $message -SmtpServer "smtp.empresa.com"
}

# 1. Verificar discos
$discos = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
foreach ($disco in $discos) {
    $percent_used = [math]::Round(($disco.SizeRemaining / $disco.Size) * 100, 2)
    if ($percent_used -lt 30) {
        Send-Alert "?? DISCO $($disco.DriveLetter): $percent_used% livre (CRÍTICO)"
    }
}

# 2. Verificar CPU
$cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
if ($cpu.LoadPercentage -gt $threshold_cpu) {
    Send-Alert "?? CPU: $($cpu.LoadPercentage)% uso (LIMITE EXCEDIDO)"
}

# 3. Verificar temperatura (requer hardware compatível)
try {
    $temp = (Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi").CurrentTemperature[0] / 10 - 273.15
    if ($temp -gt $threshold_temp) {
        Send-Alert "?? TEMPERATURA: $($temp)°C (PERIGO)"
    }
} catch { }

# 4. Verificar desligamentos inesperados
$shutdown_events = Get-EventLog -LogName System -InstanceId 6008 -After (Get-Date).AddHours(-24)
if ($shutdown_events) {
    $last_event = $shutdown_events[0] | Format-List -Property * | Out-String
    Send-Alert "?? DESLIGAMENTO INESPERADO`n$last_event"
}

# 5. Verificar saúde do disco (SMART)
$smart_status = Get-PhysicalDisk | Get-StorageReliabilityCounter | Where-Object { $_.HealthStatus -ne "Healthy" }
if ($smart_status) {
    $details = $smart_status | Select-Object DeviceId, Wear, Temperature | Format-List | Out-String
    Send-Alert "?? ALERTA SMART`n$details"
}

# 6. Checklist adicional (Memória >90%)
$ram = (Get-Counter '\Memory\% Committed Bytes In Use').CounterSamples.CookedValue
if ($ram -gt 90) {
    Send-Alert "?? MEMÓRIA: $([math]::Round($ram))% uso"
}