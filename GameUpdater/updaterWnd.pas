{$I+}
unit updaterWnd;

interface

uses
  Windows, Messages, SysUtils, Classes,  Forms,
   XPMan, ComCtrls, StdCtrls, Controls, ExtCtrls, OleCtrls, SHDocVw;

type
  TMainForm = class(TForm)
    progress: TProgressBar;
    XPManifest1: TXPManifest;
    btn: TButton;
    lab: TLabel;
    Timer: TTimer;
    panel: TPanel;
    browser: TWebBrowser;
    procedure btnClick(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Private declarations }
  public
    { Public declarations }
    procedure Failed(reason:AnsiString);
    procedure ShowReleaseNotes;
  end;

var
  MainForm: TMainForm;
  dontInstall:boolean=false;
  ver:integer;

  procedure UpdateFiles(fromDir:AnsiString);

implementation
 uses CrossPlatform,ControlFiles2,MyServis,HTTPrequests,zlibEx,DCPMD5a,ShellAPI;

{$R *.dfm}
type
 TFileRec=record
  path:AnsiString;
  packedSize,size:integer;
  hash:AnsiString;
  state:integer;
 end;
var
 stage:integer=0;
 version:integer;
 baseURL,tmpDir:AnsiString;
 req,req1,req2,req1idx,req2idx:integer;

 filelist:AnsiString; // "filelist" content from server
 files:array[1..5000] of TFileRec;
 totalFiles,processed:integer; // Всего файлов в списке / проверено файлов
 totalSize,downloaded:integer; // total bytes to download / downloaded bytes
 totalCount,downloadedCount:integer;
 failure:boolean;

procedure TMainForm.btnClick(Sender: TObject);
var
 res:HINST;
begin
 case stage of
  -2:Close; // Fatal error
  -1:stage:=0;
   6:begin
      ForceLogMessage('Running InstallUpdate.exe');
      res:=ShellExecute(0,'runas','InstallUpdate.exe',PChar('-INSTALL '+tmpDir),nil,0);
      if res<=32 then begin
       ForceLogMessage('RunAs failed with code '+inttostr(res));
       res:=ShellExecute(0,'run','InstallUpdate.exe',PChar('-INSTALL '+tmpDir),nil,0);
       if res<=32 then begin
         ForceLogMessage('ShellExecute failed with code '+inttostr(res));
         if not LaunchProcess('InstallUpdate.exe','-INSTALL '+tmpDir) then
           ForceLogMessage('LaunchProcess failed');
       end;
      end;
      Close;
   end;
  100:Close;
  else Close;
 end;
end;

procedure TMainForm.Failed(reason: AnsiString);
var
 report,log:AnsiString;
begin
 if stage>2 then begin
  log:=LoadFileAsString('updating.log');
  if length(log)>4000 then log:=copy(log,length(log)-4000,4000);
  report:=reason+#13#10+log;
  HTTPrequest('http://astralheroes.com/updatefailed',report,'');
 end;
 stage:=-1;
 lab.Caption:='Update failed: '+reason;
 btn.Caption:='Retry';
end;

procedure TMainForm.FormActivate(Sender: TObject);
begin
 if DirectoryExists('Logs') then
  UseLogFile('Logs\updating.log')
 else
  UseLogFile('updating.log');
 SetLogMode(lmVerbose);
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 ForceLogMessage('Exit');
end;

procedure TMainForm.ShowReleaseNotes;
var
 fname,lang:AnsiString;
 configName:AnsiString;
begin
 panel.Visible:=true;
 clientHeight:=348;
 try
 configName:='game.ctl';
 if FileExists(configName) then UseControlFile(configName);
 lang:=ctlGetStr('game.ctl:\Options\Language','en');
 fname:=tmpDir+'\changes_'+lang+'.txt';
 if not fileExists(fname) then fname:=tmpDir+'\changes.txt';
 if FileExists(fname) then begin
  panel.Visible:=true;
  clientHeight:=348;
  browser.Navigate('file://'+fname);
 end else
  LogMessage('Changelog file not found: '+fname);
 except
  on e:exception do LogMessage('Error in ShowReleaseNotes: '+e.message);
 end;
end;

