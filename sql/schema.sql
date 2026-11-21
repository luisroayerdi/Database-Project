-- =====================================================================
-- Music Library Database - Schema (MySQL)
-- Run: mysql -u <user> -p <db> < sql/schema.sql
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
