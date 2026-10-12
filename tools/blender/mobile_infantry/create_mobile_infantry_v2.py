import sys as _sys
from pathlib import Path as _Path
_blender_tools = _Path(__file__).resolve().parents[1]
_sys.path[:0] = [str(_Path(__file__).resolve().parent), str(_blender_tools), str(_blender_tools / "shared")]
"""Reference-driven mobile infantry: editable quad low mesh and bake-only detail mesh."""
import bpy
import importlib.util
import json
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = os.path.dirname(__file__)
spec = importlib.util.spec_from_file_location('mi_base', os.path.join(HERE, 'create_mobile_infantry.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base.COLORS.update(fabric=(.48,.465,.42), armor=(.58,.58,.54), cloth=(.052,.059,.061), edge=(.115,.133,.143), metal=(.13,.15,.16), mark=(.8,.8,.8))
base.ROUGH.update(fabric=.89, armor=.56, cloth=.91, mark=.52)
base.METAL.update(fabric=0, armor=.08, cloth=0, mark=.04)
base.BLUE = (.018,.115,.32,1)


def tilt(degrees, axis='Y'):
    return Matrix.Rotation(math.radians(degrees), 4, axis).to_quaternion()


class Builder(base.Builder):
    def __init__(self):
        super().__init__()
        self.scene.name = 'MI_V2_Asset'
        self.root['asset_version'] = 2
        self.high_objects = []

    def limb(self, name, a, b, width, depth, kind='cloth'):
        a,b = Vector(a),Vector(b)
        length = (b-a).length
        rings = [(0,width*.85,depth*.83),(.13*length,width,depth),(.43*length,width*.98,depth*.98),(.72*length,width*.88,depth*.90),(length,width*.72,depth*.78)]
        obj = self.part(name,rings,kind,a,(b-a).to_track_quat('Z','Y'),smooth=True)
        # Uneven broad folds affect silhouette without turning the cloth into plates.
        for vertex in obj.data.vertices:
            t = vertex.co.z / length
            angle = math.atan2(vertex.co.y,vertex.co.x)
            amplitude = .004*math.sin(math.pi*max(0,min(1,t)))
            vertex.co.x += amplitude*math.sin(t*19+angle*2)
            vertex.co.y += amplitude*math.cos(t*23-angle*2)
        obj.data.update()
        return obj

    def strap(self,name,a,b,width=.042,depth=.018,kind='rubber'):
        a,b = Vector(a),Vector(b)
        return self.box(name,(a+b)*.5,(width,depth,(b-a).length),kind,.003,(b-a).to_track_quat('Z','Y'))

    def build_geometry(self):
        self.part('TorsoUndersuit',[(1.035,.29,.195),(1.19,.325,.225),(1.37,.405,.25),(1.475,.365,.205),(1.51,.245,.16)],'cloth',smooth=True)
        self.part('TrouserSeat',[(.845,.31,.195),(.94,.36,.26),(1.045,.305,.215)],'fabric',smooth=True)
        self.box('UtilityBelt',(0,0,1.045),(.345,.253,.069),'rubber',.004)
        self.box('BeltBuckle',(0,-.139,1.047),(.069,.028,.047),'edge',.003)
        self.part('UpperChestPlate',[(1.235,.23,.054),(1.265,.33,.068),(1.40,.37,.065),(1.454,.295,.05)],center=(0,-.125,0))
        self.part('AbdomenPlate',[(1.10,.235,.045),(1.18,.275,.060),(1.238,.22,.047)],center=(0,-.115,0))
        self.box('ChestCollar',(0,-.128,1.452),(.18,.035,.04),'edge',.003)
        self.part('BackArmor',[(1.15,.245,.065),(1.24,.32,.09),(1.425,.295,.077),(1.46,.235,.060)],center=(0,.128,0))
        self.box('BackFaction',(0,.179,1.365),(.134,.008,.064),'mark',.002)
        self.box('BackLowerPack',(0,.178,1.15),(.18,.08,.108),'edge',.006)
        for s in [-1,1]:
            self.strap('ShoulderHarness'+str(s),(s*.137,-.107,1.39),(s*.178,-.045,1.51),.050,.027)
            self.strap('BackHarness'+str(s),(s*.137,.17,1.35),(s*.178,.045,1.51),.044,.018)
            self.box('FrontMagPouch'+str(s),(s*.112,-.163,1.075),(.069,.070,.124),'edge',.004)
            self.box('RearBeltPouch'+str(s),(s*.135,.142,1.05),(.093,.064,.093),'edge',.005)
            hip=(s*.105,0,.945)
            knee=(s*.157,-.015,.585)
            ankle=(s*.18,.008,.205)
            self.limb('TrouserThigh'+str(s),hip,knee,.211,.233,'fabric')
            self.limb('TrouserCalf'+str(s),knee,ankle,.171,.176,'fabric')
            self.box('ThighStrap'+str(s),(s*.137,-.004,.79),(.235,.253,.032),'rubber',.003)
            self.box('SideThighPouch'+str(s),(s*.252,.003,.777),(.064,.13,.16),'edge',.006)
            self.box('PouchFlap'+str(s),(s*.287,.003,.804),(.009,.096,.063),'rubber',.002)
            self.box('KneeBacking'+str(s),(s*.155,-.104,.563),(.146,.058,.139),'rubber',.010)
            self.part('KneeFaction'+str(s),[(-.065,.086,.028),(-.03,.126,.038),(.041,.121,.035),(.060,.082,.022)],'mark',(s*.155,-.139,.567),tilt(s*-6))
            self.box('AnkleGaiter'+str(s),(s*.18,0,.219),(.14,.169,.063),'rubber',.006)
            self.part('BootShaft'+str(s),[(.045,.154,.175),(.12,.153,.17),(.215,.126,.15)],'rubber',(s*.18,.005,0))
            self.box('BootToe'+str(s),(s*.18,-.094,.083),(.159,.204,.106),'edge',.019)
            self.box('BootSole'+str(s),(s*.18,-.054,.025),(.17,.291,.044),'rubber',.006)
            self.box('BootInstepStrap'+str(s),(s*.18,-.055,.141),(.158,.057,.025),'rubber',.003,tilt(-17,'X'))

        self.part('NeckSeal',[(1.45,.13,.139),(1.56,.132,.145),(1.6,.11,.13)],'rubber',smooth=True)
        self.part('HelmetInner',[(1.535,.123,.143),(1.595,.214,.212),(1.72,.242,.1972),(1.79,.211,.17)],'rubber',smooth=True)
        dome=self.part('HelmetDome',[(1.699,.257,.251),(1.751,.263,.253),(1.808,.222,.210),(1.840,.143,.144),(1.849,.06,.072)],center=(0,.014,0),smooth=True)
        dome.data.materials.append(self.materials[1])
        for index in [8,16,24,36,37,38,39]:
            dome.data.polygons[index].material_index=1
        self.box('VisorGlass',(0,-.123,1.684),(.208,.053,.072),'visor',.009)
        self.box('VisorBrow',(0,-.144,1.729),(.230,.025,.024),'edge',.003)
        self.part('RespiratorCore',[(1.547,.082,.074),(1.597,.123,.093),(1.652,.119,.073)],'rubber',(0,-.115,0))
        for s in [-1,1]:
            self.strap('CheekArmor'+str(s),(s*.042,-.152,1.553),(s*.103,-.119,1.669),.054,.037,'armor')
            self.box('CheekVent'+str(s),(s*.080,-.165,1.593),(.034,.015,.038),'edge',.003,tilt(s*24))
            self.part('EarHousing'+str(s),[(-.018,.118,.13),(-.014,.138,.151),(.013,.138,.151),(.019,.112,.124)],'edge',(s*.134,.021,1.677),tilt(90))
            self.part('EarInset'+str(s),[(-.003,.075,.084),(.003,.082,.091)],'rubber',(s*.156,.021,1.677),tilt(90))

        origin=Vector((-.025,-.287,1.19))
        rotation=tilt(35)
        gun_point=lambda offset: origin+rotation@Vector(offset)
        right_hand=gun_point((-.085,-.009,-.107))
        left_hand=gun_point((.160,-.020,-.057))
        for label,a,b,c in [('R',(-.246,0,1.429),(-.303,-.094,1.174),right_hand),('L',(.246,0,1.429),(.324,-.105,1.166),left_hand)]:
            side=-1 if label=='R' else 1
            self.limb('SleeveUpper'+label,a,b,.145,.163)
            self.limb('SleeveFore'+label,b,c,.122,.14)
            q=(Vector(b)-Vector(a)).to_track_quat('Z','Y')
            center=Vector(a)+(Vector(b)-Vector(a))*.19+Vector((side*.017,-.006,.006))
            self.part('ShoulderArmor'+label,[(-.092,.113,.160),(-.051,.168,.211),(.053,.164,.205),(.081,.118,.15)],'armor',center,q)
            self.part('ShoulderFaction'+label,[(-.067,.040,.135),(-.044,.052,.170),(.042,.052,.169),(.060,.037,.132)],'mark',center+Vector((side*.065,-.025,.025)),q)
            self.box('ElbowGuard'+label,Vector(b)+Vector((side*.025,.028,0)),(.131,.117,.092),'edge',.012,q)
            fore=(Vector(c)-Vector(b)); mid=Vector(b)+fore*.46
            self.box('ForearmArmor'+label,mid+Vector((0,-.045,.018)),(.12,.075,fore.length*.73),'armor',.012,fore.to_track_quat('Z','Y'))
            self.box('ForearmBand'+label,mid+Vector((0,-.087,.020)),(.038,.009,.07),'mark',.002,fore.to_track_quat('Z','Y'))
            self.box('Glove'+label,c,(.094,.089,.106),'rubber',.014,rotation)
            self.box('GloveKnuckle'+label,Vector(c)+Vector((0,-.045,.010)),(.085,.019,.045),'edge',.007,rotation)

        def gun(name,offset,size,kind='metal',bevel=.004):
            return self.box('Rifle_'+name,gun_point(offset),size,kind,bevel,rotation)
        gun('Receiver',(-.055,0,0),(.25,.063,.091))
        gun('Handguard',(.14,0,0),(.174,.072,.075),'edge')
        gun('Stock',(-.28,0,.005),(.205,.055,.091),'rubber',.008)
        gun('Butt',(-.391,0,.005),(.025,.069,.133),'rubber')
        gun('Barrel',(.285,0,.004),(.123,.027,.027),'metal',.002)
        gun('Muzzle',(.36,0,.004),(.061,.040,.040),'edge',.003)
        gun('Bore',(.392,0,.004),(.003,.022,.022),'rubber',.001)
        gun('Magazine',(-.006,0,-.11),(.069,.051,.147),'rubber')
        gun('Grip',(-.11,0,-.092),(.045,.05,.105),'rubber')
        gun('Rail',(.006,0,.054),(.30,.031,.014),'edge',.002)
        gun('ScopeBase',(-.035,0,.078),(.091,.035,.040),'rubber')
        scope_q=rotation@tilt(90)
        self.part('Rifle_Optic',[(-.063,.044,.044),(-.047,.055,.055),(.047,.05,.05),(.063,.038,.038)],'rubber',gun_point((-.031,0,.111)),scope_q)
        self.scene.view_layers[0].update()

    def validate(self):
        report=super().validate()
        report.update(version=2,reference='assets/concept_art/机动兵.png',high_detail_collection='MI_V2_BakeSources',ao_baked=getattr(self,'baked',False),normal_baked=getattr(self,'baked',False))
        return report

    def grey_preview(self):
        self.textures()
        self.studio()
        self.scene.cycles.samples=40
        self.render('mobile-infantry-front-v2-grey.png',(2.5,-6,2.8),target=(0,0,.95),scale=2.17)


def create_grey():
    previous=bpy.context.window.scene
    try:
        b=Builder()
        bpy.app.driver_namespace['mi_v2_builder']=b
        bpy.context.window.scene=b.scene
        b.build_geometry()
        b.layout_uv()
        b.validate()
        b.grey_preview()
        return b
    finally:
        bpy.context.window.scene=previous


def create():
    """Rebuild, bake, export and render without replacing the user's open blend."""
    previous=bpy.context.window.scene
    try:
        builder=create_grey()
        bpy.context.window.scene=builder.scene
        modules={}
        for name in ['bake_mobile_infantry_v2','finalize_mobile_infantry_v2']:
            module_spec=importlib.util.spec_from_file_location(name,os.path.join(HERE,name+'.py'))
            module=importlib.util.module_from_spec(module_spec)
            module_spec.loader.exec_module(module)
            modules[name]=module
        baker=modules['bake_mobile_infantry_v2']
        finalizer=modules['finalize_mobile_infantry_v2']
        baker.bake(builder,base.OUT)
        baker.weather(builder,base.OUT)
        builder.report['high_detail_collection']=builder.high_collection.name
        finalizer.export(builder,base)
        finalizer.render(builder)
        return builder
    finally:
        bpy.context.window.scene=previous


if __name__=='__main__':
    create()
