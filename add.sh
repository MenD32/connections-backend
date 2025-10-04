#!/bin/bash

# Function to validate date format YYYY-MM-DD
validate_date() {
    local date_regex='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    if [[ ! $1 =~ $date_regex ]]; then
        echo "Error: Date must be in YYYY-MM-DD format"
        exit 1
    fi
    
    # Additional validation could be added here if needed
}

# Default to today's date if not provided
DATE=$(date +%Y-%m-%d)

# Parse command line arguments
while getopts ":d:" opt; do
    case ${opt} in
        d )
            DATE=$OPTARG
            validate_date "$DATE"
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            echo "Usage: $0 [-d YYYY-MM-DD]" 1>&2
            exit 1
            ;;
        : )
            echo "Option -$OPTARG requires an argument" 1>&2
            echo "Usage: $0 [-d YYYY-MM-DD]" 1>&2
            exit 1
            ;;
    esac
done

echo "Using date: $DATE"

data=`curl -X GET "https://www.nytimes.com/svc/connections/v2/$DATE.json" -H "Content-Type: application/json"`
# Check if the data is valid JSON
if ! echo "$data" | jq . >/dev/null 2>&1; then
    echo "Error: Failed to fetch valid data from NYT API"
    exit 1
fi

# Create solutions.json if it doesn't exist
if [ ! -f solutions.json ]; then
    echo "{}" > solutions.json
fi

# Add or update the data for the specific date
temp_file=$(mktemp)
jq --arg date "$DATE" --argjson data "$data" '.[$date] = $data' solutions.json > "$temp_file"
mv "$temp_file" solutions.json

echo "Data for $DATE added to solutions.json"