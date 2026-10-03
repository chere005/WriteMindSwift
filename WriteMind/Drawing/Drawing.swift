import AppKit
import Foundation

/// Where an item has been put since it was made.
///
/// `dx`/`dy` are fractions of the pane, so a moved object keeps its place when
/// the window is resized. Scale and rotation are applied about the item's own
/// centre **in view space** — not in the normalised space the points are
/// stored in — because the pane is not square, and rotating in normalised
/// space would shear everything it touched.
struct ItemTransform: Codable, Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var scale: Double = 1
    /// Radians, clockwise on screen.
    var rotation: Double = 0

    static let identity = ItemTransform()
}

/// One pen stroke — its own object (Sean, 2026-09-18: "drawings should be
/// objects by stroke"). Points are normalised to the editor pane (0…1 on both
/// axes) so a drawing keeps its place when the window is resized.
struct Stroke: Codable, Equatable, Identifiable {
    var id = UUID()
    var colorHex: String
    var width: Double
    var points: [CGPoint]
    var transform = ItemTransform()
    /// The group this belongs to, if it has been put in one (Sean,
    /// 2026-09-20: "select drawn (or captured) stuff for grouping,
    /// deleting, ungrouping"). Picking any member picks them all; the
    /// objects are otherwise untouched by it, so ungrouping moves nothing.
    var group: UUID?
    /// How hard the pen was pressed at each point, 0…1 — PARALLEL TO
    /// `points`, one for one, or nil for a stroke whose device said
    /// nothing (a mouse, a trackpad, and every stroke drawn before
    /// 2026-10-02). Anything that writes `points` writes this in the same
    /// breath: `starting(at:…)` and `append(_:pen:)` are the only two that
    /// do today, and a third — a split, a crop, a merge — keeps the two
    /// the same length or the ink reads the wrong pressure at every point
    /// after the first one it got wrong.
    var pressures: [Double]?
    /// What it was written with. nil is the LEGACY stroke — a smoothed
    /// line of one width, drawn exactly as it was before there were tools,
    /// so nothing Sean has already drawn changes shape. Set, the stroke is
    /// `InkOutline`'s filled outline (see `InkPaths.path`).
    var tool: InkTool?

    // Sidecars written before objects existed have no `transform`, and the
    // synthesized decoder would reject them — a default only applies to the
    // memberwise init, never to decoding. Every key added since is
    // decodeIfPresent for the same reason; the synthesized encoder writes
    // a nil optional as NO key, so a legacy stroke's JSON is byte for byte
    // what it was.
    private enum CodingKeys: String, CodingKey { case id, colorHex, width, points, transform, group, pressures, tool }

    init(id: UUID = UUID(), colorHex: String, width: Double, points: [CGPoint],
         transform: ItemTransform = ItemTransform(), group: UUID? = nil,
         pressures: [Double]? = nil, tool: InkTool? = nil) {
        self.id = id
        self.colorHex = colorHex
        self.width = width
        self.points = points
        self.transform = transform
        self.group = group
        self.pressures = pressures
        self.tool = tool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        colorHex = try container.decode(String.self, forKey: .colorHex)
        width = try container.decode(Double.self, forKey: .width)
        points = try container.decode([CGPoint].self, forKey: .points)
        transform = try container.decodeIfPresent(ItemTransform.self, forKey: .transform) ?? ItemTransform()
        group = try container.decodeIfPresent(UUID.self, forKey: .group)
        pressures = try? container.decodeIfPresent([Double].self, forKey: .pressures)
        // A tool this build has never heard of is still ink: the pen,
        // rather than a decode failure that would empty the whole note's
        // drawing (`DrawingStore.load`).
        if let raw = try? container.decodeIfPresent(String.self, forKey: .tool) {
            tool = InkTool(rawValue: raw) ?? .pen
        } else {
            tool = nil
        }
    }

