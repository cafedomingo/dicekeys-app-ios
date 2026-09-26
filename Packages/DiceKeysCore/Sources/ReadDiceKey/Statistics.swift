//
//  Statistics.swift
//  ReadDiceKey
//
//  Ports of lib-read-dicekey/utilities/statistics.h and utilities/bit-operations.h:
//  medians, the bimodal threshold search that separates black from white samples,
//  circular-angle averaging and the small bit helpers the undoverline decoder uses.
//

import Foundation

// MARK: - Medians

/// statistics.h `medianInPlace<uchar>`: the C++ averages the two middle values in `int`
/// arithmetic, so the result truncates.
func medianUInt8(_ numbers: inout [UInt8]) -> UInt8 {
    numbers.sort()
    if numbers.isEmpty {
        return 0
    } else if numbers.count % 2 > 0 {
        return numbers[numbers.count / 2]
    } else {
        let c = numbers.count / 2
        return UInt8((Int(numbers[c]) + Int(numbers[c - 1])) / 2)
    }
}

/// statistics.h `medianInPlace<float>`.
func medianFloat(_ numbers: inout [Float]) -> Float {
    numbers.sort()
    if numbers.isEmpty {
        return 0
    } else if numbers.count % 2 > 0 {
        return numbers[numbers.count / 2]
    } else {
        let c = numbers.count / 2
        return (numbers[c] + numbers[c - 1]) / 2
    }
}

// MARK: - Bimodal threshold (statistics.h)

/// `sumOfDifferenceSquaresInRange`.
private func sumOfDifferenceSquaresInRange(
    _ values: [UInt8], _ fromIndexInclusive: Int, _ toIndexExclusive: Int, _ expectedValue: Double
) -> Double {
    var error = 0.0
    let limitExclusive = min(toIndexExclusive, values.count)
    var i = fromIndexInclusive
    while i < limitExclusive {
        let difference = expectedValue - Double(values[i])
        error += difference * difference
        i += 1
    }
    return error
}

/// `findMinimalErrorForRange`: ternary search for the value that minimises the squared
/// error over a range of the sorted samples.
private func findMinimalErrorForRange(
    _ numbers: [UInt8], _ fromIndexInclusive: Int, _ toIndexExclusive: Int,
    _ lowerBoundIn: Double, _ upperBoundIn: Double, allowablePositionError: Double = 0.1
) -> Double {
    var centerOfMassLowerBound = lowerBoundIn
    var centerOfMassUpperBound = upperBoundIn
    var errorAtLowerBound = sumOfDifferenceSquaresInRange(numbers, fromIndexInclusive, toIndexExclusive, centerOfMassLowerBound)
    var errorAtUpperBound = sumOfDifferenceSquaresInRange(numbers, fromIndexInclusive, toIndexExclusive, centerOfMassUpperBound)
    while centerOfMassUpperBound - centerOfMassLowerBound > allowablePositionError {
        let oneThirdPoint = centerOfMassLowerBound + ((centerOfMassUpperBound - centerOfMassLowerBound) / 3.0)
        let twoThirdsPoint = centerOfMassLowerBound + ((centerOfMassUpperBound - centerOfMassLowerBound) * 2.0 / 3.0)
        let errorAtOneThirdPoint = sumOfDifferenceSquaresInRange(numbers, fromIndexInclusive, toIndexExclusive, oneThirdPoint)
        let errorAtTwoThirdsPoint = sumOfDifferenceSquaresInRange(numbers, fromIndexInclusive, toIndexExclusive, twoThirdsPoint)
        if errorAtOneThirdPoint < errorAtTwoThirdsPoint {
            centerOfMassUpperBound = twoThirdsPoint
            errorAtUpperBound = errorAtTwoThirdsPoint
        } else {
            centerOfMassLowerBound = oneThirdPoint
            errorAtLowerBound = errorAtOneThirdPoint
        }
    }
    return min(errorAtLowerBound, errorAtUpperBound)
}

