-- MySQL dump 10.13  Distrib 5.1.44, for Win32 (ia32)
--
-- Host: localhost    Database: astralheroes
-- ------------------------------------------------------
-- Server version 5.1.44-community

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `attachments`
--

DROP TABLE IF EXISTS `attachments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `attachments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `topic` int(11) NOT NULL DEFAULT '0',
  `msg` int(11) NOT NULL DEFAULT '0',
  `filename` varchar(150) NOT NULL DEFAULT '' COMMENT 'Source file name',
  `filesize` int(11) NOT NULL DEFAULT '0',
  `thumbnail` varchar(45) NOT NULL DEFAULT '',
  `th_width` smallint(6) NOT NULL DEFAULT '0',
  `th_height` smallint(6) NOT NULL DEFAULT '0',
  `filetype` varchar(10) NOT NULL DEFAULT '' COMMENT 'file name is "id.filetype"',
  PRIMARY KEY (`id`),
  KEY `msg` (`msg`),
  KEY `topic` (`topic`)
) ENGINE=MyISAM AUTO_INCREMENT=2893 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `changes`
--

DROP TABLE IF EXISTS `changes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `changes` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `playerid` int(11) NOT NULL DEFAULT '0',
  `parameter` enum('hp','crystals','gold','custFame','clsFame','draftFame','totalFame','custLevel','clsLevel','draftLevel','totalLevel','custPlace','clsPlace','draftPlace','totalPlace','cards') NOT NULL DEFAULT 'hp',
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `oldval` int(11) NOT NULL DEFAULT '0',
  `newval` int(11) NOT NULL DEFAULT '0',
  `reason` int(11) NOT NULL DEFAULT '0',
  `comment` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`playerid`,`Id`),
  KEY `date` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
/*!50100 PARTITION BY LINEAR KEY (playerID)
PARTITIONS 16 */;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `clientinfo`
--

DROP TABLE IF EXISTS `clientinfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `clientinfo` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `playerID` int(11) NOT NULL DEFAULT '0',
  `InstanceID` int(11) NOT NULL DEFAULT '0',
  `date` date NOT NULL DEFAULT '0000-00-00',
  `info` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`Id`),
  KEY `Instance` (`InstanceID`),
  KEY `date` (`date`),
  KEY `playerID` (`playerID`)
) ENGINE=MyISAM AUTO_INCREMENT=742555 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dailystat`
--

DROP TABLE IF EXISTS `dailystat`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dailystat` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `date` date NOT NULL DEFAULT '0000-00-00',
  `newplayers` int(11) NOT NULL DEFAULT '0',
  `DAU` int(11) NOT NULL DEFAULT '0',
  `duels` int(11) NOT NULL DEFAULT '0',
  `custom` int(11) NOT NULL DEFAULT '0',
  `classic` int(11) NOT NULL DEFAULT '0',
  `draft` int(11) NOT NULL DEFAULT '0',
  `campaign` int(11) NOT NULL DEFAULT '0',
  `quests` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Id`)
) ENGINE=MyISAM AUTO_INCREMENT=2317 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `decks`
--

DROP TABLE IF EXISTS `decks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `decks` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `owner` int(11) NOT NULL DEFAULT '0',
  `name` varchar(255) NOT NULL DEFAULT '',
  `data` varchar(255) NOT NULL DEFAULT '',
  `cost` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Id`),
  KEY `owner` (`owner`)
) ENGINE=MyISAM AUTO_INCREMENT=151853 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `duels`
--

DROP TABLE IF EXISTS `duels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `duels` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `dueltype` tinyint(4) NOT NULL DEFAULT '0',
  `scenario` tinyint(3) NOT NULL DEFAULT '0',
  `winner` int(8) NOT NULL,
  `loser` int(8) NOT NULL DEFAULT '0',
  `date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `turns` tinyint(4) NOT NULL DEFAULT '0',
  `duration` int(6) NOT NULL DEFAULT '0',
  `firstPlr` tinyint(3) NOT NULL DEFAULT '0',
  `winnerLevel` tinyint(3) NOT NULL DEFAULT '0',
  `loserLevel` tinyint(3) NOT NULL DEFAULT '0',
  `winnerDeck` varchar(80) DEFAULT NULL,
  `loserDeck` varchar(80) DEFAULT NULL,
  `winnerFame` smallint(5) NOT NULL DEFAULT '0',
  `loserFame` smallint(5) NOT NULL DEFAULT '0',
  `replayID` int(11) DEFAULT '0',
  `replayAccess` tinyint(3) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`,`date`),
  KEY `date` (`date`),
  KEY `loserID` (`loser`),
  KEY `winnerID` (`winner`)
) ENGINE=MyISAM AUTO_INCREMENT=7845219 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC
/*!50100 PARTITION BY HASH (month(date))
PARTITIONS 12 */;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `duels_new`
--

