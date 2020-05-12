// Author: Alexey Stankevich (Apus Software)
unit UMissionsLogic;
interface
type

tMissionsInfo=record
 Name:string;
 Desc,TempDesc:string;
 TextReward:string;
 RewardCrystals:integer;
 RewardGold:integer;
 RewardAstralPower:integer;
 Progress,MaxProgress:integer;
 completed:boolean;
 ImageNum:integer;
end;

const
MissionLevels:array[0..11] of integer=(0,3,5,10,15,20,25,30,40,50,75,9999);

Maxmission=50;
MissionsInfo:array[1..maxmission] of tMissionsInfo=
(
{1}
(
 name:'Total Annihilation';
 desc:'Defeat an opponent by dealing more than 20 damage with your final hit.';
 textreward:'%1 Crystals%%25';
 rewardcrystals:25;
 imagenum:34;
),
{2}
(
 name:'Battle Fury';
 desc:'Win 10 matches in the League.';
 textreward:'2 days of Premium Membership^~~^Premium Account Benefits:~'+'  ^+100% Hero Points earned in Custom Deck battles.^~  ^Entry fee is removed for Random Deck battles.^~  ^Entry fee is removed for Draft Tournaments.^';
 MaxProgress:10;
 imagenum:45;
),
{3}
(
 name:'United We Stand';
 desc:'Join an existing guild, or create a new guild.';
 textreward:'%1 Crystals%%30';
 rewardcrystals:30;
 imagenum:4;
),
{4}
(
 name:'You Shall Not Pass';
 desc:'Successfully defend your guild caravan from the attack of another player.';
 textreward:'%1 Crystals%%50';
 rewardcrystals:50;
 imagenum:43;
),
{5}
(
 name:'It Takes a Thief';
 desc:'Successfully rob 3 caravans.';
 textreward:'%1 Gold%%25';
 rewardgold:25;
 MaxProgress:3;
 imagenum:39;
),
{6}
(
 name:'Champion';
 desc:'Win a Draft Tournament in the Online League.';
 textreward:'%1 Gold%%50';
 rewardgold:50;
 imagenum:25{10};
),
{7}
(
 name:'Wolf in Sheep''s Clothing';
 desc:'Defeat an opponent using the attack of a Sheep as your final hit.';
 textreward:'%1 Crystals%%25';
 rewardcrystals:25;
 imagenum:46;
),
{8}
(
 name:'Vampire Hunter';
 desc:'Kill 100 vampires.';
 textreward:'%1 Crystals%%30';
 rewardcrystals:30;
 MaxProgress:100;
 imagenum:44;
),
{9}
(
 name:'Elf Help';
 desc:'Summon 100 elves.';
 textreward:'%1 Crystals%%20';
 rewardcrystals:20;
 MaxProgress:100;
 imagenum:30;
),
{10}(),{11}(),{12}(),{13}(),{14}(),{15}(),{16}(),{17}(),{18}(),{19}(),{20}(),
{21}
(
 name:'Mercenary';
 desc:'Complete 5 quests.';
 textreward:'%1 Gold%%10';
 rewardgold:10;
 MaxProgress:5;
 imagenum:8{35};
),
{22}
(
 name:'Hale and Hearty';
 desc:'Defeat a Quest opponent with 50 or more life remaining.';
 textreward:'%1 Crystals%%10';
 rewardcrystals:10;
 imagenum:22{36};
),
{23}
(
 name:'Summoner';
 desc:'Complete a Quest using a deck that contains no Spells.';
 textreward:'%1 Crystals%%25';
 rewardcrystals:25;
 imagenum:17;
),
{24}
(
 name:'Spellcaster';
 desc:'Complete a Quest using a deck that contains no Creatures.';
 textreward:'%1 Crystals%%75';
 rewardcrystals:75;
 imagenum:42;
),
{25}
(
 name:'Dragon Master';
 desc:'Defeat a Quest opponent after summoning 3 Dragons during the battle.';
 textreward:'%1 Crystals%%30';
 rewardcrystals:30;
 imagenum:41;
),
{26}
(
 name:'Strength in Numbers';
 desc:'Defeat a Quest opponent with 6 ally creatures on the board~at the end of the battle.';
 textreward:'%1 Crystals%%20';
 rewardcrystals:20;
 imagenum:21;
),
{27}
(
 name:'Sole Survivor';
 Desc:'Defeat a Quest opponent with no ally creatures on the board~at the end of the battle.';
 TextReward:'%1 Crystals%%20';
 RewardCrystals:20;
 imagenum:7;
),
{28}(),{29}(),{30}(),{31}(),{32}(),{33}(),{34}(),{35}(),{36}(),{37}(),{38}(),{39}(),{40}(),
{41}
(
 name:'Custom Decks: Level %1';
 Desc:'Achieve Level %1 in Custom Decks mode.';
 TextReward:'%1 Astral Power%%5';
 RewardAstralPower:5;
 ImageNum:28;
),
{42}
(
 name:'Random Decks: Level %1';
 Desc:'Achieve Level %1 in Random Decks mode.';
 TextReward:'%1 Astral Power%%5';
 RewardAstralPower:5;
 ImageNum:27;
),
{43}
(
 name:'Draft Tournaments: Level %1';
 Desc:'Achieve Level %1 in Draft Tournaments mode.';
 TextReward:'%1 Astral Power%%5';
 RewardAstralPower:5;
 ImageNum:20;
),
{44}
(
 name:'Collector: %1 cards';
 Desc:'Collect %1 cards.^~^Repeatable mission.';
 TextReward:'%1 Astral Power%%5';
 RewardAstralPower:5;
 ImageNum:1;
),
{45}
(
 name:'Collector: %1 cards%%100';
 Desc:'Collect %1 cards.%%100';
 TextReward:'5 Astral Power and new title: "Advanced Mage"';
 RewardAstralPower:5;
 imagenum:29;
),
{46}
(
 name:'Collector: %1 cards%%200';
 Desc:'Collect %1 cards.%%200';
 TextReward:'5 Astral Power and new title: "Expert Mage"';
 RewardAstralPower:5;
 imagenum:29;
),
{47}
(
 name:'Collector: %1 cards%%300';
 Desc:'Collect %1 cards.%%300';
 TextReward:'5 Astral Power and new title: "Magister"';
 RewardAstralPower:5;
 imagenum:29;
),
{48}
(
 name:'Collector: %1 cards%%400';
 Desc:'Collect %1 cards.%%400';
 TextReward:'5 Astral Power and new title: "Archmage"';
 RewardAstralPower:5;
 imagenum:29;
),
{49}(),{50}());


implementation

end.
