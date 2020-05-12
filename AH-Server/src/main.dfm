object ServiceObj: TServiceObj
  OldCreateOrder = False
  DisplayName = 'AHserver'
  BeforeInstall = ServiceBeforeInstall
  BeforeUninstall = ServiceBeforeInstall
  OnExecute = ServiceExecute
  OnStart = ServiceStart
  OnStop = ServiceStop
  Height = 150
  Width = 215
end
