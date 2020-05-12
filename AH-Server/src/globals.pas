unit globals;
interface
 uses windows,ControlFiles2,MyServis,logging;
const
 MAX_CONNECTIONS_LIMIT = 20000;
 MAX_WORKERS           = 10;
 MAX_USERS             = 2000;

 MINUTE =  1/1440;
 SECOND =  1/86400;

type
  TMimeType=record
   extension:UTF8String;
   mimeType:UTF8String;
  end;

  // ���� ��� �������������� ����. ����� �������� pattern, �� ��� ������ ����� ����� ����� ������� ������ �������� cache-control 
  TCacheControl=record
   pattern:UTF8String;
   value:UTF8String;
  end;

  TServerStat=record
   // �������� �������������� ������� �� �������� ����
   sentBytes,  // ������� ������
   recvBytes,
   httpConnections,   // ���-�� ������������� ����������,
   httpRequests,   // ������������ ��������
   httpErrors,  // ���-�� ��������, �� ������� �������� �������
   authErrors, // ���-�� ������ �����������
   tasks,       // ���-�� ����������� ������
   dbQueries,   // ���-�� ����������� �������� � ��
   dbFailures,   // ���-�� ����� ��� ��������� � ��
   failures,      // ���-�� ����� (������� � ��� ���������������� ����)
   logMessages,   // ���-�� ������� � ��� (���� �������)
   duelsStarted,  // ���-�� ��������� ���
   draftsStarted, // ���-�� ����������� �������
   publicMsg,     // ���-�� ������������ ��������� ��������� � ����
   privMsg,       // ���-�� ��������� ��������� � ����
   ipBanned,      // ����������� ���� �� IP
   connDenied,    // ���������� ����������� �� ������� ���� IP
   connBroken,    // ������������ (������������ ��������)
   gdUpdates,     // �������� �� ������ GD
     res:int64;
   // ������������ ��������
   connections, // ���-�� ������������� ����������
   users,      // ���-�� ������ (������� �����)
   usersAlive, // ���-�� ����� ������
   duels,      // ���-�� ���
   drafts,     // ���-�� �������
   cpuUsageKernel, // ������������� ���������� ��������, ����� � ms
   cpuUsageUser,  // ������������� ���������� ��������, ����� � ms
   cpuTotal,   // ������������� ���������� (�������������)
   maxQueue,   // ���� ������ ������� ������
   memoryUsed, // ������� ������ ���������� ������
    res2:integer;
  end;


 TServerState=(ssStarting,ssFailure,ssRunning,ssLimited,ssClosing,ssRestarting);

var
 // ����� �������� ��� ���������� ���������� �� �������
 // ��� ��������� ����������� �� �� ��� ������ ������� � ����� ��������� �����������
 serverStat:TServerStat;

 MAX_CONNECTIONS:integer = 6000; // up to MAX_CONNECTIONS_LIMIT

 INBUF_SIZE:integer = 40000; // ������ ������ �������� ������ (����. ������ �������, �� ������ ���� ������ 4�)
 REQUEST_TIMEOUT:integer = 5000; // 5 ������ - ���� ������ �� ��������� �� ����� �����, ���������� �����������
 KEEP_ALIVE_TIMEOUT:integer = 40000; // 40 ������ ������� �������� keep alive ���������� ����� �������� ������
 DATA_TIMEOUT:integer = 20000; // ����� ����������� comet-������ 20 ������
 USER_TIMEOUT:integer = 35000; // ����� ������������ �����, ����� �������� �� ��������� �� ��������
 NET_LOOP_INTERVAL:integer = 10;  // ���������� �������� ������ �������� ����� � ��������� � ��� ��������
 HTTP_PORT:integer = 80;
 MAX_LOCAL_FILESIZE:integer = 2048*1024; // ������������ ������ ������, ���������� �������� (2048 KB)

 NUM_WORKERS:integer = 3;  // ���-�� �������, �������������� "�������" �������

 MAX_URGENCY:integer = 2;

 SEND_ACAO:boolean=false; // Access-Control-Allow-Origin

 SPARE_SERVER:boolean=false;

 STEAM_API_KEY:UTF8String='';

 LOG_VERBOSITY:byte=logImportant; // minimal level to write to file
 LOG_FLUSH_INTERVAL:byte=50;  // ������������� ������ � ��� (� �������� �������� ����� (1-10 ��))
 // ��� ����� �������� ����������
 LOG_HTTP:boolean=false; // log HTTP requests and responses
 LOG_SQL:boolean=false; // Log all SQL queries
 LOG_TASKS:boolean=false; 

 SERVER_NAME:UTF8String='ApusServer';

 MySQL_HOST:UTF8String='127.0.0.1';
 MySQL_DATABASE:UTF8String='';
 MySQL_LOGIN:UTF8String='';
 MySQL_PASSWORD:UTF8String='';

 serviceMode:boolean=true;
 WorkingDir:UTF8String;
 needExit:boolean=false;
 ctl:TControlFile;

 accessToken,controlToken:UTF8String;

 homeDir:UTF8String; // ���� � ����������� ������
 MimeTypes:array of TMimeType; 
 cacheRules:array of TCacheControl;

 // ����� �������� (���) ����� � ���������� ����� �������� ����������� ���������� ���
 BOT_DELAY_CLASSIC:integer=15;
 BOT_DELAY_CUSTOM:integer=15;
 BOT_DELAY_DRAFT:integer=15;

 BOT_TURN_DELAY:integer=1;
 BOT_ACTION_DELAY:integer=1;

 serverState:TServerState=ssStarting;
 restartTime:TDateTime; // ����� ������������ �������
 restartNotices:integer; // ���-�� ������������ �����������
 welcomeEn,welcomeRu,altWelcomeEn,altWelcomeRu:UTF8String;
 altWelcomeForDate:TDateTime;

 chatFilter:WStringArr; // ������ ����, ������� ���������� �� *** � ����

 // ������ �� ���� ���������� ���������� �� ���� ������� (����� ���������� ��-�����)
 // ������ �������������� ������ ������ ���� ������
 gSect:TMyCriticalSection;

 // HTML templates
 loginPage,adminPage:UTF8String;

 // Currently processed user request
 curUser:integer;
 curUserCmd:UTF8String;

 function ShortMD5(st:UTF8String):UTF8String;

implementation
 uses SysUtils,DCPmd5a;

 function ShortMD5(st:UTF8String):UTF8String;
  begin
   result:=MD5(st);
   setLength(result,10);
  end;

{ TCustomMySQLDatabase }

initialization
 InitCritSect(gSect,'Global',20);
finalization
 DeleteCritSect(gSect);
end.