DROP TABLE IF EXISTS `duels_new`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `duels_new` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `dueltype` tinyint(4) NOT NULL DEFAULT '0',
  `scenario` tinyint(3) NOT NULL DEFAULT '0',
  `winner` int(8) NOT NULL,
  `loser` int(8) NOT NULL DEFAULT '0',
  `date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `turns` tinyint(4) NOT NULL DEFAULT '0',
  `duration` int(6) NOT NULL DEFAULT '0',
  `firstPlr` tinyint(3) NOT NULL DEFAULT '0',
  `winnerLevel` tinyint(3) NOT NULL DEFAULT '0',
  `loserLevel` tinyint(3) NOT NULL DEFAULT '0',
  `winnerDeck` varchar(80) DEFAULT NULL,
  `loserDeck` varchar(80) DEFAULT NULL,
  `winnerFame` smallint(6) NOT NULL DEFAULT '0',
  `loserFame` smallint(6) NOT NULL DEFAULT '0',
  `replayID` int(11) NOT NULL DEFAULT '0',
  `replayAccess` tinyint(3) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`,`date`)
) ENGINE=MyISAM AUTO_INCREMENT=7842596 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `eventlog`
--

DROP TABLE IF EXISTS `eventlog`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `eventlog` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `playerid` int(11) NOT NULL DEFAULT '0',
  `event` varchar(30) NOT NULL,
  `info` varchar(250) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`,`created`),
  KEY `created` (`created`),
  KEY `user` (`playerid`)
) ENGINE=MyISAM AUTO_INCREMENT=10704416 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC
/*!50100 PARTITION BY HASH (month(created))
PARTITIONS 12 */;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `eventlog_new`
--

DROP TABLE IF EXISTS `eventlog_new`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `eventlog_new` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `playerid` int(11) NOT NULL DEFAULT '0',
  `event` varchar(30) NOT NULL,
  `info` varchar(250) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`,`created`),
  KEY `created` (`created`),
  KEY `user` (`playerid`)
) ENGINE=MyISAM AUTO_INCREMENT=10697793 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `fchanges`
--

DROP TABLE IF EXISTS `fchanges`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `fchanges` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `item` int(8) NOT NULL,
  `userid` int(8) unsigned NOT NULL,
  `operation` tinyint(3) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=62296 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `guildlog`
--

DROP TABLE IF EXISTS `guildlog`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `guildlog` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `guild` int(11) NOT NULL DEFAULT '0',
  `date` datetime DEFAULT NULL,
  `msg` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`Id`),
  KEY `guild` (`guild`)
) ENGINE=MyISAM AUTO_INCREMENT=107848 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `guildmembers`
--

DROP TABLE IF EXISTS `guildmembers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `guildmembers` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `playerID` int(11) NOT NULL DEFAULT '0',
  `guild` int(11) NOT NULL DEFAULT '0',
  `rank` tinyint(3) NOT NULL DEFAULT '1',
  `powers` tinyint(3) NOT NULL DEFAULT '12',
  `rewards` tinyint(3) NOT NULL DEFAULT '0',
  `treasures` int(11) NOT NULL DEFAULT '0',
  `exp` int(11) NOT NULL DEFAULT '0',
  `r1` smallint(6) NOT NULL DEFAULT '0',
  `r2` smallint(6) NOT NULL DEFAULT '0',
  `r3` smallint(6) NOT NULL DEFAULT '0',
  `deposit` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Id`),
  UNIQUE KEY `plrID` (`playerID`),
  KEY `guild` (`guild`)
) ENGINE=MyISAM AUTO_INCREMENT=5582 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `guildplaces`
--

