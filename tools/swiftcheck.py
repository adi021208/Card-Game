#!/usr/bin/env python3
"""
Structural checker for the DECK Swift sources.

There is no Swift toolchain on this machine, so this stands in for the parts of
the compiler that catch mechanical mistakes: unbalanced delimiters, duplicate
type declarations, references to types that do not exist anywhere in the
project, and enum cases used in a switch that the enum does not define.

It is deliberately conservative: it reports only things it is confident about.
"""
import os, re, sys, json
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --- switch exhaustiveness (file-scoped) ------------------------------------

def enum_bodies(code):
    """Enum name -> set of case names, for enums declared in this file."""
    out = {}
    for m in re.finditer(r'\benum\s+([A-Z][A-Za-z0-9_]*)[^{\n]*\{', code):
        name, start = m.group(1), m.end() - 1
        depth, i = 0, start
        while i < len(code):
            if code[i] == '{': depth += 1
            elif code[i] == '}':
                depth -= 1
                if depth == 0: break
            i += 1
        cases = set()
        for cm in re.finditer(r'^\s*(?:indirect\s+)?case\s+([^\n]+)$', code[start:i], re.M):
            raw = cm.group(1)
            # A `case .foo:` or `case let .foo(x):` line inside the enum body is a
            # switch label, not a declaration.
            if re.match(r'\s*(?:let\s+|var\s+)?\.', raw): continue
            for part in re.split(r',(?![^(]*\))', raw):
                nm = re.match(r'\s*([a-z_][A-Za-z0-9_]*)', part)
                if nm and nm.group(1) not in ('let', 'var'): cases.add(nm.group(1))
        out[name] = cases
    return out


def check_switches(path, code):
    """Reports a switch that omits a case of an enum declared in the same file."""
    enums = enum_bodies(code)
    if not enums: return []
    problems = []
    for m in re.finditer(r'\bswitch\b([^\{\n]*)\{', code):
        start = m.end() - 1
        depth, i = 0, start
        while i < len(code):
            if code[i] == '{': depth += 1
            elif code[i] == '}':
                depth -= 1
                if depth == 0: break
            i += 1
        body = code[start + 1:i]
        if re.search(r'^\s*default\s*:', body, re.M): continue
        labels = set()
        for cm in re.finditer(r'^\s*case\s+(.+?)\s*:', body, re.M):
            for part in re.split(r',(?![^(]*\))', cm.group(1)):
                part = part.replace('let ', '').replace('var ', '')
                nm = re.search(r'\.([a-z_][A-Za-z0-9_]*)', part)
                if nm: labels.add(nm.group(1))
        if not labels: continue
        matches = [(n, c) for n, c in enums.items() if labels <= c]
        if len(matches) != 1: continue
        name, cases = matches[0]
        missing = sorted(cases - labels)
        if missing:
            line = code.count('\n', 0, m.start()) + 1
            problems.append(f"{path}:{line}: switch over '{name}' does not handle {missing}")
    return problems


# --- lexing -----------------------------------------------------------------

def strip_code(src):
    """Replace string literals and comments with spaces, preserving offsets."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i+1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif c == '/' and i + 1 < n and src[i+1] == '*':
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('/*', j): depth += 1; j += 2
                elif src.startswith('*/', j): depth -= 1; j += 2
                else: j += 1
            seg = src[i:j]
            out.append(''.join(ch if ch == '\n' else ' ' for ch in seg)); i = j
        elif src.startswith('"""', i):
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
            seg = src[i:j]
            out.append(''.join(ch if ch == '\n' else ' ' for ch in seg)); i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\': j += 2; continue
                if src[j] == '"': j += 1; break
                if src[j] == '\n': break
                j += 1
            seg = src[i:j]
            out.append(''.join(ch if ch == '\n' else ' ' for ch in seg)); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)


