"""Rebuild the small licensed sign font from NotoSansSC[wght].ttf (requires fonttools)."""
import argparse
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path,help='Official Google Fonts Noto Sans SC variable font')
a=parser.parse_args()
out=Path(__file__).resolve().parents[1]/'games/forma-playground/assets/fonts'
f=TTFont(a.source)
sub=subset.Subsetter(options=subset.Options())
sub.populate(text=''.join(chr(i) for i in range(32,127))+'掠夺者终点将箱子推到封印上信号塔家园')
sub.subset(f)
f=instantiateVariableFont(f,{'wght':500},inplace=True)
for nid,val in [(1,'Forma Game Signs'),(2,'Regular'),(3,'FormaGameSigns-20260909'),(4,'Forma Game Signs Regular'),(6,'FormaGameSigns-Regular')]:
    for pid,eid,lang in [(3,1,0x409),(1,0,0)]:f['name'].setName(val,nid,pid,eid,lang)
f.save(out/'forma-game-signs.ttf')
