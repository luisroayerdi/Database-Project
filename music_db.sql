-- =====================================================================
-- Team 1 - Deborah Akran, Jerry Phan, Luis Ayerdi-Morales, Kaleb Luellen, Daniel Martinez
-- Music Library Database - Schema and Tests (MySQL 8.0.16+)
-- Run: mysql -u <user> -p < music_db.sql
--
-- Requirements:
--   R1: Song.release_date <= Album.release_date      (triggers)
--   R2: One creator_user_id per playlist              (NOT NULL FK)
--   R3: collaborator_user_id must exist in Users      (FK)
--   R4: Song.streams >= 0                             (CHECK)
--   R5: Password length >= 10                         (CHECK)
--
-- NULL policy (all other columns are NOT NULL):
--   Playlist.last_updated  not updated since creation
--   Artist.description     artist opted out
--   Users.email            no email registered
-- =====================================================================

CREATE DATABASE IF NOT EXISTS music_db;
USE music_db;

-- Drop children before parents
DROP TABLE IF EXISTS Playlist_Collaborators;
DROP TABLE IF EXISTS Playlist_Songs;
DROP TABLE IF EXISTS User_Playlists;
DROP TABLE IF EXISTS User_Songs;
DROP TABLE IF EXISTS User_Albums;
DROP TABLE IF EXISTS Playlist;
DROP TABLE IF EXISTS Album_Songs;
DROP TABLE IF EXISTS Album;
DROP TABLE IF EXISTS Song_Features;
DROP TABLE IF EXISTS Song;
DROP TABLE IF EXISTS Artist;
DROP TABLE IF EXISTS Users;

-- Users Table
CREATE TABLE Users (
    user_id   INT AUTO_INCREMENT PRIMARY KEY,
    password  VARCHAR(255) NOT NULL,
    email     VARCHAR(255) NULL UNIQUE,
    CONSTRAINT chk_password_min_length CHECK (CHAR_LENGTH(password) >= 10)  -- R5
);

-- Artist Table
CREATE TABLE Artist (
    artist_id    INT AUTO_INCREMENT PRIMARY KEY,
    description  TEXT NULL,
    artist_name  VARCHAR(255) NOT NULL
);

-- Song Table
CREATE TABLE Song (
    song_id       INT AUTO_INCREMENT PRIMARY KEY,
    genre         VARCHAR(100) NOT NULL,
    release_date  DATE NOT NULL,
    artist_id     INT NOT NULL,
    streams       BIGINT NOT NULL DEFAULT 0,
    name          VARCHAR(255) NOT NULL,
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id) ON DELETE CASCADE,
    CONSTRAINT chk_streams_nonnegative CHECK (streams >= 0)  -- R4
);

-- Top songs by genre (COMPOSITE INDEX)
CREATE INDEX idx_song_genre_streams ON Song (genre, streams DESC);

-- Song_Features Table
CREATE TABLE Song_Features (
    song_id             INT NOT NULL,
    featured_artist_id  INT NOT NULL,
    PRIMARY KEY (song_id, featured_artist_id),
    FOREIGN KEY (song_id)            REFERENCES Song(song_id)     ON DELETE CASCADE,
    FOREIGN KEY (featured_artist_id) REFERENCES Artist(artist_id) ON DELETE CASCADE
);

-- Album Table
CREATE TABLE Album (
    album_id      INT AUTO_INCREMENT PRIMARY KEY,
    artist_id     INT NOT NULL,
    release_date  DATE NOT NULL,
    genre         VARCHAR(100) NOT NULL,
    title         VARCHAR(255) NOT NULL,
    FOREIGN KEY (artist_id) REFERENCES Artist(artist_id) ON DELETE CASCADE
);

-- Album_Songs Table
CREATE TABLE Album_Songs (
    album_id        INT NOT NULL,
    song_id         INT NOT NULL,
    track_position  INT NOT NULL,
    PRIMARY KEY (album_id, song_id),
    UNIQUE (album_id, track_position),  -- one song per slot
    FOREIGN KEY (album_id) REFERENCES Album(album_id) ON DELETE CASCADE,
    FOREIGN KEY (song_id)  REFERENCES Song(song_id)   ON DELETE CASCADE,
    CONSTRAINT chk_album_track_pos CHECK (track_position > 0)
);

