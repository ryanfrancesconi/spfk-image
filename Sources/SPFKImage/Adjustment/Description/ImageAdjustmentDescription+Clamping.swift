// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

// Each section clamps its own fields to their ``ImageAdjustmentDescription/Parameter/range``.
// Field by field rather than through `Parameter.keyPath`: a section is clamped on every assignment,
// including each column a stored row decodes into it, and a keypath read copies the whole
// description.

func clampField(_ value: inout Double, _ parameter: ImageAdjustmentDescription.Parameter) {
    value = parameter.sanitize(value)
}
