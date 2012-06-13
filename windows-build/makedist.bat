CMD /C "CD /D %CD%\winpvdrivers && makedist"
CMD /C "CD /D %CD%\core\win && makedist"

CMD /C "CD /D %CD% && wix"
