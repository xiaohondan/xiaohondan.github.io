<#
.SYNOPSIS
    本地授权服务脚本 - 兼容版，支持刷新验证码，Ctrl+C 直接退出（会释放端口）
#>

$port = 8085
$authCode = Get-Random -Minimum 100000 -Maximum 999999
$authVerified = $false

Clear-Host
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "           ?? 本地授权脚本已启动" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   授权码: $authCode" -ForegroundColor Green
Write-Host "   请在网页授权界面输入以上 6 位数字完成登录" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   服务地址: http://localhost:$port" -ForegroundColor Gray
Write-Host "   等待授权请求... (按 Ctrl+C 直接退出，网页可刷新验证码)`n" -ForegroundColor Gray

# 启动监听器
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try {
    $listener.Start()
} catch {
    Write-Host "? 启动监听失败: $_" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

$exitFlag = $false

# 主循环（使用 try/finally 确保退出时关闭监听器）
try {
    while (-not $exitFlag) {
        # 等待请求（同步阻塞，按 Ctrl+C 时会抛出异常，我们捕获后退出）
        try {
            $context = $listener.GetContext()
        } catch {
            # 捕获因 Ctrl+C 或其他异常导致的 GetContext 中断
            Write-Host "`n?? 收到中断信号，正在关闭服务..." -ForegroundColor Yellow
            break
        }
        
        $request = $context.Request
        $response = $context.Response

        # CORS 预检
        if ($request.HttpMethod -eq 'OPTIONS') {
            $response.AddHeader('Access-Control-Allow-Origin', '*')
            $response.AddHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            $response.AddHeader('Access-Control-Allow-Headers', 'Content-Type')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        # GET /refresh
        if ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq '/refresh') {
            try {
                $authCode = Get-Random -Minimum 100000 -Maximum 999999
                $authVerified = $false
                Write-Host "?? 授权码已刷新: $authCode" -ForegroundColor Cyan
                $result = @{ code = $authCode } | ConvertTo-Json
                $response.StatusCode = 200
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
            } catch {
                Write-Host "?? 刷新验证码时出错: $_" -ForegroundColor Red
                $response.StatusCode = 500
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $errResult = @{ error = "Internal server error" } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($errResult)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
            }
            continue
        }

        # POST 请求处理
        if ($request.HttpMethod -eq 'POST') {
            $urlPath = $request.Url.AbsolutePath
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            if ($urlPath -eq '/auth') {
                if ($authVerified) {
                    $result = @{ success = $true } | ConvertTo-Json
                } else {
                    try {
                        $json = $body | ConvertFrom-Json
                        $inputCode = $json.code
                    } catch {
                        $inputCode = $null
                    }
                    $isValid = ($inputCode -eq $authCode)
                    if ($isValid) {
                        $authVerified = $true
                        Write-Host "? 授权码验证成功，等待网页确认退出..." -ForegroundColor Green
                        $result = @{ success = $true } | ConvertTo-Json
                    } else {
                        Write-Host "? 授权码验证失败 (输入: $inputCode, 正确: $authCode)" -ForegroundColor Red
                        $result = @{ success = $false } | ConvertTo-Json
                    }
                }
                $response.StatusCode = 200
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
            }
            elseif ($urlPath -eq '/confirm') {
                Write-Host "?? 收到确认信号，脚本即将退出。" -ForegroundColor Cyan
                $result = @{ status = "exit" } | ConvertTo-Json
                $response.StatusCode = 200
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                $exitFlag = $true
                break
            }
            else {
                $response.StatusCode = 404
                $response.Close()
            }
        }
        else {
            $response.StatusCode = 405
            $response.Close()
        }
    }
} finally {
    # 确保无论何种退出都会关闭监听器并释放端口
    $listener.Stop()
    $listener.Close()
    Write-Host "?? 本地授权服务已关闭。" -ForegroundColor Magenta
}

Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')