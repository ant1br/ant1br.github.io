<#
.SYNOPSIS
    Versão unificada do Agente de Monitoramento para facilitar a depuração.
.DESCRIPTION
    Este script contém toda a lógica e configuração em um único arquivo.
.NOTES
    Autor: Adriano
    Versão: 3.4 - Correção Final de Codificação Forçada
#>

# --- FORÇAR PROTOCOLO DE SEGURANÇA (ESSENCIAL) ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================
# --- CONFIGURAÇÕES - EDITE ESTA SEÇÃO ---
# ==============================================================================
$Threshold_DiskUsagePercent = 80; $Threshold_CpuUsagePercent = 90; $Threshold_TemperatureCelsius = 85; $Threshold_MemoryUsagePercent = 90
$Alert_EmailTo = ""; $Alert_EmailFrom = ""; $Alert_SmtpServer = ""; $Alert_SmtpPort = 587; $Alert_SmtpUser = ""; $Alert_SmtpPassword = ""
$Alert_TelegramBotToken = "7552066559:AAFVj4e8xpcY75OaUFuQzN490PNdOONrg1U"
$Alert_TelegramChatId = "1746230419"
$Log_FileName = "monitor_agent_unified_alerts.log"
$HealthCheck_PingUrl = "COLE_SUA_URL_REAL_AQUI"
# ==============================================================================

