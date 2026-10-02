import CoreGraphics
import Foundation

// THE SIDECAR KEEPS ONE FRAME, AND EACH PANE SHOWS IT THROUGH ITS OWN.
//
// Objects are stored as they always were — fractions of the pane, measured
// down the MARKDOWN pane's document (`PaneMapping` says why that pane) —
// and the rendered page shows them through a `PaneMapping` from that
// pane's cells to its own. Everything the layer does — drawing, hit
// testing, the handles, a drag, a new stroke, a placement — then happens
// in the frame on screen, and what it changes comes back the same way
// (`stored`). So nothing in the canvas knows there are two panes, and an
// object drawn in either mode sits beside the same words in both.

extension CanvasItem {
    /// This item where `mapping` puts it — moved WHOLE, by where the
    /// mapping puts the top left of its box (or of its group's, `corner`),
    /// so a picture is never stretched and a word written in ink is never
    /// squashed: the two panes give a seam a different height, and a
    /// picture across one would otherwise come out a different shape on
    /// each side.
    ///
    /// A connector is the exception and is mapped point by point — its
    /// ends, its corners and any segment a hand put somewhere — because
    /// its two ends belong to two different nodes, and each node has
    /// moved by its own amount. x and y map separately, so a routed
    /// line's square corners stay square; `Drawing.shown` then lets
    /// `reconnect` put each attached end back on its node's edge.
    func carried(through mapping: PaneMapping, in size: CGSize, corner: CGPoint? = nil) -> CanvasItem {
        guard size.width > 0, size.height > 0 else { return self }
        if case .connector(var connector) = self {
            if connector.transform != ItemTransform() {
                // The transform baked into the points first, the way
                // `Drawing.reconnect` bakes it: mapped as it stood, a
                // move half-way through a drag would be undone.
                let placed = outline(in: size)
                if placed.count >= 2 {
                    connector.start = Self.fraction(placed[0], in: size)
                    connector.end = Self.fraction(placed[placed.count - 1], in: size)
                    connector.bends = placed.dropFirst().dropLast().map { Self.fraction($0, in: size) }
                }
                connector.transform = ItemTransform()
            }
            let map = { (point: CGPoint) -> CGPoint in
                Self.fraction(mapping.point(CGPoint(x: point.x * size.width, y: point.y * size.height)), in: size)
            }
            connector.start = map(connector.start)
            connector.end = map(connector.end)
            connector.bends = connector.bends.map(map)
            connector.overrides = connector.overrides.map { override in
                var moved = override
                moved.value = override.vertical
                    ? Double(mapping.x(CGFloat(override.value) * size.width) / size.width)
                    : Double(mapping.y(CGFloat(override.value) * size.height) / size.height)
                return moved
            }
            return .connector(connector)
        }
        let corner = corner ?? bounds(in: size).origin
        let landed = mapping.point(corner)
        var moved = self
        moved.transform.dx += Double((landed.x - corner.x) / size.width)
        moved.transform.dy += Double((landed.y - corner.y) / size.height)
        return moved
    }

    private static func fraction(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: point.y / size.height)
    }
}

extension Drawing {
    /// Items where `mapping` puts them. A GROUP goes as one, by the top
    /// left of all of it: Writing taken off the tablet's page is a group of
    /// strokes, and each going by its own corner would pull the letters of
    /// a word apart wherever the word crosses the edge of a cell. Anything
    /// on its own goes by its own corner.
    static func carried(_ items: [CanvasItem], through mapping: PaneMapping, in size: CGSize) -> [CanvasItem] {
        var corners: [UUID: CGPoint] = [:]
        for item in items where item.connector == nil {
            guard let group = item.group else { continue }
            let origin = item.bounds(in: size).origin
            corners[group] = corners[group].map { CGPoint(x: min($0.x, origin.x), y: min($0.y, origin.y)) } ?? origin
        }
        return items.map { item in
            item.carried(through: mapping, in: size, corner: item.group.flatMap { corners[$0] })
        }
    }

    /// The drawing as the pane on screen shows it. The identity hands the
    /// drawing back untouched — the markdown pane IS the stored frame.
    func shown(through mapping: PaneMapping, in size: CGSize) -> Drawing {
        guard !mapping.isIdentity, size.width > 0, size.height > 0 else { return self }
        var shown = self
        shown.items = Self.carried(items, through: mapping, in: size)
        if shown.items.contains(where: { $0.connector != nil }) { shown.reconnect(in: size) }
        return shown
    }

    /// What the layer did on the pane on screen, as the sidecar keeps it.
    ///
    /// `before` is what that pane was shown (`shown(through:in:)` of
    /// `self`). An item it still holds UNCHANGED is this drawing's own,
    /// bit for bit: a gesture writes the whole drawing back for every
    /// frame of a drag, and the items it did not touch must not come back
    /// a rounding error away — every write is a save, and an arrow's route
    /// would wander. Everything else — moved, scaled, new — goes back
    /// through the inverse, and attached arrows are put back on their
    /// nodes in this frame.
    func stored(_ shown: Drawing, wasShown before: Drawing, through mapping: PaneMapping,
                in size: CGSize) -> Drawing {
        guard !mapping.isIdentity, size.width > 0, size.height > 0 else { return shown }
        var mine: [UUID: CanvasItem] = [:]
        for item in items { mine[item.id] = item }
        var seen: [UUID: CanvasItem] = [:]
        for item in before.items { seen[item.id] = item }
        let kept = shown.items.map { item -> CanvasItem? in
            guard seen[item.id] == item else { return nil }
            return mine[item.id]
        }
        let changed = zip(shown.items, kept).filter { $0.1 == nil }.map(\.0)
        var stored = shown
        guard !changed.isEmpty else {
            stored.items = kept.compactMap { $0 }
            return stored
        }
        let carried = Dictionary(Self.carried(changed, through: mapping.inverse, in: size).map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        stored.items = zip(shown.items, kept).map { item, kept in kept ?? carried[item.id] ?? item }
        if stored.items.contains(where: { $0.connector != nil }) { stored.reconnect(in: size) }
        return stored
    }
}