DROP TABLE IF EXISTS `guildplaces`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `guildplaces` (
  `date` date NOT NULL DEFAULT '0000-00-00',
  `place` tinyint(3) NOT NULL DEFAULT '0',
  `guild` int(5) unsigned NOT NULL DEFAULT '0',
  `level` tinyint(3) NOT NULL DEFAULT '0',
  `exp` int(11) NOT NULL DEFAULT '0',
  KEY `guild` (`guild`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `guilds`
--

DROP TABLE IF EXISTS `guilds`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `guilds` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(40) NOT NULL DEFAULT '',
  `size` tinyint(3) NOT NULL DEFAULT '8',
  `exp` int(11) NOT NULL DEFAULT '0',
  `daily` tinyint(3) NOT NULL DEFAULT '0',
  `level` int(11) NOT NULL DEFAULT '1',
  `treasures` int(11) NOT NULL DEFAULT '0',
  `bonuses` varchar(30) NOT NULL DEFAULT '00000000000000000000',
  `cards` varchar(30) NOT NULL DEFAULT '00000000000000000000',
  `flags` int(11) NOT NULL DEFAULT '0',
  `motto` varchar(255) DEFAULT NULL,
  `carLaunch1` datetime DEFAULT NULL,
  `carLaunch2` datetime DEFAULT NULL,
  PRIMARY KEY (`Id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=MyISAM AUTO_INCREMENT=1037 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `lastread`
--

DROP TABLE IF EXISTS `lastread`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `lastread` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `user` int(8) unsigned NOT NULL,
  `topic` int(6) unsigned NOT NULL,
  `msg` int(8) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user` (`user`,`topic`)
) ENGINE=MyISAM AUTO_INCREMENT=74252 DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `messages` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `topic` int(8) unsigned NOT NULL DEFAULT '0',
  `prev` int(8) unsigned NOT NULL DEFAULT '0',
  `msg` mediumtext NOT NULL,
  `created` datetime NOT NULL,
  `author` int(8) unsigned NOT NULL DEFAULT '0',
  `ip` varchar(15) CHARACTER SET cp1251 NOT NULL,
  `authorname` varchar(30) NOT NULL,
  `flags` int(6) unsigned NOT NULL DEFAULT '0',
  `score` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `topic` (`topic`)
) ENGINE=MyISAM AUTO_INCREMENT=27335 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `penalties`
--

DROP TABLE IF EXISTS `penalties`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `penalties` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `user` int(8) unsigned NOT NULL DEFAULT '0',
  `mute` int(6) NOT NULL DEFAULT '0',
  `ban` int(6) NOT NULL DEFAULT '0',
  `reason` varchar(80) NOT NULL,
  `created` datetime NOT NULL,
  `author` int(8) unsigned NOT NULL DEFAULT '0',
  `notes` varchar(250) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `user` (`user`)
) ENGINE=MyISAM AUTO_INCREMENT=309 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `places`
--