# --- LÓGICA DO SCRIPT (NÃO PRECISA EDITAR ABAIXO DESTA LINHA) ---
$ScriptDir = $PSScriptRoot; $Global:LogFilePath = Join-Path -Path $ScriptDir -ChildPath $Log_FileName
function Write-Log { param( [Parameter(Mandatory=$true)][string]$Message, [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO" ); $LogLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] - $Message"; try { $LogLine | Add-Content -Path $Global:LogFilePath -Encoding UTF8 } catch {} }

# --- FUNÇÃO DE ALERTA ATUALIZADA (A MUDANÇA CRÍTICA ESTÁ AQUI) ---
function Send-Alert {
    param( [Parameter(Mandatory=$true)][string]$Message )
    
    $hostname = $env:COMPUTERNAME
    # Mensagem de alerta sem o emoji para simplificar o teste
    $fullMessage = "ALERTA NO SERVIDOR: $hostname`n`n$Message"
    Write-Log -Message $Message -Level "WARN"
    Write-Host $fullMessage

    if ($Alert_TelegramBotToken -and $Alert_TelegramChatId) {
        try {
            $uri = "https://api.telegram.org/bot$Alert_TelegramBotToken/sendMessage"
            
            # 1. Criar o corpo da mensagem como um objeto PowerShell
            $bodyObject = @{
                chat_id = $Alert_TelegramChatId
                text    = $fullMessage
            }
            
            # 2. Converter o objeto para uma string JSON
            $jsonString = $bodyObject | ConvertTo-Json -Compress
            
            # 3. (A MÁGICA) - Converter a string JSON para um array de bytes com codificação UTF-8 explícita
            $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
            
            Write-Log "Enviando alerta para o Telegram com corpo codificado em UTF-8 manualmente."
            
            # 4. Enviar o array de bytes diretamente no corpo da requisição
            Invoke-RestMethod -Uri $uri -Method Post -Body $utf8Bytes -ContentType 'application/json; charset=utf-8' -ErrorAction Stop -TimeoutSec 15
            
            Write-Log "Alerta enviado ao Telegram com sucesso."
        } catch {
            Write-Log "FALHA CRÍTICA AO ENVIAR ALERTA PARA O TELEGRAM." -Level "ERROR"
            $errorDetails = $_ | Format-List * -Force | Out-String
            Write-Log "Detalhes do Erro do Telegram: $errorDetails" -Level "ERROR"
        }
    }
    # A lógica de e-mail permanece a mesma
    if ($Alert_EmailTo) { # ...
    }
}

function Invoke-HealthCheckPing { param( [ValidateSet("start", "success", "fail")][string]$Status = "success" ); if ([string]::IsNullOrWhiteSpace($HealthCheck_PingUrl) -or $HealthCheck_PingUrl -like '*SUA-URL*') { return }; $finalUrl = $HealthCheck_PingUrl; if ($Status -eq 'start') { $finalUrl += "/start" } elseif ($Status -eq 'fail') { $finalUrl += "/fail" }; try { Write-Log "Enviando ping para Healthchecks.io (Status: $Status)..."; Invoke-WebRequest -Uri $finalUrl -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop } catch { Write-Log "Falha ao enviar ping para Healthchecks.io: $($_.Exception.Message)" -Level "ERROR" } }

# --- FUNÇÕES DE VERIFICAÇÃO ---
function Check-DiskUsage { Write-Log "Verificando uso de disco..."; $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }; foreach ($volume in $volumes) { $percentUsed = [math]::Round((($volume.Size - $volume.SizeRemaining) / $volume.Size) * 100, 1); if ($percentUsed -gt $Threshold_DiskUsagePercent) { Send-Alert "Uso de Disco Critico em $($volume.DriveLetter):: $percentUsed% usado. (Limite: $Threshold_DiskUsagePercent%)" } else { Write-Log "Disco $($volume.DriveLetter):: Uso esta normal: $percentUsed%." -Level "INFO" } } }
function Check-CpuUsage { Write-Log "Verificando uso de CPU..."; try { $cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty LoadPercentage; $cpuLoad = [math]::Round($cpuInfo, 1); if ($cpuLoad -gt $Threshold_CpuUsagePercent) { Send-Alert "Uso de CPU Elevado: $cpuLoad% usado. (Limite: $Threshold_CpuUsagePercent%)" } else { Write-Log "Uso de CPU esta normal: $cpuLoad%." -Level "INFO" } } catch { Write-Log "Nao foi possivel obter o uso da CPU via WMI/CIM." -Level "ERROR" } }
function Check-MemoryUsage { Write-Log "Verificando uso de memoria..."; try { $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem; $totalMemory = $osInfo.TotalVisibleMemorySize; $freeMemory = $osInfo.FreePhysicalMemory; $usedMemory = $totalMemory - $freeMemory; $memoryPercent = [math]::Round(($usedMemory / $totalMemory) * 100, 1); if ($memoryPercent -gt $Threshold_MemoryUsagePercent) { Send-Alert "Uso de Memoria Elevado: $memoryPercent% usada. (Limite: $Threshold_MemoryUsagePercent%)" } else { Write-Log "Uso de memoria esta normal: $memoryPercent%." -Level "INFO" } } catch { Write-Log "Nao foi possivel obter o uso da Memoria via WMI/CIM." -Level "ERROR" } }
function Check-Temperature { Write-Log "Verificando temperatura..."; try { $temp_info = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop; if ($temp_info) { $currentTemp = [math]::Round(($temp_info[0].CurrentTemperature / 10.0) - 273.15, 1); if ($currentTemp -gt $Threshold_TemperatureCelsius) { Send-Alert "Temperatura Elevada: $currentTemp C. (Limite: $Threshold_TemperatureCelsius C)" } else { Write-Log "Temperatura esta normal: $currentTemp C." -Level "INFO" } } } catch { Write-Log "Sensor de temperatura nao encontrado ou inacessivel." -Level "INFO" } }
function Check-UnexpectedShutdowns { Write-Log "Verificando desligamentos inesperados..."; $filter = @{ LogName = 'System'; ID = 6008; StartTime = (Get-Date).AddHours(-24) }; $latestEvent = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction SilentlyContinue; if ($latestEvent) { Send-Alert "Desligamento Inesperado detectado em $($latestEvent.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))" } else { Write-Log "Nenhum desligamento inesperado encontrado nas ultimas 24 horas." -Level "INFO" } }
function Check-DiskHealth { Write-Log "Verificando saude do disco (SMART)..."; try { $disks = Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop; $unhealthyDisks = $disks | Where-Object { $_.HealthStatus -ne 'Healthy' -and -not([string]::IsNullOrWhiteSpace($_.HealthStatus)) }; if ($unhealthyDisks) { foreach ($disk in $unhealthyDisks) { Send-Alert "Alerta de Saude de Disco (SMART): Status '$($disk.HealthStatus)' no disco $($disk.DeviceId)" } } else { Write-Log "Status de saude (SMART) de todos os discos esta 'Healthy' ou nao pode ser determinado." -Level "INFO" } } catch { Write-Log "Nao foi possivel verificar a saude do disco (SMART): $($_.Exception.Message)" -Level "ERROR" } }

# --- EXECUÇÃO PRINCIPAL ---
$scriptSucceeded = $true; Invoke-HealthCheckPing -Status 'start'; Write-Log -Message "--- Iniciando verificacao de rotina ---"; try { Check-DiskUsage; Check-CpuUsage; Check-MemoryUsage; Check-Temperature; Check-UnexpectedShutdowns; Check-DiskHealth } catch { $scriptSucceeded = $false; $errorMessage = "Ocorreu um erro critico durante a execucao do script: $($_.Exception.Message)"; Write-Log -Message $errorMessage -Level "ERROR" } finally { Write-Log -Message "--- Verificacao de rotina concluida ---"; if ($scriptSucceeded) { Invoke-HealthCheckPing -Status 'success' } else { Invoke-HealthCheckPing -Status 'fail' } }