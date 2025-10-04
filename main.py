from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
import psycopg2
from psycopg2.extras import RealDictCursor
import json
from datetime import date, datetime
from typing import Any
import os
from contextlib import contextmanager

app = FastAPI(
    title="NYTimes Connections API",
    description="API to fetch NYTimes Connections game data",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# Database configuration
DATABASE_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "password"),
    "database": os.getenv("DB_NAME", "connections")
}

# Pydantic models
class Category(BaseModel):
    title: str
    level: int
    words: List[str]

class ConnectionsGame(BaseModel):
    id: int
    print_date: str
    editor: str
    categories: Any

@contextmanager
def get_db_connection():
    """Context manager for database connections"""
    conn = None
    try:
        conn = psycopg2.connect(**DATABASE_CONFIG)
        yield conn
    except psycopg2.Error as e:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if conn:
            conn.close()

def parse_date_string(date_str: str) -> date:
    """Parse date string in YYYY-MM-DD format"""
    try:
        return datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(
            status_code=400, 
            detail="Invalid date format. Expected YYYY-MM-DD"
        )

@app.get("/v1/connections/{date}", response_model=ConnectionsGame)
async def get_connections_game(date: str):
    """
    Get NYTimes Connections game data for a specific date
    
    Args:
        date: Date in YYYY-MM-DD format
        
    Returns:
        ConnectionsGame: Game data including categories and words
    """
    # Validate date format
    parsed_date = parse_date_string(date)
    
    with get_db_connection() as conn:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Query the database
        cursor.execute("""
            SELECT game_date, game_id, editor, categories
            FROM solutions 
            WHERE game_date = %s
        """, (parsed_date,))
        
        result = cursor.fetchone()
        
        if not result:
            raise HTTPException(
                status_code=404, 
                detail=f"No game data found for date {date}"
            )
        
        # Parse the JSONB categories data
        categories_data = result['categories']
        
        return ConnectionsGame(
            id=result['game_id'],
            print_date=result['game_date'].strftime("%Y-%m-%d"),
            editor=result['editor'],
            categories=categories_data
        )

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "NYTimes Connections API",
        "version": "1.0.0",
        "endpoints": {
            "get_game": "/v1/connections/{date}",
            "health": "/health"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)