def check_balance(path, code):
    problems = []
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    line = 1
    for ch in code:
        if ch == '\n': line += 1
        elif ch in '([{': stack.append((ch, line))
        elif ch in ')]}':
            if not stack:
                problems.append(f"{path}:{line}: unmatched '{ch}'")
            else:
                open_ch, open_line = stack.pop()
                if open_ch != pairs[ch]:
                    problems.append(f"{path}:{line}: '{ch}' closes '{open_ch}' opened at line {open_line}")
    for open_ch, open_line in stack:
        problems.append(f"{path}:{open_line}: unclosed '{open_ch}'")
    return problems


DECL_RE = re.compile(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
    r'(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+|package\s+)?'
    r'(?:final\s+|indirect\s+)*'
    r'(struct|class|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)',
    re.M)

EXT_RE = re.compile(r'^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?extension\s+([A-Za-z_][A-Za-z0-9_.]*)', re.M)

# Nested type declarations still count as declared names for our purposes.
CASE_RE = re.compile(r'^\s*(?:indirect\s+)?case\s+([a-z_][A-Za-z0-9_]*)', re.M)

KNOWN = set("""
DeckCore DeckGames DeckAI DeckCatalog DeckProgression DeckEngine SwiftUI UIKit Combine StoreKit GameKit
UserNotifications CoreHaptics AVFoundation Observation XCTest Testing
XCTAssert XCTAssertTrue XCTAssertFalse XCTAssertEqual XCTAssertNotEqual XCTAssertNil
XCTAssertNotNil XCTAssertGreaterThan XCTAssertLessThan XCTAssertGreaterThanOrEqual
XCTAssertLessThanOrEqual XCTAssertThrowsError XCTAssertNoThrow XCTFail XCTestCase
XCTAssertEqualWithAccuracy XCTUnwrap XCTSkip XCTestExpectation XCTAssertIdentical
Package PackageDescription Target SwiftSetting LinkerSetting DEBUG RELEASE
Any AnyObject AnyHashable Array ArraySlice Bool Character ClosedRange CodingKey Codable
CodingKeyRepresentable Collection Comparable CustomStringConvertible Data Date DateComponents
DateFormatter DateInterval Decodable Decoder Dictionary Double Encodable Encoder Equatable Error
ExpressibleByArrayLiteral ExpressibleByStringLiteral Float Hashable Hasher Identifiable Int Int8
Int16 Int32 Int64 IteratorProtocol JSONDecoder JSONEncoder KeyedDecodingContainer LazyMapSequence
Locale NSLock NSObject Never Numeric Optional OptionSet PartialRangeFrom Range RandomNumberGenerator
RangeReplaceableCollection RawRepresentable Result Self Sendable Sequence Set String StringProtocol
Strideable SubSequence Substring SystemRandomNumberGenerator TimeInterval TimeZone URL UUID UInt
UInt8 UInt16 UInt32 UInt64 UnkeyedDecodingContainer Void Calendar CharacterSet Comparator
FileManager IndexSet Measurement NumberFormatter Notification NotificationCenter OperationQueue
ProcessInfo PropertyListDecoder PropertyListEncoder RunLoop Task Thread Timer URLSession UserDefaults
Bundle NSNumber NSString NSError NSRange NSAttributedString Foundation Swift Numeric BinaryInteger BinaryFloatingPoint
FloatingPoint SignedInteger UnsignedInteger CaseIterable MainActor Actor AsyncStream AsyncSequence
Continuation CheckedContinuation Duration Clock Instant ContiguousArray Slice Mirror
DispatchQueue DispatchTime DispatchWorkItem OSLog Logger Character UnicodeScalar
""".split())

