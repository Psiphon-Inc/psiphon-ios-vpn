import XCTest

import UtilitiesTests

var tests = [XCTestCaseEntry]()
tests += UtilitiesTests.allTests()
tests += Rfc3339CTimestampTests.allTests()
XCTMain(tests)