/// `errorAtBimodalSeparationIndex`.
private func errorAtBimodalSeparationIndex(_ sorted: [UInt8], _ firstHighModeIndex: Int) -> Double {
    let lowModeError = findMinimalErrorForRange(sorted, 0, firstHighModeIndex, Double(sorted[0]), Double(sorted[firstHighModeIndex]))
    let highModeError = findMinimalErrorForRange(sorted, firstHighModeIndex, sorted.count, Double(sorted[firstHighModeIndex]), Double(sorted[sorted.count - 1]))
    return lowModeError + highModeError
}

/// `findFirstIndexOfHighModeInBimodalDistibution` (binary search on the separation index).
private func findFirstIndexOfHighModeInBimodalDistribution(
    _ sorted: [UInt8], _ minIndexOfHighModeStartInclusive: Int, _ maxIndexOfHighModeStartInclusive: Int
) -> Int {
    var minIndex = minIndexOfHighModeStartInclusive
    var maxIndex = maxIndexOfHighModeStartInclusive
    // The C++ recurses; this loop is the same search.
    while minIndex < maxIndex {
        let lowCenter = (minIndex + maxIndex) / 2
        let highCenter = lowCenter + 1
        let errorAtLowCenter = errorAtBimodalSeparationIndex(sorted, lowCenter)
        let errorAtHighCenter = errorAtBimodalSeparationIndex(sorted, highCenter)
        if errorAtLowCenter < errorAtHighCenter {
            maxIndex = lowCenter
        } else {
            minIndex = highCenter
        }
    }
    return minIndex
}

/// statistics.h `bimodalThreshold<uchar>`: the value halfway between the highest sample of
/// the low mode and the lowest sample of the high mode. At least `minSamplesAtLowMode`
/// samples end up below it and `minSamplesAtHighMode` above it.
///
/// The C++ throws with fewer than two samples; the scanner never calls it that way
/// (31 and 11 samples), so this returns 0 instead of trapping.
func bimodalThreshold(_ numbers: [UInt8], minSamplesAtLowMode: Int = 1, minSamplesAtHighMode: Int = 1) -> UInt8 {
    if numbers.count <= 1 {
        return 0
    }
    let sorted = numbers.sorted()
    let minIndex = max(1, minSamplesAtLowMode)
    let maxIndex = sorted.count - max(1, minSamplesAtHighMode)
    if minIndex > maxIndex {
        // Invalid in the C++ as well (it throws); fall back to the middle.
        let mid = sorted.count / 2
        return UInt8((Int(sorted[mid - 1]) + Int(sorted[mid])) / 2)
    }
    let firstIndexAtHighMode = findFirstIndexOfHighModeInBimodalDistribution(sorted, minIndex, maxIndex)
    return UInt8((Int(sorted[firstIndexAtHighMode - 1]) + Int(sorted[firstIndexAtHighMode])) / 2)
}

// MARK: - Grid spacing (statistics.h findAndValidateMeanDifference)

/// Returns the mean step between sorted values if every step is within 5% (or a minimum
/// tolerance) of that mean, otherwise NaN.
func findAndValidateMeanDifference(_ sortedValues: [Float], minBoundEdgeRange minBoundEdgeRangeIn: Float = Float.nan) -> Float {
    if sortedValues.count < 2 {
        return Float.nan
    }
    let meanDifference = (sortedValues[sortedValues.count - 1] - sortedValues[0]) / Float(sortedValues.count - 1)
    let absMeanDifference = abs(meanDifference)
    var minBoundEdgeRange = minBoundEdgeRangeIn
    if minBoundEdgeRange.isNaN {
        minBoundEdgeRange = absMeanDifference / 5
    }
    let meanBoundLow = min(absMeanDifference - minBoundEdgeRange, absMeanDifference * 0.95)
    let meanBoundHigh = max(absMeanDifference + minBoundEdgeRange, absMeanDifference * 1.05)
    var allDistancesAreCloseToTheMeanDistance = true
    var d = 1
    while d < sortedValues.count && allDistancesAreCloseToTheMeanDistance {
        let difference = sortedValues[d] - sortedValues[d - 1]
        let absDifference = abs(difference)
        allDistancesAreCloseToTheMeanDistance = allDistancesAreCloseToTheMeanDistance
            && (meanBoundLow < absDifference) && (absDifference < meanBoundHigh)
        d += 1
    }
    if !allDistancesAreCloseToTheMeanDistance {
        return Float.nan
    }
    return meanDifference
}