SWIFTUI = set("""
View Text Image Button Color Font ViewBuilder State Binding ObservedObject StateObject
EnvironmentObject Environment Published ObservableObject VStack HStack ZStack ScrollView List
NavigationStack NavigationLink NavigationPath NavigationSplitView Spacer Divider Group ForEach
GeometryReader GeometryProxy Path Shape InsettableShape Rectangle RoundedRectangle Circle Ellipse
Capsule Canvas GraphicsContext Animation AnyTransition Transition Angle UnitPoint Alignment Edge
EdgeInsets CGFloat CGPoint CGSize CGRect CGAffineTransform Gradient LinearGradient RadialGradient
AngularGradient Shadow Material Blur ShapeStyle Toggle Slider Stepper Picker TextField SecureField
Form Section Label Menu Sheet Alert ConfirmationDialog TabView Tab PreferenceKey ViewModifier
EnvironmentValues EnvironmentKey Namespace MatchedGeometryEffect DragGesture TapGesture LongPressGesture
MagnificationGesture RotationGesture SimultaneousGesture SequenceGesture ExclusiveGesture GestureState
Gesture AnyView EmptyView Preview PreviewProvider App Scene WindowGroup Commands UIApplication
UIViewRepresentable UIViewControllerRepresentable UIView UIViewController UIColor UIFont UIImage
UIScreen UIDevice UIImpactFeedbackGenerator UINotificationFeedbackGenerator UISelectionFeedbackGenerator
Observable Bindable ScrollViewProxy ScrollViewReader ProgressView ContentUnavailableView
AnyShape TimelineView Canvas GraphicsContext EmptyShape UnevenRoundedRectangle RectangleCornerRadii
LazyVGrid LazyHGrid LazyVStack LazyHStack GridItem Grid GridRow DisclosureGroup NavigationSplitViewVisibility
TextEditor DatePicker ColorPicker ShareLink PhotosPicker Chart RenameButton EditButton
LabeledContent Gauge OutlineGroup Table TableColumn ControlGroup
SymbolRenderingMode ContentMode Axis ScrollTargetBehavior VisualEffect KeyframeAnimator
PhaseAnimator Spring UnitCurve StrokeStyle FillStyle Transform3D ContainerRelativeShape
AccessibilityTraits AccessibilityAdjustmentDirection LocalizedStringKey LocalizedStringResource
CGVector CGColor CGPath CGContext CGImage CGGradient CGBlendMode CACurrentMediaTime CATransform3D
DynamicTypeSize ColorScheme ScenePhase OpenURLAction Transaction Product StoreKit AppStore VerificationResult Transaction StoreKitError GKLocalPlayer
GKLeaderboard GKAchievement GKGameCenterViewController UNUserNotificationCenter UNMutableNotificationContent
UNCalendarNotificationTrigger UNNotificationRequest UNAuthorizationOptions AVAudioSession AVAudioEngine
AVAudioPlayerNode AVAudioPCMBuffer AVAudioFormat AVAudioFrameCount AVAudioTime AVAudioSessionCategory
Int32 UInt32 Float32 Float64 CHHapticEngine CHHapticPattern CHHapticEvent
CHHapticEventParameter UIFeedbackGenerator ProcessInfo Set Dictionary
Text Layout LayoutSubviews ProposedViewSize ViewThatFits AnyLayout HorizontalAlignment
VerticalAlignment ToolbarItem ToolbarItemGroup ToolbarPlacement SafeAreaRegions
""".split())

