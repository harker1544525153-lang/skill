#一键推送 skill 到 GitHub 仓库
#用法：网络恢复后，在 PowerShell 中运行： .\upload.ps1
Set-Location $PSScriptRoot

Write-Host "=== 当前仓库状态 ===" -ForegroundColor Cyan
git status --short
Write-Host ""

Write-Host "=== 正在推送 ===" -ForegroundColor Cyan
git push -u origin master

if ($LASTEXITCODE -eq 0) {
    Write-Host "推送成功！" -ForegroundColor Green
    Write-Host "仓库地址：https://github.com/harker1544525153-lang/skill"
} else {
    Write-Host "推送失败，请检查网络连接或 GitHub 凭据" -ForegroundColor Red
}
