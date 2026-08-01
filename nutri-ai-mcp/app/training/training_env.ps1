$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if ($env:NUTRI_TRAIN_PYTHON) {
    $py = $env:NUTRI_TRAIN_PYTHON
}
else {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $root)
    $workspacePython = Join-Path $workspaceRoot 'envs\test\python.exe'
    $venvPython = Join-Path $root '.venv\Scripts\python.exe'

    if (Test-Path -LiteralPath $workspacePython) {
        $py = $workspacePython
    }
    elseif (Test-Path -LiteralPath $venvPython) {
        $py = $venvPython
    }
    else {
        $py = (Get-Command python -ErrorAction Stop).Source
    }
}

if (-not (Test-Path -LiteralPath $py -PathType Leaf)) {
    throw "Training Python was not found: $py. Set NUTRI_TRAIN_PYTHON to a valid executable."
}
