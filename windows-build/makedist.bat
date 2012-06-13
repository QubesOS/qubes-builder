CMD /C "CD /D %CD%\winpvdrivers && makedist" || exit 1
CMD /C "CD /D %CD%\core\win && makedist" || exit 1

CMD /C "CD /D %CD% && wix" || exit 1
