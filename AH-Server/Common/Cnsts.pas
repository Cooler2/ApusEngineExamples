
// Author: Alexey Stankevich (Apus Software)
{$WARNINGS OFF}
unit Cnsts;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
const

netVersion:integer=001;  // not used

sVersion:string='v 1.2a';
version:integer=01201;    //
minVersion:integer=01200; // Минимальная версия, которую разрешено пускать на сервер без автоапдейта

elementnames:array[0..5] of string[10]=('^All cards^','^Order^','^Chaos^','^Life^','^Death^','^^');
ainames:array[1..17] of string[32]=('^Novice Mage^','^Advanced Mage^','^Expert Mage^','^Magister^','^Archmage^','^Supreme Mage^','Expmage7','Expmage8','Expmage9','CMP Mage','Expmage11','Expmage12','Expmage13','Expmage14','Expmage15','BM Mutated','Supreme Mage II');
aiclassiclevels:array[1..6] of integer=(2,4,8,12,20,30);
TitleNames:array[1..6] of string[32]=('Novice Mage','Mage','Advanced Mage','Expert Mage','Magister','Archmage');
GuildRankNames:array[0..3] of string[32]=('','Recruit','Veteran','Guild Master');
GuildExpRequied:array[1..30] of integer=(0,300,500,750,1200,2000,3000,5000,7500,12000,20000,30000,50000,75000,120000,200000,300000,500000,750000,1200000,2000000,3000000,5000000,7500000,12000000,20000000,30000000,50000000,75000000,120000000);
GuildUpgradeCosts:array[1..4] of integer=(100,200,500,1000);

// официально поддерживаемые языки
languageCodes:array[0..1] of string[8]=('en','ru');
languagedesc:array[0..1] of string[8]=('eng','rus');
languagenames:array[0..1] of WideString=('English','Русский');
// Другие языки, которые могут быть изначально выбраны
userLangCodes:array[0..1] of string=('es','fr');
userLangFiles:array[0..1] of string=('language_HR.es','language_AR.fr');

guildcards:array[1..20] of integer=(111,121,85,34,50,  122,86,13,76,60,  27,117,125,136,80,  88,130,94,104,146);

numAIthreads=4;

numServerthreads=10;

AIMaxWidth=2000;

//needdrafttesting=true;
needdrafttesting=false;

//needdecksgenerating=true;
needdecksgenerating=false;


AICasheSize=10000;

numDraftCards=20;
draftc=12;

{$IFDEF LOCAL}
localtesting:boolean=true;
{$ELSE}
localtesting:boolean=false;
{$ENDIF}

//localtesting:boolean=false;

resizeselected=false;
xresize=2;
yresize=3;
scaleX:single=1.0;

type

tCardInfo=record
 name:string;
 translatednames:array[0..5] of string;
 mentalcost:integer;
 element,cost:integer;
 damage,life:integer;       // if life=0, spell
 bonus:integer;             // 10=1
 basicfrequency:integer;
 draftfrequency:integer;
 logicparam,logicparam2:integer;
 desc:string;
 killAIeffect:integer;
 drawAIeffect:integer;
 isElf:boolean;
 isVampire:boolean;
 badstart,killcard,drawcard:boolean;
 requiretarget:boolean;
 targettype:integer;        // 0-any,1 - only opponents, 2- only self
 abilitycost:integer;       // 0 - нет абилки, -1 значит нулевая стоимость по мане
 abilityrequiretarget:boolean;
 abilitytargettype:integer;        // 0-any,1 - only opponents, 2- only self
 dangerousability:boolean;
 abilityrequirecard:boolean;
 power1,powercost,power10:byte;
 ignoreforhand:boolean;
 autoeffect:boolean;
 effecttoenemycreatures:boolean;
 skiplandingeffect:boolean;
 special:boolean;
 guild:boolean;
 basic:boolean;
 mutationimpossible:boolean;
 overrideEffect:integer; // указывает на необходимость использования нестандартного выбора эффектов
 soundEffect:string;
 imageFrom:integer;
end;

tBonusInfo=record
 name:string;
 desc:string;
 imagenum:integer;
end;

const

mincard=-5;
numcards=162;
maxcardsamount=136*6;

type tCardinfoArray=array[mincard..numcards] of tcardinfo;
tconsts=object
 iCardinfo:tCardinfoArray;
 inetVersion:integer;
 isVersion:string[31];
 iversion:integer;
 procedure importdata;
 procedure exportdata;
end;


const