// MARK: - Circular ranges (statistics.h)

/// `majorityOfThree`: the value at least two arguments share, or 0.
@inline(__always)
func majorityOfThree(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
    if a == b || a == c {
        return a
    } else if b == c {
        return b
    }
    return 0
}

/// `reduceToSignedRange`: reduces `x` to (-R, R].
@inline(__always)
func reduceToSignedRange(_ x: Float, _ magnitudeInPlusAndMinusDirection: Float) -> Float {
    let range = 2 * magnitudeInPlusAndMinusDirection
    let xModRange = x - ((x / range).rounded(.toNearestOrAwayFromZero) * range)
    if xModRange > magnitudeInPlusAndMinusDirection {
        return xModRange - range
    } else if xModRange <= -magnitudeInPlusAndMinusDirection {
        return xModRange + range
    } else {
        return xModRange
    }
}

/// `distanceInCircularRangeFromNegativeNToNWithInputsInRange`.
@inline(__always)
func distanceInCircularRangeFromNegativeNToNWithInputsInRange(_ aModN: Float, _ bModN: Float, _ r: Float) -> Float {
    let distanceWithinCircle = abs(aModN - bModN)
    let distAroundCircle = (2 * r) - distanceWithinCircle
    return min(distanceWithinCircle, distAroundCircle)
}

/// `distanceInModCircularRangeFromNegativeNToN`.
@inline(__always)
func distanceInModCircularRangeFromNegativeNToN(_ a: Float, _ b: Float, _ n: Float) -> Float {
    distanceInCircularRangeFromNegativeNToNWithInputsInRange(reduceToSignedRange(a, n), reduceToSignedRange(b, n), n)
}

/// `findPointOnCircularSignedNumberLineClosestToCenterOfMass`: of all the points reduced to
/// (-R, R], the one with the smallest summed circular distance to the others (returned as
/// the original, unreduced value).
func findPointOnCircularSignedNumberLineClosestToCenterOfMass(_ points: [Float], _ r: Float) -> Float {
    if points.isEmpty {
        return Float.nan
    }
    let pointsInRange = points.map { reduceToSignedRange($0, r) }
    var minDistance = Float.greatestFiniteMagnitude
    var indexAtWhichMinDistanceFound = 0
    for candidateIndex in 0..<pointsInRange.count {
        var distance: Float = 0
        let candidatePointModN = pointsInRange[candidateIndex]
        for otherPointModN in pointsInRange {
            distance += distanceInCircularRangeFromNegativeNToNWithInputsInRange(candidatePointModN, otherPointModN, r)
        }
        if distance < minDistance {
            minDistance = distance
            indexAtWhichMinDistanceFound = candidateIndex
        }
    }
    return points[indexAtWhichMinDistanceFound]
}

// MARK: - bit-operations.h

@inline(__always)
func countOneBits(_ x: UInt32) -> Int { x.nonzeroBitCount }

@inline(__always)
func hammingDistance(_ a: UInt32, _ b: UInt32) -> Int { countOneBits(a ^ b) }

/// `reverseBits`: reverses the low `lengthInBits` bits.
func reverseBits(_ bitsToReverse: UInt32, _ lengthInBits: Int) -> UInt32 {
    var bits = bitsToReverse
    var reversed: UInt32 = 0
    for _ in 0..<lengthInBits {
        reversed <<= 1
        if bits & 1 != 0 {
            reversed += 1
        }
        bits >>= 1
    }
    return reversed
}
