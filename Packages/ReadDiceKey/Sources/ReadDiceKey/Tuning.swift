//
//  Tuning.swift
//  ReadDiceKey
//
//  The thresholds the scanner is tuned by, one group per step of the pipeline. Why each has
//  its value, and what it was measured against, is in docs/scanning.md, "Constants and where
//  they come from".
//

/// The thresholds the scanner is tuned by, one group per step of the pipeline.
enum Tuning {
    /// Finding the rectangles that could be bars (`Bars.swift`).
    enum Bars {
        /// The brightness levels the frame is thresholded at: k thirteenths of white, k from 2 to 13.
        static let thresholds = (2...13).map { UInt8($0 * Int(UInt8.max) / 13) }
        /// Fewest pixels in a dark region for a rectangle to be fitted around it.
        static let minimumRegionPixels = 50
        /// The most a rectangle's thickness for its length may be off the printed bar's, as a
        /// factor either way.
        static let proportionSlack: Float = 1.5
        /// How many areas either side of its middle, in order of size, make up the run whose
        /// middle is taken as the bars' area: the tightest such run, by its largest area over its
        /// smallest.
        static let modalRunHalfWidth = 17
        /// A run tighter than this also wins when its middle is more than `largerRunFactor` times
        /// the area found so far, so that a crowd of equal tiny specks cannot outvote the bars.
        static let largerRunTightness: Float = 1.2
        /// How many times the area found so far a run's middle must be to win by
        /// `largerRunTightness`.
        static let largerRunFactor: Float = 3
        /// The least ratio of a rectangle's area to the bars' area, either way round, for it to be kept.
        static let areaTolerance: Float = 0.75
    }

    /// Reading a bar as a line (`Undoverline.swift`).
    enum Lines {
        /// How far either side of each end of a bar's rectangle the line's end is looked for, as a
        /// share of the bar's length.
        static let endSearch: Float = 0.03
        /// How many pixels each brightness sample is the median of where a bar's end is looked
        /// for. 3 lie in a line across the bar, which keeps the sample inside a thin bar.
        static let endSamplePixels = 3
        /// How many pixels a dot's sample is the median of, by the spacing in pixels between dots:
        /// those of the first entry the spacing is under, else the whole neighborhood. Each count is
        /// the pixels nearest the dot out to a whole ring of the neighborhood, or 3 in a line across
        /// the bar.
        static let samplePixels: [(spacingUnder: Float, pixels: Int)] = [(2, 1), (3, 3), (4, 5), (5, 9), (5.5, 13)]
        /// The least gap between the lightest dark dot and the darkest light dot, as a share of the
        /// distance between the two groups' mean brightness, for a line to be read. Dots that
        /// barely split could as well have split elsewhere, into another code.
        static let minimumDotGap: Float = 0.2
    }

    /// Fitting the grid to the lines and pinning it to the key (`GridFit.swift`, `Grid.swift`).
    enum Grid {
        /// Face centers closer than this many faces are one die's two lines.
        static let sameDieDistance: Float = 0.8
        /// Times the grid is refitted to the lines it gathers, flat and again in perspective.
        static let refits = 3
        /// Fewest lines a grid is fitted to or pinned with.
        static let minimumLines = 8
        /// Fewest lines on the flat grid for it to be refitted in perspective.
        static let minimumLinesForPerspective = 16
        /// How many columns and rows beyond the lines the flat grid kept the perspective refits
        /// gather lines from, so that dice farther out are not taken in.
        static let perspectiveWindow = 1
        /// An outermost column or row with no more lines than this is strays beyond the key.
        static let maximumStrayLines = 2
        /// Fewest slots with lines in the outermost column or row opposite strays for them to be
        /// dropped when the lines span one column or row too many: with fewer, it may be strays itself.
        static let minimumSlotsOppositeStrays = 3
        /// The least share of the frame's lines that must lie on the key.
        static let minimumShareOnKey: Float = 0.6
        /// Fewest slots with lines in each outermost row and column.
        static let minimumSlotsOnEachEdge = 2
        /// The most a line in the key's slots may measure off their median, in columns and rows,
        /// as a share of it.
        static let maximumFaceSideDeviation: Float = 0.5
        /// The smallest pivot the least-squares fit divides by; a smaller one means its points
        /// cannot fix the grid.
        static let smallestPivot = 1e-9
    }

    /// Placing the lines in the grid's slots (`Grid.swift`, `Slots.swift`).
    enum Slots {
        /// How far from a whole column and row, in steps along each axis, a face's center may be
        /// and still be in that slot. The fit gathers the faces on the grid by it too.
        static let tolerance: Float = 0.25
        /// The least a line may measure in columns and rows, as a share of the median line's, to
        /// be placed in a slot. A bar cut short, by the frame's edge or a cover, still passes as
        /// a bar, and both bars of a die cut at the same place read the same wrong face.
        static let minimumLineLength: Float = 0.95
    }

    /// Settling a face by its printed text (`FaceText.swift`).
    enum Text {
        /// Samples across a face, in the grid its text is compared in.
        static let gridWidth = 48
        /// The band of a face between its bars that holds the text, as shares of its height.
        static let band: ClosedRange<Float> = 0.22...0.78
        /// How many samples either way the comparison shifts, for error in the die's center.
        static let maximumShift = 3
        /// The least correlation of a die's text with the best face's for it to settle the die.
        static let minimumScore: Float = 0.7
        /// How far the best face's correlation must lead the next face's.
        static let minimumLeadOverOtherFaces: Float = 0.03
        /// How far the best face's correlation must lead the best at any other quarter turn.
        static let minimumLeadOverOtherTurns: Float = 0.15
        /// The most uncertain a predicted size may be, in variances of one die's measured size.
        static let maximumSizeVariance: Float = 1
    }

    /// Merging what successive frames read (`DiceKeyScanner.swift`).
    enum Merge {
        /// Fewest faces a frame must share with the faces known to be read as the same key.
        static let minimumFacesInCommon = 5
    }
}
