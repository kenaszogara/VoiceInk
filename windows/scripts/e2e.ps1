# End-to-end check: hotkey -> record -> whisper.cpp -> filler filter -> paste into Notepad.
# The mic is replaced by a TTS clip (--fake-mic) so it runs unattended; everything else is the real app.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$app = Join-Path $root '.venv\Scripts\voiceink.exe'
$work = Join-Path $env:TEMP 'voiceink-e2e'
New-Item -ItemType Directory -Force $work | Out-Null
$wav = Join-Path $work 'dictation.wav'
$log = Join-Path $work 'app.log'
$doc = Join-Path $work ("notepad-{0}.txt" -f (Get-Random))
$spoken = 'So, um, I think we should, like, ship it today, you know?'

Add-Type -AssemblyName System.Speech
$tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
$tts.SetOutputToWaveFile($wav, (New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo 16000, 'Sixteen', 'Mono'))
$tts.Speak($spoken)
$tts.Dispose()

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static void Tap(byte vk, uint flags) { keybd_event(vk, 0, flags, UIntPtr.Zero); keybd_event(vk, 0, flags | 2, UIntPtr.Zero); }
}
'@

$proc = Start-Process $app -ArgumentList '--fake-mic', "`"$wav`"", '--once' -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Hidden -PassThru
trap { if (-not $proc.HasExited) { $proc.Kill() }; break }
$deadline = (Get-Date).AddMinutes(10)
while (-not (Select-String -Path $log -Pattern '^ready' -Quiet -ErrorAction SilentlyContinue)) {
    if ($proc.HasExited -or (Get-Date) -gt $deadline) { Get-Content $log, "$log.err"; throw 'app did not become ready' }
    Start-Sleep -Milliseconds 300
}
Write-Host "app ready (pid $($proc.Id))"

New-Item -ItemType File $doc | Out-Null
Start-Process notepad.exe "`"$doc`""
$name = Split-Path $doc -Leaf
$window = $null
for ($i = 0; $i -lt 50 -and -not $window; $i++) {
    Start-Sleep -Milliseconds 200
    $window = Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$name*" } | Select-Object -First 1
}
if (-not $window) { throw "Notepad window for $name not found" }
[Win]::Tap(0x12, 0)  # a stray Alt lets a background process take the foreground
[Win]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
if ([Win]::GetForegroundWindow() -ne $window.MainWindowHandle) { throw 'could not focus Notepad' }

# Hold Right Ctrl (VK_RCONTROL, extended key) for a second, the way a user would.
[Win]::keybd_event(0xA3, 0x1D, 1, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1000
[Win]::keybd_event(0xA3, 0x1D, 3, [UIntPtr]::Zero)

if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw 'app did not paste within 2 minutes' }
Start-Sleep -Milliseconds 300
[Win]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait('^w')  # close only our tab; other Notepad tabs stay

$appOut = Get-Content $log
$heard = ($appOut | Where-Object { $_ -like 'heard:*' }) -replace '^heard:\s*', ''
$pasted = ($appOut | Where-Object { $_ -like 'pasted:*' }) -replace '^pasted:\s*', ''
$inNotepad = (Get-Content $doc -Raw).Trim()
Write-Host "spoken:     $spoken"
Write-Host "heard:      $heard"
Write-Host "pasted:     $pasted"
Write-Host "in Notepad: $inNotepad"
if (-not $inNotepad) { throw 'Notepad is empty' }
if ($inNotepad -ne $pasted) { throw 'Notepad text differs from what the app pasted' }
if ($pasted -eq $heard) { throw 'filler filter changed nothing' }
Write-Host 'E2E PASS'
