Write-Output "Making the MSI..."
Write-Output "-----------------"
$ErrorActionPreference = 'Stop'
Get-ChildItem env:

Write-Output "[*] Installing goversioninfo"
go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@latest
$ENV:PATH="$ENV:PATH;$($env:home)\go\bin"
# See ./cmd/rpport/versioninfo.json.md

Write-Output "[*] Installing WIX"
choco install wixtoolset

Write-Output "[*] Versioning the build"
cd cmd/rport
goversioninfo.exe -product-version $env:GITHUB_REF_NAME -file-version $env:GITHUB_REF_NAME
cd ../../

Write-Output "[*] Building rport.exe for windows"
go build -ldflags "-s -w -X github.com/cloudradar-monitoring/rport/share.BuildVersion=$($env:GITHUB_REF_NAME)" -o rport.exe ./cmd/rport/...
Get-ChildItem -File *.exe
.\rport.exe --version
Write-Output "[*] Compressing rport.exe to zip"
$zip = "rport-$($env:GITHUB_REF_NAME)_x86_64.zip"
Compress-Archive rport.exe -DestinationPath $zip
Get-ChildItem *.zip

Write-Output "[*] Uploading $($zip)"
& curl.exe -fs https://$env:DOWNLOAD_SERVER/exec/upload.php `
 -H "Authentication: $env:MSI_UPLOAD_TOKEN" `
 -F file=@$zip -F dest_dir="rport/unstable/msi"

Write-Output "[*] Creating wixobj's"
& 'C:\Program Files (x86)\WiX Toolset v3.11\bin\candle.exe' -dPlatform=x64 -ext WixUtilExtension opt/resource/*.wxs

Write-Output "[*] Creating MSI"
& 'C:\Program Files (x86)\WiX Toolset v3.11\bin\light.exe' `
  -loc opt/resource/Product_en-us.wxl `
  -ext WixUtilExtension -ext WixUIExtension -sval `
  -out rport-client.msi LicenseAgreementDlg_HK.wixobj WixUI_HK.wixobj Product.wixobj
Get-ChildItem -File *.msi

Write-Output "[*] Creating a self signed certificate"
$cert = New-SelfSignedCertificate -DnsName rport.io -CertStoreLocation cert:\LocalMachine\My -type CodeSigning
$MyPassword = ConvertTo-SecureString -String "MyPassword" -Force -AsPlainText
Export-PfxCertificate -cert $cert -FilePath mycert.pfx -Password $MyPassword

Write-Output "[*] Signing the generated MSI"
& 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x86\signtool.exe' sign /fd SHA256 /f mycert.pfx /p MyPassword rport-client.msi

Write-Output "[*] Uploading MSI to download server"
$upload = "rport-$($env:GITHUB_REF_NAME)_x86_64.msi"
Copy-Item rport-client.msi $upload
Get-ChildItem -File *.msi
& curl.exe -V
& curl.exe -fs https://$env:DOWNLOAD_SERVER/exec/upload.php `
 -H "Authentication: $env:MSI_UPLOAD_TOKEN" `
 -F file=@$upload -F dest_dir="rport/unstable/msi"