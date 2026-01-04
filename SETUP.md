# Setup Instructions

## Python CLI (legacy)

The legacy Python CLI lives under `python-cli/`. It is kept for the original scripts/tools, but it is not used by the Rust core or the macOS app.

## Python Version

This project requires **Python 3.10 or newer** due to the use of modern type hints.

## Initial Setup

1. Install Python 3.11: `brew install python@3.11`
2. Create virtual environment: `python3.11 -m venv python-cli/venv`
3. Activate: `source python-cli/venv/bin/activate`
4. Install dependencies: `pip install -r python-cli/requirements.txt`

## Running

Run the Python tools from the `python-cli/` directory (the shell scripts there will activate the virtual environment):

```bash
cd python-cli
./stats.sh
./stat-page.sh
```
