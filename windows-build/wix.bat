
SET WIXEXT=-ext "%WIX%\bin\WixBalExtension.dll"
FOR /F %%V IN (core\version_win) DO SET CORE_VERSION=%%V

call winpvdrivers\set_version.bat

"%WIX%\bin\candle.exe" bundle.wxs %WIXEXT% && "%WIX%\bin\light.exe" -o qubesdrivers.exe bundle.wixobj %WIXEXT%
