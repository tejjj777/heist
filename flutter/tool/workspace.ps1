$taskWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$env:FLUTTER_ROOT = Join-Path $taskWorkspace 'sdk\flutter'
$env:PATH = (Join-Path $env:FLUTTER_ROOT 'bin') + ';' + $env:PATH
$env:APPDATA = Join-Path $taskWorkspace '.flutter-config'
$env:PUB_CACHE = Join-Path $taskWorkspace '.pub-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
$androidTools = Join-Path $taskWorkspace 'sdk\android'
if (Test-Path $androidTools) {
  $env:ANDROID_HOME = $androidTools
  $env:ANDROID_SDK_ROOT = $androidTools
}
$javaFolder = Get-ChildItem (Join-Path $taskWorkspace 'sdk\java') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($javaFolder) {
  $env:JAVA_HOME = $javaFolder.FullName
  $env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH
}
$env:GRADLE_USER_HOME = Join-Path $taskWorkspace '.gradle'
$env:ANDROID_USER_HOME = Join-Path $taskWorkspace '.android'
$proxyAddress = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { $env:HTTP_PROXY }
if ($proxyAddress -and -not $env:JAVA_TOOL_OPTIONS) {
  $buildProxy = [Uri]$proxyAddress
  if (-not $buildProxy.UserInfo) {
    # Java does not automatically honor HTTP_PROXY. Use the existing workspace
    # proxy and Windows trusted roots; certificate validation remains enabled.
    $env:JAVA_TOOL_OPTIONS = "-Dhttp.proxyHost=$($buildProxy.Host) -Dhttp.proxyPort=$($buildProxy.Port) -Dhttps.proxyHost=$($buildProxy.Host) -Dhttps.proxyPort=$($buildProxy.Port) -Djavax.net.ssl.trustStoreType=Windows-ROOT"
  }
}
