"""Compare authored JSON and optional Rojo output with an independent rbx-dom export.

The fixture is a read-only snapshot of the five roots from the user's 1.rbxl.
It intentionally excludes scripts, avatar Rig and Studio editor state.
"""
from pathlib import Path
import json
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ALIASES = {'size':'Size', 'shape':'Shape', 'ScaleFactor':'Scale',
           'Color3uint8':'Color', 'MaterialVariantSerialized':'MaterialVariant',
           'InitialSize':'MeshSize', 'MeshContent':'MeshId', 'TextureContent':'TextureID'}
CF = ['X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22']


def f32(value):
    return struct.unpack('<f',struct.pack('<f',float(value)))[0]


def xml_instances(path, place=False):
    root = ET.parse(path).getroot()
    shared = {x.attrib['md5']: ''.join((x.text or '').split())
              for x in root.findall('./SharedStrings/SharedString')}
    result = {}
    def value(x):
        if x.tag in ('float','double'): return f32(x.text)
        if x.tag in ('int','int64','token'): return int(x.text)
        if x.tag == 'bool': return x.text=='true'
        if x.tag in ('Vector3','Vector2','Color3'):
            return [f32(v.text) for v in x]
        if x.tag=='Color3uint8':
            n=int(x.text);return [f32(((n>>shift)&255)/255) for shift in (16,8,0)]
        if x.tag=='CoordinateFrame': return [f32(x.findtext(k)) for k in CF]
        if x.tag=='OptionalCoordinateFrame':
            c=x.find('CFrame');return None if c is None else [f32(c.findtext(k)) for k in CF]
        if x.tag in ('Content','ContentId'): return x.findtext('uri') or x.findtext('url') or ''
        if x.tag=='SharedString': return shared[x.text]
        return x.text or ''
    def visit(node, prefix):
        p=node.find('Properties');name=p.findtext("string[@name='Name']")
        current=prefix+'/'+name
        result[current]={'ClassName':node.attrib['class'],'Properties':{
            ('Texture' if node.attrib['class'] in ('Texture','Decal') and x.attrib['name']=='TextureContent'
             else ALIASES.get(x.attrib['name'],x.attrib['name'])):value(x) for x in p}}
        for child in node.findall('Item'): visit(child,current)
    roots=root.findall('Item')
    if place:
        roots=next(x for x in roots if x.attrib['class']=='Workspace').findall('Item')
    for node in roots: visit(node,'Workspace')
    return result


def normalize(v):
    if isinstance(v,dict):
        if 'OptionalCFrame' in v:
            cf=v['OptionalCFrame']
            return None if cf is None else normalize(cf['position']+sum(cf['orientation'],[]))
        assert len(v)==1, v
        return normalize(next(iter(v.values())))
    if isinstance(v,list): return [normalize(x) for x in v]
    if isinstance(v,float): return f32(v)
    return v


def run(build_path=None):
    reference=xml_instances(ROOT/'tools/fixtures/authored_world.rbxmx')
    source={}
    def visit(node,path):
        source[path]=node
        for child in node.get('Children',[]): visit(child,path+'/'+child['Name'])
    for name in ('Garden','Flower','Bee','Baseplate','SpawnLocation'):
        path=ROOT/'src/Workspace'/f'{name}.model.json'
        node=json.loads(path.read_text(encoding='utf-8'))
        assert 'Name' not in node, f'{path}: top-level Name must be omitted'
        visit(node,'Workspace/'+name)
    assert set(source)==set(reference), 'Authored hierarchy changed during export'
    built=xml_instances(build_path,True) if build_path else None
    checks=0
    for path,node in source.items():
        assert node['ClassName']==reference[path]['ClassName'], path
        if built:
            assert path in built and built[path]['ClassName']==node['ClassName'],path
        for key,v in node.get('Properties',{}).items():
            expected=reference[path]['Properties'][key]
            assert normalize(v)==expected, f'Source differs from original: {path}.{key}'
            if built:
                assert built[path]['Properties'].get(key)==expected, f'Build differs from original: {path}.{key}'
            checks+=1
    assert len([p for p in source if p.startswith('Workspace/Garden/Slots/Slot')])==9
    print(f'WORLD FIDELITY: PASS ({len(source)} instances, {checks} properties'+
          (', clean build matches original)' if built else ', JSON matches original)'))


if __name__=='__main__':
    run(sys.argv[1] if len(sys.argv)>1 else None)