function MyCopyDir(sour,dest:AnsiString):boolean; // Скопировать каталог со всем содержимым
  var
   sr:TSearchRec;
   buf:pointer;
   f,f2:file;
   size,total:integer;
   target:AnsiString;
  begin
   result:=true;
   if not DirectoryExists(dest) then begin
    LogMessage('Creating directory: '+dest);
    try
     CreateDir(dest);
    except
     on e:exception do ForceLogMessage('Directory creation error: '+e.message);
    end;
   end;
   FindFirst(sour+'\*.*',faAnyFile,sr);
   while FindNext(sr)=0 do begin
    if (sr.name[1]='.') or
       (sr.Attr and faVolumeID>0) then continue;
    if sr.Attr and faDirectory>0 then
     result:=result and MyCopyDir(sour+'\'+sr.name,dest+'\'+sr.name)
    else begin
     target:=dest;
     if target<>'' then target:=target+'\';
     target:=target+sr.Name;
     if pos('_del',sr.name)=length(sr.name)-3 then begin
      setLength(sr.name,length(sr.Name)-4);
      ForceLogMessage('Deleting: '+sr.name);
      try
       DeleteFile(target);
      except
       on e:exception do ForceLogMessage('Error deleting file: '+e.message);
      end;
     end else begin
      if pos('INSTALLUPDATE.EXE',target)>0 then target:=target+'.NEW';
      LogMessage(Format('Moving: %s -> %s',
        [sour+'\'+sr.name,target]));
      getmem(buf,1024*256);
      try
       total:=0;
       assign(f,sour+'\'+sr.name);
       reset(f,1);
       assign(f2,target);
       rewrite(f2,1);
       repeat
        blockread(f,buf^,1024*256,size);
        blockwrite(f2,buf^,size);
        inc(total,size);
       until size<1024*256;
       close(f);
       close(f2);
       LogMessage('OK! Copied '+inttostr(total)+' bytes');
       DeleteFile(sour+'\'+sr.name);
      except
       on e:exception do ForceLogMessage('Error copying file '+sr.name+': '+e.message);
      end;
      freemem(buf);
     end;
     result:=result and (IOresult=0);
    end;
   end;
   FindClose(sr);
  end;

procedure UpdateFiles(fromDir:AnsiString);
 var
  f:file;
  st:AnsiString;
 begin
  try
   if DirectoryExists('Logs') then
    UseLogFile('Logs\GameUpdate.log')
   else
    UseLogFile('GameUpdate.log');
   ForceLogMessage('Installing update from '+fromDir);
   try
    // проверка доступности файла на запись
    st:=ExtractFilePath(ParamStr(0))+'astralheroes.exe';
    LogMessage('Check if the game is not running: '+st);
    assign(f,st);
    reset(f,1);
    close(f);
   except
    on e:exception do begin
     LogMessage('Game executable is locked! ');
     ErrorMessage('Game executable is locked: is it running?'#13#10' Please make sure the game is closed and press "OK"');
    end;
   end;
   MyCopyDir(fromDir,ExtractFilePath(ParamStr(0)));
   ForceLogMessage('Launching astral heroes...');
   LaunchProcess('AstralHeroes.exe');
  except
   on e:exception do ErrorMessage('ERROR! Installation failed!'#13#10+e.message+#13#10'More details in GameUpdate.log');
  end;
 end;

procedure ProcessFileList(filelist:AnsiString);
var
 sa,items:AStringArr;
 i,j,n:integer;
 path,st:AnsiString;
begin
 // Format: path hash p_size full_size
 sa:=splitA(#13#10,filelist);
 path:=''; totalFiles:=0; processed:=0;
 for i:=0 to high(sa) do begin
  items:=splitA(';',sa[i]);
  if length(items)=4 then begin
   inc(totalFiles);
   st:=items[0];
   files[totalFiles].hash:=items[1];
   files[totalFiles].packedSize:=StrToIntDef(items[2],0);
   files[totalFiles].size:=StrToIntDef(items[3],0);
   j:=pos('*',st);
   if j>0 then begin
    n:=StrToIntDef(copy(st,1,j-1),0);
    delete(st,1,j);
    path:=copy(path,1,n)+st;
   end else
    path:=st;
   LogMessage('File entry: '+path+'; hash='+items[1]+'; packed='+items[2]+' size='+items[3]);
   files[totalFiles].path:=path;
   files[totalFiles].state:=1;
  end;
  mainForm.progress.position:=Round(10*i/length(sa));
 end;
 stage:=3;
 LogMessage('Start stage 3');
 if totalFiles<100 then failure:=true; // что-то не так со списком файлов - наверно это вообще не список
end;

procedure CheckRequest(var r:integer;idx:integer);
var
 res:integer;
 response,path:AnsiString;
 buf:pointer;
 size,outSize:integer;
begin
 if r=0 then exit;
 res:=GetRequestResult(r,response);
 if res=httpStatusFailed then begin
  failure:=true; exit;
 end;
 if res in [httpStatusCompleted,httpStatusSent] then begin
  size:=GetRequestState(r);
  if size>=0 then inc(downloaded,size);
 end;
 if res=httpStatusCompleted then begin
  if length(response)<>files[idx].packedSize then begin
   ForceLogMessage(Format('ERROR: Packed size mismatch: %d <> %d for %s',
     [length(response),files[idx].packedSize,files[idx].path]));
   failure:=true;
   exit;
  end;
  // Возможно стоит вынести распаковку в отдельный поток, но пока пойдёт и так
  move(response[1],size,4);
  ASSERT((size>=0) and (size<256*1024*1024)); // unpacked size up to 256 MB
  path:=tmpDir+'\'+files[idx].path;
  LogMessage(Format('Unpacking %s, size: %d -> %d',[path,length(response)-12,size]));
  ZDecompress(@response[13],length(response)-12,buf,outSize,size);
  if outSize<>size then LogMessage(Format('Warning: size mismatch: %d <> %d',[outSize,size]));
  try
   ForceDirectories(ExtractFileDir(path));
  except
   on e:exception do ForceLogMessage('ERROR! Can''t create dir for '+path);
  end;
  try
   SaveFile(path,buf,outSize);
  except
   on e:exception do ForceLogMessage('ERROR! Failed to save file to '+path);
  end;
  FreeMem(buf);
  r:=0;
  files[idx].state:=4;
 end;
end;

procedure HandleFiles;
var
 i,counter,unhandled,fSize:integer;
 buf:ByteArray;
 hash,st,path:AnsiString;
 finished:boolean;
begin
 counter:=0; unhandled:=0;
 totalSize:=0; downloaded:=0;
 totalCount:=0; downloadedCount:=0;
 // 1-й проход: посчитаем кол-во необработанных файлов, а также проверим часть файлов на необходимость апдейта
 for i:=1 to totalFiles do begin
  if counter>1000000 then continue; // Уже достаточно для этого раза, продолжим в другой раз
  if files[i].state=1 then begin
   // Файл не был проверен - проверить на необходимость апдейта
   // При этом важно учитывать, что файл, возможно, уже был скачан ранее
   path:=files[i].path;
   if FileExists(tmpDir+'\'+path) then path:=tmpDir+'\'+path;
   fSize:=GetFileSize(path);
   if fSize<>files[i].size then begin
    files[i].state:=2; // needs update
    inc(counter,5000);
    LogMessage(files[i].path+' size mismatch');
   end else begin
    SetLength(buf,fSize);
    try
     ReadFile(path,@buf[0],0,fSize);
     hash:=copy(MD5(buf[0],fSize),1,12);

    except
     on e:exception do begin
       ForceLogMessage('File read error: '+path+' - '+e.message);
       hash:='';
     end;
    end;
    if hash<>files[i].hash then begin
     files[i].state:=2; // needs update
     LogMessage(path+' hash mismatch: '+hash+' <> '+files[i].hash);
    end else
     files[i].state:=0; // up to date
    inc(counter,fSize);
   end;
  end;
 end;
 processed:=totalFiles;
 for i:=1 to totalFiles do begin
  if files[i].state=1 then dec(processed);
   if files[i].state>=2 then begin
    inc(totalSize,files[i].packedSize);
    inc(totalCount);
   end;
   if files[i].state=4 then begin
    inc(downloaded,files[i].packedSize);
    inc(downloadedCount);
   end;
 end;
 // проверим, может уже скачались какие-то файлы?
 CheckRequest(req1,req1idx);
 CheckRequest(req2,req2idx);

 if (req1=0) or (req2=0) then begin
  // 2-й проход: запустим закачку файлов (если требуется)
  for i:=1 to totalFiles do begin
   if files[i].state=2 then begin
    files[i].state:=3;
    st:=baseURL+StringReplace(files[i].path+'_','\','/',[rfReplaceAll]);
    if req1=0 then begin
     req1:=HTTPrequest(st,'','');
     req1idx:=i;
    end else
     if req2=0 then begin
      req2:=HTTPrequest(st,'','');
      req2idx:=i;
     end;
   end;
   if (req1<>0) and (req2<>0) then break;
  end;
 end;
 // 3-й проход: всё ли закончено?
 finished:=true;
 for i:=1 to totalFiles do
  if not (files[i].state in [0,4]) then finished:=false;
 if finished then begin
  stage:=4;
  ForcelogMessage('All downloaded!');
 end;
end;

{procedure InstallUpdate;
begin
 LogMessage('Copying new files...');
 if not MyCopyDir('upd','') then begin
  ForceLogMessage('ERROR: some files were not copied from "upd"');
  failure:=true;
 end else begin
  stage:=5;
  ForceLogMessage('All done!');
 end;
end;}

procedure TMainForm.TimerTimer(Sender: TObject);
var
 response:AnsiString;
 res:integer;
 free,total,totalFree:int64;
 path:string;
 v1,v2:single;
begin
 try
 case stage of
  0:begin
     // Just launched
     failure:=false;
     if ver>0 then version:=ver
      else version:=StrToIntDef(paramStr(1),0);
     progress.position:=0;
//     if not DirectoryExists('upd') then CreateDir('upd');
     ForceLogMessage('Updating to version '+inttostr(version));
     lab.caption:='Connecting astralheroes.com...';
     baseURL:='http://astralheroes.com/update/'+IntToStr(version)+'/';
     req:=HTTPrequest(baseURL+'filelist','','');
     tmpDir:=GetEnvironmentVariable('TEMP')+'\AstralHeroesUpdate';
     ForceLogMessage('Temp dir: '+tmpDir);
     if not DirectoryExists(tmpDir) then begin
      ForceLogMessage('Creating '+tmpDir);
      CreateDir(tmpDir);
      ForceLogMessage('Created');
     end;
     path:=tmpDir;
     GetDiskFreeSpaceEx(PChar(path),free,total,@totalfree);
     LogMessage('Free space on temp volume: '+SizeToStr(free)+' of '+SizeToStr(total));
     if free<40*1024*1024 then begin
      lab.caption:='ERROR! Not enough space on TEMP volume (40MB needed)!';
      stage:=-2;
      exit;
     end;
     path:=ExtractFileDir(ParamStr(0));
     GetDiskFreeSpaceEx(PChar(path),free,total,@totalfree);
     LogMessage('Free space on target volume: '+SizeToStr(free)+' of '+SizeToStr(total));
     if free<20*1024*1024 then begin
      lab.caption:='ERROR! Not enough space on TARGET volume (20MB needed)!';
      stage:=-2;
      exit;
     end;
     stage:=1;
  end;
  1:begin
     // Waiting for files list
     res:=GetRequestResult(req,response);
     if res=httpStatusFailed then begin
      Failed('can''t connect http://astralheroes.com!');
      exit;
     end;
     if res=httpStatusCompleted then begin
       progress.position:=10;
       application.ProcessMessages;
       filelist:=response;
       lab.Caption:='Processing list of files...';
       stage:=2;
       LogMessage('Start stage 2');
     end;
  end;
  2:begin
     ProcessFileList(filelist);
     if failure then Failed('server error, please try later.');
    end;
  3:begin
     HandleFiles;
     if failure then begin
      Failed('download error, please try later.');
      exit;
     end;
     v1:=0; v2:=0;
     if totalFiles>0 then v1:=processed/totalFiles;
     if totalSize>0 then v2:=downloaded/totalSize;
     progress.position:=10+round(20*v1+70*v2);

     LogMessage(Format('STAGE 3: processed %d / %d  downloaded %d / %d  Progr=%d',
       [processed,totalFiles,downloaded,totalSize,progress.position]));
     lab.Caption:=Format('Downloading files: %d of %d (%s of %s)',
       [downloadedCount,totalCount,SizeToStr(downloaded),sizeToStr(totalSize)]);
    end;
   4:begin
     if dontInstall then begin
      ShowReleaseNotes;
      progress.position:=100;
      lab.caption:='Download complete! Press "Update" to update game files.';
      btn.Caption:='Update';
      stage:=6; exit;
     end;
   end;
   5:begin
     lab.Caption:='Done!';
     progress.Position:=100;
     LogMessage('Launching the game...');
     application.ProcessMessages;
     Sleep(300);
     LaunchProcess('astralheroes.exe');
     Close;
    stage:=99;
   end;
   6:begin

   end;
 end;
 except
  on e:exception do begin
   ForceLogMessage('Fatal error: '+e.message);
   Failed('internal error (see log for details)');
  end;
 end;
end;

end.