    /// A stroke the pen has just put down. The FIRST event decides what it
    /// is for good: a tablet's nib makes ink with a pressure per point,
    /// written with `tool` — the pen picked on the pen menu, or on the
    /// page's bar; a mouse or a trackpad makes the legacy line it always
    /// made, whatever tool is picked.
    static func starting(at point: CGPoint, colorHex: String, width: Double, pen: PenSample,
                         tool: InkTool = .pen) -> Stroke {
        var stroke = Stroke(colorHex: colorHex, width: width, points: [point])
        if case .pen(let pressure) = pen {
            stroke.pressures = [pressure]
            stroke.tool = tool
        }
        return stroke
    }

    /// The next point, and — on a stroke that has pressures — the next
    /// pressure with it. A sample that did not come from the nib mid-stroke
    /// repeats the last pressure, so the two arrays never part company.
    mutating func append(_ point: CGPoint, pen: PenSample) {
        points.append(point)
        guard var pressures else { return }
        if case .pen(let pressure) = pen {
            pressures.append(pressure)
        } else {
            pressures.append(pressures.last ?? InkOutline.defaultPressure)
        }
        self.pressures = pressures
    }

    /// The tool the stroke is drawn with: its own, the pen for a stroke
    /// that has pressures and no tool, and nil — the legacy line — for one
    /// with neither.
    var inkTool: InkTool? { tool ?? (pressures == nil ? nil : .pen) }

    /// Half the widest the ink can be, in points before the transform:
    /// what the stroke's box and its hit test reach out by. A legacy
    /// stroke's is half its width, as it always was.
    var reach: Double { inkTool?.reach(width: width) ?? width / 2 }
}

/// A picture dropped on the page: added from the Add Image button, or pasted.
/// The file itself lives in `_drawings/media`; this is where it sits.
struct ImageItem: Codable, Equatable, Identifiable {
    var id = UUID()
    /// File name inside `_drawings/media`.
    var file: String
    /// The centre, as a fraction of the pane, before the transform moves it.
    var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Width as a fraction of the pane's width. The height comes from
    /// `aspect`, so the pane's shape never squashes the picture.
    var width: Double = 0.35
    /// Pixel height ÷ pixel width.
    var aspect: Double = 1
    var transform = ItemTransform()
    /// Put away, but not thrown away: the picture whose writing has been
    /// read into the note is hidden rather than deleted, so the button that
    /// brings the drawing back has something to bring back (Sean,
    /// 2026-09-19: "have a button that reverts to original drawing after
    /// pasting"). A hidden picture is as if it were not on the pane at all.
    var hidden: Bool = false
    /// The group this belongs to, if it has been put in one (Sean,
    /// 2026-09-20: "select drawn (or captured) stuff for grouping,
    /// deleting, ungrouping"). Picking any member picks them all; the
    /// objects are otherwise untouched by it, so ungrouping moves nothing.
    var group: UUID?

    private enum CodingKeys: String, CodingKey {
        case id, file, center, width, aspect, transform, hidden, group
    }

    init(id: UUID = UUID(), file: String, center: CGPoint = CGPoint(x: 0.5, y: 0.5),
         width: Double = 0.35, aspect: Double = 1, transform: ItemTransform = ItemTransform(),
         hidden: Bool = false, group: UUID? = nil) {
        self.id = id
        self.file = file
        self.center = center
        self.width = width
        self.aspect = aspect
        self.transform = transform
        self.hidden = hidden
        self.group = group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        file = try container.decode(String.self, forKey: .file)
        center = try container.decodeIfPresent(CGPoint.self, forKey: .center) ?? CGPoint(x: 0.5, y: 0.5)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0.35
        aspect = try container.decodeIfPresent(Double.self, forKey: .aspect) ?? 1
        transform = try container.decodeIfPresent(ItemTransform.self, forKey: .transform) ?? ItemTransform()
        // A sidecar written before pictures could be hidden shows them all.
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        group = try container.decodeIfPresent(UUID.self, forKey: .group)
    }
}

/// Everything on the drawing layer, back to front.
enum CanvasItem: Identifiable, Equatable {
    case stroke(Stroke)
    case image(ImageItem)
    case shape(ShapeItem)
    case connector(ConnectorItem)

    var id: UUID {
        switch self {
        case .stroke(let stroke): return stroke.id
        case .image(let image): return image.id
        case .shape(let shape): return shape.id
        case .connector(let connector): return connector.id
        }
    }

