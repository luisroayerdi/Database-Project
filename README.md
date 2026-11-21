# Database-Project

A MySQL schema for a music library (users, artists, songs, albums, playlists), with constraints and triggers that enforce its requirements, plus tests that check each one.

## Project structure

```
.
└── music_db.sql   # Schema (tables, constraints, index, triggers) + requirement tests
```

## How to run

Requires MySQL 8.0.16+ (CHECK constraints are enforced from that version on).

```bash
mysql -u root -p < music_db.sql
```

Creates `music_db` if missing, rebuilds all tables, then runs the tests (prints PASS/FAIL). Test data is rolled back, so the tables are left empty.
