# Multiline Call Arguments

Call should have each parameter on a separate line

* **Identifier:** `multiline_call_arguments`
* **Enabled by default:** No
* **Supports autocorrection:** No
* **Kind:** style
* **Analyzer rule:** No
* **Minimum Swift compiler version:** 5.0.0
* **Default configuration:**
  <table>
  <thead>
  <tr><th>Key</th><th>Value</th></tr>
  </thead>
  <tbody>
  <tr>
  <td>
  severity
  </td>
  <td>
  warning
  </td>
  </tr>
  <tr>
  <td>
  allows_single_line
  </td>
  <td>
  true
  </td>
  </tr>
  </tbody>
  </table>

## Non Triggering Examples

```swift
//
// max_number_of_single_line_parameters: 2
//

foo(
param1: "param1",
    param2: false,
    param3: []
)

```

```swift
//
// max_number_of_single_line_parameters: 1
//

foo(param1: 1,
    param2: false,
    param3: [])

```

```swift
//
// max_number_of_single_line_parameters: 2
//

foo(param1: 1, param2: false)

```

```swift
//
// max_number_of_single_line_parameters: 2
//

Enum.foo(param1: 1, param2: false)

```

```swift
//
// allows_single_line: false
//

foo(param1: 1)

```

```swift
//
// allows_single_line: false
//

Enum.foo(param1: 1)

```

```swift
//
// allows_single_line: true
//

Enum.foo(param1: 1, param2: 2, param3: 3)

```

```swift
//
// allows_single_line: false
//

foo(
    param1: 1,
    param2: 2,
    param3: 3
)

```

## Triggering Examples

```swift
//
// max_number_of_single_line_parameters: 2
//

↓foo(param1: 1, param2: false, param3: [])

```

```swift
//
// max_number_of_single_line_parameters: 2
//

↓Enum.foo(param1: 1, param2: false, param3: [])

```

```swift
//
// max_number_of_single_line_parameters: 3
//

↓foo(param1: 1, param2: false,
        param3: [])

```

```swift
//
// max_number_of_single_line_parameters: 3
//

↓Enum.foo(param1: 1, param2: false,
        param3: [])

```

```swift
//
// allows_single_line: false
//

↓foo(param1: 1, param2: false)

```

```swift
//
// allows_single_line: false
//

↓Enum.foo(param1: 1, param2: false)

```