    var stroke: Stroke? { if case .stroke(let stroke) = self { return stroke } else { return nil } }
    var image: ImageItem? { if case .image(let image) = self { return image } else { return nil } }
    var shape: ShapeItem? { if case .shape(let shape) = self { return shape } else { return nil } }
    var connector: ConnectorItem? { if case .connector(let connector) = self { return connector } else { return nil } }

    /// The group this object is in — see `Stroke.group`. A connector has
    /// none: it is held by the nodes at its ends, which have their own,
    /// and it follows them wherever the group goes.
    var group: UUID? {
        get {
            switch self {
            case .stroke(let stroke): return stroke.group
            case .image(let image): return image.group
            case .shape(let shape): return shape.group
            case .connector: return nil
            }
        }
        set {
            switch self {
            case .stroke(var stroke): stroke.group = newValue; self = .stroke(stroke)
            case .image(var image): image.group = newValue; self = .image(image)
            case .shape(var shape): shape.group = newValue; self = .shape(shape)
            case .connector: break
            }
        }
    }

    /// A hidden picture: drawn nowhere, clicked nowhere, and no obstacle to
    /// the text. Only a picture can be hidden.
    var isHidden: Bool {
        if case .image(let image) = self { return image.hidden }
        return false
    }

    var transform: ItemTransform {
        get {
            switch self {
            case .stroke(let stroke): return stroke.transform
            case .image(let image): return image.transform
            case .shape(let shape): return shape.transform
            case .connector(let connector): return connector.transform
            }
        }
        set {
            switch self {
            case .stroke(var stroke): stroke.transform = newValue; self = .stroke(stroke)
            case .image(var image): image.transform = newValue; self = .image(image)
            case .shape(var shape): shape.transform = newValue; self = .shape(shape)
            case .connector(var connector): connector.transform = newValue; self = .connector(connector)
            }
        }
    }
}

extension CanvasItem: Codable {
    private enum CodingKeys: String, CodingKey { case kind, stroke, image, shape, connector }
    private enum Kind: String, Codable { case stroke, image, shape, connector }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .stroke: self = .stroke(try container.decode(Stroke.self, forKey: .stroke))
        case .image: self = .image(try container.decode(ImageItem.self, forKey: .image))
        case .shape: self = .shape(try container.decode(ShapeItem.self, forKey: .shape))
        case .connector: self = .connector(try container.decode(ConnectorItem.self, forKey: .connector))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stroke(let stroke):
            try container.encode(Kind.stroke, forKey: .kind)
            try container.encode(stroke, forKey: .stroke)
        case .image(let image):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(image, forKey: .image)
        case .shape(let shape):
            try container.encode(Kind.shape, forKey: .kind)
            try container.encode(shape, forKey: .shape)
        case .connector(let connector):
            try container.encode(Kind.connector, forKey: .kind)
            try container.encode(connector, forKey: .connector)
        }
    }
}

struct Drawing: Codable, Equatable {
    var items: [CanvasItem] = []

    var isEmpty: Bool { items.isEmpty }
    var strokes: [Stroke] { items.compactMap(\.stroke) }
    var images: [ImageItem] { items.compactMap(\.image) }
    var shapes: [ShapeItem] { items.compactMap(\.shape) }
    var connectors: [ConnectorItem] { items.compactMap(\.connector) }

    init(items: [CanvasItem] = []) { self.items = items }
    init(strokes: [Stroke]) { items = strokes.map(CanvasItem.stroke) }

    /// The index of the item that a click at `point` lands on, topmost first.
    func index(at point: CGPoint, in size: CGSize) -> Int? {
        items.indices.reversed().first { !items[$0].isHidden && items[$0].hitTest(point, in: size) }
    }

    /// This drawing with everything in `snapshot` moved, scaled and turned
    /// about `pivot` from where it stood when the gesture began — worked out
    /// on ONE copy, because the canvas writes the result back once. On the
    /// rendered page every write is mapped back through the markdown pane's
    /// cells, and writing the drawing once per held object took five
    /// seconds a frame for a group of two hundred (Sean, 2026-10-02: "object
    /// grouping is really slow"). Arrows attached to what moved follow.
    func manipulated(_ snapshot: [UUID: ItemTransform], translate: CGVector = .zero, scale: Double = 1,
                     rotate: Double = 0, about pivot: CGPoint, in size: CGSize) -> Drawing {
        var next = self
        for index in next.items.indices {
            let item = next.items[index]
            guard let original = snapshot[item.id] else { continue }
            next.items[index].transform = CanvasEdit.transform(
                item, from: original, translate: translate, scale: scale, rotate: rotate,
                about: pivot, in: size)
        }
        next.reconnect(in: size)
        return next
    }

