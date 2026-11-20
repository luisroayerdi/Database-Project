-- =====================================================================
-- Music Streaming Database - Requirement Tests (PostgreSQL)
-- =====================================================================
-- Run AFTER schema.sql:   psql -d <your_db> -f tests/tests.sql
--
-- Each test prints PASS or FAIL. "Should fail" tests attempt an invalid
-- operation and PASS only if the database rejects it.
-- Everything runs inside a transaction and is rolled back at the end,
-- so the database is left empty.
-- =====================================================================

\set QUIET on
\pset tuples_only on
\pset footer off

BEGIN;

-- Helper: run a statement that SHOULD be rejected
CREATE OR REPLACE FUNCTION pg_temp.expect_fail(test_name TEXT, stmt TEXT)
RETURNS VOID AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
        RAISE NOTICE 'FAIL: % (statement was accepted)', test_name;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: % (rejected: %)', test_name, SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- Helper: run a statement that SHOULD succeed
CREATE OR REPLACE FUNCTION pg_temp.expect_ok(test_name TEXT, stmt TEXT)
RETURNS VOID AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
        RAISE NOTICE 'PASS: %', test_name;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: % (error: %)', test_name, SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Sample data
-- ---------------------------------------------------------------------
INSERT INTO Users (user_id, password, email) OVERRIDING SYSTEM VALUE VALUES
    (1, 'supersecret1', 'alice@example.com'),
    (2, 'anotherpass99', NULL);                 -- NULL email allowed

INSERT INTO Artist (artist_id, description, artist_name) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Indie rock band', 'The Examples'),
    (2, NULL, 'DJ Null');                       -- NULL description allowed

INSERT INTO Song (song_id, genre, release_date, artist_id, streams, name) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Rock', '2024-01-10', 1, 5000, 'First Single'),
    (2, 'Rock', '2024-03-01', 1, 1200, 'Album Track'),
    (3, 'EDM',  '2025-06-01', 2, 0,    'Late Release');

INSERT INTO Album (album_id, artist_id, release_date, genre, title) OVERRIDING SYSTEM VALUE VALUES
    (1, 1, '2024-03-01', 'Rock', 'Debut Album');

INSERT INTO Playlist (playlist_id, user_id, title) OVERRIDING SYSTEM VALUE VALUES
    (1, 1, 'Alice Mix');

-- Advance identity counters past the hand-picked ids above
DO $$
BEGIN
    PERFORM setval(pg_get_serial_sequence('users',    'user_id'),     (SELECT MAX(user_id)     FROM Users));
    PERFORM setval(pg_get_serial_sequence('artist',   'artist_id'),   (SELECT MAX(artist_id)   FROM Artist));
    PERFORM setval(pg_get_serial_sequence('song',     'song_id'),     (SELECT MAX(song_id)     FROM Song));
    PERFORM setval(pg_get_serial_sequence('album',    'album_id'),    (SELECT MAX(album_id)    FROM Album));
    PERFORM setval(pg_get_serial_sequence('playlist', 'playlist_id'), (SELECT MAX(playlist_id) FROM Playlist));
END $$;

-- ---------------------------------------------------------------------
-- R1: Song release date <= Album release date
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_ok  ('R1a: song released before album can be added',
    'INSERT INTO Album_Songs VALUES (1, 1, 1)');
SELECT pg_temp.expect_ok  ('R1b: song released same day as album can be added',
    'INSERT INTO Album_Songs VALUES (1, 2, 2)');
SELECT pg_temp.expect_fail('R1c: song released after album is rejected',
    'INSERT INTO Album_Songs VALUES (1, 3, 3)');
SELECT pg_temp.expect_fail('R1d: moving song date past album date is rejected',
    'UPDATE Song SET release_date = ''2025-01-01'' WHERE song_id = 1');
SELECT pg_temp.expect_fail('R1e: moving album date before its songs is rejected',
    'UPDATE Album SET release_date = ''2023-12-31'' WHERE album_id = 1');

-- ---------------------------------------------------------------------
-- R2: Playlist has exactly one user_id
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_fail('R2a: playlist with no owner is rejected',
    'INSERT INTO Playlist (user_id, title) VALUES (NULL, ''Orphan'')');
SELECT pg_temp.expect_fail('R2b: playlist with non-existent owner is rejected',
    'INSERT INTO Playlist (user_id, title) VALUES (999, ''Ghost'')');
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_name = 'playlist' AND column_name = 'user_id') = 1 THEN
        RAISE NOTICE 'PASS: R2c: Playlist has exactly one user_id column';
    ELSE
        RAISE NOTICE 'FAIL: R2c: Playlist user_id column count is not 1';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- R3: Collaborator ids must exist in Users
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_ok  ('R3a: existing user can be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 2)');
SELECT pg_temp.expect_fail('R3b: non-existent user cannot be a collaborator',
    'INSERT INTO Playlist_Collaborators VALUES (1, 999)');

-- ---------------------------------------------------------------------
-- R4: Streams >= 0
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_ok  ('R4a: streams = 0 is allowed',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, 0, ''Zero'')');
SELECT pg_temp.expect_fail('R4b: negative streams on insert is rejected',
    'INSERT INTO Song (genre, release_date, artist_id, streams, name) VALUES (''Pop'', ''2024-01-01'', 1, -1, ''Negative'')');
SELECT pg_temp.expect_fail('R4c: updating streams to negative is rejected',
    'UPDATE Song SET streams = -50 WHERE song_id = 1');

-- ---------------------------------------------------------------------
-- R5: Password at least 10 characters
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_ok  ('R5a: 10-character password is allowed',
    'INSERT INTO Users (password, email) VALUES (''abcdefghij'', ''ten@example.com'')');
SELECT pg_temp.expect_fail('R5b: 9-character password is rejected',
    'INSERT INTO Users (password, email) VALUES (''abcdefghi'', ''nine@example.com'')');
SELECT pg_temp.expect_fail('R5c: changing password to a short one is rejected',
    'UPDATE Users SET password = ''short'' WHERE user_id = 1');

-- ---------------------------------------------------------------------
-- NULL policy + normalization sanity checks
-- ---------------------------------------------------------------------
SELECT pg_temp.expect_ok  ('NULL: user without email is allowed',
    'INSERT INTO Users (password, email) VALUES (''noemailpass1'', NULL)');
SELECT pg_temp.expect_ok  ('NULL: artist without description is allowed',
    'INSERT INTO Artist (description, artist_name) VALUES (NULL, ''Quiet Artist'')');
SELECT pg_temp.expect_ok  ('1NF: song added to a user library via junction table',
    'INSERT INTO User_Library (user_id, song_id) VALUES (1, 1)');
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM User_Library WHERE user_id = 2) THEN
        RAISE NOTICE 'PASS: 1NF: user with no library rows has an empty library';
    ELSE
        RAISE NOTICE 'FAIL: 1NF: user 2 unexpectedly has library rows';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- Composite index: top songs in a genre
-- ---------------------------------------------------------------------
\pset tuples_only off
\echo 'Top Rock songs (uses indx_song_genre_streams):'
SELECT name, streams
FROM Song
WHERE genre = 'Rock'
ORDER BY streams DESC;

ROLLBACK;
