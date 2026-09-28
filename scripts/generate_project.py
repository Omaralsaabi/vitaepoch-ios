#!/usr/bin/env python3
"""Generate the dependency-free Xcode project; run when adding/removing Swift files."""
from pathlib import Path
import hashlib
import json
import subprocess
root = Path(__file__).resolve().parent.parent
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def ref(s): return uid(s)
# Preserve owner signing/bundle settings when refreshing file references.
personal_settings = {}
project_file = root/'VitaEpoch.xcodeproj/project.pbxproj'
if project_file.exists():
    existing = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project_file)]))
    for item in existing['objects'].values():
        build = item.get('buildSettings', {})
        if build.get('PRODUCT_NAME') == 'VitaEpoch':
            for key in ['PRODUCT_BUNDLE_IDENTIFIER', 'DEVELOPMENT_TEAM', 'CODE_SIGN_ENTITLEMENTS', 'CODE_SIGN_STYLE']:
                if key in build: personal_settings[key] = build[key]
objects = []
def obj(name, body): objects.append(f'{uid(name)} = {{ {body} }};')
files = sorted(list(root.glob('VitaEpoch/**/*.swift')) + list(root.glob('Sources/VitaEpochCore/*.swift')))
for file in files:
    path = file.relative_to(root).as_posix()
    obj(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ref(path)};')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = VitaEpoch.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('uitestproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = VitaEpochUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = ({ref("product")},{ref("uitestproduct")}); name = Products; sourceTree = "<group>";')
obj('root', 'isa = PBXGroup; children = (' + ','.join(ref(f.relative_to(root).as_posix()) for f in files) + ',' + ref('products') + ',' + ref('uitestfile') + '); sourceTree = "<group>";')
obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(ref('build:'+f.relative_to(root).as_posix()) for f in files) + '); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for config in ['Debug', 'Release']:
    obj('project'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 6.0; }};')
    settings = '''PRODUCT_NAME = VitaEpoch; PRODUCT_BUNDLE_IDENTIFIER = com.example.vitaepoch; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; INFOPLIST_KEY_CFBundleDisplayName = VitaEpoch; INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "VitaEpoch connects to your X6 band to sync health readings and activity to this iPhone."; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; SWIFT_EMIT_LOC_STRINGS = YES;'''
    import re
    for key, value in personal_settings.items():
        settings = re.sub(r'\b'+key+r' = [^;]+;', '', settings)
        settings += f' {key} = "{value}";'
    settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == 'Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O";'
    obj('target'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
for kind in ['project','target']:
    obj(kind+'configs', f'isa = XCConfigurationList; buildConfigurations = ({ref(kind+"Debug")},{ref(kind+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {ref("targetconfigs")}; buildPhases = ({ref("sources")},{ref("frameworks")},{ref("resources")}); buildRules = (); dependencies = (); name = VitaEpoch; productName = VitaEpoch; productReference = {ref("product")}; productType = "com.apple.product-type.application";')
obj('uitestfile', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/VitaEpochUITests.swift; sourceTree = SOURCE_ROOT;')
obj('uitestbuild', f'isa = PBXBuildFile; fileRef = {ref("uitestfile")};')
obj('uitestfixture', 'isa = PBXFileReference; lastKnownFileType = text.json; path = "Tests/VitaEpochCoreTests/Fixtures/device-2026-09-26.json"; sourceTree = SOURCE_ROOT;')
obj('physicalfixture', 'isa = PBXFileReference; lastKnownFileType = folder; path = "Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27"; sourceTree = SOURCE_ROOT;')
obj('physicalfixturebuild', f'isa = PBXBuildFile; fileRef = {ref("physicalfixture")};')
obj('uitestfixturebuild', f'isa = PBXBuildFile; fileRef = {ref("uitestfixture")};')
obj('uitestresources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("uitestfixturebuild")},{ref("physicalfixturebuild")}); runOnlyForDeploymentPostprocessing = 0;')
obj('uitestsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("uitestbuild")}); runOnlyForDeploymentPostprocessing = 0;')
obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("target")}; remoteInfo = VitaEpoch;')
obj('dependency', f'isa = PBXTargetDependency; target = {ref("target")}; targetProxy = {ref("proxy")};')
for config in ['Debug', 'Release']:
    obj('uitest'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ PRODUCT_NAME = VitaEpochUITests; PRODUCT_BUNDLE_IDENTIFIER = com.example.vitaepoch.uitests; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; TEST_TARGET_NAME = VitaEpoch; SWIFT_VERSION = 6.0; }};')
obj('uitestconfigs', f'isa = XCConfigurationList; buildConfigurations = ({ref("uitestDebug")},{ref("uitestRelease")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('uitesttarget', f'isa = PBXNativeTarget; buildConfigurationList = {ref("uitestconfigs")}; buildPhases = ({ref("uitestsources")},{ref("uitestresources")}); buildRules = (); dependencies = ({ref("dependency")}); name = VitaEpochUITests; productName = VitaEpochUITests; productReference = {ref("uitestproduct")}; productType = "com.apple.product-type.bundle.ui-testing";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2640; }}; buildConfigurationList = {ref("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {ref("root")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ref("target")},{ref("uitesttarget")});')
(root/'VitaEpoch.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {ref("project")}; }}\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="VitaEpoch.app" BlueprintName="VitaEpoch" ReferencedContainer="container:VitaEpoch.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('uitesttarget')}" BuildableName="VitaEpochUITests.xctest" BlueprintName="VitaEpochUITests" ReferencedContainer="container:VitaEpoch.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="VitaEpoch.app" BlueprintName="VitaEpoch" ReferencedContainer="container:VitaEpoch.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'VitaEpoch.xcodeproj/xcshareddata/xcschemes/VitaEpoch.xcscheme').write_text(scheme)