-- Playlist Table (R2)
CREATE TABLE Playlist (
    playlist_id      INT AUTO_INCREMENT PRIMARY KEY,
    creator_user_id  INT NOT NULL,
    creation_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated     DATETIME NULL DEFAULT NULL,
    title            VARCHAR(255) NOT NULL,
    FOREIGN KEY (creator_user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_playlist_dates CHECK (last_updated >= creation_date)
);

-- Playlist_Songs Table
CREATE TABLE Playlist_Songs (
    playlist_id     INT NOT NULL,
    song_id         INT NOT NULL,
    track_position  INT NOT NULL,
    PRIMARY KEY (playlist_id, song_id),
    UNIQUE (playlist_id, track_position),  -- one song per slot
    FOREIGN KEY (playlist_id) REFERENCES Playlist(playlist_id) ON DELETE CASCADE,
    FOREIGN KEY (song_id)     REFERENCES Song(song_id)         ON DELETE CASCADE,
    CONSTRAINT chk_playlist_track_pos CHECK (track_position > 0)
);

-- Playlist_Collaborators (R3)
CREATE TABLE Playlist_Collaborators (
    playlist_id           INT NOT NULL,
    collaborator_user_id  INT NOT NULL,
    PRIMARY KEY (playlist_id, collaborator_user_id),
    FOREIGN KEY (playlist_id)          REFERENCES Playlist(playlist_id) ON DELETE CASCADE,
    FOREIGN KEY (collaborator_user_id) REFERENCES Users(user_id)        ON DELETE CASCADE
);

-- User library junction tables (replacing Users.library for 1NF)
CREATE TABLE User_Albums (
    user_id   INT NOT NULL,
    album_id  INT NOT NULL,
    PRIMARY KEY (user_id, album_id),
    FOREIGN KEY (user_id)  REFERENCES Users(user_id)  ON DELETE CASCADE,
    FOREIGN KEY (album_id) REFERENCES Album(album_id) ON DELETE CASCADE
);

CREATE TABLE User_Playlists (
    user_id      INT NOT NULL,
    playlist_id  INT NOT NULL,
    PRIMARY KEY (user_id, playlist_id),
    FOREIGN KEY (user_id)     REFERENCES Users(user_id)        ON DELETE CASCADE,
    FOREIGN KEY (playlist_id) REFERENCES Playlist(playlist_id) ON DELETE CASCADE
);

CREATE TABLE User_Songs (
    user_id  INT NOT NULL,
    song_id  INT NOT NULL,
    PRIMARY KEY (user_id, song_id),
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (song_id) REFERENCES Song(song_id)  ON DELETE CASCADE
);

-- =====================================================================
-- R1 triggers: Song.release_date <= Album.release_date
-- Checked on: Album_Songs insert/update, Song date update, Album date update
-- =====================================================================
DELIMITER //

CREATE TRIGGER album_songs_release_check_ins
BEFORE INSERT ON Album_Songs
FOR EACH ROW
BEGIN
    IF (SELECT release_date FROM Song  WHERE song_id  = NEW.song_id) >
       (SELECT release_date FROM Album WHERE album_id = NEW.album_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R1 violated: song released after album';
    END IF;
END//

CREATE TRIGGER album_songs_release_check_upd
BEFORE UPDATE ON Album_Songs
FOR EACH ROW
BEGIN
    IF (SELECT release_date FROM Song  WHERE song_id  = NEW.song_id) >
       (SELECT release_date FROM Album WHERE album_id = NEW.album_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R1 violated: song released after album';
    END IF;
END//

CREATE TRIGGER song_release_check
BEFORE UPDATE ON Song
FOR EACH ROW
BEGIN
    IF NEW.release_date <> OLD.release_date AND EXISTS (
        SELECT 1
        FROM Album_Songs s
        JOIN Album a ON a.album_id = s.album_id
        WHERE s.song_id = NEW.song_id
          AND NEW.release_date > a.release_date
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R1 violated: song date would be after an album date';
    END IF;
END//

CREATE TRIGGER album_release_check
BEFORE UPDATE ON Album
FOR EACH ROW
BEGIN
    IF NEW.release_date <> OLD.release_date AND EXISTS (
        SELECT 1
        FROM Album_Songs s
        JOIN Song so ON so.song_id = s.song_id
        WHERE s.album_id = NEW.album_id
          AND so.release_date > NEW.release_date
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R1 violated: album date would be before a song date';
    END IF;
END//

DELIMITER ;

-- =====================================================================
-- Requirement tests: each reports PASS or FAIL; test data is rolled back
-- =====================================================================

DROP PROCEDURE IF EXISTS expect_ok;
DROP PROCEDURE IF EXISTS expect_fail;
DROP TEMPORARY TABLE IF EXISTS test_results;

CREATE TEMPORARY TABLE test_results (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    result  VARCHAR(500) NOT NULL
);

DELIMITER //

-- PASS if stmt succeeds
CREATE PROCEDURE expect_ok(IN test_name VARCHAR(255), IN stmt TEXT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err = MESSAGE_TEXT;
        INSERT INTO test_results (result) VALUES (CONCAT('FAIL: ', test_name, ' (error: ', @err, ')'));
    END;
    SET @stmt = stmt;
    PREPARE s FROM @stmt;
    EXECUTE s;
    DEALLOCATE PREPARE s;
    INSERT INTO test_results (result) VALUES (CONCAT('PASS: ', test_name));
END//

-- PASS if stmt is rejected
CREATE PROCEDURE expect_fail(IN test_name VARCHAR(255), IN stmt TEXT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err = MESSAGE_TEXT;
        INSERT INTO test_results (result) VALUES (CONCAT('PASS: ', test_name, ' (rejected: ', @err, ')'));
    END;
    SET @stmt = stmt;
    PREPARE s FROM @stmt;
    EXECUTE s;
    DEALLOCATE PREPARE s;
    INSERT INTO test_results (result) VALUES (CONCAT('FAIL: ', test_name, ' (statement was accepted)'));
END//

DELIMITER ;

START TRANSACTION;

-- Sample data
INSERT INTO Users (user_id, password, email) VALUES
    (1, 'house12345', 'luislovesllvm@gmail.com'),
    (2, 'anotherpassword1000', NULL);

INSERT INTO Artist (artist_id, description, artist_name) VALUES
    (1, 'Indie rock band', 'The Strokes'),
    (2, NULL, 'DJ Deborah');

INSERT INTO Song (song_id, genre, release_date, artist_id, streams, name) VALUES
    (1, 'Rock', '2024-01-10', 1, 5000, 'First Single'),
    (2, 'Hyperpop', '2024-03-01', 1, 1200, 'Album Track'),
    (3, 'EDM',  '2025-06-01', 2, 0,    'Late Release');

INSERT INTO Album (album_id, artist_id, release_date, genre, title) VALUES
    (1, 1, '2024-03-01', 'Rock', 'My Debut Album');

INSERT INTO Playlist (playlist_id, creator_user_id, title) VALUES
    (1, 1, 'Alice Mix');

-- R1: Song release_date <= Album release_date
CALL expect_ok  ('R1a: song released before album can be added',
    'INSERT INTO Album_Songs VALUES (1, 1, 1)');
CALL expect_ok  ('R1b: song released same day as album can be added',
    'INSERT INTO Album_Songs VALUES (1, 2, 2)');
CALL expect_fail('R1c: song released after album is rejected',
    'INSERT INTO Album_Songs VALUES (1, 3, 3)');
CALL expect_fail('R1d: moving song date past album date is rejected',
    'UPDATE Song SET release_date = ''2025-01-01'' WHERE song_id = 1');
CALL expect_fail('R1e: moving album date before its songs is rejected',
    'UPDATE Album SET release_date = ''2023-12-31'' WHERE album_id = 1');
CALL expect_fail('R1f: re-pointing an album track to a later song is rejected',
    'UPDATE Album_Songs SET song_id = 3 WHERE album_id = 1 AND song_id = 1');

-- R2: One creator_user_id per playlist
CALL expect_fail('R2a: playlist with no creator is rejected',
    'INSERT INTO Playlist (creator_user_id, title) VALUES (NULL, ''Orphan'')');
CALL expect_fail('R2b: playlist with non-existent creator is rejected',
    'INSERT INTO Playlist (creator_user_id, title) VALUES (999, ''Ghost'')');
INSERT INTO test_results (result)
SELECT IF(COUNT(*) = 1,
          'PASS: R2c: Playlist has exactly one creator_user_id column',
          'FAIL: R2c: Playlist creator_user_id column count is not 1')
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND LOWER(table_name) = 'playlist'
  AND column_name = 'creator_user_id';

-- R3: Collaborators must exist in Users
CALL expect_ok  ('R3a: existing user can be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 2)');
CALL expect_fail('R3b: non-existent user cannot be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 999)');

-- R4: streams >= 0
CALL expect_ok  ('R4a: streams = 0 is allowed',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, 0, ''Zero'')');
CALL expect_fail('R4b: negative streams on insert is rejected',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, -1, ''Negative'')');
CALL expect_fail('R4c: updating streams to negative is rejected',
    'UPDATE Song SET streams = -50 WHERE song_id = 1');

-- R5: Password length >= 10
CALL expect_ok  ('R5a: 10-character password is allowed',
    'INSERT INTO Users (password, email) VALUES (''abcdefghij'', ''ten@example.com'')');
CALL expect_fail('R5b: 9-character password is rejected',
    'INSERT INTO Users (password, email) VALUES (''abcdefghi'', ''nine@example.com'')');
CALL expect_fail('R5c: changing password to a short one is rejected',
    'UPDATE Users SET password = ''short'' WHERE user_id = 1');

-- NULL policy
CALL expect_ok  ('NULL: user without email is allowed',
    'INSERT INTO Users (password, email) VALUES (''noemailpass1'', NULL)');
CALL expect_ok  ('NULL: artist without description is allowed',
    'INSERT INTO Artist (description, artist_name) VALUES (NULL, ''Quiet Artist'')');
INSERT INTO test_results (result)
SELECT IF(last_updated IS NULL,
          'PASS: NULL: new playlist has NULL last_updated',
          'FAIL: NULL: new playlist last_updated is not NULL')
FROM Playlist WHERE playlist_id = 1;
CALL expect_fail('NULL: song without genre is rejected',
    'INSERT INTO Song (genre, release_date, artist_id, name) VALUES (NULL, ''2024-01-01'', 1, ''No Genre'')');
CALL expect_fail('NULL: user without password is rejected',
    'INSERT INTO Users (password) VALUES (NULL)');

-- Normalization: library junction tables
CALL expect_ok  ('1NF: user saves an album',
    'INSERT INTO User_Albums (user_id, album_id) VALUES (1, 1)');
CALL expect_ok  ('1NF: user saves a playlist',
    'INSERT INTO User_Playlists (user_id, playlist_id) VALUES (2, 1)');
CALL expect_ok  ('1NF: user saves a song',
    'INSERT INTO User_Songs (user_id, song_id) VALUES (1, 1)');
CALL expect_fail('1NF: saving the same song twice is rejected',
    'INSERT INTO User_Songs (user_id, song_id) VALUES (1, 1)');

-- Results
SELECT result FROM test_results ORDER BY id;

-- Top Rock songs (served by idx_song_genre_streams)
SELECT name, streams
FROM Song
WHERE genre = 'Rock'
ORDER BY streams DESC;

ROLLBACK;

DROP PROCEDURE IF EXISTS expect_ok;
DROP PROCEDURE IF EXISTS expect_fail;
DROP TEMPORARY TABLE IF EXISTS test_results;
