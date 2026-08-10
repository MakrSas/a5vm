$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$compiler = 'C:\msys64\ucrt64\bin\gcc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = 'C:\Program Files\LLVM\bin\clang.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    $found = Get-Command clang -ErrorAction SilentlyContinue
    if ($found) { $compiler = $found.Source }
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'Neither LLVM Clang nor MSYS2 GCC was found.'
}

$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$common = @('-std=c11', '-Wall', '-Wextra', '-Werror', '-I', (Join-Path $root 'include'))
$sources = @((Join-Path $root 'src\memory.c'), (Join-Path $root 'src\cpu8086.c'),
    (Join-Path $root 'src\cpu386.c'),
    (Join-Path $root 'src\vga_text.c'), (Join-Path $root 'src\keyboard.c'),
    (Join-Path $root 'src\floppy.c'), (Join-Path $root 'src\disk.c'),
    (Join-Path $root 'src\ide.c'),
    (Join-Path $root 'src\bios.c'),
    (Join-Path $root 'src\bios386.c'),
    (Join-Path $root 'src\pic8259.c'), (Join-Path $root 'src\pit8253.c'),
    (Join-Path $root 'src\machine.c'))

& $compiler @common @sources (Join-Path $root 'src\main.c') '-o' (Join-Path $build 'a5vm-demo.exe')
if ($LASTEXITCODE -ne 0) { throw 'demo build failed' }
& $compiler @common @sources (Join-Path $root 'tests\test_a5vm.c') '-o' (Join-Path $build 'a5vm-tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'test build failed' }
& (Join-Path $build 'a5vm-tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
& (Join-Path $build 'a5vm-demo.exe')
if ($LASTEXITCODE -ne 0) { throw 'demo failed' }