DefCardInfo:tCardinfoArray=
(
{-5}
(name:'Unplayable card';
 cost:1000000;
 desc:'Unplayable card. For campaign only';
 power1:0;
 powercost:0;
 power10:0;
 special:true;
),
{-4}
(name:'Exhaustion';
 mentalcost:0;
 element:0;
 cost:0;
 logicparam:2;
 desc:'On Turn 20, you begin taking damage on the start of your turn. This damage increases each turn.';
 special:true;
 imageFrom:-3;
),
{-3}
(name:'Mana Storm';
 mentalcost:0;
 element:0;
 cost:2;
 logicparam:2;
 desc:'Player''s ability^, ^costs 2 mana and 2 spell power^~^Deal %1 damage to all enemy creatures and draw a card.^~~^This ability may only be used while you have no cards in your hand.';
 special:true;
),
{-2}
(name:'Sheep';
 mentalcost:0;
 element:0;
 cost:0;
 damage:2;
 life:2;
 desc:'';
 power1:20;
 powercost:20;
 power10:20;
 special:true;
),
{-1}
(name:'Ritual of Power';
 desc:'Gain 1 mana.~You cannot replace this card.';
 power1:30;
 powercost:30;
 power10:5;
 special:true;
),
(
 power1:110;
 powercost:110;
 power10:110;
 special:true;
),
{1}
(name:'Unholy Monument';
 mentalcost:30;
 element:4;
 cost:3;
 damage:0;
 life:18;
 bonus:35;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:3;
 desc:'Ability~Increase the attack of another creature~by %1 until the end of your turn.';
 abilitycost:-1;
 abilityrequiretarget:true;
 power1:90;
 powercost:110;
 power10:100;
 basic:true;
),
{2}
(name:'Goblin Pyromancer';
 mentalcost:10;
 element:2;
 cost:3;
 damage:4;
 life:15;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:4;
 desc:'Ability~Deal %1 damage to any creature.~Goblin Pyromancer may only use this ability while unopposed.';
 abilitycost:-1;
 abilityrequiretarget:true;
 power1:100;
 powercost:110;
 power10:80;
 soundEffect:'AbilityAggressive';
),
{3}
(name:'Lightning Bolt';
 mentalcost:20;
 element:2;
 cost:3;
 life:0;
 basicfrequency:6;
 draftfrequency:4;
 logicparam:20;
 desc:'Deal %1 damage to an enemy creature.';
 killAIeffect:8;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:105;
 powercost:105;
 power10:95;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{4}
(name:'Fire Ball';
 mentalcost:60;
 element:2;
 cost:2;
 life:0;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:12;
 logicparam2:4;
 desc:'Deal %1 damage to an enemy creature,~and %2 damage to all other enemy creatures.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:120;
 powercost:120;
 power10:100;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{5}
(name:'Orc Trooper';
 mentalcost:5;
 element:2;
 cost:2;
 damage:4;
 life:15;
 bonus:5;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Ability~Add an Orc Trooper card into your hand.';
 drawAIeffect:4;
 abilitycost:4;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
),
{6}
(name:'Orc Berserker';
 mentalcost:30;
 element:2;
 cost:2;
 damage:4;
 life:14;
 basicfrequency:6;
 draftfrequency:5;
 desc:'If Orc Berserker receives damage during your turn,~its attack is permanently increased~by an amount equal to that damage.';
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
 mutationimpossible:true;
),
{7}
(name:'Orc Mystic';
 mentalcost:55;
 element:2;
 cost:3;
 damage:3;
 life:15;
 bonus:5;
 basicfrequency:3;
 draftfrequency:5;
 logicparam:numcards;
 desc:'When you summon Orc Mystic,~add a random Chaos spell to your hand.';
 drawcard:true;
 power1:110;
 powercost:120;
 power10:140;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{8}
(name:'Battle Priest';
 mentalcost:15;
 element:2;
 cost:3;
 damage:4;
 life:16;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:4;
 desc:'Whenever an adjacent or opposing creature dies,~Battle Priest''s attack is permanently increased by %1.';
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
),
{9}
(name:'Goblin Chieftain';
 mentalcost:10;
 element:2;
 cost:3;
 damage:3;
 life:19;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:2;
 desc:'Goblin Chieftain increases the attack of adjacent creatures by %1.';
 power1:100;
 powercost:100;
 power10:90;
 skiplandingeffect:true;
 basic:true;
),
{10}
(name:'Planar Burst';
 mentalcost:85;
 element:2;
 cost:3;
 life:0;
 basicfrequency:4;
 draftfrequency:3;
 logicparam:14;
 desc:'Deal %1 damage to ALL creatures.';
 killAIeffect:8;
 badstart:true;
 killcard:true;
 power1:100;
 powercost:100;
 power10:100;
 autoeffect:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{11}
(name:'Priest of Fire';
 mentalcost:65;
 element:2;
 cost:3;
 damage:2;
 life:16;
 bonus:10;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:2;
 desc:'Whenever an ally creature uses an ability,~Priest of Fire deals %1 damage to the opponent~and all enemy creatures.';
 power1:90;
 powercost:110;
 power10:110;
 basic:true;
 mutationimpossible:true;
),
{12}
(name:'Flame Wave';
 mentalcost:25;
 element:2;
 cost:3;
 life:0;
 basicfrequency:4;
 draftfrequency:5;
 logicparam:8;
 desc:'Deal %1 damage to all enemy creatures.';
 killAIeffect:12;
 killcard:true;
 power1:100;
 powercost:100;
 power10:100;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{13}
(name:'Goblin Saboteur';
 mentalcost:60;
 element:2;
 cost:4;
 damage:3;
 life:10;
 basicfrequency:8;
 draftfrequency:5;
 desc:'When you summon Goblin Saboteur,~the opponent loses 1 spell power.';
 power1:80;
 powercost:110;
 power10:80;
 ignoreforhand:true;
 skiplandingeffect:true;
 guild:true;
),
{14}
(name:'Chain Lightning';
 mentalcost:35;
 element:2;
 cost:5;
 life:0;
 basicfrequency:7;
 draftfrequency:6;
 desc:'Deal damage equal to your spell power~to the opponent and all enemy creatures.';
 killAIeffect:7;
 power1:30;
 powercost:90;
 power10:200;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{15}
(name:'Dragon';
 mentalcost:30;
 element:2;
{ cost:8;
 damage:8;
 life:32;}
 cost:7;
 damage:7;
 life:30;
 bonus:20;
 basicfrequency:8;
 draftfrequency:5;
 logicparam:12;
 logicparam2:4;
 desc:'Ability~Deal %1 damage to an enemy creature,~and %2 damage to all other enemy creatures.';
 abilitycost:2;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:30;
 powercost:180;
 power10:180;
 basic:true;
),
{16}
(name:'Forest Sprite';
 mentalcost:30;
 element:3;
 cost:2;
 damage:4;
 life:14;
 bonus:-1;
 basicfrequency:4;
 draftfrequency:3;
 logicparam:8;
 desc:'Ability~Deal %1 damage to an enemy creature. This ability may only be used~if Forest Sprite was summoned during this turn.';
 killAIeffect:2;
 badstart:true;
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:100;
 powercost:110;
 power10:110;
),
{(name:'Forest Sprite';
 mentalcost:85;
 element:3;
 cost:3;
 damage:3;
 life:8;
 bonus:10;
 basicfrequency:3;
 draftfrequency:2;
 desc:'Whenever you summon a creature~adjacent to Forest Sprite, draw a card.';
 drawAIeffect:7;
 drawcard:true;
 power1:80;
 powercost:100;
 power10:150;
),}
{17}
(name:'Crusader';
 mentalcost:20;
 element:1;
 cost:3;
 damage:4;
 life:15;
 bonus:10;
 basicfrequency:8;
 draftfrequency:5;
 desc:'Whenever Crusader deals damage directly~to the opponent, you gain 1 spell power.~Ability~Move Crusader to target empty slot.';
 abilitycost:2;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:90;
 basic:true;
),
{18}
(name:'Clone';
 mentalcost:65;
 element:3;
 cost:0;
 life:0;
 basicfrequency:9;
 draftfrequency:5;
 desc:'Add a copy of any creature on the board to your hand.';
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
 soundEffect:'SpellNeutral';
),
{19}
(name:'Templar';
 mentalcost:30;
 element:1;
 cost:5;
 damage:5;
 life:24;
 bonus:10;
 basicfrequency:3;
 draftfrequency:3;
 logicparam:5;
 desc:'Ability~Decrease Templar''s attack by %1 until~the end of your turn, and draw a card.';
 drawAIeffect:9;
 drawcard:true;
 abilitycost:1;
 power1:60;
 powercost:110;
 power10:150;
 basic:true;
),
{20}
(name:'Apprentice';
 mentalcost:30;
 element:1;
 cost:2;
 damage:1;
 life:6;
 basicfrequency:7;
 draftfrequency:5;
 desc:'When you summon Apprentice, gain 1 spell power.';
 power1:140;
 powercost:140;
 power10:50;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{21}
(name:'Justice';
 mentalcost:25;
 element:1;
 cost:2;
 life:0;
 basicfrequency:4;
 draftfrequency:5;
 desc:'Deal damage to each enemy creature equal to its attack.~Then, the opponent discards the first card in their hand.';
 killAIeffect:3;
 badstart:true;
 killcard:true;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
 soundEffect:'SpellDamage';
),
{22}
(name:'Tornado Gust';
 mentalcost:80;
 element:1;
 cost:0;
 life:0;
 basicfrequency:8;
 draftfrequency:4;
 logicparam:2;
 desc:'Return a creature to its owner''s hand.~If you target an ally creature with this spell, gain %1 mana.';
 badstart:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:50;
 basic:true;
 mutationimpossible:true;
 soundEffect:'SpellNeutral';
),
{23}
(name:'Warlord';
 mentalcost:10;
 element:1;
 cost:3;
 damage:5;
 life:16;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Warlord increases the attack~of all other ally creatures by 1.';
 power1:90;
 powercost:105;
 power10:80;
 skiplandingeffect:true;
 basic:true;
),
{24}
(name:'Inquisitor';
 mentalcost:60;
 element:1;
 cost:3;
 damage:3;
 life:14;
 bonus:5;
 basicfrequency:8;
 draftfrequency:4;
 desc:'Whenever you kill any creature with a spell,~Inquisitor raises your spell power by 1.';
 power1:110;
 powercost:130;
 power10:80;
 basic:true;
),
{25}
(name:'Spiritual Chains';
 mentalcost:25;
 element:1;
 cost:6;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Remove any creature from the board and add it to your hand.';
 killAIeffect:10;
 killcard:true;
 requiretarget:true;
 power1:50;
 powercost:125;
 power10:160;
 basic:true;
 soundEffect:'SpellNeutral';
),
{26}
(name:'Inspiration';
 mentalcost:50;
 element:1;
 cost:1;
 life:0;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:3;
 desc:'Increase the attack of all ally creatures~by %1 until the end of your turn.';
 badstart:true;
 power1:90;
 powercost:90;
 power10:80;
 basic:true;
 mutationimpossible:true;
 soundEffect:'SpellNeutral';
),
{27}
(name:'Bishop';
 mentalcost:65;
 element:1;
 cost:2;
 damage:3;
 life:8;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:3;
 desc:'When you summon Bishop, gain %1 mana.';
 power1:150;
 powercost:150;
 power10:60;
 ignoreforhand:true;
 skiplandingeffect:true;
 guild:true;
),
{28}
(name:'Vindictive Angel';
 mentalcost:20;
 element:1;
 cost:7;
 damage:5;
 life:30;
 bonus:30;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Vindictive Angel doubles all damage~done to enemy creatures.';
 power1:40;
 powercost:160;
 power10:160;
 basic:true;
),
{29}
(name:'Newfound Truth';
 mentalcost:35;
 element:1;
 cost:6;
 life:0;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Choose an unopposed enemy creature.~It moves to the opposing empty slot,~and becomes an ally creature.';
 killAIeffect:8;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:50;
 powercost:140;
 power10:150;
),
{30}
(name:'Divine Justice';
 mentalcost:20;
 element:1;
 cost:5;
 life:0;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:12;
 logicparam2:12;
 desc:'Restore %1 life to one creature,~and deal %2 damage to all other creatures.';
 killAIeffect:9;
 requiretarget:true;
 targettype:0;
 power1:70;
 powercost:115;
 power10:125;
 autoeffect:true;
 basic:true;
 soundEffect:'SpellNeutral';
),
{31}
(name:'Leprechaun';
 mentalcost:5;
 element:3;
 cost:1;
 damage:3;
 life:10;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:4;
 desc:'Ability~Restore %1 life to wounded adjacent creatures.';
 abilitycost:1;
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
),
{32}
(name:'Elven Scout';
 mentalcost:20;
 element:3;
 cost:1;
 damage:3;
 life:8;
 bonus:5;
 basicfrequency:5;
 draftfrequency:4;
 desc:'Ability~Move Elven Scout to target empty slot.';
 isElf:true;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:120;
 powercost:120;
 power10:50;
 basic:true;
),
{33}
(name:'Elven Ritual';
 mentalcost:60;
 element:3;
 cost:0;
 life:0;
 basicfrequency:8;
 draftfrequency:5;
 logicparam:2;
 logicparam2:2;
 desc:'Gain %1 mana and %2 life.';
 power1:120;
 powercost:120;
 power10:10;
 basic:true;
),
{34}
(name:'Dryad';
 mentalcost:10;
 element:3;
 cost:1;
 damage:3;
 life:10;
 bonus:5;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Dryad''s attack is permanently increased by 1.~Then, if Dryad''s attack is 6 or higher, draw a card.';
 abilitycost:1;
 power1:120;
 powercost:120;
 power10:75;
 guild:true;
),
{35}
(name:'Halfling';
 mentalcost:50;
 element:3;
 cost:1;
 damage:2;
 life:5;
{damage:5;
 life:25;}
 basicfrequency:3;
 draftfrequency:4;
 desc:'When you summon Halfling, draw a card.';
 drawAIeffect:4;
 drawcard:true;
 power1:120;
 powercost:120;
 power10:120;
 skiplandingeffect:true;
 basic:true;
),
{36}
(name:'Elven Bard';
 mentalcost:40;
 element:3;
 cost:2;
 damage:2;
 life:13;
 bonus:8;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Target ally creature immediately performs an extra attack.';
 isElf:true;
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:100;
 basic:true;
),
{37}
(name:'Elven Lord';
 mentalcost:80;
 element:3;
 cost:5;
 damage:6;
 life:24;
 bonus:35;
 basicfrequency:7;
 draftfrequency:4;
 logicparam:3;
 desc:'Whenever you summon another Elf, draw a card.~Ability~Deal %1 damage to an enemy creature.`el';
 drawAIeffect:2;
 isElf:true;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:80;
 powercost:120;
 power10:140;
 skiplandingeffect:true;
 mutationimpossible:true;
 soundEffect:'AbilityAggressive';
),
{38}
(name:'Elven Archer';
 mentalcost:5;
 element:3;
 cost:2;
 damage:3;
 life:12;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:4;
 desc:'Ability~Deal %1 damage to an enemy creature.`ea';
 killAIeffect:2;
 isElf:true;
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
),
{39}
(name:'Elven Priest';
 mentalcost:25;
 element:3;
 cost:2;
 damage:3;
 life:14;
 bonus:20;
 basicfrequency:7;
 draftfrequency:5;
 desc:'At the beginning of your turn,~Elven Priest grants you 1 additional mana.';
 isElf:true;
 power1:120;
 powercost:120;
 power10:60;
 basic:true;
),
{40}
(name:'Faerie Mage';
 mentalcost:40;
 element:3;
 cost:1;
 damage:3;
 life:9;
 bonus:5;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Deal damage to the opponent equal to your spell power.';
 abilitycost:5;
 power1:110;
 powercost:110;
 power10:140;
 basic:true;
),
{41}
(name:'Ancient Zubr';
 mentalcost:10;
 element:3;
 cost:3;
 damage:2;
 life:20;
 bonus:25;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Ancient Zubr attack two times per turn.~Ability~Permanently increase Ancient Zubr''s attack by 1.';
 abilitycost:2;
 power1:90;
 powercost:110;
 power10:110;
 basic:true;
),
{42}
(name:'Unicorn';
 mentalcost:15;
 element:3;
 cost:4;
 damage:6;
 life:18;
 bonus:20;
 basicfrequency:8;
 draftfrequency:5;
 desc:'Spell damage that would be dealt to Unicorn~is converted to healing instead.';
 power1:80;
 powercost:110;
 power10:110;
 basic:true;
),
{43}
(name:'Archivist';
 mentalcost:20;
 element:3;
 cost:4;
 damage:4;
 life:20;
 bonus:20;
 basicfrequency:3;
 draftfrequency:4;
 desc:'Ability~Draw a card.`ar';
 drawAIeffect:8;
 drawcard:true;
 abilitycost:2;
 power1:65;
 powercost:90;
 power10:150;
 basic:true;
),
{44}
(name:'Pure Knowledge';
 mentalcost:40;
 element:3;
 cost:5;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:3;
 desc:'Draw %1 cards.';
 drawAIeffect:10;
 drawcard:true;
 power1:60;
 powercost:100;
 power10:160;
 basic:true;
 soundeffect:'spellgood';
),
{45}
(name:'Rejuvenation';
 mentalcost:50;
 element:3;
 cost:6;
 basicfrequency:3;
 draftfrequency:2;
 logicparam:8;
 logicparam2:2;
 desc:'Gain %1 life and draw %2 cards.';
 drawAIeffect:7;
 drawcard:true;
 power1:50;
 powercost:90;
 power10:140;
 basic:true;
 soundeffect:'spellgood';
),
{46}
(name:'Soul Burst';
 mentalcost:40;
 element:4;
 cost:0;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Destroy an opposed ally creature, then destroy~the enemy creature that is opposing it.';
 killAIeffect:5;
 badstart:true;
 requiretarget:true;
 targettype:2;
 power1:90;
 powercost:90;
 power10:90;
 mutationimpossible:true;
 soundeffect:'spelldestroy';
),
{47}
(name:'Vampire Initiate';
 mentalcost:15;
 element:4;
 cost:1;
 damage:3;
 life:10;
 bonus:5;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:5;
 desc:'When Vampire Initiate kills any creature,~he transforms into a Vampire Mystic and heals %1 life.';
 isvampire:true;
 power1:120;
 powercost:120;
 power10:65;
 basic:true;
),
{48}
(name:'Steal Essence';
 mentalcost:50;
 element:4;
 cost:1;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:5;
 desc:'Deal %1 damage to any creature,~then add a copy of that creature to your hand.';
 killAIeffect:4;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:120;
 powercost:120;
 power10:130;
 autoeffect:true;
 basic:true;
 soundEffect:'SpellDamage,vol=40%';
),
{49}
(name:'Adept of Darkness';
 mentalcost:30;
 element:4;
 cost:2;
 damage:3;
 life:14;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:3;
 desc:'Ability~Destroy target ally creature, and gain %1 mana.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:105;
 powercost:105;
 power10:70;
 basic:true;
),
{50}
(name:'Reaver';
 mentalcost:60;
 element:4;
 cost:2;
 damage:4;
 life:15;
 basicfrequency:3;
 draftfrequency:5;
 desc:'Whenever either player''s spell power is reduced~by a creature or spell, draw a card.';
 power1:100;
 powercost:100;
 power10:80;
 guild:true;
 mutationimpossible:true;
),
{51}
(name:'Cull the Weak';
 mentalcost:30;
 element:4;
 cost:2;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:3;
 desc:'Destroy any creature whose cost is %1 or lower.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
 soundeffect:'spelldestroy';
),
{52}
(name:'Dark Knight';
 mentalcost:35;
 element:4;
 cost:2;
 damage:3;
 life:15;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Whenever an ally creature uses an ability,~Dark Knight''s attack is permanently increased by 2.';
 power1:100;
 powercost:100;
 power10:90;
 basic:true;
 mutationimpossible:true;
),
{53}
(name:'Lich';
 mentalcost:20;
 element:4;
 cost:5;
 damage:5;
 life:15;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:5;
 desc:'When you summon Lich, deal %1 damage~to the opponent and all enemy creatures.';
 power1:70;
 powercost:110;
 power10:130;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{54}
(name:'Vampire Mystic';
 mentalcost:25;
 element:4;
 cost:3;
 damage:4;
 life:20;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:5;
 logicparam2:4;
 desc:'When Vampire Mystic kills any creature,~he transforms into a Vampire Elder and heals %1 life.~Ability~Deal %2 damage to any creature.`vm';
 isvampire:true;
 abilitycost:2;
 abilityrequiretarget:true;
 power1:90;
 powercost:110;
 power10:110;
 basic:true;
),
{55}
(name:'Soul Trap';
 mentalcost:50;
 element:4;
 cost:2;
 damage:0;
 life:8;
 bonus:40;
 basicfrequency:7;
 draftfrequency:4;
 desc:'Whenever an enemy creature dies,~Soul Trap raises your spell power by 1.';
 badstart:true;
 power1:100;
 powercost:120;
 power10:95;
 basic:true;
),
{56}
(name:'Soul Hunter';
 mentalcost:10;
 element:4;
 cost:4;
 damage:4;
 life:22;
 bonus:10;
 basicfrequency:8;
 draftfrequency:5;
 logicparam:4;
 desc:'Whenever Soul Hunter kills a creature,~add a copy of that creature to your hand.~Ability~Deal %1 damage to any creature.`sh';
 killAIeffect:3;
 drawAIeffect:3;
 abilitycost:2;
 abilityrequiretarget:true;
 power1:70;
 powercost:110;
 power10:120;
 basic:true;
),
{57}
(name:'Vampire Elder';
 mentalcost:80;
 element:4;
 cost:5;
 damage:5;
 life:30;
 bonus:15;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:5;
 desc:'Whenever you summon another Vampire, draw a card.~Ability~Deal %1 damage to all enemy creatures.`ve';
 isvampire:true;
 abilitycost:3;
 power1:70;
 powercost:120;
 power10:170;
 basic:true;
 mutationimpossible:true;
),
{58}
(name:'Touch of Death';
 mentalcost:45;
 element:4;
 cost:4;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:4;
 desc:'Destroy any creature and gain %1 life.';
 killAIeffect:10;
 killcard:true;
 requiretarget:true;
 power1:90;
 powercost:120;
 power10:120;
 basic:true;
 soundeffect:'spelldestroy';
),
{59}
(name:'Vampire Lord';
 mentalcost:30;
 element:4;
 cost:6;
 damage:6;
 life:36;
 bonus:20;
 basicfrequency:6;
 draftfrequency:4;
 desc:'Whenever an ally creature deals damage,~that creature''s attack is permanently increased by 2.';
 isvampire:true;
 power1:50;
 powercost:120;
 power10:120;
),
{60}
(name:'Spiritual Plague';
 mentalcost:70;
 element:4;
 cost:6;
 basicfrequency:7;
 draftfrequency:4;
 desc:'Destroy a creature, as well as all other creatures~whose cost is lower than that creature''s cost.';
 killAIeffect:9;
 requiretarget:true;
 power1:80;
 powercost:120;
 power10:130;
 guild:true;
 soundeffect:'spelldestroy';
),
{61}
(name:'Insanian Wizard';
 mentalcost:35;
 element:2;
 cost:4;
 damage:4;
 life:20;
 bonus:10;
 basicfrequency:3;
 draftfrequency:5;
 desc:'Ability~Transform an ally creature into a 2/2 Sheep, and draw a card.';
 drawAIeffect:6;
 drawcard:true;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:110;
),
{62}
(name:'Orc Shaman';
 mentalcost:30;
 element:2;
 cost:1;
 damage:3;
 life:9;
 bonus:5;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:3;
 desc:'Ability~Deal %1 damage to the opponent. Orc Shaman may use~this ability multiple times in the same turn.';
 abilitycost:3;
 power1:100;
 powercost:100;
 power10:150;
 basic:true;
),
{63}
(name:'Polymorph';
 mentalcost:40;
 element:1;
 cost:2;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Transform any creature into a 2/2 Sheep.';
 killAIeffect:8;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
 soundEffect:'SpellNeutral';
),
{64}
(name:'Bastion of Order';
 mentalcost:15;
 element:1;
 cost:6;
 damage:0;
 life:60;
 bonus:35;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:12;
 logicparam2:12;
 desc:'Ability~Deal %1 damage to any creature,~and %2 damage to Bastion of Order.';
 killAIeffect:7;
 abilitycost:2;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:55;
 powercost:105;
 power10:145;
 basic:true;
),
{65}
(name:'Elven Mystic';
 mentalcost:70;
 element:3;
 cost:2;
 damage:3;
 life:14;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:2;
 desc:'Whenever you cast a spell,~Elven Mystic''s attack is permanently increased by %1.';
 isElf:true;
 power1:110;
 powercost:110;
 power10:75;
 basic:true;
),
{66}
(name:'Elven Cavalry';
 mentalcost:25;
 element:3;
 cost:3;
 damage:4;
 life:18;
 bonus:15;
 basicfrequency:6;
 draftfrequency:6;
 desc:'Ability~Elven Cavalry immediately perfoms extra attack. Elven Cavalry~may use this ability multiple times in the same turn.';
 isElf:true;
 abilitycost:3;
 power1:90;
 powercost:90;
 power10:160;
 basic:true;
),
{67}
(name:'Blood Ritual';
 mentalcost:35;
 element:4;
 cost:4;
 life:0;
 basicfrequency:4;
 draftfrequency:5;
 desc:'Destroy an ally creature, then deal damage~equal to that creature''s life to all enemy creatures.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:2;
 power1:90;
 powercost:100;
 power10:110;
 basic:true;
 soundeffect:'spelldestroy';
),
{68}
(name:'Demonic Rage';
 mentalcost:55;
 element:4;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:3;
 logicparam:9;
 logicparam2:5;
 desc:'Deal %1 damage to any creature, and increase~its attack by %2 until the end of your turn.';
 killAIeffect:4;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:100;
 autoeffect:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{69}
(name:'Lazy Ogre';
 mentalcost:25;
 element:2;
 cost:1;
 damage:1;
 life:14;
 bonus:15;
 basicfrequency:7;
 draftfrequency:4;
 logicparam:5;
 desc:'Ability~Lazy Ogre''s attack is increased~by %1 until the end of your turn.';
 badstart:true;
 abilitycost:1;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
),
{70}
(name:'Fire Bolt';
 mentalcost:5;
 element:2;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:10;
 desc:'Deal %1 damage to any creature.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:70;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{71}
(name:'Witch Doctor';
 mentalcost:70;
 element:2;
 cost:2;
 damage:3;
 life:15;
 bonus:5;
 basicfrequency:4;
 draftfrequency:5;
 logicparam:3;
 desc:'Whenever the opponent''s spell power~is reduced by a creature or spell,~Witch Doctor raises your spell power by 1.~Ability~You gain %1 life.`wd';
 abilitycost:1;
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
 mutationimpossible:true;
),
{72}
(name:'Astral Guard';
 mentalcost:15;
 element:1;
 cost:1;
 damage:3;
 life:9;
 bonus:5;
 basicfrequency:5;
 draftfrequency:4;
 desc:'Creatures adjacent to Astral Guard~cannot be targeted by the opponent''s spells.';
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
),
{73}
(name:'Meditation';
 mentalcost:55;
 element:1;
 cost:2;
 life:0;
 basicfrequency:7;
 draftfrequency:3;
 logicparam:8;
 logicparam2:8;
 desc:'Gain 1 spell power. If your spell power~becomes %1 or greater, then gain %2 life.';
 power1:120;
 powercost:120;
 power10:100;
 basic:true;
),
{74}
(name:'Guardian Angel';
 mentalcost:45;
 element:1;
 cost:4;
 damage:5;
 life:20;
 bonus:5;
 basicfrequency:7;
 draftfrequency:4;
 desc:'Guardian Angel can''t be targeted by spells.~All damage done to you is redirected to Guardian Angel.';
 power1:90;
 powercost:100;
 power10:110;
 basic:true;
),
{75}
(name:'Cure';
 mentalcost:30;
 element:3;
 cost:1;
 life:0;
 basicfrequency:7;
 draftfrequency:4;
 logicparam:8;
 desc:'Gain %1 life.`cu';
 badstart:true;
 power1:80;
 powercost:80;
 power10:80;
 soundeffect:'spellgood';
),
{76}
(name:'Virtuous Cycle';
 mentalcost:60;
 element:3;
 cost:2;
 life:0;
 basicfrequency:5;
 draftfrequency:3;
 logicparam:3;
 desc:'Gain %1 life for each creature you have in play,~and draw a card.';
 badstart:true;
{ drawAIeffect:2;
 power1:130;
 powercost:130;
 power10:80;}
 power1:50;
 powercost:60;
 power10:110;
 guild:true;
 mutationimpossible:true;
 soundeffect:'spellgood';
),
{77}
(name:'Nature Ritual';
 mentalcost:5;
 element:3;
 cost:5;
 life:0;
 basicfrequency:3;
 draftfrequency:3;
 logicparam:2;
 desc:'Fully heal one creature, and draw %1 cards.';
 drawAIeffect:10;
 drawcard:true;
 requiretarget:true;
 power1:70;
 powercost:100;
 power10:150;
 basic:true;
 soundeffect:'spellgood';
),
{78}
(name:'Vampire Priest';
 mentalcost:35;
 element:4;
 cost:2;
 damage:4;
 life:12;
 bonus:10;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:4;
 logicparam2:4;
 desc:'Ability~Deal %1 damage to an ally creature,~and you gain %2 life.';
 isvampire:true;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:100;
 powercost:100;
 power10:80;
 basic:true;
),
{79}
(name:'Banshee';
 mentalcost:5;
 element:4;
 cost:4;
 damage:5;
 life:20;
 bonus:10;
 basicfrequency:8;
 draftfrequency:5;
 logicparam:5;
 desc:'Ability~Destroy an ally creature,~and deal %1 damage to all enemy creatures.';
 killAIeffect:4;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:80;
 powercost:120;
 power10:120;
 basic:true;
),
{80}
(name:'Offering to Dorlak';
 mentalcost:65;
 element:4;
 cost:0;
 life:0;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:2;
 desc:'Destroy an ally creature, and draw %1 cards.';
 drawAIeffect:5;
 requiretarget:true;
 targettype:2;
 power1:90;
 powercost:90;
 power10:110;
 guild:true;
 mutationimpossible:true;
 soundeffect:'spelldestroy';
),
{81}
(name:'Harpy';
 mentalcost:90;
 element:2;
 cost:4;
 damage:4;
 life:13;
 bonus:10;
 basicfrequency:8;
 draftfrequency:4;
 desc:'Ability~Your opponent loses 1 spell power.~Harpy may only use this ability while unopposed.';
 abilitycost:1;
 power1:80;
 powercost:110;
 power10:100;
 mutationimpossible:true;
),
{82}
(name:'Air Elemental';
 mentalcost:45;
 element:2;
 cost:3;
 damage:4;
 life:16;
 bonus:20;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Ability~Return another ally creature to your hand.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:100;
 powercost:110;
 power10:110;
 basic:true;
 mutationimpossible:true;
),
{83}
(name:'Fire Elemental';
 mentalcost:10;
 element:2;
 cost:5;
 damage:-1;
 life:25;
 bonus:10;
 basicfrequency:6;
 draftfrequency:4;
 logicparam:5;
 logicparam2:5;
 desc:'Fire Elemental''s attack is equal to your spell power.~Ability~Deal %1 damage to an opposed ally creature~and to the enemy creature that is opposing it.';
 killAIeffect:3;
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:65;
 powercost:90;
 power10:150;
 skiplandingeffect:true;
),
{84}
(name:'Metamorph';
 mentalcost:20;
 element:2;
 cost:1;
 damage:1;
 life:15;
 bonus:10;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Metamorph''s attack becomes equal to~target creature''s current attack power.';
 abilitycost:1;
 abilityrequiretarget:true;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{85}
(name:'Unstable Ooze';
 mentalcost:60;
 element:2;
 cost:2;
 damage:4;
 life:15;
 bonus:10;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:4;
 desc:'If Unstable Ooze dies during your turn, gain %1 mana.';
 power1:110;
 powercost:110;
 power10:70;
 guild:true;
 mutationimpossible:true;
),
{86}
(name:'Tenacious Ooze';
 mentalcost:5;
 element:2;
 cost:3;
 damage:6;
 life:18;
 bonus:8;
 basicfrequency:4;
 draftfrequency:4;
 desc:'Whenever Tenacious Ooze''s attack would be increased~until the end of turn, its attack is permanently~increased by that amount instead.';
 power1:10;
 powercost:110;
 power10:90;
 guild:true;
 mutationimpossible:true;
),
{87}
(name:'Paladin';
 mentalcost:10;
 element:1;
 cost:2;
 damage:4;
 life:15;
 bonus:6;
 basicfrequency:7;
 draftfrequency:5;
 desc:'At the beginning of your turn,~Paladin''s attack is permanently increased by 1.';
 power1:100;
 powercost:100;
 power10:70;
 basic:true;
),
{88}
(name:'Temple Warrior';
 mentalcost:75;
 element:1;
 cost:2;
 damage:2;
 life:14;
 bonus:10;
 basicfrequency:7;
 draftfrequency:4;
 logicparam:4;
 logicparam2:4;
 desc:'Ability~Temple Warrior increases the attack of another creature~by %1 until the end of your turn, and receives %2 damage.';
 abilitycost:-1;
 abilityrequiretarget:true;
 power1:120;
 powercost:120;
 power10:100;
 guild:true;
),
{89}
(name:'Suppress';
 mentalcost:10;
 element:1;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Deal damage to any creature~equal to three times its attack.';
 killAIeffect:8;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
 soundEffect:'SpellDamage';
),
{90}
(name:'Glory Seeker';
 mentalcost:85;
 element:1;
 cost:1;
 damage:3;
 life:9;
 bonus:5;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Destroy an enemy creature whose attack is 6 or higher.';
 abilitycost:2;
 abilityrequiretarget:true;
 abilitytargettype:1;
 dangerousability:true;
 power1:120;
 powercost:120;
 power10:90;
),
{91}
(name:'Holy Avenger';
 mentalcost:5;
 element:1;
 cost:2;
 damage:3;
 life:17;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:2;
 desc:'Whenever another ally creature dies,~Holy Avenger''s attack is permanently increased by 2.';
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{92}
(name:'Preacher';
 mentalcost:20;
 element:1;
 cost:1;
 damage:3;
 life:9;
 bonus:5;
 basicfrequency:5;
 draftfrequency:4;
 desc:'Ability~Double the attack of a creature~until the end of your turn.';
 abilitycost:3;
 abilityrequiretarget:true;
 power1:110;
 powercost:110;
 power10:75;
 basic:true;
),
{93}
(name:'Lord of the Coast';
 mentalcost:45;
 element:1;
 cost:2;
 damage:2;
 life:13;
 bonus:20;
 basicfrequency:7;
 draftfrequency:4;
 logicparam:2;
 desc:'Whenever you summon another creature~while Lord of the Coast is on the board,~that creature''s attack is permanently increased by %1.';
 power1:120;
 powercost:120;
 power10:80;
 basic:true;
),
{94}
(name:'Seeker of Knowledge';
 mentalcost:10;
 element:3;
 cost:3;
 damage:3;
 life:18;
 bonus:20;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Whenever you gain a new card,~Seeker of Knowledge''s attack is permanently increased by 1.';
 power1:70;
 powercost:110;
 power10:110;
 guild:true;
),
{95}
(name:'Hasten';
 mentalcost:95;
 element:3;
 cost:1;
 life:0;
 basicfrequency:7;
 draftfrequency:4;
 desc:'Target ally creature immediately performs extra attack.~Then, draw a card.';
 badstart:true;
 requiretarget:true;
 targettype:2;
 power1:100;
 powercost:100;
 power10:130;
 basic:true;
 soundeffect:'spellneutral';
),
{96}
(name:'Druid';
 mentalcost:70;
 element:3;
 cost:3;
 damage:3;
 life:18;
 bonus:15;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Druid doubles all damage~done to enemy creatures by your spells.';
 power1:120;
 powercost:125;
 power10:90;
 basic:true;
),
{97}
(name:'Fountain of Light';
 mentalcost:75;
 element:3;
 cost:8;
 life:0;
 basicfrequency:3;
 draftfrequency:4;
 logicparam:4;
 logicparam2:4;
 desc:'Draw %1 cards and gain %2 mana.';
 drawcard:true;
 power1:30;
 powercost:180;
 power10:200;
 basic:true;
 soundEffect:'spellgood';
),
{98}
(name:'Elven Dancer';
 mentalcost:55;
 element:3;
 cost:0;
 damage:3;
 life:7;
 bonus:5;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Elven Dancer swaps position with another ally creature.';
 iself:true;
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:120;
 powercost:120;
 power10:50;
 basic:true;
),
{99}
(name:'Mummy';
 mentalcost:5;
 element:4;
 cost:1;
 damage:3;
 life:8;
 bonus:5;
 basicfrequency:6;
 draftfrequency:4;
 logicparam:3;
 logicparam2:3;
 desc:'Ability~Deal %1 damage to any creature. You gain %2 life.';
 abilitycost:2;
 abilityrequiretarget:true;
 power1:110;
 powercost:110;
 power10:75;
 basic:true;
),
{100}
(name:'Ergodemon';
 mentalcost:20;
 element:4;
 cost:2;
 damage:3;
 life:12;
 bonus:10;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:6;
 logicparam2:6;
 desc:'Ability~Destroy another ally creature and restore %1 life to Ergodemon.~Ergodemon''s attack is increased by %2 until the end of your turn.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{101}
(name:'Cultist';
 mentalcost:5;
 element:4;
 cost:3;
 damage:4;
 life:15;
 bonus:10;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Ability~Destroy an ally creature and increase your spell power by 1.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
),
{102}
(name:'Energy Wave';
 mentalcost:15;
 element:2;
 cost:6;
 life:0;
 basicfrequency:7;
 draftfrequency:5;
{ logicparam:11;
 desc:'Deal %1 damage to all enemy creatures,~and gain 1 mana for each creature you kill with this spell.';}
 logicparam:10;
 logicparam2:10;
 desc:'Deal %1 damage to all enemy creatures,~and heal %2 life to all ally creatures.';
 killAIeffect:10;
 power1:50;
 powercost:130;
 power10:140;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{103}
(name:'Devourer';
 mentalcost:15;
 element:4;
 cost:2;
 damage:4;
 life:13;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:4;
 desc:'Whenever Devourer kills a creature,~its attack is permanently increased by %1.~Ability~Move Devourer to target empty slot.';
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:80;
),
{104}
(name:'Ghoul';
 mentalcost:15;
 element:4;
 cost:1;
 damage:3;
 life:9;
 bonus:1;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:3;
 logicparam2:3;
 desc:'Ability~Deal %1 damage to another ally creature and restore %2 life to Ghoul.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:60;
 guild:true;
),
{105}
(name:'Acid Bolt';
 mentalcost:80;
 element:2;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Deal damage to any creature equal to half~its remaining life (rounded up), and draw a card.';
 killAIeffect:7;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:120;
 powercost:120;
 power10:170;
 basic:true;
 soundEffect:'SpellDamage, vol=75%';
),
{106}
(name:'Chaotic Wave';
 mentalcost:40;
 element:2;
 cost:3;
 life:0;
 basicfrequency:4;
 draftfrequency:5;
 logicparam:3;
 desc:'Deal %1 damage to all enemy creatures,~and the opponent loses 1 spell power.';
 killAIeffect:4;
 killcard:true;
 power1:120;
 powercost:120;
 power10:90;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage,vol=40%';
),
{107}
(name:'Fire Drake';
 mentalcost:5;
 element:2;
 cost:2;
 damage:3;
 life:13;
 bonus:5;
 basicfrequency:6;
 draftfrequency:4;
 logicparam:3;
 desc:'Ability~Move Fire Drake to target empty slot and~deal %1 damage to ALL other creatures.';
 killAIeffect:2;
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{108}
(name:'Ascension';
 mentalcost:35;
 element:1;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Gain 1 spell power.';
 power1:130;
 powercost:130;
 power10:35;
 basic:true;
),
{109}
(name:'Anathema';
 mentalcost:30;
 element:1;
 cost:2;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Deal damage to one enemy creature equal to~the total attack of all creatures in play.';
 killAIeffect:9;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:100;
 powercost:120;
 power10:120;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{110}
(name:'Prophet';
 mentalcost:15;
 element:1;
 cost:3;
 damage:4;
 life:17;
 bonus:5;
 basicfrequency:6;
 draftfrequency:4;
 desc:'Ability~Lose 1 spell power and draw a card.';
 drawAIeffect:2;
 abilitycost:-1;
 power1:80;
 powercost:90;
 power10:150;
 basic:true;
),
{111}
(name:'Hierophant';
 mentalcost:30;
 element:1;
 cost:4;
 damage:4;
 life:17;
 bonus:25;
 basicfrequency:8;
 draftfrequency:5;
 desc:'Whenever an ally creature uses an ability,~Hierophant raises your spell power by 1.';
 power1:100;
 powercost:120;
 power10:110;
 guild:true;
 mutationimpossible:true;
),
{112}
(name:'Wisp';
 mentalcost:30;
 element:3;
 cost:3;
 damage:4;
 life:16;
 bonus:10;
 basicfrequency:3;
 draftfrequency:3;
 logicparam:2;
 desc:'You may play another creature in Wisp''s slot.~If you do so, draw %1 cards.';
 drawAIeffect:4;
 drawcard:true;
 power1:100;
 powercost:110;
 power10:120;
),
{113}
(name:'Gryphon';
 mentalcost:45;
 element:3;
 cost:3;
 damage:5;
 life:15;
 basicfrequency:4;
 draftfrequency:4;
 desc:'When you summon Gryphon,~it immediately performs extra attack.~Ability~Return Gryphon to your hand.';
 killAIeffect:6;
 abilitycost:2;
 power1:110;
 powercost:125;
 power10:170;
 skiplandingeffect:true;
 basic:true;
),
{114}
(name:'Forbidden Ritual';
 mentalcost:60;
 element:4;
 cost:1;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Destroy any creature.~Its owner gains life equal to the creature''s life.';
 killAIeffect:8;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:80;
 basic:true;
 mutationimpossible:true;
 soundeffect:'spelldestroy';
),
{115}
(name:'Undead Librarian';
 mentalcost:50;
 element:4;
 cost:2;
 damage:3;
 life:15;
 bonus:3;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Whenever Undead Librarian receives damage~during your turn, draw a card.';
 drawAIeffect:2;
 power1:100;
 powercost:100;
 power10:80;
 basic:true;
 mutationimpossible:true;
),
{116}
(name:'Gluttonous Zombie';
 mentalcost:75;
 element:4;
 cost:1;
 damage:2;
 life:12;
 bonus:5;
 basicfrequency:3;
 draftfrequency:4;
 logicparam:12;
 desc:'Ability~Deal %1 damage to any creature whose attack~is lower than Gluttonous Zombie''s attack.';
 abilitycost:-1;
 abilityrequiretarget:true;
 dangerousability:true;
 power1:110;
 powercost:110;
 power10:70;
 basic:true;
 mutationimpossible:true;
),
{117}
(name:'Harbinger';
 mentalcost:40;
 element:2;
 cost:4;
 damage:5;
 life:28;
 bonus:10;
 basicfrequency:8;
 draftfrequency:5;
 desc:'Ability~Discard all cards in your hand,~then draw as many cards as you discarded.';
 drawAIeffect:3;
 abilitycost:-1;
 power1:50;
 powercost:120;
 power10:130;
 guild:true;
),
{118}
(name:'Goblin Thief';
 mentalcost:30;
 element:2;
 cost:2;
 damage:2;
 life:6;
 bonus:0;
 basicfrequency:5;
 draftfrequency:5;
 desc:'When you summon Goblin Thief,~your opponent discards the first card in his or her hand.';
 power1:120;
 powercost:120;
 power10:80;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{119}
(name:'Bargul';
 mentalcost:95;
 element:2;
 cost:4;
 damage:4;
 life:8;
 bonus:5;
 basicfrequency:5;
 draftfrequency:3;
 logicparam:8;
 desc:'When you summon Bargul, deal %1 damage to ALL other creatures.~Bargul is immune to all damage except attack damage.';
 killAIeffect:5;
 power1:80;
 powercost:110;
 power10:110;
 ignoreforhand:true;
 skiplandingeffect:true;
 mutationimpossible:true;
),
{120}
(name:'Heretic';
 mentalcost:40;
 element:1;
 cost:2;
 damage:3;
 life:8;
 bonus:16;
 basicfrequency:6;
 draftfrequency:4;
 desc:'Whenever you cast a Chaos spell or summon a Chaos creature,~Heretic raises your spell power by 1.';
 power1:120;
 powercost:120;
 power10:75;
 basic:true;
 mutationimpossible:true;
),
{121}
(name:'Balance Keeper';
 mentalcost:20;
 element:1;
 cost:1;
{ damage:3;
 life:10;}
 damage:4;
 life:9;
 bonus:3;
 basicfrequency:5;
 draftfrequency:4;
// desc:'Ability~Your life is set equal to the opponent''s life.';Deal %1 damage to the opponent.
 logicparam:4;
 logicparam2:4;
 desc:'Ability~Deal %1 damage to the opponent and you gain %2 life.~This ability may only be used while opponent has more life than you.';
// abilitycost:3;
 abilitycost:1;
 power1:110;
 powercost:110;
 power10:80;
 guild:true;
),
{122}
(name:'United Prayer';
 mentalcost:70;
 element:1;
 cost:3;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 desc:'Gain 1 spell power for each ally creature.';
 power1:120;
 powercost:120;
 power10:50;
 guild:true;
),
{123}
(name:'Elven Mage';
 mentalcost:15;
 element:3;
 cost:2;
 damage:3;
 life:14;
 bonus:12;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:3;
 desc:'Elven Mage increases the damage of your spells by %1.';
 isElf:true;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{124}
(name:'Treefolk';
 mentalcost:20;
 element:3;
 cost:3;
 damage:4;
 life:18;
 bonus:1;
 basicfrequency:5;
 draftfrequency:5;
 desc:'When you summon Treefolk, draw a card~for each other ally Treefolk on the board.~Treefolk is immune to all damage during your turn.';
 power1:100;
 powercost:110;
 power10:100;
 skiplandingeffect:true;
 basic:true;
 mutationimpossible:true;
),
{125}
(name:'Nature''s Touch';
 mentalcost:20;
 element:3;
 cost:2;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:12;
 logicparam2:12;
 desc:'Restore %1 life to an ally creature,~and deal %2 damage to the enemy creature~opposing it (if there is one).';
 killAIeffect:7;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:2;
 power1:110;
 powercost:110;
 power10:90;
 autoeffect:true;
 effecttoenemycreatures:true;
 guild:true;
 soundEffect:'SpellNeutral';
),
{126}
(name:'Drain Life';
 mentalcost:25;
 element:4;
 cost:1;
 life:0;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:8;
 logicparam2:4;
 desc:'Deal %1 damage to any creature, and gain %2 life.';
 killAIeffect:7;
 badstart:true;
 killcard:true;
 requiretarget:true;
 power1:100;
 powercost:100;
 power10:80;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{127}
(name:'Void Bolt';
 mentalcost:25;
 element:4;
 cost:2;
 life:0;
 basicfrequency:6;
 draftfrequency:5;
 logicparam:4;
 desc:'Deal %1 damage to an enemy creature~for each empty slot on your side of the board.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:110;
 powercost:110;
 power10:100;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{128}
(name:'Dark Phantom';
 mentalcost:20;
 element:4;
 cost:3;
 damage:4;
 life:14;
 bonus:10;
 basicfrequency:7;
 draftfrequency:5;
 desc:'Whenever Dark Phantom deals damage directly to the opponent,~the opponent discards the first card in his or her hand.';
 power1:100;
 powercost:110;
 power10:90;
 basic:true;
),
{129}
(name:'Minotaur Commander';
 mentalcost:75;
 element:2;
 cost:3;
 damage:3;
 life:12;
 bonus:20;
 basicfrequency:5;
 draftfrequency:3;
 desc:'Minotaur Commander allows all ally creatures~to attack on the same turn they are summoned.';
 power1:100;
 powercost:120;
 power10:110;
 basic:true;
),
{130}
(name:'Armageddon';
 mentalcost:85;
 element:2;
 cost:6;
 life:0;
 basicfrequency:5;
 draftfrequency:3;
 logicparam:2;
 desc:'Destroy ALL creatures.~You and the opponent both lose %1 spell power.';
 killAIeffect:9;
 killcard:true;
 power1:100;
 powercost:120;
 power10:120;
 guild:true;
 soundeffect:'spelldestroy';
),
{131}
(name:'Phoenix';
 mentalcost:25;
 element:2;
 cost:3;
 damage:5;
 life:18;
 bonus:1;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:5;
 desc:'Ability~Return Phoenix to your hand and~deal %1 damage to all enemy creatures.';
 killAIeffect:6;
 abilitycost:3;
 power1:80;
 powercost:90;
 power10:150;
 skiplandingeffect:true;
 basic:true;
),
{132}
(name:'Monk';
 mentalcost:5;
 element:1;
 cost:2;
 damage:2;
 life:15;
 bonus:15;
 basicfrequency:7;
 draftfrequency:5;
 logicparam:2;
 logicparam2:2;
 desc:'Ability~Restore %1 life to a creature, and increase~its attack by %2 until the end of your turn.';
 abilitycost:1;
 abilityrequiretarget:true;
 power1:110;
 powercost:110;
 power10:80;
 basic:true;
),
{133}
(name:'Ascetic';
 mentalcost:50;
 element:1;
 cost:2;
 damage:2;
 life:9;
 bonus:30;
 basicfrequency:8;
 draftfrequency:5;
 desc:'Ability~Discard the first card in your hand (as additional cost),~and gain 2 spell power.';
 badstart:true;
 abilitycost:1;
 abilityrequirecard:true;
 power1:120;
 powercost:120;
 power10:60;
 basic:true;
),
{134}
(name:'Sword Master';
 mentalcost:25;
 element:1;
 cost:5;
 damage:4;
 life:20;
 basicfrequency:6;
 draftfrequency:4;
 desc:'When you summon Sword Master,~he immediately performs two attacks.';
 power1:90;
 powercost:110;
 power10:110;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{135}
(name:'Timeweaver';
 mentalcost:30;
 element:3;
 cost:3;
 damage:4;
 life:13;
 basicfrequency:6;
 draftfrequency:5;
 desc:'When you summon Timeweaver,~adjacent creatures immediately perform extra attack.';
 power1:100;
 powercost:110;
 power10:100;
 ignoreforhand:true;
 skiplandingeffect:true;
 basic:true;
),
{136}
(name:'Refilled Memory';
 mentalcost:50;
 element:3;
 cost:4;
 life:0;
 basicfrequency:3;
 draftfrequency:5;
 logicparam:4;
 desc:'Discard all cards in your hand, then draw %1 cards.';
 drawAIeffect:8;
 badstart:true;
 drawcard:true;
 power1:60;
 powercost:90;
 power10:150;
 guild:true;
 soundEffect:'spellNeutral';
),
{137}
(name:'Elven Sage';
 mentalcost:10;
 element:3;
 cost:6;
 damage:6;
 life:25;
 bonus:60;
 basicfrequency:3;
 draftfrequency:3;
 desc:'At the beginning of your turn,~Elven Sage grants you 1 additional card.';
 drawAIeffect:10;
 isElf:true;
 drawcard:true;
 power1:50;
 powercost:110;
 power10:150;
 basic:true;
),
{138}
(name:'Final Sacrifice';
 mentalcost:90;
 element:4;
 cost:4;
 life:0;
 basicfrequency:4;
 draftfrequency:4;
 desc:'You take damage equal to half of your remaining life (rounded down),~and the opponent takes an equal amount of damage.';
 badstart:true;
 power1:95;
 powercost:95;
 power10:95;
 mutationimpossible:true;
 soundEffect:'SpellDamage';
),
{139}
(name:'Fire Storm';
 mentalcost:70;
 element:2;
 cost:2;
 life:0;
 basicfrequency:6;
 draftfrequency:3;
 logicparam:6;
 desc:'Deal %1 damage to ALL creatures,~and draw a card.';
 killAIeffect:4;
 badstart:true;
 power1:95;
 powercost:95;
 power10:95;
 autoeffect:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{140}
(name:'Familiar';
 mentalcost:65;
 element:4;
 cost:0;
 damage:2;
 life:6;
 bonus:1;
 basicfrequency:3;
 draftfrequency:4;
 desc:'When you summon Familiar, gain 1 mana.~Ability~Draw 2 cards. When Familiar uses this ability, it dies.';
 drawAIeffect:2;
 drawcard:true;
 abilitycost:5;
 power1:130;
 powercost:130;
 power10:110;
 skiplandingeffect:true;
),
{141}
(name:'Efreet';
 mentalcost:50;
 element:2;
 cost:5;
 damage:6;
 life:25;
 bonus:15;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:2;
 desc:'Efreet lowers the cost of Chaos cards in your hand by %1.';
 power1:75;
 powercost:110;
 power10:110;
 basic:true;
),
{142}
(name:'Siege Golem';
 mentalcost:10;
 element:1;
 cost:4;
 damage:4;
 life:18;
 bonus:20;
 basicfrequency:8;
 draftfrequency:5;
 logicparam:4;
 desc:'Whenever you summon a creature adjacent to Siege Golem,~Siege Golem deals %1 damage to all enemy creatures.';
 killAIeffect:4;
 power1:100;
 powercost:120;
 power10:110;
 basic:true;
),
{143}
(name:'Zealot';
 mentalcost:5;
 element:1;
 cost:1;
 damage:3;
 life:10;
 bonus:2;
 basicfrequency:5;
 draftfrequency:4;
 logicparam:3;
 logicparam2:10;
 desc:'Ability~Zealot summons %1/%2 Zealots into empty adjacent slots.';
 drawAIeffect:3;
 abilitycost:7;
 power1:100;
 powercost:100;
 power10:100;
 basic:true;
),
{144}
(name:'Elven Hero';
 mentalcost:10;
 element:3;
 cost:2;
 damage:4;
 life:16;
 bonus:10;
 basicfrequency:5;
 draftfrequency:5;
 desc:'Ability~Elven Hero and adjacent creatures immediately perform extra attack.';
 isElf:true;
 abilitycost:5;
 power1:100;
 powercost:100;
 power10:150;
),
{145}
(name:'Triumph of Good';
 mentalcost:90;
 element:3;
 cost:10;
 life:0;
 basicfrequency:4;
 draftfrequency:3;
 desc:'Destroy all enemy creatures.';
 killAIeffect:8;
 power1:10;
 powercost:160;
 power10:160;
 basic:true;
 soundeffect:'spelldestroy';
),
{146}
(name:'Cursed Soul';
 mentalcost:20;
 element:4;
 cost:4;
 damage:5;
 life:16;
 bonus:-2;
 basicfrequency:4;
 draftfrequency:3;
 logicparam:5;
 logicparam2:16;
 desc:'Ability~Transform adjacent creatures into %1/%2 Cursed Souls.';
 abilitycost:1;
 power1:80;
 powercost:100;
 power10:100;
 guild:true;
),
{147}
(name:'Warlock';
 mentalcost:40;
 element:4;
 cost:3;
 damage:2;
 life:18;
 bonus:10;
 basicfrequency:4;
 draftfrequency:4;
 logicparam:3;
 desc:'Whenever a creature dies, Warlock''s attack~is permanently increased by 1.~Ability~Warlock''s attack is permanently decreased~by %1 (as additional cost). Draw a card.';
 drawAIeffect:3;
 abilitycost:-1;
 power1:100;
 powercost:100;
 power10:100;
),
{148}
(name:'Greater Demon';
 mentalcost:30;
 element:4;
 cost:8;
 damage:8;
 life:40;
 bonus:10;
 basicfrequency:5;
 draftfrequency:5;
 logicparam:8;
 logicparam2:8;
 desc:'Ability~Deal %1 damage to one adjacent creature,~and %2 damage to all enemy creatures.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:50;
 powercost:180;
 power10:180;
 basic:true;
),
{149}
(name:'Angry Bird';
 mentalcost:99;
 element:2;
 cost:1;
 damage:3;
 life:3;
 bonus:-20;
 basicfrequency:0;
 draftfrequency:0;
 logicparam:8;
 desc:'When you summon Angry Bird,~deal %1 damage to the opposing creature.';
 power1:70;
 powercost:70;
 power10:70;
 skiplandingeffect:true;
 special:true;
),
{150}
(name:'Weakened Ghoul';
 mentalcost:99;
 element:4;
 cost:1;
 damage:3;
 life:6;
 basicfrequency:0;
 draftfrequency:0;
 desc:'';
 power1:100;
 powercost:100;
 power10:100;
 special:true;
 imageFrom:104;
),
{151}
(name:'Demon';
 mentalcost:99;
 element:4;
 cost:2;
 damage:4;
 life:10;
 basicfrequency:0;
 draftfrequency:0;
 desc:'';
 power1:100;
 powercost:100;
 power10:100;
 special:true;
 imageFrom:100;
),
{152}
(name:'Orc Brigand';
 mentalcost:99;
 element:2;
 cost:1;
 damage:3;
 life:7;
 basicfrequency:0;
 draftfrequency:0;
 desc:'';
 power1:100;
 powercost:100;
 power10:100;
 special:true;
 imageFrom:6;
),
{153}
(name:'Elven Archer'+char(9){#$EF#$BB#$BF};
 mentalcost:99;
 element:3;
 cost:2;
 damage:3;
 life:11;
 bonus:5;
 basicfrequency:7;
 draftfrequency:5;
 desc:'';
 killAIeffect:2;
 isElf:true;
 abilitycost:0;
 power1:110;
 powercost:110;
 power10:70;
 special:true;
 imageFrom:38;
),
{154}
(name:'Monk'+char(9);
 mentalcost:99;
 element:1;
 cost:2;
 damage:2;
 life:14;
 bonus:15;
 basicfrequency:7;
 draftfrequency:5;
 desc:'';
 abilitycost:0;
 power1:110;
 powercost:110;
 power10:80;
 special:true;
 imageFrom:132;
),
{155}
(name:'Astral Chaneller';
 mentalcost:15;
 element:1;
 cost:3;
 damage:3;
 life:12;
 bonus:20;
 basicfrequency:6;
 draftfrequency:6;
 desc:'Whenever you summon a creature adjacent~to Astral Chaneller, gain +1 spell power.';
 drawAIeffect:7;
 drawcard:true;
 power1:95;
 powercost:120;
 power10:140;
 basic:true;
),
{156}
(name:'Test of Endurance';
 mentalcost:60;
 element:1;
 cost:3;
 life:0;
 basicfrequency:5;
 draftfrequency:6;
 logicparam:10;
 logicparam2:3;
 desc:'Deal %1 damage to ALL creatures. Then, deal %2 damage~to opponent for each survived ally creature.';
 killAIeffect:8;
 badstart:true;
 power1:95;
 powercost:100;
 power10:100;
 autoeffect:true;
 basic:true;
 mutationimpossible:true;
 soundeffect:'spelldamage';
),
{157}
(name:'Incinerate';
 mentalcost:40;
 element:2;
 cost:5;
 life:0;
 basicfrequency:6;
 draftfrequency:6;
 logicparam:5;
 desc:'Destroy any enemy creature, then~deal %1 damage to all other enemy creatures.';
 killAIeffect:10;
 badstart:true;
 killcard:true;
 requiretarget:true;
 targettype:1;
 power1:80;
 powercost:120;
 power10:120;
 autoeffect:true;
 effecttoenemycreatures:true;
 basic:true;
 soundEffect:'SpellDamage';
),
{158}
(name:'Energy Mage';
 mentalcost:25;
 element:2;
 cost:2;
 damage:4;
 life:14;
 bonus:10;
 basicfrequency:4;
 draftfrequency:6;
 logicparam:10;
 desc:'Ability~Gain %1 mana.';
 abilitycost:6;
 power1:100;
 powercost:100;
 power10:130;
 basic:true;
 mutationimpossible:true;
),
{159}
(name:'Assault Snake';
 mentalcost:55;
 element:3;
 cost:4;
 damage:4;
 life:20;
 bonus:10;
 basicfrequency:6;
 draftfrequency:6;
 desc:'Ability~Move Assault Snake to target neighboring empty slot.~Then, it perform extra attack.';
 abilitycost:1;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:90;
 powercost:110;
 power10:120;
),
{160}
(name:'Elf Summoner';
 mentalcost:15;
 element:3;
 cost:3;
 damage:4;
 life:20;
 bonus:5;
 basicfrequency:6;
 draftfrequency:6;
 logicparam:4;
 logicparam2:20;
 desc:'Ability~Elf Summoner summons a %1/%2 Assault Snake~to target neighboring empty slot.';
 isElf:true;
 abilitycost:5;
 abilityrequiretarget:true;
 abilitytargettype:2;
 power1:90;
 powercost:100;
 power10:140;
),
{161}
(name:'Tentacle Demon';
 mentalcost:45;
 element:4;
 cost:4;
 damage:4;
 life:24;
 bonus:0;
 basicfrequency:6;
 draftfrequency:6;
 logicparam:9;
 desc:'While opposed, receives +%1 Attack.~Ability~Move enemy creature to empty slot opposing to Tentacle Demon.';
 abilitycost:-1;
 abilityrequiretarget:true;
 abilitytargettype:1;
 power1:80;
 powercost:110;
 power10:110;
),
{162}
(name:'Nightmare Horror';
 mentalcost:10;
 element:4;
 cost:3;
 damage:5;
 life:5;
 bonus:5;
 basicfrequency:6;
 draftfrequency:6;
 desc:'All damage done to Nightmare Horror is reduced to 1.';
{ abilitycost:6;
 abilityrequiretarget:true;
 abilitytargettype:2;}
 power1:95;
 powercost:110;
 power10:100;
)
);

BonusInfo:array[1..20] of tBonusInfo=
(
(name:'Mighty Heroes';
 desc:'Guild members receive +10 Astral Power.';
 imagenum:12;
),
 // 2
(name:'Diligent Heroes';
 desc:'Whenever a Guild member completes a non-Guild daily quest,~they earn 1 Gold for the Guild Treasury.';
 imagenum:9;
),
 // 3
(name:'Resourceful Heroes';
 desc:'Cost to launch Caravans is reduced by 20%.';
 imagenum:22;
),
 // 4
(name:'Creative Heroes';
 {20 exp}
 desc:'Whenever a Guild member crafts a card (for 200 Gold or 200 Crystals),~they earn %1 experience points for the Guild.';
 imagenum:38;
),
 // 5
(name:'Strategic Heroes';
 desc:'Halves the number of victories needed~to complete daily Guild quests.';
 imagenum:32;
),
 // 6
(name:'Enterprise';
 desc:'Each day, 10 gold is added to the Guild Treasury.~Additionally guild receives 1 gold for~every 1000 gold in the Guild Treasury.';
 imagenum:5;
),
 // 7
(name:'Ferocity';
 desc:'Guild members earn 50% more Gold when robbing Caravans.';
 imagenum:31;
),
 // 8
(name:'Aristocracy';
 desc:'For every 100 gold currently in the Guild Treasury,~the Guild earns 1% extra experience.';
 imagenum:25;
),
 // 9
(name:'Spoils of War';
 desc:'Whenever a Guild member wins a battle~in Random Decks mode or Draft Tournament mode,~they earn 1 gold for the Guild Treasury.';
 imagenum:15;
),
 // 10
(name:'Valor';
 {25 exp}
 desc:'Each day, guild receive %1 guild experience~for each guild member with Archmage title.';
 imagenum:40;
),
 // 11
(name:'Patronage';
 desc:'Each time a Guild member purchases Gold,~they also earn bonus Gold for the Guild treasury~equal to 10% of the amount purchased.';
 imagenum:18;
),
 // 12
(name:'Leadership';
 desc:'The Guild earns X% more experience points,~where X is the highest Level of any member in the Guild.';
 imagenum:37;
),
 // 13
(name:'Mysticism';
 desc:'Guild members receive +15 Astral Power.';
 imagenum:16;
),
 // 14
(name:'Fighting Spirit';
 {3 exp}
 desc:'Whenever a Guild member wins a battle~in Random Decks mode or Draft Tournament mode,~they earn %1 experience points for the Guild.';
 imagenum:26;
),
 // 15
(name:'Sparring';
 desc:'Guild members earn 2 extra Hero Points~for each victory in the online League.';
 imagenum:23;
),
 // 16
(name:'Guild of Wizards';
 desc:'Guild members receive +25 Astral Power.';
 imagenum:3;
),
 // 17
(name:'Guild of Sages';
 desc:'Guild members with full card collections~convert the Hero Points they earn for victories~into few experience points for the Guild.';
 imagenum:6;
),
 // 18
(name:'Guild of Merchants';
 desc:'The Guild receives double experience from Caravans.';
 imagenum:33;
),
 // 19
(name:'Guild of Thieves';
 desc:'Guild members can attack Caravans twice as often.';
 imagenum:8;
),
 // 20
(name:'Guild of Adventurers';
 {5 exp}
 desc:'Whenever a Guild member completes a non-Guild daily quest,~they earn %1 experience points for the Guild.';
 imagenum:13;
));


var tinyfont,digitsfont,digitsfont1,digitsfont2:integer;
    consts:tconsts;

 CardInfo:tCardInfoArray;
 smallUIFont,       // уменьшенный шрифт
 mainUIFont,        // Основной шрифт для элементов UI и подписей к ним
 largeUIFont,       // Увеличенный шрифт для элементов UI
 titleFont,         // крупный шрифт для больших заголовков
 playerBoxFont,     // шрифт для подписей на панелях игрока
 signFont1,          // Шрифт для летающих цифр (у крич)
 signFont2,          // Шрифт для летающих цифр (у параметров игрока)
 cardDescFont,      // Основной шрифт для хинта описания карт
 cardDescTitleFont, // Шрифт для заголовка (названия) в описаниях карт
 logChatFont,       // шрифт, которым рисуется лог/чат
 wndTitleFont,      // Шрифт для заголовков окон (крупный)
 wndTitleFontS,     // Шрифт для заголовков окон (помельче)
 iconFont           // FontAwesome
  :cardinal;

 orangeEnemyCards:boolean=false;

// Вызывать ДО ModifyCnsts
procedure LoadConsts(configDir:string='';cnstsfilename:string='inf\gd.spe';obligatory:boolean=false);
// Если от сервера получены новые константы, то нужно вызвать LoadConst а затем ModifyCnsts
procedure ModifyCnsts;
procedure SaveConsts(outname:string='Inf\gd.spe');


// Возвращает строку, однозначно определяемую константами карт
function CardInfoDigest:string;

implementation
uses sysutils,UDict,MyServis;

procedure SaveConsts(outname:string='Inf\gd.spe');
var f:text;
    q,w:integer;
begin
 consts.importdata;
 assign(f,outname);
 rewrite(f);
 for q:=mincard to numcards do
 begin
  writeln(f,consts.icardinfo[q].mentalcost);
  writeln(f,consts.icardinfo[q].cost);
  writeln(f,consts.icardinfo[q].damage);
  writeln(f,consts.icardinfo[q].life);
  writeln(f,consts.icardinfo[q].logicparam);
  writeln(f,consts.icardinfo[q].logicparam2);
 end;
 for q:=mincard to numcards do
 begin
  writeln(f,consts.icardinfo[q].name);
  writeln(f,consts.icardinfo[q].desc);
 end;
 writeln(f,consts.inetVersion);
 writeln(f,consts.isVersion);
 writeln(f,consts.iversion);
 close(f);
end;

procedure LoadConsts(configDir:string='';cnstsfilename:string='inf\gd.spe';obligatory:boolean=false);
 var f:text;
     q,w,v,oldnumcards:integer;
     s:string;
     fname:string;
begin
 fname:=FileName(ConfigDir+cnstsfilename);
 if fileexists(fname) then
 try
  if obligatory then
   v:=version
  else begin
   assign(f,fname);
   reset(f);
   while not eof(f) do
   begin
    readln(f,s);
    Val(s,v,q);
    if q<>0 then
     v:=-1;
   end;
   close(f);
  end;
  if v>version then
  begin
   assign(f,fname);
   reset(f);
   oldnumcards:=numcards;
   q:=1;
   while q<=oldnumcards do
   begin
    readln(f,consts.icardinfo[q].mentalcost);
    readln(f,consts.icardinfo[q].cost);
    readln(f,consts.icardinfo[q].damage);
    readln(f,consts.icardinfo[q].life);
    readln(f,consts.icardinfo[q].logicparam);
    readln(f,consts.icardinfo[q].logicparam2);
    if q=7 then
     oldnumcards:=consts.icardinfo[q].logicparam;
    inc(q);
   end;
   for q:=mincard to oldnumcards do
   begin
    readln(f,consts.icardinfo[q].name);
    readln(f,consts.icardinfo[q].desc);
   end;
   readln(f,consts.inetVersion);
   readln(f,consts.isVersion);
   readln(f,consts.iversion);
   close(f);
   consts.exportdata;
  end;
 except
 end;
end;

procedure tconsts.importdata;
begin
 consts.icardinfo:=defcardinfo;
 consts.inetVersion:=netversion;
 consts.isVersion:=sVersion;
 consts.iversion:=version;
end;

procedure tconsts.exportdata;
var q:integer;
begin
 for q:=mincard to numcards do
 begin
  DefCardInfo[q].name:=consts.icardinfo[q].name;
  DefCardInfo[q].mentalcost:=consts.icardinfo[q].mentalcost;
  DefCardInfo[q].cost:=consts.icardinfo[q].cost;
  DefCardInfo[q].damage:=consts.icardinfo[q].damage;
  DefCardInfo[q].life:=consts.icardinfo[q].life;
  DefCardInfo[q].logicparam:=consts.icardinfo[q].logicparam;
  DefCardInfo[q].logicparam2:=consts.icardinfo[q].logicparam2;
  DefCardInfo[q].desc:=consts.icardinfo[q].desc;
 end;
 netversion:=consts.inetVersion;
 sVersion:=consts.isVersion;
 version:=consts.iversion;
end;

procedure ModifyCnsts;
var q,w,e:integer;
    s,s2:string;
begin
 {$IFNDEF AHSTAT}
 cardinfo:=defcardinfo;
 for q:=mincard to numcards do
 begin
  s2:=udict.simplify(cardinfo[q].name);
  cardinfo[q].translatednames[0]:=translate(s2);
  for w:=1 to 5 do
   cardinfo[q].translatednames[w]:=translate(s2+'`'+inttostr(w));

  cardinfo[q].name:='^'+cardinfo[q].name+'^';
  s:='';
  if cardinfo[q].life=0 then
  begin
   if q=-4 then
    s:=s+'Game rule^~^'
   else
   if (q<>-3) then
   begin
    case cardinfo[q].element of
     0:s:='^Basic spell^';
     1:s:='^Order spell^';
     2:s:='^Chaos spell^';
     3:s:='^Life spell^';
     4:s:='^Death spell^';
    end;
    s:=s+', ^cost^ '+inttostr(cardinfo[q].cost)+'~^';
   end;
  end else
  begin
   case cardinfo[q].element of
    0:s:='^Creature^';
    1:s:='^Order creature^';
    2:s:='^Chaos creature^';
    3:s:='^Life creature^';
    4:s:='^Death creature^';
   end;
   if cardinfo[q].cost>=0 then
    s:=s+', ^cost^ '+inttostr(cardinfo[q].cost);
{   if cardinfo[q].desc='' then
   begin
    s:=s+'~^Attack^ '+inttostr(cardinfo[q].damage);
   end else}
   if cardinfo[q].damage>=0 then
    s:=s+', ^attack^ '+inttostr(cardinfo[q].damage);
   s:=s+', ^life^ '+inttostr(cardinfo[q].life);
   if cardinfo[q].desc<>'' then
    s:=s+'~^';
  end;
  s2:=cardinfo[q].desc;
  w:=pos('Ability~',s2);
  if w>0 then
  begin
   e:=cardinfo[q].abilitycost;
   if e=-1 then
    e:=0;
   if w>2 then
    s2:=copy(s2,1,w-2)+'^~^Ability^ (^cost^ '+inttostr(e)+')~^'+copy(s2,w+8,255)+'^'
   else
    s2:='^Ability^ (^cost^ '+inttostr(e)+')~^'+copy(s2,w+8,255)+'^';
  end;


//  if pos('%1',s2)>0 then
  if cardinfo[q].logicparam<>0 then
   s2:=s2+'%%'+inttostr(cardinfo[q].logicparam);
//  if pos('%2',s2)>0 then
  if cardinfo[q].logicparam2<>0 then
   s2:=s2+'%%'+inttostr(cardinfo[q].logicparam2);
  cardinfo[q].desc:=translate(s+s2);
 end;
 {$ENDIF}
end;

function CardInfoDigest:string;
var
 i:integer;
begin
 result:='';
 for i:=mincard to numcards do
  with CardInfo[i] do
   result:=result+Format('%d,%d,%d,%d,%d,%d;',
     [mentalcost,cost,damage,life,logicparam,logicparam2]);

end;

begin
end.

