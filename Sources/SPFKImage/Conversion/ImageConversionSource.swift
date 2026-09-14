// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// One file's conversion: where ``ImageFormatConverter`` reads, where it writes, and how.
public struct ImageConversionSource: Sendable {
    public var input: URL
    public var output: URL
    public var options: ImageConversionOptions

    /// The file ``input`` stands in for, when it is a render of that file with pending edits applied.
    /// The output may not replace this file any more than it may replace ``input``.
    public var originalInput: URL?

    public init(input: URL, output: URL, options: ImageConversionOptions, originalInput: URL? = nil) {
        self.input = input
        self.output = output
        self.options = options
        self.originalInput = originalInput
    }
}
