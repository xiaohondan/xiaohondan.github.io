<#
.SYNOPSIS
    本地授权服务脚本
#>

# 设置端口号
$port = 8085

cls

# 启动前检查端口是否可用（已注释，如需检查请取消注释）
# try {
#     $tcpTest = Test-NetConnection -ComputerName localhost -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
#     if ($tcpTest -eq $true) {
#         Write-Host "?? 端口 $port 已被占用，请关闭占用程序或修改脚本中的端口号。" -ForegroundColor Red
#         Write-Host "按任意键退出..."
#         $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
#         exit 1
#     }
# } catch {
#     # 如果Test-NetConnection不可用，跳过检查
#     Write-Host "?? 端口检查跳过（Test-NetConnection不可用）" -ForegroundColor Gray
# }

# 生成随机授权码
$authCode = Get-Random -Minimum 100000 -Maximum 999999
cls
# 显示授权码
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "           本地授权脚本已启动" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "     @小红蛋  bilibili:小红蛋  QQ：3815099625" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   授权码: $authCode" -ForegroundColor Green
Write-Host "   请在网页授权界面输入以上 6 位数字完成登录" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   服务地址: http://xiaohondan.github.io/auth 或http://localhost:$port" -ForegroundColor Gray
Write-Host "   等待授权请求... (按 Ctrl+C 可强制退出)`n" -ForegroundColor Gray

# 启动 HTTP 监听器
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try {
    $listener.Start()
} catch {
    Write-Host " 启动监听失败: $_" -ForegroundColor Red
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

$exitFlag = $false
$authVerified = $false

while (-not $exitFlag) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # 处理 OPTIONS 预检请求（CORS）
        if ($request.HttpMethod -eq 'OPTIONS') {
            $response.AddHeader('Access-Control-Allow-Origin', '*')
            $response.AddHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
            $response.AddHeader('Access-Control-Allow-Headers', 'Content-Type')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($request.HttpMethod -eq 'POST') {
            $urlPath = $request.Url.AbsolutePath

            # 读取请求体
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            # 路由 /auth
            if ($urlPath -eq '/auth') {
                if ($authVerified) {
                    $result = @{ success = $true } | ConvertTo-Json
                    $response.StatusCode = 200
                    $response.ContentType = 'application/json'
                    $response.AddHeader('Access-Control-Allow-Origin', '*')
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.Close()
                    continue
                }

                try {
                    $json = $body | ConvertFrom-Json
                    $inputCode = $json.code
                } catch {
                    $inputCode = $null
                }

                $isValid = ($inputCode -eq $authCode)
                if ($isValid) {
                    $authVerified = $true
                    Write-Host " 授权码验证成功 (输入: $inputCode)，等待网页确认退出..." -ForegroundColor Green
                    $result = @{ success = $true } | ConvertTo-Json
                } else {
                    Write-Host " 授权码验证失败 (输入: $inputCode, 正确: $authCode)" -ForegroundColor Red
                    $result = @{ success = $false } | ConvertTo-Json
                }

                $response.StatusCode = 200
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
            }
            # 路由 /confirm
            elseif ($urlPath -eq '/confirm') {
                Write-Host " 收到网页确认信号，授权流程完成，脚本即将退出。" -ForegroundColor Cyan
                $result = @{ status = "exit" } | ConvertTo-Json
                $response.StatusCode = 200
                $response.ContentType = 'application/json'
                $response.AddHeader('Access-Control-Allow-Origin', '*')
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                $exitFlag = $true
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
    } catch {
        Write-Host " 处理请求时出错: $_" -ForegroundColor Red
        # 继续循环，不退出
    }
}

$listener.Stop()
Write-Host " 本地授权服务已关闭，脚本退出。" -ForegroundColor Magenta
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')