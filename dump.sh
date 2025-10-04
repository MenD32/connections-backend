#!/bin/bash

# PostgreSQL Database Import Script for NYTimes Connections Solutions
#
# This script imports NYTimes Connections game solutions from a JSON file
# into a PostgreSQL database with proper JSONB structure for categories.
#
# Usage:
#   ./dump.sh                              # Uses default solutions.json
#   JSON_FILE=my_data.json ./dump.sh       # Uses custom JSON file
#   POSTGRES_HOST=myhost ./dump.sh         # Custom database host
#
# Environment Variables:
#   POSTGRES_USER     - Database user (default: postgres)
#   POSTGRES_DB       - Database name (default: connections)  
#   POSTGRES_HOST     - Database host (default: localhost)
#   POSTGRES_PORT     - Database port (default: 5432)
#   POSTGRES_PASSWORD - Database password (default: empty)
#   JSON_FILE         - JSON file to import (default: solutions.json)
#
# Database Schema:
#   - game_date: DATE (unique) - The date of the game
#   - game_id: INTEGER - NYTimes game ID number
#   - editor: VARCHAR - Game editor name
#   - categories: JSONB - Array of category objects with words and difficulty
#
# JSON Format Expected:
#   [
#     {
#       "date": "2024-10-01",
#       "id": 478,
#       "editor": "Wyna Liu", 
#       "categories": [
#         {
#           "title": "CATEGORY NAME",
#           "level": 1,
#           "difficulty": "Easy",
#           "words": ["WORD1", "WORD2", "WORD3", "WORD4"]
#         }
#       ]
#     }
#   ]

# Set PostgreSQL connection parameters from environment variables with defaults
DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-connections}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_PASSWORD="${POSTGRES_PASSWORD:-password}"

JSON_FILE="${JSON_FILE:-solutions.json}"

# Check if file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: $JSON_FILE not found"
    exit 1
fi

# Create the database if it doesn't exist
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres <<EOF
SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = '$DB_NAME'
)\gexec
EOF

# Check if database creation was successful
if [ $? -ne 0 ]; then
    echo "❌ Error creating database $DB_NAME"
    exit 1
fi

echo "✅ Database $DB_NAME is ready"

# Create table if it doesn't exist
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS solutions (
    id SERIAL PRIMARY KEY,
    game_date DATE NOT NULL UNIQUE,
    game_id INTEGER,
    editor VARCHAR(255),
    categories JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_solutions_game_date ON solutions(game_date);
CREATE INDEX IF NOT EXISTS idx_solutions_categories ON solutions USING GIN(categories);
EOF

# Insert data into the database using COPY with proper JSON handling
TEMP_SQL=$(mktemp)

# Create a temporary SQL file with the JSON data
cat > "$TEMP_SQL" <<SQL_START
WITH json_data AS (
  SELECT '
SQL_START

# Escape the JSON content and append it
cat "$JSON_FILE" | sed "s/'/''/g" >> "$TEMP_SQL"

cat >> "$TEMP_SQL" <<'SQL_END'
'::json as data
)
INSERT INTO solutions (game_date, game_id, editor, categories)
SELECT 
    game_date::DATE,
    (game_data->>'id')::INTEGER as game_id,
    game_data->>'editor' as editor,
    COALESCE(game_data->'categories', '[]'::json) as categories
FROM json_data,
LATERAL json_each(json_data.data) as date_entries(game_date, game_data)
WHERE game_data->>'status' = 'OK'
ON CONFLICT (game_date) DO UPDATE SET
    game_id = EXCLUDED.game_id,
    editor = EXCLUDED.editor,
    categories = EXCLUDED.categories,
    created_at = CURRENT_TIMESTAMP;
SQL_END

# Execute the SQL file
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$TEMP_SQL"

# Store the exit code
PSQL_EXIT_CODE=$?

# Clean up temporary file
rm -f "$TEMP_SQL"

# Check if the insertion was successful
if [ $PSQL_EXIT_CODE -eq 0 ]; then
    echo "✅ Successfully imported solutions from $JSON_FILE"
    
    # Show count of imported records
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -c "
    SELECT 'Total records: ' || COUNT(*) FROM solutions;
    "
else
    echo "❌ Error importing solutions from $JSON_FILE"
    exit 1
fi