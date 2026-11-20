-- =====================================================================
-- Music Streaming Database - Schema (PostgreSQL)
-- =====================================================================
-- Run:  psql -d <your_db> -f sql/schema.sql
--
-- Requirements enforced:
--   R1: Song release date must be <= its album's release date  (triggers)
--   R2: A playlist has exactly one owner user_id                (NOT NULL FK)
--   R3: Collaborator ids must exist in Users                    (FK)
--   R4: Streams >= 0                                            (CHECK)
--   R5: Passwords are at least 10 characters                    (CHECK)
--
-- NULL policy:
--   Users.email          NULL = user did not register an email
--   Artist.description   NULL = artist opted out of a description
--   Users.library        replaced by the User_Library junction table
--                        (see Normalization); no rows = empty library
-- =====================================================================

DROP TABLE IF EXISTS Playlist_Collaborators CASCADE;
DROP TABLE IF EXISTS Playlist_Songs         CASCADE;
DROP TABLE IF EXISTS Playlist               CASCADE;
DROP TABLE IF EXISTS User_Library           CASCADE;
DROP TABLE IF EXISTS Album_Songs            CASCADE;
DROP TABLE IF EXISTS Album                  CASCADE;
DROP TABLE IF EXISTS Song_Features          CASCADE;
DROP TABLE IF EXISTS Song                   CASCADE;
DROP TABLE IF EXISTS Artist                 CASCADE;
DROP TABLE IF EXISTS Users                  CASCADE;

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
CREATE TABLE Users (
    user_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    password  VARCHAR(255) NOT NULL,
    email     VARCHAR(255) UNIQUE,            -- NULL = no email registered
    -- R5: password must be at least 10 characters
    CONSTRAINT chk_password_min_length CHECK (char_length(password) >= 10)
);

-- ---------------------------------------------------------------------
-- Artist
-- ---------------------------------------------------------------------
CREATE TABLE Artist (
    artist_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    description  TEXT,                         -- NULL = opted out
    artist_name  VARCHAR(255) NOT NULL
);

-- ---------------------------------------------------------------------
-- Song
-- ---------------------------------------------------------------------
CREATE TABLE Song (
    song_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genre         VARCHAR(100),
    release_date  DATE NOT NULL,
    artist_id     INTEGER NOT NULL REFERENCES Artist(artist_id) ON DELETE CASCADE,
    streams       BIGINT NOT NULL DEFAULT 0,
    name          VARCHAR(255) NOT NULL,
    -- R4: streams can never be negative
    CONSTRAINT chk_streams_nonnegative CHECK (streams >= 0)
);

-- Composite index: quickly sort the most popular songs within a genre
CREATE INDEX indx_song_genre_streams ON Song (genre, streams DESC);

-- ---------------------------------------------------------------------
-- Song_Features  (featured artists on a song)
-- ---------------------------------------------------------------------
CREATE TABLE Song_Features (
    song_id             INTEGER NOT NULL REFERENCES Song(song_id)     ON DELETE CASCADE,
    featured_artist_id  INTEGER NOT NULL REFERENCES Artist(artist_id) ON DELETE CASCADE,
    PRIMARY KEY (song_id, featured_artist_id)
);

-- ---------------------------------------------------------------------
-- Album
-- ---------------------------------------------------------------------
CREATE TABLE Album (
    album_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    artist_id     INTEGER NOT NULL REFERENCES Artist(artist_id) ON DELETE CASCADE,
    release_date  DATE NOT NULL,
    genre         VARCHAR(100),
    title         VARCHAR(255) NOT NULL
);

-- ---------------------------------------------------------------------
-- Album_Songs
-- ---------------------------------------------------------------------
CREATE TABLE Album_Songs (
    album_id        INTEGER NOT NULL REFERENCES Album(album_id) ON DELETE CASCADE,
    song_id         INTEGER NOT NULL REFERENCES Song(song_id)   ON DELETE CASCADE,
    track_position  INTEGER NOT NULL CHECK (track_position > 0),
    PRIMARY KEY (album_id, song_id),
    UNIQUE (album_id, track_position)          -- no two songs in the same slot
);

