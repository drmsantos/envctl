#!/usr/bin/env python3
"""
envctl — DevOps Environment Control
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from tui.menu import main

if __name__ == "__main__":
    main()