def collect(paths):
    declared = defaultdict(list)     # name -> [path]
    enum_cases = defaultdict(set)    # EnumName -> {case,...}
    files = {}
    problems = []
    for path in paths:
        src = open(path, encoding='utf-8').read()
        code = strip_code(src)
        files[path] = code
        problems += check_balance(path, code)
        problems += check_switches(path, code)
        # Qualify each declaration with its enclosing type path, so two games
        # may each declare their own nested `State` without a false duplicate.
        decls = [(m.start(), m.group(2)) for m in DECL_RE.finditer(code)]
        opens = []  # (name, depth_at_open)
        depth = 0
        di = 0
        pending = None
        for idx, ch in enumerate(code):
            while di < len(decls) and decls[di][0] <= idx:
                pending = decls[di][1]
                declared['.'.join([n for n, _ in opens] + [pending])].append(path)
                di += 1
            if ch == '{':
                depth += 1
                if pending is not None:
                    opens.append((pending, depth))
                    pending = None
            elif ch == '}':
                while opens and opens[-1][1] == depth:
                    opens.pop()
                depth -= 1
        # enum cases, scoped by brace matching
        for m in re.finditer(r'\benum\s+([A-Z][A-Za-z0-9_]*)[^{]*\{', code):
            name = m.group(1)
            start = m.end() - 1
            depth, i = 0, start
            while i < len(code):
                if code[i] == '{': depth += 1
                elif code[i] == '}':
                    depth -= 1
                    if depth == 0: break
                i += 1
            body = code[start:i]
            for cm in CASE_RE.finditer(body):
                enum_cases[name].add(cm.group(1))
            for cm in re.finditer(r'^\s*case\s+(.+)$', body, re.M):
                for part in cm.group(1).split(','):
                    nm = re.match(r'\s*([a-z_][A-Za-z0-9_]*)', part)
                    if nm: enum_cases[name].add(nm.group(1))
    return declared, enum_cases, files, problems


TYPE_REF_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\b')

def main():
    targets = sys.argv[1:] or ['DeckEngine/Sources', 'DeckEngine/Tests', 'Deck']
    paths = []
    for t in targets:
        full = os.path.join(ROOT, t)
        for dirpath, _, filenames in os.walk(full):
            for fn in sorted(filenames):
                if fn.endswith('.swift'):
                    paths.append(os.path.join(dirpath, fn))
    declared, enum_cases, files, problems = collect(paths)

    # Generic parameters and associated types are declared names too.
    generics = set()
    for code in files.values():
        for m in re.finditer(r'\bassociatedtype\s+([A-Z][A-Za-z0-9_]*)', code):
            generics.add(m.group(1))
        for m in re.finditer(r'(?:struct|class|enum|func|typealias|actor)\s+\w+\s*<([^>]*)>', code):
            for part in m.group(1).split(','):
                nm = re.match(r'\s*([A-Z][A-Za-z0-9_]*)', part)
                if nm: generics.add(nm.group(1))
        for m in re.finditer(r'\bElement\b|\bSelf\b', code):
            generics.add(m.group(0))

    for name, locs in sorted(declared.items()):
        if len(locs) > 1:
            uniq = sorted(set(locs))
            if len(uniq) > 1:
                problems.append(f"duplicate declaration of '{name}' in: " + ', '.join(os.path.relpath(u, ROOT) for u in uniq))

    leaf_names = {name.split('.')[-1] for name in declared}
    known = leaf_names | KNOWN | SWIFTUI | generics
    unknown = defaultdict(list)
    for path, code in files.items():
        # Skip member accesses (.Foo) and labels.
        for m in TYPE_REF_RE.finditer(code):
            name = m.group(1)
            if name in known: continue
            start = m.start()
            if start > 0 and code[start-1] in '.`': continue
            after = code[m.end():m.end()+1]
            before = code[max(0,start-2):start]
            if after == ':' and before.strip().endswith(('(', ',')): continue  # argument label
            if len(name) <= 2: continue
            line = code.count('\n', 0, start) + 1
            unknown[name].append(f"{os.path.relpath(path, ROOT)}:{line}")

    print(f"scanned {len(paths)} files, {len(declared)} declared types")
    if problems:
        print("\n=== STRUCTURAL PROBLEMS ===")
        for p in sorted(set(problems)): print("  " + p)
    if unknown:
        print("\n=== UNKNOWN TYPE REFERENCES ===")
        for name in sorted(unknown):
            locs = unknown[name]
            print(f"  {name}  ({len(locs)}x)  e.g. {locs[0]}")
    if not problems and not unknown:
        print("clean")
    return 1 if problems else 0

if __name__ == '__main__':
    sys.exit(main())
