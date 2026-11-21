-- =====================================================================
-- Music Library Database - Requirement Tests (MySQL 8.0.16+)
-- Run after schema.sql: mysql -u <user> -p <db> < tests/tests.sql
--
-- Each test reports PASS or FAIL. Test data is rolled back at the end.
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

-- ---------------------------------------------------------------------
-- R2: One creator_user_id per playlist
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- R3: Collaborators must exist in Users
-- ---------------------------------------------------------------------
CALL expect_ok  ('R3a: existing user can be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 2)');
CALL expect_fail('R3b: non-existent user cannot be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 999)');

-- ---------------------------------------------------------------------
-- R4: streams >= 0
-- ---------------------------------------------------------------------
CALL expect_ok  ('R4a: streams = 0 is allowed',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, 0, ''Zero'')');
CALL expect_fail('R4b: negative streams on insert is rejected',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, -1, ''Negative'')');
CALL expect_fail('R4c: updating streams to negative is rejected',
    'UPDATE Song SET streams = -50 WHERE song_id = 1');

-- ---------------------------------------------------------------------
-- R5: Password length >= 10
-- ---------------------------------------------------------------------
CALL expect_ok  ('R5a: 10-character password is allowed',
    'INSERT INTO Users (password, email) VALUES (''abcdefghij'', ''ten@example.com'')');
CALL expect_fail('R5b: 9-character password is rejected',
    'INSERT INTO Users (password, email) VALUES (''abcdefghi'', ''nine@example.com'')');
CALL expect_fail('R5c: changing password to a short one is rejected',
    'UPDATE Users SET password = ''short'' WHERE user_id = 1');

-- ---------------------------------------------------------------------
-- NULL policy
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- Normalization: library junction tables
-- ---------------------------------------------------------------------
CALL expect_ok  ('1NF: user saves an album',
    'INSERT INTO User_Albums (user_id, album_id) VALUES (1, 1)');
CALL expect_ok  ('1NF: user saves a playlist',
    'INSERT INTO User_Playlists (user_id, playlist_id) VALUES (2, 1)');
CALL expect_ok  ('1NF: user saves a song',
    'INSERT INTO User_Songs (user_id, song_id) VALUES (1, 1)');
CALL expect_fail('1NF: saving the same song twice is rejected',
    'INSERT INTO User_Songs (user_id, song_id) VALUES (1, 1)');

-- ---------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------
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
