$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$VenvPython = Join-Path $RepoRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $VenvPython)) {
    $BootstrapPython = $env:CODEX_PYTHON
    if (-not $BootstrapPython) {
        $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if ($PythonCommand) { $BootstrapPython = $PythonCommand.Source }
    }
    if (-not $BootstrapPython) {
        throw '未找到 Python。请在 Codex 中说“初始化 WebUI 预览环境”。'
    }
    & $BootstrapPython -m venv (Join-Path $RepoRoot '.venv')
    & $VenvPython -m pip install -r (Join-Path $RepoRoot 'requirements.txt')
}

Set-Location $RepoRoot
& $VenvPython (Join-Path $PSScriptRoot 'dev_preview.py')