-- ---------------------------------------------------------------------
-- Normalization: User_Library junction table
-- Replaces the multi-valued Users.library column (which violated 1NF).
-- A user with no rows here simply has an empty library.
-- ---------------------------------------------------------------------
CREATE TABLE User_Library (
    user_id   INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    song_id   INTEGER NOT NULL REFERENCES Song(song_id)  ON DELETE CASCADE,
    added_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, song_id)
);

-- ---------------------------------------------------------------------
-- Playlist
-- R2: exactly one owner -> single NOT NULL user_id column
-- ---------------------------------------------------------------------
CREATE TABLE Playlist (
    playlist_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    creation_date  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    title          VARCHAR(255) NOT NULL,
    CONSTRAINT chk_playlist_dates CHECK (last_updated >= creation_date)
);

-- ---------------------------------------------------------------------
-- Playlist_Songs
-- ---------------------------------------------------------------------
CREATE TABLE Playlist_Songs (
    playlist_id     INTEGER NOT NULL REFERENCES Playlist(playlist_id) ON DELETE CASCADE,
    song_id         INTEGER NOT NULL REFERENCES Song(song_id)         ON DELETE CASCADE,
    track_position  INTEGER NOT NULL CHECK (track_position > 0),
    PRIMARY KEY (playlist_id, song_id),
    UNIQUE (playlist_id, track_position)
);

-- ---------------------------------------------------------------------
-- Playlist_Collaborators
-- R3: collaborator_user_id must exist in Users (foreign key)
-- ---------------------------------------------------------------------
CREATE TABLE Playlist_Collaborators (
    playlist_id           INTEGER NOT NULL REFERENCES Playlist(playlist_id) ON DELETE CASCADE,
    collaborator_user_id  INTEGER NOT NULL REFERENCES Users(user_id)        ON DELETE CASCADE,
    PRIMARY KEY (playlist_id, collaborator_user_id)
);

-- =====================================================================
-- R1: Song release_date <= Album release_date
-- This spans two tables, so a CHECK can't do it; triggers cover every
-- way the rule could be broken:
--   (a) adding/changing a row in Album_Songs
--   (b) moving a Song's release_date later
--   (c) moving an Album's release_date earlier
-- =====================================================================

-- (a) Album_Songs insert/update
CREATE OR REPLACE FUNCTION trg_album_songs_release_check()
RETURNS TRIGGER AS $$
DECLARE
    v_song_date  DATE;
    v_album_date DATE;
BEGIN
    SELECT release_date INTO v_song_date  FROM Song  WHERE song_id  = NEW.song_id;
    SELECT release_date INTO v_album_date FROM Album WHERE album_id = NEW.album_id;

    IF v_song_date > v_album_date THEN
        RAISE EXCEPTION 'R1 violated: song % release date (%) is after album % release date (%)',
            NEW.song_id, v_song_date, NEW.album_id, v_album_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER album_songs_release_check
BEFORE INSERT OR UPDATE ON Album_Songs
FOR EACH ROW EXECUTE FUNCTION trg_album_songs_release_check();

-- (b) Song release_date update
CREATE OR REPLACE FUNCTION trg_song_release_check()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Album_Songs s
        JOIN Album a ON a.album_id = s.album_id
        WHERE s.song_id = NEW.song_id
          AND NEW.release_date > a.release_date
    ) THEN
        RAISE EXCEPTION 'R1 violated: song % release date (%) would be after one of its albums',
            NEW.song_id, NEW.release_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER song_release_check
BEFORE UPDATE OF release_date ON Song
FOR EACH ROW EXECUTE FUNCTION trg_song_release_check();

-- (c) Album release_date update
CREATE OR REPLACE FUNCTION trg_album_release_check()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Album_Songs s
        JOIN Song so ON so.song_id = s.song_id
        WHERE s.album_id = NEW.album_id
          AND so.release_date > NEW.release_date
    ) THEN
        RAISE EXCEPTION 'R1 violated: album % release date (%) would be before one of its songs',
            NEW.album_id, NEW.release_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER album_release_check
BEFORE UPDATE OF release_date ON Album
FOR EACH ROW EXECUTE FUNCTION trg_album_release_check();