    /// Everything that is actually on the pane.
    var visibleItems: [CanvasItem] { items.filter { !$0.isHidden } }

    /// Every item the marquee touches. Touching is enough — Sean, 2026-09-18:
    /// "if it's in the selection rectangle, it's included, the whole drawing
    /// doesn't need to be highlighted".
    ///
    /// A hidden picture is as if it were not on the pane at all, here as in
    /// `index(at:)` and `bounds(of:)`: a rectangle dragged over the blank
    /// space it used to fill would otherwise hand it to ⌫, and nothing on
    /// screen would have said it was there.
    func ids(touching rect: CGRect, in size: CGSize) -> Set<UUID> {
        Set(items.filter { !$0.isHidden && $0.intersects(rect, in: size) }.map(\.id))
    }

    subscript(id id: UUID) -> CanvasItem? {
        get { items.first { $0.id == id } }
        set {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            if let newValue { items[index] = newValue } else { items.remove(at: index) }
        }
    }

    /// The topmost thing an arrow can be attached to at this point: a shape
    /// or a picture. Ink and other arrows are not.
    func attachable(at point: CGPoint, in size: CGSize) -> UUID? {
        for item in items.reversed() {
            switch item {
            case .shape, .image:
                if item.hitTest(point, in: size) { return item.id }
            case .stroke, .connector:
                continue
            }
        }
        return nil
    }

    /// Put every attached connector end back on the edge of what it is
    /// attached to, after anything has moved. A connector's own transform is
    /// baked into its points first, so a dragged arrow stays dragged and
    /// only its attached ends snap.
    mutating func reconnect(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        func normalised(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x / size.width, y: point.y / size.height)
        }
        // A line with an end on a node turns right angles; the routing is
        // worked out here and baked into the item, so everything that draws
        // or clicks a connector reads one list of points (Sean, 2026-09-19).
        var routedIndices: [Int] = []
        var routedBoxes: [(start: CGRect?, end: CGRect?)] = []
        let obstacleBoxes = nodeBoxes(in: size)

        for index in items.indices {
            guard case .connector(var connector) = items[index] else { continue }
            if connector.transform != ItemTransform() {
                let placed = items[index].outline(in: size)
                if placed.count >= 2 {
                    connector.start = normalised(placed[0])
                    connector.end = normalised(placed[placed.count - 1])
                    connector.bends = placed.dropFirst().dropLast().map(normalised)
                }
                connector.transform = ItemTransform()
            }
            let startNode = connector.startNode.flatMap { self[id: $0] }
            let endNode = connector.endNode.flatMap { self[id: $0] }
            let a = startNode?.placedCenter(in: size)
                ?? CGPoint(x: connector.start.x * size.width, y: connector.start.y * size.height)
            let b = endNode?.placedCenter(in: size)
                ?? CGPoint(x: connector.end.x * size.width, y: connector.end.y * size.height)
            if connector.isRouted {
                routedIndices.append(index)
                routedBoxes.append((startNode?.bounds(in: size), endNode?.bounds(in: size)))
            } else {
                connector.bends = []
                if let startNode {
                    connector.start = normalised(startNode.boundaryPoint(from: a, towards: b, in: size))
                }
                if let endNode {
                    connector.end = normalised(endNode.boundaryPoint(from: b, towards: a, in: size))
                }
            }
            // Only write it back when something actually moved: an assignment
            // marks the note's drawing dirty and schedules a save, and this
            // runs on every layout pass.
            if items[index] != .connector(connector) { items[index] = .connector(connector) }
        }

        guard !routedIndices.isEmpty else { return }

        /// A free end is a box with no size: the routing joins two boxes.
        func box(_ given: CGRect?, or point: CGPoint) -> CGRect {
            given ?? CGRect(origin: point, size: .zero)
        }

