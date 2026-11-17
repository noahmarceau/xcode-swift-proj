#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project; Python standard library only."""
from pathlib import Path
import hashlib, json, plistlib
root=Path(__file__).resolve().parents[1]
objects={}
def ident(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key,isa,**kwargs):
    i=ident(key);objects[i]=dict(isa=isa,**kwargs);return i

def ref(path,kind): return obj('file:'+path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>')
app_paths=sorted(str(p.relative_to(root)) for folder in ['App','Core','Features','Services'] for p in (root/folder).glob('*.swift'))
shared=['LiveActivity/WorkoutAttributes.swift','LiveActivity/WorkoutIntent.swift']
widget_paths=shared+['LiveActivity/WorkoutWidget.swift']
app_paths+=shared
test_paths=['Tests/FormaTests.swift']
resources=['Resources/common-foods.csv','Resources/PrivacyInfo.xcprivacy']
all_paths=sorted(set(app_paths+widget_paths+test_paths+resources+['Config/App-Info.plist','Config/Widget-Info.plist','Config/Health.entitlements']))
refs={p:ref(p,'sourcecode.swift' if p.endswith('.swift') else 'text.plist.xml' if p.endswith(('.plist','.entitlements','.xcprivacy')) else 'text') for p in all_paths}
products={name:obj('product:'+name,'PBXFileReference',explicitFileType=typ,includeInIndex=0,path=path,sourceTree='BUILT_PRODUCTS_DIR') for name,typ,path in [('Forma','wrapper.application','Forma.app'),('FormaLive','wrapper.app-extension','FormaLive.appex'),('FormaTests','wrapper.cfbundle','FormaTests.xctest')]}
products_group=obj('products','PBXGroup',children=list(products.values()),name='Products',sourceTree='<group>')
main_group=obj('main-group','PBXGroup',children=list(refs.values())+[products_group],sourceTree='<group>')
def phase(target,typ,paths):
    files=[obj('build:'+target+':'+p,'PBXBuildFile',fileRef=refs[p]) for p in paths]
    return obj(target+typ,typ,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
configs=['Debug','Release','HealthDebug','HealthRelease']
def config_list(target):
    result=[]
    for name in configs:
        debug='Debug' in name; health='Health' in name
        s={}
        if target=='project':
            s=dict(ALWAYS_SEARCH_USER_PATHS='NO',CLANG_ENABLE_MODULES='YES',CLANG_ENABLE_OBJC_ARC='YES',IPHONEOS_DEPLOYMENT_TARGET='17.0',SDKROOT='iphoneos',SWIFT_VERSION='5.0',SWIFT_STRICT_CONCURRENCY='minimal',SWIFT_OPTIMIZATION_LEVEL='-Onone' if debug else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if debug else 'dwarf-with-dsym',ENABLE_TESTABILITY='YES' if debug else 'NO',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if debug else '',GCC_PREPROCESSOR_DEFINITIONS=['$(inherited)','DEBUG=1'] if debug else ['$(inherited)'])
        else:
            s=dict(PRODUCT_NAME='$(TARGET_NAME)',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='',TARGETED_DEVICE_FAMILY='1',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO',MARKETING_VERSION='1.0',CURRENT_PROJECT_VERSION='1',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'],GENERATE_INFOPLIST_FILE='NO')
            if target=='Forma':
                s.update(PRODUCT_BUNDLE_IDENTIFIER='com.noahmarceau.forma',INFOPLIST_FILE='Config/App-Info.plist',SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited)'+(' HEALTHKIT_ENABLED' if health else ''),CODE_SIGN_ENTITLEMENTS='Config/Health.entitlements' if health else '')
            elif target=='FormaLive':
                s.update(PRODUCT_BUNDLE_IDENTIFIER='com.noahmarceau.forma.live',INFOPLIST_FILE='Config/Widget-Info.plist',SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) WIDGET_EXTENSION',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'])
            else:
                s.update(PRODUCT_BUNDLE_IDENTIFIER='com.noahmarceau.forma.tests',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/Forma.app/Forma',BUNDLE_LOADER='$(TEST_HOST)',SKIP_INSTALL='YES')
        result.append(obj('config:'+target+':'+name,'XCBuildConfiguration',name=name,buildSettings=s))
    return obj('config-list:'+target,'XCConfigurationList',buildConfigurations=result,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

def dependency(target):
    proxy=obj('proxy:'+target,'PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=ident('target:'+target),remoteInfo=target)
    return obj('dependency:'+target,'PBXTargetDependency',target=ident('target:'+target),targetProxy=proxy)
embed_file=obj('embed-file','PBXBuildFile',fileRef=products['FormaLive'],settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed=obj('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed_file],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
for target,paths,typ in [('Forma',app_paths,'com.apple.product-type.application'),('FormaLive',widget_paths,'com.apple.product-type.app-extension'),('FormaTests',test_paths,'com.apple.product-type.bundle.unit-test')]:
    phases=[phase(target,'PBXSourcesBuildPhase',paths),phase(target,'PBXFrameworksBuildPhase',[]),phase(target,'PBXResourcesBuildPhase',resources if target=='Forma' else [])]
    if target=='Forma':phases.append(embed)
    obj('target:'+target,'PBXNativeTarget',buildConfigurationList=config_list(target),buildPhases=phases,buildRules=[],dependencies=[dependency('FormaLive')] if target=='Forma' else [dependency('Forma')] if target=='FormaTests' else [],name=target,productName=target,productReference=products[target],productType=typ)
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{ident('target:'+x):{'CreatedOnToolsVersion':'16.0'} for x in products}},buildConfigurationList=config_list('project'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=products_group,projectDirPath='',projectRoot='',targets=[ident('target:'+x) for x in products])
def dump(v,depth=0):
    pad='\t'*depth
    if isinstance(v,dict):return '{\n'+''.join(pad+'\t'+json.dumps(str(k))+' = '+dump(val,depth+1)+';\n' for k,val in v.items())+pad+'}'
    if isinstance(v,list):return '('+', '.join(dump(x,depth) for x in v)+')'
    if isinstance(v,int):return str(v)
    return json.dumps(v)
project={'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ident('project')}
(root/'Forma.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+dump(project)+'\n')
for scheme,debug,release in [('Forma Local','Debug','Release'),('Forma Health','HealthDebug','HealthRelease')]:
    def br(target):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:"+target)}" BuildableName="{target+ (".app" if target=="Forma" else ".xctest")}" BlueprintName="{target}" ReferencedContainer="container:Forma.xcodeproj"/>'
    xml=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{br('Forma')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="{debug}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{br('FormaTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="{debug}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br('Forma')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="{release}" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br('Forma')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="{debug}"/><ArchiveAction buildConfiguration="{release}" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (root/f'Forma.xcodeproj/xcshareddata/xcschemes/{scheme}.xcscheme').write_text(xml)
base={'CFBundleDevelopmentRegion':'$(DEVELOPMENT_LANGUAGE)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}
app=dict(base,CFBundleDisplayName='Forma',CFBundlePackageType='APPL',LSRequiresIPhoneOS=True,NSSupportsLiveActivities=True,UILaunchScreen={},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],NSHealthShareUsageDescription='Forma reads body weight and active and resting energy to compare your nutrition and training progress.',NSHealthUpdateUsageDescription='Forma does not write health data.',CFBundleURLTypes=[{'CFBundleURLName':'Forma','CFBundleURLSchemes':['forma']}])
widget=dict(base,CFBundleDisplayName='Forma Workout',CFBundlePackageType='XPC!',NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})
for path,data in [('Config/App-Info.plist',app),('Config/Widget-Info.plist',widget),('Config/Health.entitlements',{'com.apple.developer.healthkit':True}),('Resources/PrivacyInfo.xcprivacy',{'NSPrivacyTracking':False,'NSPrivacyCollectedDataTypes':[],'NSPrivacyAccessedAPITypes':[]})]:
    with (root/path).open('wb') as f:plistlib.dump(data,f)
print('Generated Xcode project with app, Live Activity extension, and test targets.')
