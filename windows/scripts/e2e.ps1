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
trap {
    if (-not $proc.HasExited) { $proc.Kill() }
    # Leave no empty test tab behind; a tab with unsaved text stays so nothing is lost.
    if ($window -and (Find-Tab) -and (Find-Tab).Current.Name -like '*Unmodified*') { try { Focus-Tab; [System.Windows.Forms.SendKeys]::SendWait('^w') } catch {} }
    break
}
$deadline = (Get-Date).AddMinutes(10)
while (-not (Select-String -Path $log -Pattern '^ready' -Quiet -ErrorAction SilentlyContinue)) {
    if ($proc.HasExited -or (Get-Date) -gt $deadline) { Get-Content $log, "$log.err"; throw 'app did not become ready' }
    Start-Sleep -Milliseconds 300
}
Write-Host "app ready (pid $($proc.Id))"

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
$A = [System.Windows.Automation.AutomationElement]
$Desc = [System.Windows.Automation.TreeScope]::Descendants
$Type = $A::ControlTypeProperty
$Select = [System.Windows.Automation.SelectionItemPattern]::Pattern

# Notepad may open the file as a tab in a window holding your own tabs, so every
# keystroke below goes only to our tab, after UI Automation confirms it is selected.
function Find-Tab($tabName = $name) {
    $tabs = $A::FromHandle($window.MainWindowHandle).FindAll($Desc, (New-Object System.Windows.Automation.PropertyCondition $Type, ([System.Windows.Automation.ControlType]::TabItem)))
    $tabs | Where-Object { $_.Current.Name -like "$tabName*" } | Select-Object -First 1
}
function Find-Doc {
    $A::FromHandle($window.MainWindowHandle).FindFirst($Desc, (New-Object System.Windows.Automation.PropertyCondition $Type, ([System.Windows.Automation.ControlType]::Document)))
}
function Focus-Tab($tabName = $name) {
    $tab = Find-Tab $tabName
    if (-not $tab) { throw "Notepad tab $tabName not found" }
    $tab.GetCurrentPattern($Select).Select()
    if ([Win]::GetForegroundWindow() -ne $window.MainWindowHandle) {
        [Win]::Tap(0x12, 0)  # Alt lets a background process take the foreground...
        [Win]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 300
        [Win]::Tap(0x1B, 0)  # ...and Esc clears the menu key tips that Alt can open
    }
    (Find-Doc).SetFocus()  # selecting a tab leaves keyboard focus on the tab strip, where Ctrl+V does nothing
    Start-Sleep -Milliseconds 300
    if (-not $tab.GetCurrentPattern($Select).Current.IsSelected -or [Win]::GetForegroundWindow() -ne $window.MainWindowHandle -or
        $A::FocusedElement.Current.ControlType -ne [System.Windows.Automation.ControlType]::Document) {
        throw 'could not focus the text area of our Notepad tab'
    }
}
function Read-Tab {
    (Find-Doc).GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1).Trim()
}

New-Item -ItemType File $doc | Out-Null
Start-Process notepad.exe "`"$doc`""
$name = Split-Path $doc -Leaf
$window = $null
for ($i = 0; $i -lt 50 -and -not $window; $i++) {
    Start-Sleep -Milliseconds 200
    $window = Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$name*" } | Select-Object -First 1
}
if (-not $window) { throw "Notepad window for $name not found" }
Focus-Tab

# Hold Right Ctrl (VK_RCONTROL, extended key) for a second, the way a user would.
[Win]::keybd_event(0xA3, 0x1D, 1, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1000
[Win]::keybd_event(0xA3, 0x1D, 3, [UIntPtr]::Zero)

if (-not $proc.WaitForExit(120000)) { $proc.Kill(); throw 'app did not paste within 2 minutes' }
Start-Sleep -Milliseconds 300
Focus-Tab
$inNotepad = Read-Tab

# Save and close our tab so no test tab is left behind.
[System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Milliseconds 800
$saved = (Get-Content $doc -Raw)
if ($saved) { $saved = $saved.Trim() }
if ($saved -eq $inNotepad) { Focus-Tab; [System.Windows.Forms.SendKeys]::SendWait('^w') }

$appOut = Get-Content $log
$heard = ($appOut | Where-Object { $_ -like 'heard:*' }) -replace '^heard:\s*', ''
$pasted = ($appOut | Where-Object { $_ -like 'pasted:*' }) -replace '^pasted:\s*', ''
Write-Host "spoken:     $spoken"
Write-Host "heard:      $heard"
Write-Host "pasted:     $pasted"
Write-Host "in Notepad: $inNotepad"
Write-Host "saved file: $saved"
if (-not $inNotepad) { throw 'Notepad is empty' }
if ($inNotepad -ne $pasted) { throw 'Notepad text differs from what the app pasted' }
if ($saved -ne $inNotepad) { throw 'saved file differs from the Notepad tab' }
if ($pasted -eq $heard) { throw 'filler filter changed nothing' }
Write-Host 'E2E PASS'