        var paths: [[CGPoint]] = []
        for (offset, index) in routedIndices.enumerated() {
            guard case .connector(let connector) = items[index] else { paths.append([]); continue }
            let boxes = routedBoxes[offset]
            let from = box(boxes.start, or: CGPoint(x: connector.start.x * size.width,
                                                    y: connector.start.y * size.height))
            let to = box(boxes.end, or: CGPoint(x: connector.end.x * size.width,
                                                y: connector.end.y * size.height))
            let others = obstacleBoxes.filter { $0 != from && $0 != to }
            paths.append(ConnectorRouting.path(from: from, to: to, obstacles: others))
        }

        // Two lines that would run down the same corridor are moved apart —
        // unless a hand put one there.
        var fixed: Set<Int> = []
        for (offset, index) in routedIndices.enumerated() {
            if case .connector(let connector) = items[index], !connector.overrides.isEmpty {
                fixed.insert(offset)
            }
        }
        let lanes = ConnectorRouting.channels(for: paths, fixed: fixed)

        for (offset, index) in routedIndices.enumerated() {
            guard case .connector(var connector) = items[index] else { continue }
            let boxes = routedBoxes[offset]
            let from = box(boxes.start, or: CGPoint(x: connector.start.x * size.width,
                                                    y: connector.start.y * size.height))
            let to = box(boxes.end, or: CGPoint(x: connector.end.x * size.width,
                                                y: connector.end.y * size.height))
            let others = obstacleBoxes.filter { $0 != from && $0 != to }
            var path = ConnectorRouting.path(from: from, to: to, obstacles: others, channel: lanes[offset])
            path = ConnectorRouting.applying(connector.overrides, to: path,
                                             start: boxes.start, end: boxes.end, in: size)
            connector.start = normalised(path[0])
            connector.end = normalised(path[path.count - 1])
            connector.bends = path.dropFirst().dropLast().map(normalised)
            if items[index] != .connector(connector) { items[index] = .connector(connector) }
        }
    }

    /// The boxes of everything a line can be attached to — what it has to
    /// route around.
    func nodeBoxes(in size: CGSize) -> [CGRect] {
        items.compactMap { item in
            guard !item.isHidden else { return nil }
            switch item {
            case .shape(let shape) where shape.kind.isNode: return item.bounds(in: size)
            case .image: return item.bounds(in: size)
            default: return nil
            }
        }
    }

    /// Without these items — and without the arrows attached to them, which
    /// would otherwise be left pointing at nothing.
    func removing(_ ids: Set<UUID>) -> Drawing {
        var copy = self
        copy.items.removeAll { item in
            if ids.contains(item.id) { return true }
            if case .connector(let connector) = item {
                if let node = connector.startNode, ids.contains(node) { return true }
                if let node = connector.endNode, ids.contains(node) { return true }
            }
            return false
        }
        return copy
    }

    // `items` replaced `strokes` on disk; a sidecar written before that still
    // reads, and is written back in the new shape the next time it is saved.
    private enum CodingKeys: String, CodingKey { case items, strokes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try container.decodeIfPresent([CanvasItem].self, forKey: .items) {
            self.items = items
        } else if let strokes = try container.decodeIfPresent([Stroke].self, forKey: .strokes) {
            self.items = strokes.map(CanvasItem.stroke)
        } else {
            self.items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

/// What an imported picture turned out to be: the file that now sits in
/// `_drawings/media`, and how big it really is.
struct ImportedImage: Equatable {
    var file: String
    var pixelWidth: Double
    var pixelHeight: Double

    var aspect: Double { pixelWidth > 0 ? pixelHeight / pixelWidth : 1 }
}

/// Drawings live beside the notes in a VISIBLE folder, one JSON per note.
/// Pictures go in `_drawings/media`, named by UUID so two notes can never
/// collide, and a note's drawing cells in `_drawings/cells`.
///
/// It was a hidden `.drawings` until 2026-10-02 (Sean: "visible data
/// generally speaking" — and, asked whether the existing folders should move
/// too: "yes"). `migrateHiddenData` moves what is there, once, and nothing
/// that is there is ever overwritten or deleted.
enum DrawingStore {
    static let folderName = DrawingCells.dataFolder
    /// What the folder was called before it was visible.
    static let legacyFolderName = ".drawings"
    static let mediaFolderName = "media"

    private static func legacyFolder(in directory: URL) -> URL {
        directory.appending(path: legacyFolderName, directoryHint: .isDirectory)
    }

    /// THE HIDDEN `.drawings` MOVED INTO THE VISIBLE `_drawings`, one item at
    /// a time and never over anything: a sidecar or a picture whose name is
    /// already there stays in the hidden folder, where `load` and `mediaURL`
    /// still find it, and a folder that is in both is merged the same way.
    /// An emptied `.drawings` goes (a folder is not data); one with anything
    /// left in it stays. Returns how many items moved. Safe to run on every
    /// load: with no `.drawings` it is one `fileExists`.
    @discardableResult
    static func migrateHiddenData(in directory: URL) -> Int {
        let fileManager = FileManager.default
        let legacy = legacyFolder(in: directory)
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: legacy.path, isDirectory: &isFolder), isFolder.boolValue else { return 0 }
        let visible = directory.appending(path: folderName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: visible, withIntermediateDirectories: true)
        } catch {
            NSLog("WriteMind: could not make \(folderName) to move the hidden drawings into: \(error)")
            return 0
        }
        let moved = mergeMoving(from: legacy, into: visible)
        if moved > 0 { NSLog("WriteMind: moved \(moved) item(s) from \(legacyFolderName) to \(folderName) in \(directory.path)") }
        return moved
    }

    private static func mergeMoving(from source: URL, into target: URL) -> Int {
        let fileManager = FileManager.default
        var moved = 0
        let children = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [])) ?? []
        for child in children {
            let destination = target.appending(path: child.lastPathComponent)
            let isFolder = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !fileManager.fileExists(atPath: destination.path) {
                do {
                    try fileManager.moveItem(at: child, to: destination)
                    moved += 1
                } catch {
                    NSLog("WriteMind: could not move \(child.lastPathComponent): \(error)")
                }
            } else if isFolder, (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                moved += mergeMoving(from: child, into: destination)
            }
            // Anything else is a name that is taken: it stays where it is.
        }
        // Emptied, it goes. Not while anything is left in it.
        if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? fileManager.removeItem(at: source)
        }
        return moved
    }

    static func url(for noteURL: URL, in directory: URL) -> URL {
        directory
            .appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: noteURL.deletingPathExtension().lastPathComponent + ".json")
    }

    static func mediaFolder(in directory: URL) -> URL {
        directory
            .appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: mediaFolderName, directoryHint: .isDirectory)
    }

    /// Where a picture is — in `_drawings/media`, or, if the move left it
    /// behind (a name that was already taken there), in the hidden folder
    /// it came from.
    static func mediaURL(_ file: String, in directory: URL) -> URL {
        let visible = mediaFolder(in: directory).appending(path: file)
        if FileManager.default.fileExists(atPath: visible.path) { return visible }
        let hidden = legacyFolder(in: directory)
            .appending(path: mediaFolderName, directoryHint: .isDirectory).appending(path: file)
        return FileManager.default.fileExists(atPath: hidden.path) ? hidden : visible
    }

    static func load(for noteURL: URL, in directory: URL) -> Drawing {
        var file = url(for: noteURL, in: directory)
        if !FileManager.default.fileExists(atPath: file.path) {
            // Left behind in the hidden folder by a move that never overwrites.
            let hidden = legacyFolder(in: directory)
                .appending(path: noteURL.deletingPathExtension().lastPathComponent + ".json")
            if FileManager.default.fileExists(atPath: hidden.path) { file = hidden }
        }
        guard let data = try? Data(contentsOf: file) else { return Drawing() }
        return (try? JSONDecoder().decode(Drawing.self, from: data)) ?? Drawing()
    }

    static func save(_ drawing: Drawing, for noteURL: URL, in directory: URL) {
        let file = url(for: noteURL, in: directory)
        if drawing.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(drawing).write(to: file, options: .atomic)
        } catch {
            NSLog("WriteMind: failed to save drawing: \(error)")
        }
    }

    // MARK: - Pictures

    static func loadImage(_ file: String, in directory: URL) -> NSImage? {
        NSImage(contentsOf: mediaURL(file, in: directory))
    }

    /// Copy a picture off the disk into the note's media folder, keeping the
    /// original bytes — a JPEG stays a JPEG.
    static func importImage(from source: URL, in directory: URL) -> ImportedImage? {
        guard let image = NSImage(contentsOf: source) else { return nil }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = UUID().uuidString + "." + ext
        do {
            try FileManager.default.createDirectory(at: mediaFolder(in: directory), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: mediaURL(name, in: directory))
        } catch {
            NSLog("WriteMind: could not add that picture: \(error)")
            return nil
        }
        let size = pixelSize(of: image)
        return ImportedImage(file: name, pixelWidth: size.width, pixelHeight: size.height)
    }

    /// The pasteboard hands over an image, not a file, so this one writes a
    /// PNG — or, given a quality, a JPEG: a photographed page is a photo, and
    /// a PNG of one is megabytes for nothing.
    static func importImage(_ image: NSImage, in directory: URL, jpegQuality: Double? = nil) -> ImportedImage? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let data: Data?
        let name: String
        if let jpegQuality {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
            name = UUID().uuidString + ".jpg"
        } else {
            data = rep.representation(using: .png, properties: [:])
            name = UUID().uuidString + ".png"
        }
        guard let data else { return nil }
        do {
            try FileManager.default.createDirectory(at: mediaFolder(in: directory), withIntermediateDirectories: true)
            try data.write(to: mediaURL(name, in: directory), options: .atomic)
        } catch {
            NSLog("WriteMind: could not add that picture: \(error)")
            return nil
        }
        return ImportedImage(file: name, pixelWidth: Double(rep.pixelsWide), pixelHeight: Double(rep.pixelsHigh))
    }

    /// A vector graphic — a one-page PDF — into the note's media folder.
    /// It goes in as the bytes it was made as: re-drawing it through
    /// NSImage would flatten it to pixels, which is the whole thing this
    /// avoids (Sean, 2026-09-19: "make it a vector graphic so it scales
    /// well").
    static func importVector(_ pdf: Data, size: CGSize, in directory: URL) -> ImportedImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let name = UUID().uuidString + ".pdf"
        do {
            try FileManager.default.createDirectory(at: mediaFolder(in: directory), withIntermediateDirectories: true)
            try pdf.write(to: mediaURL(name, in: directory), options: .atomic)
        } catch {
            NSLog("WriteMind: could not add that drawing: \(error)")
            return nil
        }
        return ImportedImage(file: name, pixelWidth: Double(size.width), pixelHeight: Double(size.height))
    }

    /// An NSImage whose one representation says the pixel size it really has.
    /// `NSImage(cgImage:size:)` reports the pixels doubled on a Retina screen,
    /// and a picture would then be placed at twice its size.
    static func image(from cgImage: CGImage) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    /// A new picture holding the part of `file` inside `rect` (fractions of
    /// the picture, top-left origin). The original is left where it is —
    /// the undo history still points at it, and the sweep takes it when
    /// nothing does. A JPEG stays a JPEG.
    static func cropImage(_ file: String, to rect: CGRect, in directory: URL) -> ImportedImage? {
        guard let source = NSImage(contentsOf: mediaURL(file, in: directory)),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixels = CGRect(x: rect.minX * CGFloat(cgImage.width), y: rect.minY * CGFloat(cgImage.height),
                            width: rect.width * CGFloat(cgImage.width), height: rect.height * CGFloat(cgImage.height))
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1,
              let cropped = cgImage.cropping(to: pixels) else { return nil }
        let isJPEG = ["jpg", "jpeg"].contains((file as NSString).pathExtension.lowercased())
        return importImage(image(from: cropped), in: directory, jpegQuality: isJPEG ? 0.85 : nil)
    }

    /// Pixels, not points — `NSImage.size` is in points, and a retina PNG
    /// reports half its real width there.
    static func pixelSize(of image: NSImage) -> CGSize {
        let reps = image.representations.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
        if let best = reps.max(by: { $0.width < $1.width }), best.width > 0 { return best }
        return image.size
    }

    /// The sidecar follows a note into another section. Both sidecars live in
    /// the same hidden folder, so this is a rename — but it is spelled out
    /// because the note's own move is across folders, and its pictures have
    /// to travel with it.
    static func move(from oldURL: URL, in oldDirectory: URL, to newURL: URL, in newDirectory: URL) {
        let source = url(for: oldURL, in: oldDirectory)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let drawing = load(for: oldURL, in: oldDirectory)
        let destination = url(for: newURL, in: newDirectory)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: source, to: destination)

        guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return }
        try? FileManager.default.createDirectory(at: mediaFolder(in: newDirectory), withIntermediateDirectories: true)
        for image in drawing.images {
            let from = mediaURL(image.file, in: oldDirectory)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try? FileManager.default.moveItem(at: from, to: mediaURL(image.file, in: newDirectory))
        }
    }

    static func rename(from oldURL: URL, to newURL: URL, in directory: URL) {
        let source = url(for: oldURL, in: directory)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.moveItem(at: source, to: url(for: newURL, in: directory))
    }

    /// A copy gets copies of the pictures, so deleting either note later can
    /// never take the other one's pictures with it.
    static func copyingMedia(_ drawing: Drawing, in directory: URL) -> Drawing {
        var copy = drawing
        for index in copy.items.indices {
            guard case .image(var image) = copy.items[index] else { continue }
            let source = mediaURL(image.file, in: directory)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let name = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension)
            do {
                try FileManager.default.copyItem(at: source, to: mediaURL(name, in: directory))
                image.file = name
                image.id = UUID()
                copy.items[index] = .image(image)
            } catch {
                NSLog("WriteMind: could not copy a picture: \(error)")
            }
        }
        return copy
    }

    /// The start of the name of a picture that belongs to a drawing cell
    /// (`Docking.carryPictures`): never swept, as nothing under
    /// `_drawings/cells` is — a cell's file points at it by name and
    /// nothing else knows it is there.
    static let cellPicturePrefix = "cell-"

    /// Delete the pictures in this folder that no note in it points at any
    /// more. Notes share `_drawings/media`, so a picture is only an orphan
    /// when EVERY sidecar has stopped mentioning it — which is why this reads
    /// them all rather than trusting the note in front of it.
    ///
    /// `keeping` is what the OPEN note still needs and no sidecar says yet:
    /// every picture its drawing, its undo history and its redo future name
    /// (`NoteStore.mediaInUse`), because the sweep runs mid-note (⌘S) and an
    /// undo after it brought back a picture whose file was gone. A cell's own
    /// pictures are never swept. And NOTHING is deleted when any sidecar
    /// cannot be read: skipping it, as this used to, deleted every picture
    /// only that one named.
    static func pruneMedia(in directory: URL, keeping: Set<String> = []) {
        // While anything of the hidden folder is still there its sidecars
        // name pictures this sweep does not read: it deletes nothing.
        guard !FileManager.default.fileExists(atPath: legacyFolder(in: directory).path) else { return }
        let media = mediaFolder(in: directory)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: media, includingPropertiesForKeys: nil), !files.isEmpty else { return }

        let sidecars = (try? FileManager.default.contentsOfDirectory(
            at: directory.appending(path: folderName, directoryHint: .isDirectory),
            includingPropertiesForKeys: nil)) ?? []
        var referenced = keeping
        for sidecar in sidecars where sidecar.pathExtension == "json" {
            guard let data = try? Data(contentsOf: sidecar),
                  let drawing = try? JSONDecoder().decode(Drawing.self, from: data) else { return }
            referenced.formUnion(drawing.images.map(\.file))
        }
        for file in files {
            let name = file.lastPathComponent
            if referenced.contains(name) || name.hasPrefix(cellPicturePrefix) { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func delete(for noteURL: URL, in directory: URL) {
        let drawing = load(for: noteURL, in: directory)
        for image in drawing.images {
            try? FileManager.default.removeItem(at: mediaURL(image.file, in: directory))
        }
        try? FileManager.default.removeItem(at: url(for: noteURL, in: directory))
    }
}
