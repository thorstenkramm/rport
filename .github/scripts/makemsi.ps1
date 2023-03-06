Write-Output "Making the MSI..."
Write-Output "-----------------"
$ErrorActionPreference = 'Stop'
Get-ChildItem env:

Write-Output "[*] Install goversioninfo"
#go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo
go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@latest
$ENV:PATH="$ENV:PATH;$($env:home)\go\bin"

Write-Output "[*] Install WIX"
choco install wixtoolset

Write-Output "[*] Building MSI"
Get-Content new.json > cmd\rport\versioninfo.json
Write-Output "Version the client with whatever is in versioninfo.json"
go generate cmd/rport/main.go
Write-Output "[*] Build rport client for windows"
go build -ldflags "-s -w -X {{.Env.PROJECT}}/share.BuildVersion={{.Version}}" -o rport.exe ./cmd/rport/...
Get-ChildItem -File *.exe
.\rport.exe --version

Write-Output "[*] Creating wixobj's"
& 'C:\Program Files (x86)\WiX Toolset v3.11\bin\candle.exe' -dPlatform=x64 -ext WixUtilExtension opt/resource/*.wxs
Write-Output "[*] Creating MSI"
& 'C:\Program Files (x86)\WiX Toolset v3.11\bin\light.exe' -loc opt/resource/Product_en-us.wxl -ext WixUtilExtension -ext WixUIExtension -sval -out rport-client.msi LicenseAgreementDlg_HK.wixobj WixUI_HK.wixobj Product.wixobj
Get-ChildItem -File *.msi

Write-Output "[*] Creating a self signed certificate"
$cert = New-SelfSignedCertificate -DnsName rport.io -CertStoreLocation cert:\LocalMachine\My -type CodeSigning
$MyPassword = ConvertTo-SecureString -String "MyPassword" -Force -AsPlainText
Export-PfxCertificate -cert $cert -FilePath mycert.pfx -Password $MyPassword

Write-Output "[*] Signing the generated MSI"
& 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x86\signtool.exe' sign /fd SHA256 /f mycert.pfx /p MyPassword rport-client.msi

Write-Output "[*] Uploading MSI to download server"
$file = "rport-client.msi"
& curl.exe -fs https://$($env:DOWNLOAD_SERVER)/exec/upload.php -H "Authentication: $($env:MSI_UPLOAD_TOKEN)" -F file=@$($file) -F dest_dir="rport/unstable/msi"