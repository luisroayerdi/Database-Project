# Database-Project

A PostgreSQL schema for a music streaming service (users, artists, songs, albums, playlists), with constraints and triggers that enforce its business rules, plus a test script that checks each rule.

## Project structure

```
.
├── sql/
│   └── schema.sql   # Tables, constraints, and triggers
└── tests/
    └── tests.sql    # Requirement tests (prints PASS/FAIL, rolls back)
```

## How to run

Requires PostgreSQL (`psql`).

```bash
createdb music_db
psql -d music_db -f sql/schema.sql
psql -d music_db -f tests/tests.sql
```

`tests.sql` runs inside a transaction and rolls back, so the database is left empty afterwards.
