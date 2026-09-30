import os
import sys
sys.path.insert(0,os.path.dirname(__file__))
sys.dont_write_bytecode=True
import render_barracks_mechanical_preview as preview

preview.OUT=os.path.join(preview.PROJECT_ROOT,'assets','concept_art','barracks_realistic_v3')
preview.VERSION='v3'
preview.LABEL='轻度写实'
preview.main()
