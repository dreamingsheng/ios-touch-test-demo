#!/usr/bin/env python3
"""Add the NativeSuiteUITests target to the CI-restored Xcode project.

The repository's project file is intentionally left untouched until this script
runs in the temporary build layout. Only Python's standard library is used.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_DIR = ROOT / "TouchTestApp.xcodeproj"
PBXPROJ = PROJECT_DIR / "project.pbxproj"
TEST_SOURCE = ROOT / "uitests" / "NativeSuiteUITests.swift"
SCHEME = PROJECT_DIR / "xcshareddata" / "xcschemes" / "NativeSuiteUITests.xcscheme"

IDS = {
    "source_build": "AA1300010000000000000001",
    "source_ref": "AA1300020000000000000001",
    "product_ref": "AA1300020000000000000002",
    "group": "AA1300030000000000000001",
    "sources": "AA1300040000000000000001",
    "frameworks": "AA1300040000000000000002",
    "resources": "AA1300040000000000000003",
    "target": "AA1300050000000000000001",
    "debug": "AA1300070000000000000001",
    "release": "AA1300070000000000000002",
    "config_list": "AA1300080000000000000001",
    "proxy": "AA1300090000000000000001",
    "dependency": "AA13000A0000000000000001",
}

OBJECT_START = re.compile(r"(?m)^\s*([A-F0-9]{24})(?:\s*/\*.*?\*/)?\s*=\s*\{")


def object_span(text: str, object_id: str) -> tuple[int, int]:
    match = re.search(rf"(?m)^\s*{re.escape(object_id)}(?:\s*/\*.*?\*/)?\s*=\s*\{{", text)
    if not match:
        raise RuntimeError(f"PBX object {object_id} was not found")
    opening = text.find("{", match.start())
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                semicolon = text.find(";", index)
                return match.start(), semicolon + 1
    raise RuntimeError(f"PBX object {object_id} is not balanced")


def objects(text: str):
    for match in OBJECT_START.finditer(text):
        object_id = match.group(1)
        start, end = object_span(text, object_id)
        yield object_id, text[start:end]


def find_object(text: str, isa: str, name: str | None = None) -> str:
    for object_id, block in objects(text):
        if re.search(rf"\bisa\s*=\s*{re.escape(isa)}\s*;", block) and (
            name is None or re.search(rf"\bname\s*=\s*\"?{re.escape(name)}\"?\s*;", block)
        ):
            return object_id
    raise RuntimeError(f"Could not find {isa} named {name!r}")


def block_for(text: str, object_id: str) -> str:
    start, end = object_span(text, object_id)
    return text[start:end]


def replace_block(text: str, object_id: str, block: str) -> str:
    start, end = object_span(text, object_id)
    return text[:start] + block + text[end:]


def insert_list_item(text: str, object_id: str, key: str, item: str) -> str:
    block = block_for(text, object_id)
    if re.search(rf"\b{re.escape(item.split()[0])}\b", block):
        return text
    pattern = re.compile(rf"(\b{re.escape(key)}\s*=\s*\()")
    if not pattern.search(block):
        raise RuntimeError(f"List {key!r} was not found in {object_id}")
    block = pattern.sub(rf"\1\n\t\t\t\t{item},", block, count=1)
    return replace_block(text, object_id, block)


def project_identifiers(text: str) -> tuple[str, str, str, str]:
    project_id = find_object(text, "PBXProject")
    project = block_for(text, project_id)
    main_group = re.search(r"\bmainGroup\s*=\s*([A-F0-9]{24})", project)
    product_group = re.search(r"\bproductRefGroup\s*=\s*([A-F0-9]{24})", project)
    if not main_group or not product_group:
        raise RuntimeError("PBXProject is missing mainGroup or productRefGroup")

    app_target = None
    for object_id, block in objects(text):
        if ("isa = PBXNativeTarget;" in block and
                "productType = \"com.apple.product-type.application\";" in block and
                re.search(r"\bname\s*=\s*TouchTestApp\s*;", block)):
            app_target = object_id
            break
    if app_target is None:
        raise RuntimeError("TouchTestApp application target was not found")
    return project_id, main_group.group(1), product_group.group(1), app_target


def add_target() -> tuple[str, str]:
    if not PBXPROJ.is_file():
        raise SystemExit(f"Missing Xcode project: {PBXPROJ}")
    if not TEST_SOURCE.is_file():
        raise SystemExit(f"Missing UI test source: {TEST_SOURCE}")

    text = PBXPROJ.read_text(encoding="utf-8")
    project_id, main_group, product_group, app_target = project_identifiers(text)

    if "name = NativeSuiteUITests;" in text:
        if IDS["target"] not in text:
            raise RuntimeError("A different NativeSuiteUITests target already exists; refusing to merge blindly")
        return app_target, project_id
    collisions = [value for value in IDS.values() if value in text]
    if collisions:
        raise RuntimeError(f"Deterministic PBX ids already exist: {collisions}")

    text = insert_list_item(text, main_group, "children", f'{IDS["group"]} /* NativeSuiteUITests */')
    text = insert_list_item(text, product_group, "children", f'{IDS["product_ref"]} /* NativeSuiteUITests.xctest */')
    text = insert_list_item(text, project_id, "targets", f'{IDS["target"]} /* NativeSuiteUITests */')

    project = block_for(text, project_id)
    target_attributes = re.compile(r"(\bTargetAttributes\s*=\s*\{)")
    if target_attributes.search(project):
        attribute = (
            f'\n\t\t\t\t{IDS["target"]} /* NativeSuiteUITests */ = '
            f'{{CreatedOnToolsVersion = 16.0; TestTargetID = {app_target};}};'
        )
        project = target_attributes.sub(rf"\1{attribute}", project, count=1)
        text = replace_block(text, project_id, project)

    definitions = f'''
\t\t{IDS["source_build"]} /* NativeSuiteUITests.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS["source_ref"]} /* NativeSuiteUITests.swift */; }};
\t\t{IDS["source_ref"]} /* NativeSuiteUITests.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NativeSuiteUITests.swift; sourceTree = "<group>"; }};
\t\t{IDS["product_ref"]} /* NativeSuiteUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NativeSuiteUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{IDS["group"]} /* NativeSuiteUITests */ = {{isa = PBXGroup; children = ({IDS["source_ref"]} /* NativeSuiteUITests.swift */,); path = uitests; sourceTree = "<group>"; }};
\t\t{IDS["sources"]} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({IDS["source_build"]} /* NativeSuiteUITests.swift in Sources */,); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{IDS["frameworks"]} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{IDS["resources"]} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{IDS["proxy"]} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {project_id} /* Project object */; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = TouchTestApp; }};
\t\t{IDS["dependency"]} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {app_target} /* TouchTestApp */; targetProxy = {IDS["proxy"]} /* PBXContainerItemProxy */; }};
\t\t{IDS["target"]} /* NativeSuiteUITests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {IDS["config_list"]} /* Build configuration list for PBXNativeTarget "NativeSuiteUITests" */;
\t\t\tbuildPhases = ({IDS["sources"]} /* Sources */, {IDS["frameworks"]} /* Frameworks */, {IDS["resources"]} /* Resources */,);
\t\t\tbuildRules = ();
\t\t\tdependencies = ({IDS["dependency"]} /* PBXTargetDependency */,);
\t\t\tname = NativeSuiteUITests;
\t\t\tproductName = NativeSuiteUITests;
\t\t\tproductReference = {IDS["product_ref"]} /* NativeSuiteUITests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";
\t\t}};
\t\t{IDS["debug"]} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Touch Test UI Tests"; IPHONEOS_DEPLOYMENT_TARGET = 16.0; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.example.TouchTestDemo.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = TouchTestApp; }}; name = Debug; }};
\t\t{IDS["release"]} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Touch Test UI Tests"; IPHONEOS_DEPLOYMENT_TARGET = 16.0; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.example.TouchTestDemo.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = TouchTestApp; }}; name = Release; }};
\t\t{IDS["config_list"]} /* Build configuration list for PBXNativeTarget "NativeSuiteUITests" */ = {{isa = XCConfigurationList; buildConfigurations = ({IDS["debug"]} /* Debug */, {IDS["release"]} /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
'''
    marker = "\tobjects = {"
    if marker not in text:
        raise RuntimeError("The project file has no objects dictionary")
    text = text.replace(marker, marker + definitions, 1)
    PBXPROJ.write_text(text, encoding="utf-8", newline="\n")
    return app_target, project_id


def write_scheme(app_target: str) -> None:
    xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TouchTestApp.app" BlueprintName="TouchTestApp" ReferencedContainer="container:TouchTestApp.xcodeproj"/>
      </BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{IDS['target']}" BuildableName="NativeSuiteUITests.xctest" BlueprintName="NativeSuiteUITests" ReferencedContainer="container:TouchTestApp.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES">
    <MacroExpansion><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TouchTestApp.app" BlueprintName="TouchTestApp" ReferencedContainer="container:TouchTestApp.xcodeproj"/></MacroExpansion>
    <Testables><TestableReference skipped="NO" parallelizable="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{IDS['target']}" BuildableName="NativeSuiteUITests.xctest" BlueprintName="NativeSuiteUITests" ReferencedContainer="container:TouchTestApp.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TouchTestApp.app" BlueprintName="TouchTestApp" ReferencedContainer="container:TouchTestApp.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TouchTestApp.app" BlueprintName="TouchTestApp" ReferencedContainer="container:TouchTestApp.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    SCHEME.parent.mkdir(parents=True, exist_ok=True)
    SCHEME.write_text(xml, encoding="utf-8", newline="\n")


def main() -> None:
    app_target, _ = add_target()
    write_scheme(app_target)
    print(f"Configured NativeSuiteUITests in {PBXPROJ}")
    print(f"Shared scheme: {SCHEME}")


if __name__ == "__main__":
    main()
