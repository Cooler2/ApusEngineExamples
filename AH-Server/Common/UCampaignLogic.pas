// Author: Alexey Stankevich (Apus Software)
unit UCampaignLogic;
interface
uses ULogic,UDeck,Cnsts,types;

type

tCampaignMage=record
 name,fullname:String[31];
 facenum:integer;
 deck:tcampaigndeck;
 deck2:tcampaigndeck;
 actfirst,actsecond:boolean;
 haveritual:boolean;
 startinglife:integer;
 winsrequired:integer;
 specificcharacterrequired:integer;
 reward:integer;                   // 1 card, 2 gold, 3 astral power
 rewardparam:integer;
 location:TPoint;
 arrowDir:integer;
end;

const

CampaignMages:array[1..49] of tCampaignMage=
(
{1}
(
 name:'Novice Necromancer';
 facenum:5;
 deck:(-5,150,-5,151,-5,150,-5,150,-5,151,-5,-5,151,-5,-5);
 actsecond:true;
 startinglife:10;
 location:(x:1770;y:1192);
 arrowDir:1;
),
{2}
(
 name:'Ugruk';
 facenum:12;
 deck:(-5,5,152,-5,-5,3,-5,5,152,5,-5,58,152,12,70);
 actsecond:true;
 startinglife:20;
 location:(x:1864;y:1030);
 arrowDir:1;
),
{3}
(
 name:'Evil Spirit';
 facenum:17;
 deck:(99,-5,53,99,-5,58,99,1,-5,79,99,58,-5,99,79);
 actsecond:true;
 startinglife:25;
// location:(x:1570;y:1195);
 location:(x:1510;y:1185);
),
{4}
(
 name:'Eitheros';
 facenum:10;
 deck:(89,23,-5,143,28,-5,143,23,89,134,-5,132,143,-5,89);
 actsecond:true;
 startinglife:25;
 location:(x:1340;y:905);
 arrowDir:1;
),
{5}
(
 name:'Mendeleev';
 fullname:'Alchemist Mendeleev';
 facenum:18;
 deck:(63,121,-5,142,140,127,-5,142,63,140,55,-5,142,127,121);
 actsecond:true;
 startinglife:25;
// location:(x:1985;y:810);
// location:(x:2018;y:860);
 location:(x:2005;y:850);
),
{6}
(
 name:'Dalibor';
 facenum:15;
 deck:(-5,118,70,50,106,126,70,50,118,126,50,12,126,106,70);
 actsecond:true;
 startinglife:25;
 location:(x:1738;y:784);
),
{7}
(
 name:'Luterius';
 facenum:9;
 deck:(-5,108,73,20,108,89,45,137,108,20,145,20,108,89,20);
 actsecond:true;
 startinglife:25;
 location:(x:1690;y:635);
 arrowDir:1;
),
{8}
(
 name:'Elmiana';
 facenum:6;
 deck:(32,3,-5,38,-5,66,65,38,32,125,-5,65,3,38,125);
 actfirst:true;
 startinglife:27;
 location:(x:1134;y:659);
 arrowDir:1;
),
{9}
(
 name:'Gunertha';
 facenum:19;
 deck:(-5,51,52,69,-5,147,52,-5,12,104,69,52,147,-5,51);
 actsecond:true;
 startinglife:25;
 location:(x:1392;y:475);
),
{10}
(
 name:'Toralvas';
 facenum:13;
 deck:(89,86,132,26,-5,109,86,109,132,-5,26,109,86,132,26);
 actsecond:true;
 startinglife:25;
 location:(x:1395;y:744);
),
{11}
(
 name:'Critana';
 facenum:8;
 deck:(84,70,134,-5,8,84,105,72,-5,70,8,-5,105,134,72);
 actfirst:true;
 startinglife:25;
 location:(x:910;y:810);
),
{12}
(
 name:'Gydda';
 facenum:7;
 deck:(73,108,13,-5,106,73,13,12,106,73,81,-5,14,13,106);
 actsecond:true;
 startinglife:25;
 location:(x:875;y:395);
 arrowDir:1;
),
{13}
(
 name:'Mictiant';
 facenum:14;
 deck:(12,141,-5,15,-5,5,12,5,-5,15,-5,117,141,12,5);
 actsecond:true;
 startinglife:30;
 location:(x:502;y:843);
 arrowDir:1;
),
{14}
(
 name:'Graboth';
 facenum:16;
 deck:(54,47,-5,126,78,-5,127,47,126,78,57,-5,127,47,126);
 actsecond:true;
 startinglife:25;
 location:(x:880;y:585);
 arrowDir:1;
),
{15}
(
 name:'Kevzes';
 facenum:4;
 deck:(139,127,128,60,147,101,127,-5,139,128,10,147,127,128,-5);
 actfirst:true;
 location:(x:1095;y:864);
 arrowDir:1;
),
{16}
(
 name:'Erigar';
 fullname:'Erigar, keeper of the coast';
 facenum:1;
 deck:(34,-5,41,132,66,89,34,93,90,132,66,89,34,93,132);
 haveritual:true;
// location:(x:1130;y:1380);
 location:(x:1035;y:1375);
 arrowDir:1;
),
{17}
(
 name:'Cooler';
 fullname:'Cooler, lord of Wind';
 facenum:21;
 deck:(20,149,25,22,118,25,149,82,3,22,82,149,25,14,22);
 actsecond:true;
 haveritual:true;
 location:(x:1170;y:1574);
),
{18}
(
 name:'Estarh';
 fullname:'Estarh, lord of Chaos';
 facenum:2;
 deck:(-5,4,94,12,-5,105,-5,4,94,15,-5,-5,4,94,-5);
 actsecond:true;
 haveritual:true;
 location:(x:540;y:1756);
),
{19}
(
 name:'Yngreed';
 fullname:'Yngreed, lord of War';
 facenum:11;
 deck:(99,143,122,90,70,26,136,99,62,143,70,35,26,99,143);
 haveritual:true;
 location:(x:834;y:1525);
),
{20}
(
 name:'Kevzes';
 facenum:4;
 deck:(4,126,139,130,70,53,68,148,126,119,70,10,55,128,4);
 haveritual:true;
 location:(x:516;y:1623);

),
{21}
(
 name:'Player';
 deck:(70,153,35,12,75,153,70,153,35,153,12,153,75,153,70);
 startinglife:25;
),
{22}
(
 name:'Player';
 deck:(35,38,75,65,70,12,42,35,65,38,70,75,38,65,70);
 startinglife:25;
),
{23}
(
 name:'Player';
 deck:(5,38,35,31,70,65,41,12,43,38,75,70,65,38,42);
 startinglife:25;
),
{24}
(
 name:'Player';
 deck:(72,48,154,134,109,72,127,48,154,109,134,127,72,48,134);
 startinglife:25;
),
{25}
(
 name:'Player';
 deck:(132,127,72,134,143,48,19,109,87,132,127,72,134,48,109);
 startinglife:25;
),
{26}
(
 name:'Player';
 deck:(48,143,58,72,132,127,87,109,23,48,72,127,109,134,132);
 startinglife:25;
),
{27}(),
{28}(),
{29}(),
{30}(),
{31}(),
{32}(),
{33}(),
{34}(),
{35}(),
{36}(),
{37}(),
{38}{Dungeon of Shadows}(facenum:17; location:(x:1360;y:885);arrowDir:1),
{39}{Colosseum}(facenum:9; location:(x:760;y:1000)),
{40}(),
{41}
(
 name:'Hermit';
 fullname:'Deranged Hermit';
 facenum:15;
 deck:(41,41,94,94,35,68,126,127,127,44,44,33,33,31,1);
 startinglife:30;
 location:(x:1098;y:456);
 arrowDir:1;
),
{42}
(
 name:'Adept';
 fullname:'Adept of Fiery Wind';
 facenum:8;
 deck:(20,102,118,118,82,82,142,142,134,70,12,3,3,89,14);
 startinglife:30;
// location:(x:716;y:1004);
 location:(x:500;y:843);
 arrowDir:1;
),
{43}
(
 name:'Demon''s Servant';
 facenum:2;
 deck:(143,143,20,49,49,101,101,101,100,100,147,148,67,51,127);
 startinglife:30;
 location:(x:1738;y:460);
),
{44}
(
 name:'Goblin Leader';
 facenum:20;
 deck:(2,2,9,9,118,118,13,13,70,70,4,4,3,14,14);
 startinglife:30;
 location:(x:2065;y:1395);
 arrowDir:1;
),
{45}
(
 name:'Cursed Mage';
 facenum:3;
 deck:(118,118,85,99,80,101,101,46,100,-5,148,117,53,53,59);
 startinglife:30;
 location:(x:1510;y:1185);
),
{46}
(
 name:'Forest Witch';
 facenum:19;
 deck:(131,131,113,113,16,16,70,70,32,32,4,4,3,38,38);
 startinglife:30;
 location:(x:2030;y:980);
),
{47}
(
 name:'Dark Elf';
 facenum:5;
 deck:(47,47,128,128,95,36,103,135,135,127,127,126,125,125,-5);
 startinglife:30;
 location:(x:1390;y:470);
),
{48}
(
 name:'Insanian Lord';
 facenum:10;
 deck:(61,61,20,20,118,118,63,63,70,70,143,3,7,12,26);
 startinglife:30;
 location:(x:1570;y:860);
 arrowDir:1;
),
{49}
(
 name:'Adept';
 fullname:'Adept of Chance';
 facenum:11;
 deck:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
 startinglife:30;
 location:(x:1770;y:1192);
 arrowDir:1;
));

