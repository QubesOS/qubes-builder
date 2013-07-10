CMD /C "CD /D %CD%\winpvdrivers && makedist" || GOTO END
rem the below line will success only if you have access to ITL proprietary code
CMD /C "CD /D %CD%\core\win && makedist" || GOTO END
CMD /C "CD /D %CD%\gui-agent && makedist" || GOTO END

CMD /C "CD /D %CD% && wix" || GOTO END

:END
