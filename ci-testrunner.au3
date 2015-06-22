#include <WinAPI.au3>
#include <File.au3>

; Enable this for some debug
Local $vDebugEnabled = true
; Default paths for VS build tools
Local $vMSBuildLocation = "C:\Program Files (x86)\MSBuild\12.0\Bin"
Local $vVstestConsoleLocation = "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\CommonExtensions\Microsoft\TestWindow"
Local $vVisualStudioLocation = "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE"
; Project specific paths
Local $vProjectRelativePath = "\CoverageTest.sln"
Local $vTestProjectPackageRelativePath = "\Test\AppPackages\Test_1.0.0.0_x86_Debug_Test\"
; Script variables
Local $vLogFilePrefix = "CI-"
Local $vScriptAbsolutePath = ""
Local $vOutputFile = "\result.xml"

DetermineAbsolutePath()
Testrunner()
GenerateJUNITStyleReport()

Func Testrunner()
   ; delete old Logs
   Run("del.exe " & $vLogFilePrefix & "*","",@SW_HIDE, $STDOUT_CHILD)
   ; delete old AppPackages
   DirRemove ($vTestProjectPackageRelativePath , 1 )
   DirCreate ($vTestProjectPackageRelativePath)

   Sleep(500)

   ; build main app first, fails at packaging stage because of missing key, but thats ok
   Local $iPID = Run(@ComSpec & ' /C MSBuild.exe ' & $vScriptAbsolutePath  & $vProjectRelativePath & ' /p:Platform="x86" /p:Configuration=Debug /t:Clean;Build', $vMSBuildLocation, @SW_HIDE, $STDOUT_CHILD)
   ProcessWaitClose($iPID)
   Local $sResult = StdoutRead($iPID)
   ConsoleWrite ( $sResult )
   FileWrite($vLogFilePrefix &"MSBuild.log", $sResult)

   ; getting the apppackage filename
   Local $iPID = Run(@ComSpec & ' /C dir.exe /s /b *_Debug.appx', $vScriptAbsolutePath & $vTestProjectPackageRelativePath, @SW_HIDE, $STDOUT_CHILD)
   ProcessWaitClose($iPID)
   Local $sPackageFilename = StdoutRead($iPID)
   ConsoleWrite ( $sPackageFilename )
   If $sPackageFilename = "" Then
	     ConsoleWrite ( "ERROR: Getting the AppPackage filename failed, something went wrong." )
		 Exit (1)
   EndIf
   FileWrite($vLogFilePrefix & "PackageFilename.log", $sPackageFilename)

   ; getting the certificate filename
   Local $iPID = Run(@ComSpec & ' /C dir.exe /s /b *.cer', $vScriptAbsolutePath & $vTestProjectPackageRelativePath, @SW_HIDE, $STDOUT_CHILD)
   ProcessWaitClose($iPID)
   Local $sCertificateFilename = StdoutRead($iPID)
   ConsoleWrite ( $sCertificateFilename )
   FileWrite($vLogFilePrefix & "CertificateFilename.log", $sCertificateFilename)

   ;installing the debug certificate (NEEDS TO RUN WITH ADMIN PRIVILEDGES!!!)
   Local $iPID = Run(@ComSpec & ' /C Certutil.exe -addstore root ' & $sCertificateFilename, $vScriptAbsolutePath & $vTestProjectPackageRelativePath, @SW_HIDE, $STDERR_MERGED)
   ProcessWaitClose($iPID)
   Local $sResult = StdoutRead($iPID)
   ConsoleWrite ( $sResult )
   FileWrite($vLogFilePrefix & "CertificateFilename.log", $sResult)

   ;execute Visual Studio Tests
   Local $iPID = Run(@ComSpec & ' /C vstest.console.exe ' & StringReplace($sPackageFilename, @CRLF, "") & ' /InIsolation /Platform:x86', $vVstestConsoleLocation, @SW_HIDE, $STDERR_MERGED)
   ProcessWaitClose($iPID)
   Local $sTestResult = StdoutRead($iPID)
   ConsoleWrite ( $sTestResult )
   FileWrite($vLogFilePrefix & "vstest.console.log", $sTestResult)

   Local $sResult = StringInStr ( $sTestResult, "Test Run Successful.")
   If StringInStr ( $sTestResult, "Test Run Successful.") = "0" Then
	     ConsoleWrite ( "ERROR: Tests failed, check logs" )
		 Exit (1)
   EndIf
