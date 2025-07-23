echo Register the KMS Server.
slmgr.vbs /skms 10.55.6.123:1688
echo Register Windows KMS License Key
slmgr.vbs /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
echo Activate Windows...
Slmgr.vbs /ato
echo Confirm Activation Status...
slmgr.vbs /dli
echo Provide ETA of Activation expiry...
slmgr /xpr
echo Review before exiting?
pause