// IMPORTANT!!! Для сценариев 1..3 нужно запускать не только для соперника, но и для игрока!
// Втч и на сервере!
// losesNum - кол-во поражений конкретному противнику
procedure preparePlayer(var pli:tplayerinfo;campaignCharacterNum,losesNum:integer);

implementation
uses sysutils;

procedure preparePlayer(var pli:tplayerinfo;campaignCharacterNum,losesNum:integer);
var q,w,e:integer;
begin
 fillchar(pli,sizeof(pli),0);
 pli.Name:=CampaignMages[campaignCharacterNum].name;
 if CampaignMages[campaignCharacterNum].fullname<>'' then
  pli.FullName:=CampaignMages[campaignCharacterNum].fullname
 else
  pli.FullName:=pli.name;
 pli.FaceNum:=CampaignMages[campaignCharacterNum].facenum;
 pli.ForcedLife:=CampaignMages[campaignCharacterNum].startinglife;
 pli.ForcedFirst:=CampaignMages[campaignCharacterNum].actfirst;
 pli.ForcedSecond:=CampaignMages[campaignCharacterNum].actsecond;
 pli.SkipRitual:=not(CampaignMages[campaignCharacterNum].haveritual);
 case campaignCharacterNum of
  1..15:begin
         if losesNum<=0 then
          pli.control:=3
         else
          pli.control:=1;
        end;
  16..20:if losesNum<=0 then
          pli.control:=3
         else
         begin
          if losesnum=1 then
           pli.control:=2
          else
           pli.control:=1;
         end;
  41..49:if losesnum=0 then
          pli.control:=3
         else
          pli.control:=5;
 end;
 pli.Deck.ImportCampaignDeck(CampaignMages[campaignCharacterNum].deck);
 if (losesNum=-1)and(campaignCharacterNum<=15) then
 begin
  for q:=30 downto 1 do
  if pli.Deck.cards[q]=-5 then
  begin
   for w:=q downto 2 do
    pli.Deck.cards[w]:=pli.Deck.cards[w-1];
   pli.Deck.cards[1]:=pli.Deck.cards[10];
   break;
  end;
 end;
 if campaignCharacterNum>=40 then
  pli.Deck.MutateDeck(4);
 if (campaignCharacterNum>=40)or((campaignCharacterNum in [16..20])and(losesnum>0)) then
  pli.Deck.Shuffle;
 if campaignCharacterNum=49 then
  pli.Deck.GenerateRandom(1);
 pli.Deck.Name:='CMPD#'+inttostr(campaignCharacterNum)+'#';
 pli.CurDeck:=pli.Deck;
end;

end.