EndFunc


Func GenerateJUNITStyleReport()
   $file = $vLogFilePrefix & "vstest.console.log"
   FileOpen($file, 0)
   ; delete old Logs
   Run("del.exe " & $vOutputFile,"",@SW_HIDE, $STDOUT_CHILD)

   Local $lines = _FileCountLines($file)
   Local $totalTestsString = FileReadLine ( $file , $lines - 2 )
   Local $aTotalTests = StringSplit ( $totalTestsString, ".")

   Local $vTimeLine = FileReadLine ( $file , $lines)
   Local $vTimeLineTmp =  StringReplace ( $vTimeLine, "Test execution time:", "" )
   Local $vTimeLineTmp1 =  StringReplace ( $vTimeLineTmp, ",", ".")
   Local $vTimeLineTmp2 =  StringReplace ( $vTimeLineTmp1, "Seconds", "" )
   Local $vTime = StringStripWS ($vTimeLineTmp2,8)

   Local $vTotal
   Local $vPassed
   Local $vFailed
   Local $vSkipped

   For $i = 1 To $aTotalTests[0] ; Loop through the array returned by StringSplit to display the individual values.
	  If StringInStr ( $aTotalTests[$i], "Total Tests") Then
		 $vTotal = StringStripWS ( StringReplace ( $aTotalTests[$i], "Total tests: ", "" ),8)
	  EndIf
	  If StringInStr ( $aTotalTests[$i], "Passed") Then
		 $vPassed = StringStripWS ( StringReplace ( $aTotalTests[$i], "Passed: ", "" ),8)
	  EndIf
	  If StringInStr ( $aTotalTests[$i], "Failed") Then
		 $vFailed = StringStripWS ( StringReplace ( $aTotalTests[$i], "Failed: ", "" ),8)
	  EndIf
	  If StringInStr ( $aTotalTests[$i], "Skipped") Then
		$vSkipped = StringStripWS ( StringReplace ( $aTotalTests[$i], "Skipped: ", "" ),8)
	  EndIf
   Next

   ;XML header
   FileWriteLine ($vScriptAbsolutePath & $vOutputFile, '<testsuite errors="0" failures="' & $vFailed & '" name="VS report" skips="' & $vSkipped & '" tests="' & $vTotal & '" time="' & $vTime & '">')

   For $i = 1 to $lines
	  $line = FileReadLine($file, $i)
	  If StringLeft($line, 6) = "Passed" Then
		 Local $vTestname = StringStripWS ( StringReplace ($line, "Passed", "" ),8)
		 FileWriteLine ($vScriptAbsolutePath & $vOutputFile,'<testcase classname="' & $vTestname & '" name="' & $vTestname & '" />')

	  EndIf

	  If StringLeft($line, 6) = "Failed" Then
		 Local $vTestname = StringStripWS ( StringReplace ($line, "Failed", "" ),8)
		 FileWriteLine ($vScriptAbsolutePath & $vOutputFile,'<testcase classname="' & $vTestname & '" name="' & $vTestname & '" >')
		 FileWriteLine ($vScriptAbsolutePath & $vOutputFile,'<failure message="test failure">failed</failure>')
		 FileWriteLine ($vScriptAbsolutePath & $vOutputFile,'</testcase>')
	  EndIf
   Next

   DebugMsg("Saving to " & $vScriptAbsolutePath & $vOutputFile)
   FileClose($file)
   FileWriteLine ($vScriptAbsolutePath & $vOutputFile,'</testsuite>')
EndFunc

Func DetermineAbsolutePath()
   RunWait(@ComSpec & " /c %SystemDrive%&&cd %temp%&&echo %cd%>temp.tmp", "", @SW_hide); create temp file to save %cd%
   $file = FileOpen(@TempDir & "\temp.tmp", 0)
   ; Check if file opened for reading OK
   If $file = -1 Then
	   ConsoleWrite ( "ERROR: Unable to open file to determine current path." )
	   Exit (1)
   EndIf
   ; Read in lines of text until the EOF is reached
   While 1
	   $line = FileReadLine($file)
	   If @error = -1 Then ExitLoop
	   $vScriptAbsolutePath = $line
   WEnd
   FileClose($file)
   FileDelete(@TempDir & "\temp.tmp")
EndFunc

Func DebugMsg($msg)
   If $vDebugEnabled Then
	  MsgBox(0, "Debug message", $msg)
   EndIf
EndFunc
