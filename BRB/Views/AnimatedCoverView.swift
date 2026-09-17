//
//  AnimatedCoverView.swift
//  BRB
//
//  Cover image rendering shared by the veil and the Settings preview:
//  animated GIF frames when available, static image otherwise.
//  Both branches aspect-fill; callers own framing/clipping.
//

import SwiftUI

/// Aspect-filling cover image, animated when `frames` has 2+ entries.
struct CoverImageView: View {
    let frames: [GIFFrame]?
    let staticImage: NSImage

    var body: some View {
        if let frames, frames.count > 1 {
            AnimatedFramesView(frames: frames)
        } else {
            Image(nsImage: staticImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

/// Cycles `frames` by their per-frame delays. TimelineView drives redraws
/// (pauses automatically offscreen); frame lookup is O(n) over a few dozen
/// entries max — negligible per tick.
struct AnimatedFramesView: View {
    let frames: [GIFFrame]

    var body: some View {
        TimelineView(.animation) { context in
            Image(nsImage: frame(at: context.date.timeIntervalSinceReferenceDate))
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func frame(at t: TimeInterval) -> NSImage {
        let total = frames.reduce(0.0) { $0 + $1.delay }
        guard total > 0 else { return frames[0].image }
        var elapsed = t.truncatingRemainder(dividingBy: total)
        for f in frames {
            if elapsed < f.delay { return f.image }
            elapsed -= f.delay
        }
        return frames[frames.count - 1].image
    }
}
