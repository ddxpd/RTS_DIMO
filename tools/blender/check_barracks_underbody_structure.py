import os
import sys
sys.path.insert(0,os.path.dirname(__file__))
sys.dont_write_bytecode=True
from create_barracks_underbody_preview import main
main(bake=False)
