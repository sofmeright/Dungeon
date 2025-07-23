%~dp0setup.exe /download %~dp0Microsoft-Office-2024-LTSC-FULL-English_US.xml
%~dp0setup.exe /configure %~dp0Microsoft-Office-2024-LTSC-FULL-English_US.xml
slmgr.vbs /skms 10.0.0.1:1688
slmgr.vbs /ato
echo (cscript "C:\Program Files\Microsoft Office\Office16\ospp.vbs" /inpkey:<key> | if we wanted to do that)
cscript "C:\Program Files\Microsoft Office\Office16\ospp.vbs" /sethst:10.0.0.1
cscript "C:\Program Files\Microsoft Office\Office16\ospp.vbs" /setprt:1688
cscript "C:\Program Files\Microsoft Office\Office16\ospp.vbs" /act