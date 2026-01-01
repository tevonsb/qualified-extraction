# Setup Instructions

## Python Version

This project requires **Python 3.10 or newer** due to the use of modern type hints.

## Initial Setup

1. Install Python 3.11: `brew install python@3.11`
2. Create virtual environment: `python3.11 -m venv venv`
3. Activate: `source venv/bin/activate`
4. Install dependencies: `pip install -r requirements.txt`

## Running

The shell scripts will automatically activate the virtual environment.

```bash
./run.sh           # Extract all data
./run.sh --list    # List collectors
```
