param([int]$PreferredPort=8765)
$ErrorActionPreference="Stop"
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$galleryRoot=Join-Path $projectRoot "tools\effect-gallery"
$python=Get-Command python -ErrorAction SilentlyContinue
$usingLauncher=$null -eq $python
if($usingLauncher){
    $python=Get-Command py -ErrorAction SilentlyContinue
    if($null -eq $python){throw "Python 3 was not found. Install Python or serve tools/effect-gallery with another static file server."}
}
$arguments=if($usingLauncher){@("-3","-m","http.server")}else{@("-m","http.server")}
function Get-FreePort([int]$StartPort){
    for($port=$StartPort;$port -lt ($StartPort+100);$port++){
        $listener=$null
        try{
            $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$port)
            $listener.Start()
            return $port
        }
        catch{
            continue
        }
        finally{
            if($null -ne $listener){$listener.Stop()}
        }
    }
    throw "No free port was found from $StartPort to $($StartPort+99)."
}
$port=Get-FreePort $PreferredPort
$url="http://127.0.0.1:$port/"
Write-Output "Iron Front effect gallery: $url"
Write-Output "Serving directory: $galleryRoot"
Write-Output "Press Ctrl+C to stop the local server."
Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command","Start-Sleep -Milliseconds 800; Start-Process '$url'") | Out-Null
$arguments += @("--bind","127.0.0.1","--port",$port,"--directory",$galleryRoot)
& $python.Source @arguments
