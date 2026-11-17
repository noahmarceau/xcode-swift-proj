#!/usr/bin/env python3
"""Portable artifact checks. Does not replace a real Xcode build/test run."""
from pathlib import Path
import csv,plistlib,xml.etree.ElementTree as ET,subprocess,sys
root=Path(__file__).resolve().parents[1]
for file in list((root/'Config').glob('*.plist')) + list((root/'Config').glob('*.entitlements')) + list((root/'Resources').glob('*.xcprivacy')):
    with file.open('rb') as handle: plistlib.load(handle)
for file in (root/'Forma.xcodeproj/xcshareddata/xcschemes').glob('*.xcscheme'): ET.parse(file)
with (root/'Resources/common-foods.csv').open(newline='') as handle:
    reader=csv.DictReader(handle)
    rows=list(reader)
    assert len(rows)>=10
    for row in rows:
        assert None not in row, 'extra CSV fields'
        assert all(v is not None for v in row.values()),'missing CSV columns'
        assert row['name'] and row['serving']
        for key in ['calories','protein_g','carbs_g','fat_g']:assert float(row[key])>=0
subprocess.run(['bash','-n',str(root/'Tools/build-ipa.sh')],check=True)
print('PASS: plists, scheme XML, starter CSV, shell syntax')
try:
    from pbxproj import XcodeProject
    project=XcodeProject.load(str(root/'Forma.xcodeproj/project.pbxproj'))
    for ref in project.objects.get_objects_in_section('PBXFileReference'):
        if ref.sourceTree=='<group>': assert (root/ref.path).is_file(),ref.path
    print('PASS: Xcode project parsed; file references exist')
except ImportError: print('SKIP: optional pbxproj parser not installed')
try:
    from tree_sitter import Language,Parser
    import tree_sitter_swift
    parser=Parser(Language(tree_sitter_swift.language()))
    files=list(root.rglob('*.swift'))
    for file in files:
        tree=parser.parse(file.read_bytes())
        assert not tree.root_node.has_error, f'Swift syntax issue: {file}'
    print(f'PASS: {len(files)} Swift files parsed (syntax only, not type checking)')
except ImportError: print('SKIP: optional tree-sitter and tree-sitter-swift parsers not installed')
print('Xcode build, XCTest, Simulator and device checks still required.')