DROP TABLE IF EXISTS `places`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `places` (
  `playerID` int(11) NOT NULL DEFAULT '0',
  `date` date NOT NULL DEFAULT '2016-01-01',
  `place` smallint(6) NOT NULL DEFAULT '0',
  `score` smallint(6) unsigned NOT NULL DEFAULT '0',
  KEY `player` (`playerID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `players`
--

DROP TABLE IF EXISTS `players`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `players` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(40) NOT NULL DEFAULT '',
  `email` varchar(60) NOT NULL,
  `guild` varchar(40) DEFAULT NULL,
  `pwd` varchar(45) NOT NULL,
  `flags` varchar(20) NOT NULL DEFAULT 'Un',
  `lang` varchar(3) NOT NULL DEFAULT 'en',
  `created` datetime NOT NULL,
  `lastvisit` datetime DEFAULT NULL,
  `online` enum('Y','N') NOT NULL DEFAULT 'N',
  `avatar` int(11) NOT NULL DEFAULT '0',
  `gold` int(11) NOT NULL DEFAULT '0',
  `gems` int(10) NOT NULL DEFAULT '0',
  `astralPower` int(11) NOT NULL DEFAULT '600',
  `insight` int(6) NOT NULL DEFAULT '0',
  `needInsight` int(6) NOT NULL DEFAULT '9',
  `customFame` int(11) NOT NULL DEFAULT '0',
  `customLevel` int(4) NOT NULL DEFAULT '1',
  `classicFame` int(11) NOT NULL DEFAULT '0',
  `classicLevel` int(4) NOT NULL DEFAULT '1',
  `draftFame` int(11) NOT NULL DEFAULT '0',
  `draftLevel` int(4) NOT NULL DEFAULT '1',
  `trainFame` int(6) NOT NULL DEFAULT '0',
  `level` int(4) NOT NULL DEFAULT '1',
  `premium` datetime DEFAULT NULL,
  `curDeck` int(11) NOT NULL DEFAULT '0',
  `realname` varchar(45) NOT NULL DEFAULT '',
  `location` varchar(45) NOT NULL DEFAULT '',
  `about` varchar(200) NOT NULL DEFAULT '',
  `CustomWins` int(11) NOT NULL DEFAULT '0',
  `CustomLoses` int(11) NOT NULL DEFAULT '0',
  `ClassicWins` int(11) NOT NULL DEFAULT '0',
  `ClassicLoses` int(11) NOT NULL DEFAULT '0',
  `DraftWins` int(11) NOT NULL DEFAULT '0',
  `DraftLoses` int(11) NOT NULL DEFAULT '0',
  `DraftTourWins` int(11) NOT NULL DEFAULT '0',
  `tags` varchar(255) NOT NULL DEFAULT '',
  `referer` int(11) DEFAULT NULL,
  `cards` blob NOT NULL,
  `paramX` int(6) NOT NULL DEFAULT '0',
  `speciality` tinyint(3) NOT NULL DEFAULT '0',
  `HP` tinyint(3) NOT NULL DEFAULT '25',
  `quests` varchar(30) NOT NULL DEFAULT '1',
  `campaignWins` int(3) NOT NULL DEFAULT '0',
  `room` int(3) NOT NULL DEFAULT '1',
  `campaignLoses` varchar(80) NOT NULL DEFAULT '0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0',
  `optionsflags` int(11) NOT NULL DEFAULT '0',
  `friendlist` text NOT NULL,
  `blacklist` text NOT NULL,
  `missions` varchar(255) DEFAULT NULL,
  `market` varchar(100) DEFAULT NULL,
  `modified` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `dailyUpd` date NOT NULL DEFAULT '2016-01-01',
  `onEnterMsg` text,
  `carPrior` smallint(5) NOT NULL DEFAULT '0',
  `tips` varchar(40) NOT NULL DEFAULT '',
  `botLevels` tinyint(3) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  UNIQUE KEY `name` (`name`),
  KEY `modified` (`modified`)
) ENGINE=MyISAM AUTO_INCREMENT=35605 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `profiles`
--

DROP TABLE IF EXISTS `profiles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `profiles` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `email` varchar(60) NOT NULL DEFAULT '',
  `name` varchar(50) NOT NULL DEFAULT '',
  `VID` bigint(20) NOT NULL DEFAULT '0',
  `playerID` int(11) NOT NULL DEFAULT '0',
  `lastvisit` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `network` varchar(5) NOT NULL DEFAULT '',
  `networkid` varchar(50) DEFAULT NULL,
  `avatar` int(11) NOT NULL DEFAULT '0',
  `flags` varchar(20) NOT NULL DEFAULT '',
  `session` int(11) NOT NULL DEFAULT '0',
  `sessions` varchar(50) NOT NULL DEFAULT '',
  `notify` char(1) NOT NULL DEFAULT 'N',
  PRIMARY KEY (`Id`)
) ENGINE=MyISAM AUTO_INCREMENT=6768 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rates`
--

DROP TABLE IF EXISTS `rates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rates` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `msg` int(11) NOT NULL,
  `user` int(11) NOT NULL,
  `value` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `msg` (`msg`),
  KEY `user` (`user`)
) ENGINE=MyISAM AUTO_INCREMENT=21836 DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `topics`
--

DROP TABLE IF EXISTS `topics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `topics` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(40) NOT NULL,
  `chapter` int(8) unsigned NOT NULL DEFAULT '0',
  `lang` char(2) NOT NULL DEFAULT 'En',
  `flags` int(8) unsigned NOT NULL DEFAULT '0',
  `lastmsg` int(10) unsigned NOT NULL DEFAULT '0',
  `msgcount` int(10) unsigned NOT NULL DEFAULT '0',
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `guild` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`),
  KEY `chapter` (`chapter`),
  KEY `id_2` (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=1307 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users_ban`
--

DROP TABLE IF EXISTS `users_ban`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users_ban` (
  `id` int(3) unsigned NOT NULL AUTO_INCREMENT,
  `playerid` int(8) NOT NULL,
  `name` varchar(40) NOT NULL DEFAULT '',
  `date` datetime DEFAULT NULL,
  `action` varchar(10) NOT NULL DEFAULT 'B',
  `reason` varchar(200) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `id` (`id`,`playerid`),
  KEY `userid` (`playerid`)
) ENGINE=MyISAM AUTO_INCREMENT=372 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `visits`
--

DROP TABLE IF EXISTS `visits`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `visits` (
  `Id` int(11) NOT NULL AUTO_INCREMENT,
  `vid` bigint(20) NOT NULL DEFAULT '0',
  `date` datetime DEFAULT NULL,
  `ip` varchar(255) DEFAULT NULL,
  `country` varchar(2) NOT NULL DEFAULT '-',
  `playerID` int(11) DEFAULT NULL,
  `accounts` varchar(255) DEFAULT NULL,
  `page` varchar(255) NOT NULL DEFAULT '',
  `refID` int(11) NOT NULL DEFAULT '0',
  `referer` varchar(255) DEFAULT NULL,
  `tags` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`Id`),
  KEY `IP` (`ip`),
  KEY `VID` (`vid`)
) ENGINE=MyISAM AUTO_INCREMENT=1603395 DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2020-03-05 17:33:06
