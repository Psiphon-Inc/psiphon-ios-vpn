import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(NonEmptySeqTest.allTests),
        testCase(RFC3339Tests.allTests),
    ]
}
#endif
