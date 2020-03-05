program website;
uses
  MyServis,
  SysUtils,
  Logging,
  Classes,
  SCGI,
  globals in 'globals.pas',
  site in 'site.pas',
  ranking in 'ranking.pas',
  forum in 'forum.pas',
  search in 'search.pas';

var
 msg:TStringList;
begin
 SetCurrentDir(ExtractFileDir(ParamStr(0)));
 if FileExists('scgi.log') then RenameFile('scgi.log','scgi.old');
 UseLogFile('scgi.log');
 LogCacheMode(true,false,false);
 InitLogging(10,'logs',logInfo);

 SCGI.Initialize;
 AddHandler('/',IndexPage); 
 AddHandler('*',IndexPage);
 AddHandler('login',LoginRequest);
 AddHandler('logout',LogoutRequest);
 AddHandler('ranking',RankingRequest);
 AddHandler('profile',ProfileRequest);
 AddHandler('account',AccountRequest);
 AddHandler('attach',AttachFileRequest);
 AddHandler('getfile',GetFileRequest);
 AddHandler('uploadimage',UploadImageRequest);
 AddHandler('postmsg',PostMsgRequest);
 AddHandler('forumthread',ThreadRequest);
 AddHandler('chapter',ChapterRequest);
 AddHandler('getpage',PageRequest);
 AddHandler('search',SearchRequest);
 AddHandler('IndexForum',IndexForumRequest); 
 AddHandler('ListHeaders',ListHeaders);
 AddHandler('DumpData',DumpData);
 AddHandler('GetDeckList',GetDeckList);
// AddHandler('duelstat',DuelStat);
 initProc:=InitSite;
 SCGI.RunServer;
end.
