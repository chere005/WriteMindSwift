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
        let corners = Dictionary(grouping: items.filter { $0.group != nil }, by: { $0.group! })
            .compactMapValues { corner(of: $0, in: size) }
        return items.map { item in
            item.carried(through: mapping, in: size, corner: item.group.flatMap { corners[$0] })
        }
    }

    /// The top left of everything in `items` that moves whole — a
    /// connector goes point by point, and has no corner. Nil with none.
    static func corner(of items: [CanvasItem], in size: CGSize) -> CGPoint? {
        var corner: CGPoint?
        for item in items where item.connector == nil {
            let origin = item.bounds(in: size).origin
            corner = corner.map { CGPoint(x: min($0.x, origin.x), y: min($0.y, origin.y)) } ?? origin
        }
        return corner
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
    /// `self`), and what goes back as one is what was SHOWN as one: a group
    /// as it was then — the grouping the showing went by — or an object on
    /// its own.
    ///
    /// - A unit the layer did not touch is this drawing's own, bit for
    ///   bit: a gesture writes the whole drawing back for every frame of a
    ///   drag, and what it did not touch must not come back a rounding
    ///   error away — every write is a save, and an arrow's route would
    ///   wander.
    /// - A unit whose corner is where it was shown — a label typed, a
    ///   colour, ⌃G, a member deleted — keeps the offset it was shown
    ///   with, exactly: what changed changed in place, and naming a group
    ///   or taking a member out of it moves nothing here. Put back by its
    ///   own corner instead, a member of a group came back by another
    ///   amount than it went — a text box ten points up the sidecar for
    ///   every letter typed in it.
    /// - A unit the layer moved, or a new one, goes back through the
    ///   inverse by where its corner is now — ALL of it, by the corner of
    ///   all of it. `DrawingCanvas.apply` writes one member at a time, and
    ///   each put back by its own corner pulled a group apart on every
    ///   frame of a drag.
    ///
    /// A connector the layer changed goes back point by point, and
    /// attached arrows are put back on their nodes in this frame.
    func stored(_ shown: Drawing, wasShown before: Drawing, through mapping: PaneMapping,
                in size: CGSize) -> Drawing {
        guard !mapping.isIdentity, size.width > 0, size.height > 0 else { return shown }
        let mine = Self.byID(items), seen = Self.byID(before.items)
        let unit = { (item: CanvasItem) -> UUID in (seen[item.id] ?? item).group ?? item.id }
        var moved: [UUID: CGPoint] = [:]
        for (key, members) in Dictionary(grouping: shown.items.filter { $0.connector == nil }, by: unit) {
            let then = members.compactMap { item in mine[item.id] == nil ? nil : seen[item.id] }
            let corner = Self.corner(of: members, in: size)
            if then.count < members.count || corner != Self.corner(of: then, in: size) { moved[key] = corner }
        }
        var stored = shown
        stored.items = shown.items.map { item in
            if let corner = moved[unit(item)] {
                return item.carried(through: mapping.inverse, in: size, corner: corner)
            }
            // A new arrow: anything else new is in a unit that moved.
            guard let old = seen[item.id], let own = mine[item.id] else {
                return item.carried(through: mapping.inverse, in: size)
            }
            if old == item { return own }
            if item.connector != nil { return item.carried(through: mapping.inverse, in: size) }
            var back = item
            back.transform.dx = Self.offset(item.transform.dx, shown: old.transform.dx, own: own.transform.dx)
            back.transform.dy = Self.offset(item.transform.dy, shown: old.transform.dy, own: own.transform.dy)
            return back
        }
        if stored.items.contains(where: { $0.connector != nil }) { stored.reconnect(in: size) }
        return stored
    }

    /// `value` less what showing added to it — `own` itself when it is
    /// still what was shown.
    private static func offset(_ value: Double, shown: Double, own: Double) -> Double {
        value == shown ? own : value - (shown - own)
    }

    private static func byID(_ items: [CanvasItem]) -> [UUID: CanvasItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
